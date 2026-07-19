import { test } from "node:test";
import assert from "node:assert/strict";

import {
  SCRIBER_KEYCHAIN_SERVICE,
  SecretStoreError,
  createMacOsKeychainApiKeyStore,
  keychainAccountForProfile,
  usesMacOsKeychain,
  type SecurityCommandRunner,
  type SecurityCommandResult,
} from "../../src/lib/server/secret-store";

function runnerReturning(
  result: SecurityCommandResult,
  calls: Array<{ args: string[]; stdin?: string }> = []
): SecurityCommandRunner {
  return async (args, stdin) => {
    calls.push({ args, stdin });
    return result;
  };
}

test("Keychain is selected only on macOS", () => {
  assert.equal(usesMacOsKeychain("darwin"), true);
  assert.equal(usesMacOsKeychain("linux"), false);
  assert.equal(usesMacOsKeychain("win32"), false);
});

test("profile account is stable without exposing the home path", () => {
  const first = keychainAccountForProfile("/Users/alice/.scriber");
  const same = keychainAccountForProfile("/Users/alice/.scriber");
  const other = keychainAccountForProfile("/Users/alice/another-profile");
  assert.equal(first, same);
  assert.notEqual(first, other);
  assert.match(first, /^profile-[a-f0-9]{24}$/);
  assert.doesNotMatch(first, /alice|scriber/i);
});

test("read uses the scoped service/account and strips only its final newline", async () => {
  const calls: Array<{ args: string[]; stdin?: string }> = [];
  const store = createMacOsKeychainApiKeyStore(
    "/tmp/scriber-profile",
    runnerReturning({ code: 0, stdout: "sk_test_value\n", stderr: "" }, calls)
  );

  assert.equal(await store.read(), "sk_test_value");
  assert.deepEqual(calls[0].args.slice(0, 1), ["find-generic-password"]);
  assert.ok(calls[0].args.includes(SCRIBER_KEYCHAIN_SERVICE));
  assert.equal(calls[0].args.at(-1), "-w");
});

test("read treats security exit 44 as a missing item", async () => {
  const store = createMacOsKeychainApiKeyStore(
    "/tmp/scriber-profile",
    runnerReturning({ code: 44, stdout: "", stderr: "not found" })
  );
  assert.equal(await store.read(), undefined);
});

test("repeated and concurrent reads access Keychain only once per process", async () => {
  const calls: Array<{ args: string[]; stdin?: string }> = [];
  const store = createMacOsKeychainApiKeyStore(
    "/tmp/scriber-profile",
    runnerReturning({ code: 0, stdout: "sk_cached\n", stderr: "" }, calls)
  );

  assert.deepEqual(await Promise.all([store.read(), store.read(), store.read()]), [
    "sk_cached",
    "sk_cached",
    "sk_cached",
  ]);
  assert.equal(await store.read(), "sk_cached");
  assert.equal(calls.length, 1);
});

test("write sends the key through stdin, never argv", async () => {
  const calls: Array<{ args: string[]; stdin?: string }> = [];
  const store = createMacOsKeychainApiKeyStore(
    "/tmp/scriber-profile",
    runnerReturning({ code: 0, stdout: "", stderr: "" }, calls)
  );
  await store.write("sk_super_secret");

  const call = calls[0];
  assert.equal(call.args[0], "add-generic-password");
  assert.ok(call.args.includes("-U"));
  assert.equal(call.args.at(-1), "-w");
  assert.ok(!call.args.includes("-A"));
  assert.ok(!call.args.includes("-T"));
  assert.doesNotMatch(call.args.join(" "), /sk_super_secret/);
  assert.equal(call.stdin, "sk_super_secret\nsk_super_secret\n");
});

test("delete is idempotent when the item is already missing", async () => {
  const store = createMacOsKeychainApiKeyStore(
    "/tmp/scriber-profile",
    runnerReturning({ code: 44, stdout: "", stderr: "not found" })
  );
  await assert.doesNotReject(store.delete());
});

test("Keychain failures produce a typed, secret-free error", async () => {
  const store = createMacOsKeychainApiKeyStore(
    "/tmp/scriber-profile",
    runnerReturning({
      code: 36,
      stdout: "",
      stderr: "internal output that should not escape",
    })
  );

  await assert.rejects(store.read(), (error: unknown) => {
    assert.ok(error instanceof SecretStoreError);
    assert.equal(error.code, "KEYCHAIN_UNAVAILABLE");
    assert.doesNotMatch(error.message, /internal output/);
    return true;
  });
});
