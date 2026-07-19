import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const REPO = process.cwd();
const BIN = path.join(REPO, "bin", "scriber.js");
const AUDIO_DIR = path.join(os.homedir(), ".scriber", "audio");
const E2E_ENABLED = process.env.SCRIBER_E2E === "1";

const SUPPORTED = new Set([".webm", ".m4a", ".mp3", ".wav", ".ogg", ".flac", ".mp4"]);

function findSmallestAudio(): string | null {
  if (!fs.existsSync(AUDIO_DIR)) return null;
  const entries = fs
    .readdirSync(AUDIO_DIR)
    .filter((name) => SUPPORTED.has(path.extname(name).toLowerCase()))
    .map((name) => {
      const full = path.join(AUDIO_DIR, name);
      return { path: full, size: fs.statSync(full).size };
    })
    .sort((a, b) => a.size - b.size);
  return entries[0]?.path ?? null;
}

test(
  "e2e: transcribe a real audio file end-to-end",
  { skip: !E2E_ENABLED ? "set SCRIBER_E2E=1 to run (makes a real ElevenLabs API call)" : undefined },
  async () => {
    const audio = findSmallestAudio();
    assert.ok(audio, `no audio found in ${AUDIO_DIR} — record something in the web app first`);

    const outDir = fs.mkdtempSync(path.join(os.tmpdir(), "scriber-e2e-"));
    const outJson = path.join(outDir, "out.json");
    const outSrt = path.join(outDir, "out.srt");
    const outMd = path.join(outDir, "out.md");
    const outTxt = path.join(outDir, "out.txt");

    try {
      const result = spawnSync(
        "node",
        [
          BIN,
          "transcribe",
          audio,
          "--no-store",
          "-o",
          outJson,
          outSrt,
          outMd,
          outTxt,
        ],
        { cwd: REPO, encoding: "utf8" }
      );

      assert.equal(result.status, 0, `exit non-zero. stderr:\n${result.stderr}`);

      // --- stdout JSON ---
      const payload = JSON.parse(result.stdout);
      assert.equal(typeof payload.text, "string");
      assert.ok(payload.text.length > 0, "transcript should be non-empty");
      assert.equal(typeof payload.language_code, "string");
      assert.ok(payload.language_code.length > 0);
      assert.equal(typeof payload.language_probability, "number");
      assert.ok(Array.isArray(payload.words));
      assert.ok(payload.words.length > 0, "expected at least one word");

      const firstWord = payload.words[0];
      assert.equal(typeof firstWord.text, "string");
      assert.equal(typeof firstWord.start, "number");
      assert.equal(typeof firstWord.end, "number");
      assert.ok(firstWord.end >= firstWord.start);

      assert.equal(typeof payload.id, "string");
      assert.match(payload.id, /^[0-9a-f-]{36}$/);
      assert.equal(payload.noteId, null, "--no-store should leave noteId null");
      assert.deepEqual(payload.outputs, [outJson, outSrt, outMd, outTxt]);
      assert.equal(typeof payload.createdAt, "string");

      // --- stderr progress ---
      assert.match(result.stderr, /Transcribing/);
      assert.match(result.stderr, /Transcription complete/);
      assert.doesNotMatch(
        result.stderr,
        /Note saved/,
        "--no-store should NOT produce a Note-saved line"
      );

      // --- written files ---
      const jsonFile = JSON.parse(fs.readFileSync(outJson, "utf8"));
      assert.equal(jsonFile.text, payload.text);
      assert.deepEqual(jsonFile.outputs, payload.outputs);

      const srt = fs.readFileSync(outSrt, "utf8");
      assert.match(
        srt,
        /^1\n\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}\n/,
        "SRT must start with cue 1 and valid timestamps"
      );

      const md = fs.readFileSync(outMd, "utf8");
      assert.match(md, /^---\n/);
      assert.match(md, /language: /);
      assert.match(md, /languageProbability: /);
      assert.match(md, /createdAt: /);

      const txt = fs.readFileSync(outTxt, "utf8");
      assert.equal(txt.trimEnd(), payload.text.trimEnd());
    } finally {
      fs.rmSync(outDir, { recursive: true, force: true });
    }
  }
);

test(
  "e2e: --no-store really does leave ~/.scriber/notes/ untouched",
  { skip: !E2E_ENABLED ? "set SCRIBER_E2E=1 to run" : undefined },
  async () => {
    const audio = findSmallestAudio();
    assert.ok(audio);

    const notesDir = path.join(os.homedir(), ".scriber", "notes");
    const before = fs.existsSync(notesDir) ? fs.readdirSync(notesDir).sort() : [];

    const outDir = fs.mkdtempSync(path.join(os.tmpdir(), "scriber-e2e-"));
    try {
      const r = spawnSync(
        "node",
        [BIN, "transcribe", audio, "--no-store", "-q", "-o", path.join(outDir, "o.json")],
        { cwd: REPO, encoding: "utf8" }
      );
      assert.equal(r.status, 0, `exit non-zero. stderr:\n${r.stderr}`);
      // --quiet suppresses progress; stderr should be empty on success
      assert.equal(r.stderr, "", "--quiet should silence stderr on success");

      const after = fs.existsSync(notesDir) ? fs.readdirSync(notesDir).sort() : [];
      assert.deepEqual(after, before, "notes dir must be unchanged under --no-store");
    } finally {
      fs.rmSync(outDir, { recursive: true, force: true });
    }
  }
);
