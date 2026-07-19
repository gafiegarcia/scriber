#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */

const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const STANDALONE = path.join(ROOT, ".next", "standalone");
const STATIC_SRC = path.join(ROOT, ".next", "static");
const STATIC_DEST = path.join(STANDALONE, ".next", "static");
const PUBLIC_SRC = path.join(ROOT, "public");
const PUBLIC_DEST = path.join(STANDALONE, "public");
const DESKTOP_MODE = process.argv.includes("--desktop");

function fail(msg) {
  process.stderr.write(`${msg}\n`);
  process.exit(1);
}

function log(msg) {
  process.stdout.write(`${msg}\n`);
}

if (!fs.existsSync(STANDALONE)) {
  fail(
    `${STANDALONE} does not exist. Run \`next build\` with \`output: "standalone"\` in next.config.ts first.`
  );
}

function deleteTree(target) {
  if (!fs.existsSync(target)) return;
  const stat = fs.lstatSync(target);
  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    fs.unlinkSync(target);
    return;
  }
  for (const entry of fs.readdirSync(target)) {
    deleteTree(path.join(target, entry));
  }
  fs.rmdirSync(target);
}

function copyDir(src, dest) {
  deleteTree(dest);
  fs.cpSync(src, dest, { recursive: true });
}

if (fs.existsSync(STATIC_SRC)) {
  copyDir(STATIC_SRC, STATIC_DEST);
  log(`Copied ${path.relative(ROOT, STATIC_SRC)} → ${path.relative(ROOT, STATIC_DEST)}`);
} else {
  fail(`${STATIC_SRC} missing — Next build seems incomplete.`);
}

if (fs.existsSync(PUBLIC_SRC)) {
  copyDir(PUBLIC_SRC, PUBLIC_DEST);
  log(`Copied ${path.relative(ROOT, PUBLIC_SRC)} → ${path.relative(ROOT, PUBLIC_DEST)}`);
} else {
  log("No public/ directory found, skipping.");
}

// Next.js's tracer follows JS imports but routinely misses native binaries
// reached via `require.resolve()` / path-export tricks (ffmpeg-static and
// @derhuerst/ffprobe-static both do this). Copy the binaries explicitly and
// preserve the executable bit.
function copyBinary(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  try {
    fs.chmodSync(dest, 0o755);
  } catch {
    // chmod can fail silently on Windows file systems; the executable bit
    // is encoded in the path/extension there instead.
  }
}

const FFMPEG_SRC_DIR = path.join(ROOT, "node_modules", "ffmpeg-static");
const FFMPEG_DEST_DIR = path.join(STANDALONE, "node_modules", "ffmpeg-static");
const FFPROBE_SRC_DIR = path.join(
  ROOT,
  "node_modules",
  "@derhuerst",
  "ffprobe-static"
);
const FFPROBE_DEST_DIR = path.join(
  STANDALONE,
  "node_modules",
  "@derhuerst",
  "ffprobe-static"
);

if (DESKTOP_MODE) {
  deleteTree(FFMPEG_DEST_DIR);
  deleteTree(FFPROBE_DEST_DIR);
  deleteTree(path.join(STANDALONE, "node_modules", "sharp"));
  deleteTree(path.join(STANDALONE, "node_modules", "@img"));
  log("Desktop bundle: removed downloaded static media binaries and unused Sharp native modules.");
  log("Standalone bundle is ready for the desktop packager.");
  process.exit(0);
}

const ffmpegName = process.platform === "win32" ? "ffmpeg.exe" : "ffmpeg";
const ffmpegSrc = path.join(FFMPEG_SRC_DIR, ffmpegName);
const ffmpegDest = path.join(FFMPEG_DEST_DIR, ffmpegName);

if (fs.existsSync(ffmpegSrc)) {
  copyBinary(ffmpegSrc, ffmpegDest);
  log(`Copied ${path.relative(ROOT, ffmpegSrc)} → ${path.relative(ROOT, ffmpegDest)}`);
} else {
  log(`ffmpeg-static binary missing at ${ffmpegSrc} — video conversion will rely on system ffmpeg.`);
}

const probeName = process.platform === "win32" ? "ffprobe.exe" : "ffprobe";
const probeSrc = path.join(FFPROBE_SRC_DIR, probeName);
const probeDest = path.join(FFPROBE_DEST_DIR, probeName);

if (fs.existsSync(probeSrc)) {
  copyBinary(probeSrc, probeDest);
  log(`Copied ${path.relative(ROOT, probeSrc)} → ${path.relative(ROOT, probeDest)}`);
} else {
  log(`@derhuerst/ffprobe-static binary missing at ${probeSrc} — video conversion will rely on system ffprobe.`);
}

// Carry the JS entry points + package.json so `require("ffmpeg-static")`
// resolves correctly from the standalone server (Next.js usually traces
// these but we don't want to depend on it for a feature that breaks
// silently when the require fails).
function copyIfMissing(srcDir, destDir, name) {
  const src = path.join(srcDir, name);
  const dest = path.join(destDir, name);
  if (fs.existsSync(src) && !fs.existsSync(dest)) {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
  }
}
copyIfMissing(FFMPEG_SRC_DIR, FFMPEG_DEST_DIR, "index.js");
copyIfMissing(FFMPEG_SRC_DIR, FFMPEG_DEST_DIR, "package.json");
copyIfMissing(FFMPEG_SRC_DIR, FFMPEG_DEST_DIR, "LICENSE");
copyIfMissing(FFPROBE_SRC_DIR, FFPROBE_DEST_DIR, "index.js");
copyIfMissing(FFPROBE_SRC_DIR, FFPROBE_DEST_DIR, "package.json");
copyIfMissing(FFPROBE_SRC_DIR, FFPROBE_DEST_DIR, "LICENSE");

log("Standalone bundle is ready for publish.");
