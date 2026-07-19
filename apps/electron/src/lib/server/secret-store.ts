import "server-only";

import crypto from "node:crypto";
import path from "node:path";
import { spawn } from "node:child_process";

export const SCRIBER_KEYCHAIN_SERVICE =
  "com.gafiegarcia.scriber.elevenlabs-api-key";

export type ApiKeyStorageKind = "keychain" | "config-file";

export interface ApiKeySecretStore {
  read(): Promise<string | undefined>;
  write(secret: string): Promise<void>;
  delete(): Promise<void>;
}

export interface SecurityCommandResult {
  code: number | null;
  stdout: string;
  stderr: string;
}

export type SecurityCommandRunner = (
  args: string[],
  stdin?: string
) => Promise<SecurityCommandResult>;

export class SecretStoreError extends Error {
  readonly code = "KEYCHAIN_UNAVAILABLE";

  constructor(operation: "read" | "write" | "delete") {
    super(
      `Could not ${operation} the ElevenLabs API key in macOS Keychain. ` +
        "Unlock your login keychain and try again."
    );
    this.name = "SecretStoreError";
  }
}

export function usesMacOsKeychain(
  platform: NodeJS.Platform = process.platform
): boolean {
  return platform === "darwin";
}

export function getApiKeyStorageKind(): ApiKeyStorageKind {
  return usesMacOsKeychain() ? "keychain" : "config-file";
}

export function keychainAccountForProfile(profileHome: string): string {
  const normalized = path.resolve(profileHome).normalize("NFC");
  const digest = crypto.createHash("sha256").update(normalized).digest("hex");
  return `profile-${digest.slice(0, 24)}`;
}

const runSecurity: SecurityCommandRunner = (args, stdin) =>
  new Promise((resolve) => {
    const child = spawn("/usr/bin/security", args, {
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      finish({ code: null, stdout, stderr: "Keychain command timed out" });
    }, 15_000);

    const finish = (result: SecurityCommandResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolve(result);
    };

    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString("utf8");
    });
    child.on("error", (error) => {
      finish({ code: null, stdout, stderr: error.message });
    });
    child.on("close", (code) => finish({ code, stdout, stderr }));
    child.stdin.on("error", () => {
      // The update path may consume only one of the two confirmation lines.
    });
    child.stdin.end(stdin);
  });

function itemIsMissing(result: SecurityCommandResult): boolean {
  return (
    result.code === 44 ||
    result.stderr.toLowerCase().includes("could not be found in the keychain")
  );
}

export function createMacOsKeychainApiKeyStore(
  profileHome: string,
  runner: SecurityCommandRunner = runSecurity
): ApiKeySecretStore {
  const account = keychainAccountForProfile(profileHome);
  const matchArgs = [
    "-a",
    account,
    "-s",
    SCRIBER_KEYCHAIN_SERVICE,
  ];
  let hasCachedValue = false;
  let cachedValue: string | undefined;
  let pendingRead: Promise<string | undefined> | undefined;

  return {
    async read() {
      if (hasCachedValue) return cachedValue;
      if (pendingRead) return pendingRead;

      pendingRead = (async () => {
        const result = await runner([
          "find-generic-password",
          ...matchArgs,
          "-w",
        ]);
        if (itemIsMissing(result)) return undefined;
        if (result.code !== 0) throw new SecretStoreError("read");
        return result.stdout.replace(/\r?\n$/, "") || undefined;
      })();

      try {
        cachedValue = await pendingRead;
        hasCachedValue = true;
        return cachedValue;
      } finally {
        pendingRead = undefined;
      }
    },

    async write(secret) {
      // Passing a secret via `-w value` exposes it in the process list. With
      // `-w` as the final argument, security(1) reads it from stdin instead.
      // New items ask for confirmation; updates may consume only the first
      // line, so supplying two identical lines safely covers both paths.
      const result = await runner(
        [
          "add-generic-password",
          "-U",
          ...matchArgs,
          "-l",
          "Scriber ElevenLabs API key",
          "-j",
          "Stored locally by Scriber for ElevenLabs transcription",
          "-w",
        ],
        `${secret}\n${secret}\n`
      );
      if (result.code !== 0) throw new SecretStoreError("write");
      cachedValue = secret;
      hasCachedValue = true;
    },

    async delete() {
      const result = await runner([
        "delete-generic-password",
        ...matchArgs,
      ]);
      if (itemIsMissing(result)) {
        cachedValue = undefined;
        hasCachedValue = true;
        return;
      }
      if (result.code !== 0) throw new SecretStoreError("delete");
      cachedValue = undefined;
      hasCachedValue = true;
    },
  };
}
