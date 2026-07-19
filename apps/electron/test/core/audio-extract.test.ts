import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { resolveFfmpegPaths } from "../../src/lib/core/ffmpeg-runtime";
import {
  extractAudio,
  hasVideoStream,
} from "../../src/lib/core/audio-extract";

const MACH_CPU_TYPE_ARM64 = 0x0100000c;

test("packaged ffprobe is a native Apple-silicon executable", async (t) => {
  if (process.platform !== "darwin" || process.arch !== "arm64") {
    t.skip("Apple-silicon architecture check");
    return;
  }

  const paths = resolveFfmpegPaths();
  assert.ok(paths, "expected packaged ffmpeg/ffprobe paths");
  assert.notEqual(paths.source, "system", "expected a bundled or desktop-resource binary");

  const header = await fs.readFile(paths.ffprobe);
  assert.ok(header.length >= 8, "ffprobe Mach-O header is truncated");
  assert.equal(
    header.readUInt32LE(4),
    MACH_CPU_TYPE_ARM64,
    "packaged ffprobe must be arm64, not an Intel binary that depends on Rosetta"
  );
});

test("desktop wrapper can override the ffmpeg resource paths", () => {
  const normal = resolveFfmpegPaths();
  assert.ok(normal, "expected ffmpeg/ffprobe paths");

  const previousFfmpeg = process.env.SCRIBER_FFMPEG_PATH;
  const previousFfprobe = process.env.SCRIBER_FFPROBE_PATH;
  process.env.SCRIBER_FFMPEG_PATH = normal.ffmpeg;
  process.env.SCRIBER_FFPROBE_PATH = normal.ffprobe;

  try {
    const overridden = resolveFfmpegPaths();
    assert.deepEqual(overridden, {
      ffmpeg: normal.ffmpeg,
      ffprobe: normal.ffprobe,
      source: "override",
    });
  } finally {
    if (previousFfmpeg === undefined) delete process.env.SCRIBER_FFMPEG_PATH;
    else process.env.SCRIBER_FFMPEG_PATH = previousFfmpeg;
    if (previousFfprobe === undefined) delete process.env.SCRIBER_FFPROBE_PATH;
    else process.env.SCRIBER_FFPROBE_PATH = previousFfprobe;
  }
});

function runFfmpeg(ffmpeg: string, args: string[]): Promise<number> {
  return new Promise((resolve, reject) => {
    const child = spawn(ffmpeg, args, { stdio: ["ignore", "ignore", "pipe"] });
    let stderr = "";
    child.stderr.on("data", (c: Buffer) => {
      stderr += c.toString("utf8");
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve(0);
      else reject(new Error(`ffmpeg exit ${code}\n${stderr}`));
    });
  });
}

async function makeSyntheticMp4(ffmpeg: string): Promise<string> {
  const target = path.join(os.tmpdir(), `scriber-test-${crypto.randomUUID()}.mp4`);
  const wavPath = `${target}.wav`;
  const rgbPath = `${target}.rgb`;

  // Generate the inputs ourselves so the release build does not need the
  // optional libavdevice/lavfi input. Encoding still uses only FFmpeg's native
  // AAC + MPEG-4 implementations (no GPL-only libx264 dependency).
  const sampleRate = 48_000;
  const wav = Buffer.alloc(44 + sampleRate * 2);
  wav.write("RIFF", 0);
  wav.writeUInt32LE(36 + sampleRate * 2, 4);
  wav.write("WAVEfmt ", 8);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(sampleRate, 24);
  wav.writeUInt32LE(sampleRate * 2, 28);
  wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write("data", 36);
  wav.writeUInt32LE(sampleRate * 2, 40);
  for (let i = 0; i < sampleRate; i += 1) {
    wav.writeInt16LE(
      Math.round(Math.sin((i * 2 * Math.PI * 440) / sampleRate) * 12_000),
      44 + i * 2
    );
  }

  const rgb = Buffer.alloc(64 * 64 * 3 * 25);
  for (let i = 0; i < rgb.length; i += 3) {
    rgb[i] = 220;
    rgb[i + 1] = (i / 3) % 256;
    rgb[i + 2] = 40;
  }

  await Promise.all([fs.writeFile(wavPath, wav), fs.writeFile(rgbPath, rgb)]);
  try {
    await runFfmpeg(ffmpeg, [
      "-y",
      "-f",
      "rawvideo",
      "-pixel_format",
      "rgb24",
      "-video_size",
      "64x64",
      "-framerate",
      "25",
      "-i",
      rgbPath,
      "-i",
      wavPath,
      "-c:a",
      "aac",
      "-c:v",
      "mpeg4",
      "-shortest",
      "-pix_fmt",
      "yuv420p",
      target,
    ]);
    return target;
  } finally {
    await Promise.all([
      fs.unlink(wavPath).catch(() => {}),
      fs.unlink(rgbPath).catch(() => {}),
    ]);
  }
}

test("audio-extract: detects + strips a synthetic video", async () => {
  const paths = resolveFfmpegPaths();
  if (!paths) {
    // Skip the test if neither bundled nor system ffmpeg is available — this
    // matches what end users would experience on a stripped install and we
    // don't want CI to fail in that environment.
    console.warn("Skipping audio-extract test: ffmpeg/ffprobe not resolvable.");
    return;
  }

  const fixture = await makeSyntheticMp4(paths.ffmpeg);
  try {
    assert.equal(await hasVideoStream(fixture), true, "should detect video stream");

    const { outputPath, cleanup } = await extractAudio(fixture);
    try {
      const buffer = await fs.readFile(outputPath);
      assert.ok(buffer.length >= 1024, `expected ≥1KB output, got ${buffer.length}`);
      // M4A magic: bytes 4..8 spell "ftyp".
      const magic = buffer.subarray(4, 8).toString("ascii");
      assert.equal(magic, "ftyp", `expected ftyp marker at offset 4, got "${magic}"`);
    } finally {
      await cleanup();
    }
  } finally {
    await fs.unlink(fixture).catch(() => {});
  }
});
