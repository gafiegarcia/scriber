#!/usr/bin/env node
/* eslint-disable @typescript-eslint/no-require-imports */

const { execFileSync } = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const [ffmpeg, ffprobe] = process.argv.slice(2);
if (!ffmpeg || !ffprobe) {
  process.stderr.write("Usage: verify-ffmpeg-functional.js <ffmpeg> <ffprobe>\n");
  process.exit(2);
}

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "scriber-ffmpeg-verify-"));
const wavPath = path.join(tempDir, "input.wav");
const rgbPath = path.join(tempDir, "video.rgb");
const mp4Path = path.join(tempDir, "input.mp4");
const m4aPath = path.join(tempDir, "output.m4a");

function run(binary, args) {
  return execFileSync(binary, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function makeWav() {
  const sampleRate = 44_100;
  const channels = 2;
  const sampleCount = sampleRate;
  const dataBytes = sampleCount * channels * 2;
  const wav = Buffer.alloc(44 + dataBytes);

  wav.write("RIFF", 0);
  wav.writeUInt32LE(36 + dataBytes, 4);
  wav.write("WAVEfmt ", 8);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(channels, 22);
  wav.writeUInt32LE(sampleRate, 24);
  wav.writeUInt32LE(sampleRate * channels * 2, 28);
  wav.writeUInt16LE(channels * 2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write("data", 36);
  wav.writeUInt32LE(dataBytes, 40);

  for (let i = 0; i < sampleCount; i += 1) {
    const sample = Math.round(Math.sin((i * 2 * Math.PI * 440) / sampleRate) * 12_000);
    wav.writeInt16LE(sample, 44 + i * 4);
    wav.writeInt16LE(sample, 46 + i * 4);
  }
  fs.writeFileSync(wavPath, wav);
}

function makeRawVideo() {
  const width = 64;
  const height = 64;
  const frames = 25;
  const rgb = Buffer.alloc(width * height * 3 * frames);
  for (let frame = 0; frame < frames; frame += 1) {
    for (let pixel = 0; pixel < width * height; pixel += 1) {
      const offset = (frame * width * height + pixel) * 3;
      rgb[offset] = (frame * 9) % 256;
      rgb[offset + 1] = (pixel * 3) % 256;
      rgb[offset + 2] = 180;
    }
  }
  fs.writeFileSync(rgbPath, rgb);
}

function probe(file) {
  return JSON.parse(
    run(ffprobe, ["-v", "error", "-show_streams", "-of", "json", file])
  );
}

try {
  makeWav();
  makeRawVideo();

  run(ffmpeg, [
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
    "-c:v",
    "mpeg4",
    "-q:v",
    "5",
    "-c:a",
    "aac",
    "-shortest",
    "-movflags",
    "+faststart",
    mp4Path,
  ]);

  const source = probe(mp4Path);
  if (!source.streams.some((stream) => stream.codec_type === "video")) {
    throw new Error("ffprobe did not find the synthetic video stream");
  }
  if (!source.streams.some((stream) => stream.codec_type === "audio")) {
    throw new Error("ffprobe did not find the synthetic audio stream");
  }

  run(ffmpeg, [
    "-y",
    "-i",
    mp4Path,
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
    m4aPath,
  ]);

  const m4a = fs.readFileSync(m4aPath);
  if (m4a.length < 1024 || m4a.subarray(4, 8).toString("ascii") !== "ftyp") {
    throw new Error("converted M4A is missing or malformed");
  }
  const converted = probe(m4aPath);
  const audio = converted.streams.find((stream) => stream.codec_type === "audio");
  if (!audio || audio.codec_name !== "aac" || audio.channels !== 1 || audio.sample_rate !== "48000") {
    throw new Error(`unexpected converted audio metadata: ${JSON.stringify(audio)}`);
  }

  process.stdout.write(`Functional FFmpeg check passed (${crypto.randomUUID().slice(0, 8)}).\n`);
} finally {
  for (const file of [wavPath, rgbPath, mp4Path, m4aPath]) {
    try {
      fs.unlinkSync(file);
    } catch (error) {
      if (error && error.code !== "ENOENT") throw error;
    }
  }
  fs.rmdirSync(tempDir);
}
