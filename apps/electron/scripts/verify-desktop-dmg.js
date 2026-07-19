#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const rootPackage = require("../package.json");

const ROOT = path.resolve(__dirname, "..");
const dmgPath = path.resolve(
  ROOT,
  process.argv[2] ?? `dist-desktop/Scriber-${rootPackage.version}-Apple-Silicon.dmg`
);
const mountPoint = fs.mkdtempSync(path.join(os.tmpdir(), "scriber-dmg-verify-"));

function fail(message) {
  throw new Error(`Desktop DMG verification failed: ${message}`);
}

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
  if (result.status !== 0) {
    fail(`${command} ${args.join(" ")}\n${output}`);
  }
  return output;
}

let attached = false;
try {
  if (!fs.existsSync(dmgPath)) fail(`disk image is missing at ${dmgPath}`);
  run("/usr/bin/hdiutil", ["verify", dmgPath]);
  run("/usr/bin/hdiutil", [
    "attach",
    "-readonly",
    "-nobrowse",
    "-mountpoint",
    mountPoint,
    dmgPath,
  ]);
  attached = true;

  const mountedApp = path.join(mountPoint, "Scriber.app");
  const applicationsLink = path.join(mountPoint, "Applications");
  if (!fs.statSync(mountedApp).isDirectory()) fail("mounted Scriber.app is missing");
  if (!fs.lstatSync(applicationsLink).isSymbolicLink()) {
    fail("mounted Applications shortcut is not a symbolic link");
  }
  if (fs.readlinkSync(applicationsLink) !== "/Applications") {
    fail("mounted Applications shortcut does not target /Applications");
  }

  run(process.execPath, [
    path.join(ROOT, "scripts", "verify-desktop-bundle.js"),
    mountedApp,
    "arm64",
  ]);
  process.stdout.write(`Verified mountable DMG at ${dmgPath}\n`);
  process.stdout.write("Contents: Scriber.app + /Applications shortcut\n");
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.stack : String(error)}\n`);
  process.exitCode = 1;
} finally {
  if (attached) {
    const result = spawnSync("/usr/bin/hdiutil", ["detach", mountPoint], {
      encoding: "utf8",
    });
    if (result.status !== 0) {
      process.stderr.write(
        `Could not detach verification image at ${mountPoint}: ${result.stderr || result.stdout}\n`
      );
      process.exitCode = 1;
    } else {
      attached = false;
    }
  }
  if (!attached && fs.existsSync(mountPoint)) fs.rmdirSync(mountPoint);
}
