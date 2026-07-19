#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const {
  getCurrentFuseWire,
  FuseV1Options,
  FuseState,
} = require("@electron/fuses");
const { listPackage } = require("@electron/asar");
const rootPackage = require("../package.json");

const ROOT = path.resolve(__dirname, "..");
const appPath = path.resolve(ROOT, process.argv[2] ?? "dist-desktop/mac-arm64/Scriber.app");
const expectedArch = process.argv[3] ?? "arm64";

function fail(message) {
  throw new Error(`Desktop bundle verification failed: ${message}`);
}

if (expectedArch !== "arm64") {
  fail("Scriber desktop bundles support Apple-silicon arm64 only");
}

function requirePath(target, label) {
  if (!fs.existsSync(target)) fail(`${label} is missing at ${target}`);
}

function walk(directory, visit) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const target = path.join(directory, entry.name);
    visit(target, entry);
    if (entry.isDirectory() && !entry.isSymbolicLink()) walk(target, visit);
  }
}

function command(commandPath, args) {
  return execFileSync(commandPath, args, { encoding: "utf8" }).trim();
}

async function main() {
  requirePath(appPath, "Scriber.app");
  const resources = path.join(appPath, "Contents", "Resources");
  const server = path.join(resources, "scriber-standalone");
  const ffmpeg = path.join(resources, "ffmpeg", "ffmpeg");
  const ffprobe = path.join(resources, "ffmpeg", "ffprobe");
  const executable = path.join(appPath, "Contents", "MacOS", "Scriber");
  const appAsar = path.join(resources, "app.asar");
  const appAsarUnpacked = path.join(resources, "app.asar.unpacked");

  requirePath(path.join(server, "server.js"), "standalone server");
  requirePath(path.join(server, ".next", "static"), "Next.js static assets");
  requirePath(path.join(server, "public"), "public assets");
  requirePath(ffmpeg, "FFmpeg helper");
  requirePath(ffprobe, "FFprobe helper");
  requirePath(path.join(resources, "legal", "FFMPEG_DISTRIBUTION.md"), "FFmpeg legal notice");
  requirePath(executable, "Scriber executable");
  requirePath(appAsar, "desktop app ASAR");

  if ((fs.statSync(ffmpeg).mode & 0o111) === 0) fail("FFmpeg is not executable");
  if ((fs.statSync(ffprobe).mode & 0o111) === 0) fail("FFprobe is not executable");

  const forbidden = [];
  walk(server, (target, entry) => {
    const normalized = target.split(path.sep).join("/");
    if (
      normalized.includes("/node_modules/ffmpeg-static/") ||
      normalized.includes("/node_modules/@derhuerst/ffprobe-static/") ||
      entry.name.endsWith(".node")
    ) {
      forbidden.push(path.relative(appPath, target));
    }
  });
  if (forbidden.length) fail(`forbidden native files found: ${forbidden.join(", ")}`);

  walk(appPath, (target) => {
    const normalized = target.split(path.sep).join("/");
    if (
      normalized.includes("/ffmpeg-static/") ||
      normalized.includes("/ffprobe-static/")
    ) {
      forbidden.push(path.relative(appPath, target));
    }
  });
  if (forbidden.length) {
    fail(`forbidden downloaded media packages found: ${forbidden.join(", ")}`);
  }

  const asarEntries = listPackage(appAsar);
  const unexpectedAsarEntries = asarEntries.filter(
    (entry) => !["/main.cjs", "/package.json", "/runtime.cjs"].includes(entry)
  );
  if (unexpectedAsarEntries.length) {
    fail(`unexpected app.asar content: ${unexpectedAsarEntries.slice(0, 20).join(", ")}`);
  }
  if (fs.statSync(appAsar).size > 1_000_000) {
    fail(`app.asar is unexpectedly large (${fs.statSync(appAsar).size} bytes)`);
  }
  if (fs.existsSync(appAsarUnpacked)) {
    const unpackedFiles = [];
    walk(appAsarUnpacked, (target, entry) => {
      if (entry.isFile()) unpackedFiles.push(path.relative(appAsarUnpacked, target));
    });
    if (unpackedFiles.length) {
      fail(`desktop shell unexpectedly unpacked dependencies: ${unpackedFiles.slice(0, 20).join(", ")}`);
    }
  }

  for (const helper of [ffmpeg, ffprobe]) {
    const architectures = command("/usr/bin/lipo", ["-archs", helper]).split(/\s+/);
    if (architectures.length !== 1 || architectures[0] !== expectedArch) {
      fail(`${path.basename(helper)} architecture is ${architectures.join(", ")}, expected ${expectedArch}`);
    }
  }

  const plistVersion = command("/usr/bin/plutil", [
    "-extract",
    "CFBundleShortVersionString",
    "raw",
    "-o",
    "-",
    path.join(appPath, "Contents", "Info.plist"),
  ]);
  if (plistVersion !== rootPackage.version) {
    fail(`app version ${plistVersion} does not match package version ${rootPackage.version}`);
  }

  const fuses = await getCurrentFuseWire(executable);
  const expectedFuses = new Map([
    [FuseV1Options.RunAsNode, FuseState.DISABLE],
    [FuseV1Options.EnableCookieEncryption, FuseState.DISABLE],
    [FuseV1Options.EnableNodeOptionsEnvironmentVariable, FuseState.DISABLE],
    [FuseV1Options.EnableNodeCliInspectArguments, FuseState.DISABLE],
    [FuseV1Options.EnableEmbeddedAsarIntegrityValidation, FuseState.ENABLE],
    [FuseV1Options.OnlyLoadAppFromAsar, FuseState.ENABLE],
    [FuseV1Options.LoadBrowserProcessSpecificV8Snapshot, FuseState.DISABLE],
    [FuseV1Options.GrantFileProtocolExtraPrivileges, FuseState.DISABLE],
    [FuseV1Options.WasmTrapHandlers, FuseState.ENABLE],
  ]);
  for (const [fuse, expected] of expectedFuses) {
    if (fuses[fuse] !== expected) fail(`Electron fuse ${fuse} has unexpected state ${fuses[fuse]}`);
  }

  process.stdout.write(`Verified ${appPath}\n`);
  process.stdout.write(`Architecture: ${expectedArch}; version: ${plistVersion}; forbidden native modules: none\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exit(1);
});
