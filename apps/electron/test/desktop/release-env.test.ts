import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { validateReleaseEnvironment } = require(
  "../../scripts/check-desktop-release-env.js"
) as {
  validateReleaseEnvironment(
    environment: Record<string, string | undefined>,
    options?: { keychainIdentity?: string | null }
  ): {
    signingMethod: string;
    notarizationMethod: string;
  };
};

test("desktop release refuses an unsigned build", () => {
  assert.throws(
    () => validateReleaseEnvironment({}),
    /install a Developer ID Application certificate/
  );
});

test("desktop release accepts a Developer ID identity already in Keychain", () => {
  assert.equal(
    validateReleaseEnvironment(
      { APPLE_KEYCHAIN_PROFILE: "scriber-notary" },
      { keychainIdentity: "Developer ID Application: Example (TEAMID)" }
    ).signingMethod,
    "Developer ID identity in Keychain"
  );
});

test("desktop release refuses incomplete notarization credentials", () => {
  assert.throws(
    () =>
      validateReleaseEnvironment({
        CSC_NAME: "Developer ID Application: Example",
        APPLE_API_KEY: "/private/key.p8",
      }),
    /complete notarization credential set/
  );
});

test("desktop release accepts App Store Connect API credentials", () => {
  assert.deepEqual(
    validateReleaseEnvironment({
      CSC_LINK: "/private/developer-id.p12",
      APPLE_API_KEY: "/private/AuthKey.p8",
      APPLE_API_KEY_ID: "KEYID",
      APPLE_API_ISSUER: "ISSUER",
    }),
    {
      signingMethod: "CSC_LINK certificate",
      notarizationMethod: "App Store Connect API key",
    }
  );
});

test("desktop release accepts a notarytool Keychain profile", () => {
  assert.equal(
    validateReleaseEnvironment({
      CSC_NAME: "Developer ID Application: Example",
      APPLE_KEYCHAIN_PROFILE: "scriber-notary",
    }).notarizationMethod,
    "notarytool Keychain profile"
  );
});

test("local desktop config stays unsigned even when signing variables exist", () => {
  const script = [
    "const config = require('./electron-builder.config.cjs');",
    "process.stdout.write(JSON.stringify({",
    "identity: config.mac.identity,",
    "hardenedRuntime: config.mac.hardenedRuntime,",
    "notarize: config.mac.notarize",
    "}));",
  ].join("");
  const result = spawnSync(process.execPath, ["-e", script], {
    cwd: process.cwd(),
    encoding: "utf8",
    env: {
      ...process.env,
      CSC_NAME: "Developer ID Application: Example (TEAMID)",
      SCRIBER_DESKTOP_RELEASE: "",
    },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), {
    identity: null,
    hardenedRuntime: false,
    notarize: false,
  });
});

test("explicit desktop release mode enables hardened signing and notarization", () => {
  const script = [
    "const config = require('./electron-builder.config.cjs');",
    "process.stdout.write(JSON.stringify({",
    "identity: config.mac.identity,",
    "hardenedRuntime: config.mac.hardenedRuntime,",
    "notarize: config.mac.notarize",
    "}));",
  ].join("");
  const identity = "Developer ID Application: Example (TEAMID)";
  const result = spawnSync(process.execPath, ["-e", script], {
    cwd: process.cwd(),
    encoding: "utf8",
    env: {
      ...process.env,
      CSC_NAME: identity,
      SCRIBER_DESKTOP_RELEASE: "1",
    },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), {
    identity,
    hardenedRuntime: true,
    notarize: true,
  });
});
