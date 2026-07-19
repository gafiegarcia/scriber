#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */

const { spawnSync } = require("node:child_process");

function hasValue(environment, name) {
  return typeof environment[name] === "string" && environment[name].trim().length > 0;
}

const NOTARIZATION_METHODS = [
  {
    name: "App Store Connect API key",
    variables: ["APPLE_API_KEY", "APPLE_API_KEY_ID", "APPLE_API_ISSUER"],
  },
  {
    name: "Apple ID",
    variables: ["APPLE_ID", "APPLE_APP_SPECIFIC_PASSWORD", "APPLE_TEAM_ID"],
  },
  {
    name: "notarytool Keychain profile",
    variables: ["APPLE_KEYCHAIN_PROFILE"],
  },
];

function findDeveloperIdIdentity() {
  const result = spawnSync(
    "/usr/bin/security",
    ["find-identity", "-v", "-p", "codesigning"],
    { encoding: "utf8" }
  );
  if (result.status !== 0) return null;
  const match = result.stdout.match(/"(Developer ID Application:[^"]+)"/);
  return match?.[1] ?? null;
}

function validateReleaseEnvironment(environment = process.env, options = {}) {
  const keychainIdentity = options.keychainIdentity ?? null;
  const signingMethod = hasValue(environment, "CSC_LINK")
    ? "CSC_LINK certificate"
    : hasValue(environment, "CSC_NAME")
      ? "CSC_NAME identity"
      : keychainIdentity
        ? "Developer ID identity in Keychain"
        : null;
  if (!signingMethod) {
    throw new Error(
      "Mac release refused: install a Developer ID Application certificate in Keychain, " +
        "or set CSC_LINK/CSC_NAME."
    );
  }

  const notarizationMethod = NOTARIZATION_METHODS.find((method) =>
    method.variables.every((name) => hasValue(environment, name))
  );
  if (!notarizationMethod) {
    throw new Error(
      "Mac release refused: configure a complete notarization credential set: " +
        "APPLE_API_KEY + APPLE_API_KEY_ID + APPLE_API_ISSUER (recommended), " +
        "APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD + APPLE_TEAM_ID, or " +
        "APPLE_KEYCHAIN_PROFILE."
    );
  }

  return { signingMethod, notarizationMethod: notarizationMethod.name };
}

if (require.main === module) {
  try {
    const result = validateReleaseEnvironment(process.env, {
      keychainIdentity: findDeveloperIdIdentity(),
    });
    process.stdout.write(
      `Mac release credentials are configured (${result.signingMethod}; ${result.notarizationMethod}).\n`
    );
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}

module.exports = { findDeveloperIdIdentity, validateReleaseEnvironment };
