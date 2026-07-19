#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */

const path = require("node:path");
const { spawnSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");
const appPath = path.resolve(
  ROOT,
  process.argv[2] ?? "dist-desktop/mac-arm64/Scriber.app"
);

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
  if (result.status !== 0) {
    throw new Error(
      `Desktop release verification failed: ${command} ${args.join(" ")}\n${output}`
    );
  }
  return output;
}

function signatureDetails(target) {
  const details = run("/usr/bin/codesign", ["-dv", "--verbose=4", target]);
  if (!/Authority=Developer ID Application:/.test(details)) {
    throw new Error(`Desktop release verification failed: ${target} is not Developer ID signed`);
  }
  if (/Signature=adhoc/.test(details) || /TeamIdentifier=not set/.test(details)) {
    throw new Error(`Desktop release verification failed: ${target} has an ad-hoc signature`);
  }
  return details;
}

try {
  run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]);
  signatureDetails(appPath);

  const resources = path.join(appPath, "Contents", "Resources", "ffmpeg");
  for (const helper of ["ffmpeg", "ffprobe"]) {
    const helperPath = path.join(resources, helper);
    run("/usr/bin/codesign", ["--verify", "--strict", "--verbose=2", helperPath]);
    signatureDetails(helperPath);
  }

  run("/usr/bin/xcrun", ["stapler", "validate", appPath]);
  run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", appPath]);
  process.stdout.write(`Verified signed and notarized desktop release at ${appPath}\n`);
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.stack : String(error)}\n`);
  process.exitCode = 1;
}
