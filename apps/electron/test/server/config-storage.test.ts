import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import {
  createConfigStore,
  type ConfigStore,
} from "../../src/lib/server/storage";
import type { ApiKeySecretStore } from "../../src/lib/server/secret-store";

interface FakeSecretStore extends ApiKeySecretStore {
  value?: string;
  writes: string[];
  deletes: number;
}

function fakeSecretStore(initial?: string): FakeSecretStore {
  return {
    value: initial,
    writes: [],
    deletes: 0,
    async read() {
      return this.value;
    },
    async write(secret) {
      this.writes.push(secret);
      this.value = secret;
    },
    async delete() {
      this.deletes += 1;
      this.value = undefined;
    },
  };
}

async function withTempConfig(
  run: (context: { dir: string; configPath: string }) => Promise<void>
) {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "scriber-config-test-"));
  const configPath = path.join(dir, "config.json");
  try {
    await run({ dir, configPath });
  } finally {
    await fs.unlink(configPath).catch(() => {});
    await fs.rmdir(dir);
  }
}

async function readDisk(configPath: string): Promise<Record<string, unknown>> {
  return JSON.parse(await fs.readFile(configPath, "utf8"));
}

test("legacy plaintext key migrates to Keychain before being scrubbed", async () => {
  await withTempConfig(async ({ dir, configPath }) => {
    const original = {
      apiKey: "  sk_legacy  ",
      dictionary: ["Sobat HAPE"],
      theme: "dark",
    };
    await fs.writeFile(configPath, JSON.stringify(original, null, 2), {
      mode: 0o644,
    });
    const secrets = fakeSecretStore();
    const store = createConfigStore({ configPath, secretStore: secrets });

    const config = await store.read();
    assert.equal(config.apiKey, "sk_legacy");
    assert.deepEqual(secrets.writes, ["sk_legacy"]);
    assert.deepEqual(await readDisk(configPath), {
      dictionary: ["Sobat HAPE"],
      theme: "dark",
    });
    assert.equal((await fs.stat(configPath)).mode & 0o777, 0o600);
    assert.equal((await fs.stat(dir)).mode & 0o777, 0o700);
  });
});

test("concurrent config reads migrate a legacy key only once", async () => {
  await withTempConfig(async ({ configPath }) => {
    await fs.writeFile(configPath, JSON.stringify({ apiKey: "sk_legacy" }));
    const secrets = fakeSecretStore();
    let releaseWrite: (() => void) | undefined;
    const writeStarted = new Promise<void>((resolve) => {
      secrets.write = async (secret) => {
        secrets.writes.push(secret);
        resolve();
        await new Promise<void>((release) => {
          releaseWrite = release;
        });
        secrets.value = secret;
      };
    });
    const store = createConfigStore({ configPath, secretStore: secrets });

    const reads = Promise.all([store.read(), store.read(), store.read()]);
    await writeStarted;
    releaseWrite?.();
    const configs = await reads;

    assert.deepEqual(
      configs.map((config) => config.apiKey),
      ["sk_legacy", "sk_legacy", "sk_legacy"]
    );
    assert.deepEqual(secrets.writes, ["sk_legacy"]);
    assert.equal((await readDisk(configPath)).apiKey, undefined);
  });
});

test("concurrent config reads share one Keychain failure", async () => {
  await withTempConfig(async ({ configPath }) => {
    await fs.writeFile(configPath, JSON.stringify({ apiKey: "sk_preserve" }));
    const secrets = fakeSecretStore();
    let reads = 0;
    let releaseRead: (() => void) | undefined;
    const readStarted = new Promise<void>((resolve) => {
      secrets.read = async () => {
        reads += 1;
        resolve();
        await new Promise<void>((release) => {
          releaseRead = release;
        });
        throw new Error("simulated locked Keychain");
      };
    });
    const store = createConfigStore({ configPath, secretStore: secrets });

    const results = Promise.allSettled([
      store.read(),
      store.read(),
      store.read(),
    ]);
    await readStarted;
    releaseRead?.();
    const settled = await results;

    assert.equal(reads, 1);
    assert.ok(settled.every((result) => result.status === "rejected"));
    assert.equal(
      JSON.parse(await fs.readFile(configPath, "utf8")).apiKey,
      "sk_preserve"
    );
  });
});

test("failed migration preserves the plaintext file byte-for-byte", async () => {
  await withTempConfig(async ({ configPath }) => {
    const original = '{\n  "apiKey": "sk_only_copy",\n  "theme": "light"\n}\n';
    await fs.writeFile(configPath, original);
    const secrets = fakeSecretStore();
    secrets.write = async () => {
      throw new Error("simulated Keychain failure");
    };
    const store = createConfigStore({ configPath, secretStore: secrets });

    await assert.rejects(store.read(), /simulated Keychain failure/);
    assert.equal(await fs.readFile(configPath, "utf8"), original);
  });
});

test("existing Keychain value wins and conflicting plaintext is scrubbed", async () => {
  await withTempConfig(async ({ configPath }) => {
    await fs.writeFile(
      configPath,
      JSON.stringify({ apiKey: "sk_stale", dictionary: ["Scriber"] })
    );
    const secrets = fakeSecretStore("sk_keychain");
    const store = createConfigStore({ configPath, secretStore: secrets });

    assert.equal((await store.read()).apiKey, "sk_keychain");
    assert.deepEqual(secrets.writes, []);
    assert.deepEqual(await readDisk(configPath), { dictionary: ["Scriber"] });
  });
});

test("a Keychain read error never falls back to or scrubs plaintext", async () => {
  await withTempConfig(async ({ configPath }) => {
    const original = JSON.stringify({ apiKey: "sk_preserve", theme: "system" });
    await fs.writeFile(configPath, original);
    const secrets = fakeSecretStore();
    secrets.read = async () => {
      throw new Error("simulated locked Keychain");
    };
    const store = createConfigStore({ configPath, secretStore: secrets });

    await assert.rejects(store.read(), /locked Keychain/);
    assert.equal(await fs.readFile(configPath, "utf8"), original);
  });
});

test("preference writes never serialize a Keychain-backed key", async () => {
  await withTempConfig(async ({ configPath }) => {
    const secrets = fakeSecretStore("sk_keychain");
    const store = createConfigStore({ configPath, secretStore: secrets });
    const updated = await store.write({ theme: "dark" });

    assert.equal(updated.apiKey, "sk_keychain");
    assert.equal((await readDisk(configPath)).apiKey, undefined);
    assert.equal((await readDisk(configPath)).theme, "dark");
    assert.deepEqual(secrets.writes, []);
  });
});

test("Keychain-backed key can be replaced and removed", async () => {
  await withTempConfig(async ({ configPath }) => {
    const secrets = fakeSecretStore("sk_old");
    const store: ConfigStore = createConfigStore({
      configPath,
      secretStore: secrets,
    });

    assert.equal((await store.write({ apiKey: "  sk_new  " })).apiKey, "sk_new");
    assert.deepEqual(secrets.writes, ["sk_new"]);
    assert.equal((await readDisk(configPath)).apiKey, undefined);

    assert.equal((await store.write({ apiKey: "" })).apiKey, undefined);
    assert.equal(secrets.deletes, 1);
    assert.equal((await readDisk(configPath)).apiKey, undefined);
  });
});

test("non-macOS file fallback keeps its existing plaintext behavior", async () => {
  await withTempConfig(async ({ configPath }) => {
    const store = createConfigStore({ configPath, secretStore: null });
    await store.write({ apiKey: "  sk_file  ", theme: "light" });

    assert.equal((await store.read()).apiKey, "sk_file");
    assert.equal((await readDisk(configPath)).apiKey, "sk_file");
    assert.equal((await fs.stat(configPath)).mode & 0o777, 0o600);
  });
});
