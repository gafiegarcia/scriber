import { spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { assertFfmpegAvailable } from "./ffmpeg-runtime";

export class AudioExtractError extends Error {
  stderr: string;
  constructor(message: string, stderr: string) {
    super(message);
    this.name = "AudioExtractError";
    this.stderr = stderr;
  }
}

export const VIDEO_EXTENSIONS = new Set([
  "mp4",
  "mov",
  "mkv",
  "webm",
  "m4v",
  "avi",
]);

interface RunResult {
  stdout: string;
  stderr: string;
  code: number;
}

function runProcess(
  command: string,
  args: string[],
  opts: { cwd?: string } = {}
): Promise<RunResult> {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd: opts.cwd,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];
    child.stdout.on("data", (c: Buffer) => stdoutChunks.push(c));
    child.stderr.on("data", (c: Buffer) => stderrChunks.push(c));
    child.on("error", (err) => {
      resolve({
        stdout: Buffer.concat(stdoutChunks).toString("utf8"),
        stderr:
          Buffer.concat(stderrChunks).toString("utf8") +
          `\n[spawn error] ${err.message}`,
        code: -1,
      });
    });
    child.on("close", (code) => {
      resolve({
        stdout: Buffer.concat(stdoutChunks).toString("utf8"),
        stderr: Buffer.concat(stderrChunks).toString("utf8"),
        code: code ?? -1,
      });
    });
  });
}

interface FfprobeStream {
  codec_type?: string;
  disposition?: { attached_pic?: number };
}

interface FfprobeOutput {
  streams?: FfprobeStream[];
}

/**
 * Returns true if the file at `inputPath` contains a non-cover-art video
 * stream. Audio-only files in video-shaped containers (e.g. Voice Memo .m4a
 * misnamed .mp4) return false. Cover-art "video" streams (album art) are
 * treated as not-a-video so we don't run a needless conversion.
 */
export async function hasVideoStream(inputPath: string): Promise<boolean> {
  const { ffprobe } = assertFfmpegAvailable();
  const { stdout, stderr, code } = await runProcess(ffprobe, [
    "-v",
    "error",
    "-print_format",
    "json",
    "-show_streams",
    inputPath,
  ]);
  if (code !== 0) {
    throw new AudioExtractError(
      `ffprobe failed (exit ${code})`,
      stderr || "(no stderr)"
    );
  }
  let parsed: FfprobeOutput;
  try {
    parsed = JSON.parse(stdout) as FfprobeOutput;
  } catch {
    throw new AudioExtractError("ffprobe returned invalid JSON", stdout);
  }
  for (const s of parsed.streams ?? []) {
    if (s.codec_type === "video" && !s.disposition?.attached_pic) return true;
  }
  return false;
}

function tempPath(extension: string): string {
  const id = crypto.randomUUID();
  return path.join(os.tmpdir(), `scriber-${id}.${extension}`);
}

/**
 * Materialize an in-memory File / Blob to a temp file on disk so ffmpeg can
 * read it as an input path (M4A's moov atom needs random-access output, and
 * stdin streaming forces a second large Buffer in memory).
 */
export async function writeUploadToTemp(
  file: File,
  fallbackExt = "bin"
): Promise<{ path: string; cleanup: () => Promise<void> }> {
  const fromName = path.extname(file.name).slice(1).toLowerCase();
  const ext = fromName || fallbackExt;
  const target = tempPath(ext);
  const buffer = Buffer.from(await file.arrayBuffer());
  await fs.writeFile(target, buffer);
  return {
    path: target,
    cleanup: async () => {
      await fs.unlink(target).catch(() => {});
    },
  };
}

/**
 * Strip the video track and re-encode audio to AAC/M4A: 48 kHz mono, 96 kbps,
 * `+faststart` so the moov atom lands at the front (HTML5 audio plays cleanly
 * without buffering the whole file). Returns the temp output path and a
 * cleanup callback the caller MUST invoke in a finally.
 */
export async function extractAudio(
  inputPath: string
): Promise<{ outputPath: string; cleanup: () => Promise<void> }> {
  const { ffmpeg } = assertFfmpegAvailable();
  const outputPath = tempPath("m4a");
  const args = [
    "-y",
    "-i",
    inputPath,
    "-vn",
    "-c:a",
    "aac",
    "-b:a",
    "96k",
    "-ac",
    "1",
    "-ar",
    "48000",
    "-movflags",
    "+faststart",
    outputPath,
  ];
  const { stderr, code } = await runProcess(ffmpeg, args);
  if (code !== 0) {
    await fs.unlink(outputPath).catch(() => {});
    throw new AudioExtractError(
      `ffmpeg conversion failed (exit ${code})`,
      stderr || "(no stderr)"
    );
  }
  return {
    outputPath,
    cleanup: async () => {
      await fs.unlink(outputPath).catch(() => {});
    },
  };
}
