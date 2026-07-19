#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */

const path = require("node:path");
const fs = require("node:fs");
const esbuild = require("esbuild");

const ROOT = path.resolve(__dirname, "..");
const ENTRY = path.join(ROOT, "src", "cli", "index.ts");
const OUT_DIR = path.join(ROOT, ".scriber-cli");
const OUT_FILE = path.join(OUT_DIR, "index.cjs");

function log(msg) {
  process.stdout.write(`${msg}\n`);
}

fs.mkdirSync(OUT_DIR, { recursive: true });

// Shim `server-only` — the package is a build-time sentinel for Next.js
// client bundles; at Node runtime it's a no-op, so replace it with an empty
// module to avoid esbuild resolving a React-server-conditional variant that
// may throw.
const serverOnlyShim = path.join(OUT_DIR, "server-only-shim.js");
fs.writeFileSync(serverOnlyShim, "module.exports = {};\n");

const result = esbuild.buildSync({
  entryPoints: [ENTRY],
  bundle: true,
  platform: "node",
  target: "node20",
  format: "cjs",
  outfile: OUT_FILE,
  logLevel: "warning",
  tsconfig: path.join(ROOT, "tsconfig.json"),
  alias: {
    "server-only": serverOnlyShim,
  },
  // ffmpeg-static and @derhuerst/ffprobe-static derive their binary paths from
  // `__dirname`. Bundling them rewrites __dirname to .scriber-cli/, breaking
  // the lookup. Marking them external keeps the require() literal so Node's
  // module resolver finds the real package location at runtime.
  external: ["ffmpeg-static", "@derhuerst/ffprobe-static"],
  // Keep node builtins external (default), bundle everything else so the
  // published tarball needs no extra deps at CLI runtime.
});

if (result.errors && result.errors.length > 0) {
  process.stderr.write("esbuild failed\n");
  process.exit(1);
}

const stat = fs.statSync(OUT_FILE);
log(
  `CLI bundle: ${path.relative(ROOT, OUT_FILE)} (${(stat.size / 1024).toFixed(1)} KB)`
);
