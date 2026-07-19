import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const REPO = process.cwd();
const BIN = path.join(REPO, "bin", "scriber.js");

function run(
  args: string[],
  env: Record<string, string> = {}
): { status: number | null; stdout: string; stderr: string } {
  const result = spawnSync("node", [BIN, ...args], {
    cwd: REPO,
    encoding: "utf8",
    env: { ...process.env, ...env },
  });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

test("transcribe --help prints usage and exits 0", () => {
  const r = run(["transcribe", "--help"]);
  assert.equal(r.status, 0);
  assert.match(r.stdout, /scriber transcribe/);
  assert.match(r.stdout, /USAGE/);
  assert.match(r.stdout, /-o, --output/);
});

test("missing input file exits 1 with clear stderr", () => {
  const r = run(["transcribe", "./definitely-does-not-exist.mp3"]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /Input not found/);
});

test("unsupported audio extension exits 1 before any API call", () => {
  const tmp = path.join(os.tmpdir(), `scriber-test-${Date.now()}.xyz`);
  fs.writeFileSync(tmp, "not-real-audio");
  try {
    const r = run(["transcribe", tmp]);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /Unsupported audio extension/);
  } finally {
    fs.unlinkSync(tmp);
  }
});

test("unsupported output extension exits 1 before reading the audio", () => {
  // Use a real-looking audio file path that doesn't need to exist —
  // output validation runs first.
  const tmp = path.join(os.tmpdir(), `scriber-test-${Date.now()}.mp3`);
  fs.writeFileSync(tmp, "pretend");
  try {
    const r = run(["transcribe", tmp, "-o", "/tmp/out.bogus"]);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /Unsupported output format/);
  } finally {
    fs.unlinkSync(tmp);
  }
});

test("batch input (2+ files) is rejected with a clear message", () => {
  const a = path.join(os.tmpdir(), `scriber-a-${Date.now()}.mp3`);
  const b = path.join(os.tmpdir(), `scriber-b-${Date.now()}.mp3`);
  fs.writeFileSync(a, "x");
  fs.writeFileSync(b, "x");
  try {
    const r = run(["transcribe", a, b]);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /Batch input is not supported/);
  } finally {
    fs.unlinkSync(a);
    fs.unlinkSync(b);
  }
});

test("-o with no target path is rejected", () => {
  const tmp = path.join(os.tmpdir(), `scriber-test-${Date.now()}.mp3`);
  fs.writeFileSync(tmp, "x");
  try {
    const r = run(["transcribe", tmp, "-o"]);
    assert.equal(r.status, 1);
    assert.match(r.stderr, /requires at least one file path/);
  } finally {
    fs.unlinkSync(tmp);
  }
});

test("no API key configured exits 1 with guidance to run the web app", () => {
  const scriberHome = fs.mkdtempSync(path.join(os.tmpdir(), "scriber-home-"));
  const audio = path.join(os.tmpdir(), `scriber-audio-${Date.now()}.mp3`);
  fs.writeFileSync(audio, "pretend-audio");
  try {
    const r = run(["transcribe", audio], { SCRIBER_HOME: scriberHome });
    assert.equal(r.status, 1);
    assert.match(r.stderr, /No ElevenLabs API key/);
    assert.match(r.stderr, /Settings/); // points user to the web app
  } finally {
    fs.unlinkSync(audio);
    fs.rmSync(scriberHome, { recursive: true, force: true });
  }
});

test("credits --help prints usage and exits 0", () => {
  const r = run(["credits", "--help"]);
  assert.equal(r.status, 0);
  assert.match(r.stdout, /scriber credits/);
  assert.match(r.stdout, /USAGE/);
});

test("credits with no API key exits 1 with guidance", () => {
  const scriberHome = fs.mkdtempSync(path.join(os.tmpdir(), "scriber-home-"));
  try {
    const r = run(["credits"], { SCRIBER_HOME: scriberHome });
    assert.equal(r.status, 1);
    assert.match(r.stderr, /No ElevenLabs API key/);
    assert.match(r.stderr, /Settings/);
  } finally {
    fs.rmSync(scriberHome, { recursive: true, force: true });
  }
});

test("unknown flag is rejected by parseArgs", () => {
  const tmp = path.join(os.tmpdir(), `scriber-test-${Date.now()}.mp3`);
  fs.writeFileSync(tmp, "x");
  try {
    const r = run(["transcribe", tmp, "--not-a-real-flag"]);
    assert.equal(r.status, 1);
    assert.notEqual(r.stderr.trim(), "");
  } finally {
    fs.unlinkSync(tmp);
  }
});
