import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import fs from "node:fs";

// Resolve modules via Node's CJS resolver. We anchor on this file so that
// even after the route or CLI bundle is shifted around at build time, the
// require lookups still walk up to the real `node_modules/` install. We use
// __filename when available (CJS context, which is what Next.js server
// routes and the esbuild CLI bundle actually run as), with a CWD fallback
// purely so static analysis under ESM tooling doesn't trip.
const requireFromHere = createRequire(
  typeof __filename === "string" ? __filename : `${process.cwd()}/`
);

export interface FfmpegPaths {
  ffmpeg: string;
  ffprobe: string;
  source: "override" | "bundled" | "system";
}

let cached: FfmpegPaths | null | undefined;

function isExecutableFile(p: string | null | undefined): p is string {
  if (!p) return false;
  try {
    const stat = fs.statSync(p);
    if (!stat.isFile()) return false;
    fs.accessSync(p, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function tryOverride(): FfmpegPaths | null {
  const ffmpeg = process.env.SCRIBER_FFMPEG_PATH;
  const ffprobe = process.env.SCRIBER_FFPROBE_PATH;
  if (isExecutableFile(ffmpeg) && isExecutableFile(ffprobe)) {
    return { ffmpeg, ffprobe, source: "override" };
  }
  return null;
}

function tryBundled(): FfmpegPaths | null {
  let ffmpegPath: string | null = null;
  let ffprobePath: string | null = null;
  try {
    const mod = requireFromHere("ffmpeg-static") as unknown;
    if (typeof mod === "string") ffmpegPath = mod;
  } catch {
    // package missing — fall through to system
  }
  try {
    const mod = requireFromHere("@derhuerst/ffprobe-static") as unknown;
    if (typeof mod === "string") ffprobePath = mod;
  } catch {
    // package missing — fall through to system
  }
  if (isExecutableFile(ffmpegPath) && isExecutableFile(ffprobePath)) {
    return { ffmpeg: ffmpegPath, ffprobe: ffprobePath, source: "bundled" };
  }
  return null;
}

function whichBinary(name: string): string | null {
  const finder = process.platform === "win32" ? "where" : "which";
  try {
    const out = execFileSync(finder, [name], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const first = out.split(/\r?\n/).map((l) => l.trim()).find(Boolean);
    return first && isExecutableFile(first) ? first : null;
  } catch {
    return null;
  }
}

function trySystem(): FfmpegPaths | null {
  const ffmpeg = whichBinary("ffmpeg");
  const ffprobe = whichBinary("ffprobe");
  if (ffmpeg && ffprobe) return { ffmpeg, ffprobe, source: "system" };
  return null;
}

export function resolveFfmpegPaths(): FfmpegPaths | null {
  // The desktop wrapper points these at its signed app resources. Check on
  // every call so tests and embedding hosts can set them before launching a
  // conversion without being defeated by the fallback cache.
  const override = tryOverride();
  if (override) return override;
  if (cached !== undefined) return cached;
  cached = tryBundled() ?? trySystem();
  return cached;
}

export function assertFfmpegAvailable(): FfmpegPaths {
  const paths = resolveFfmpegPaths();
  if (!paths) {
    throw new Error(
      "Video support unavailable — ffmpeg/ffprobe were not found. Install ffmpeg (e.g. `brew install ffmpeg` on macOS) and try again."
    );
  }
  return paths;
}
