import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { createGzip, createGunzip } from "node:zlib";
import { pipeline } from "node:stream/promises";
import * as tar from "tar-stream";

import {
  createBackupArchive,
  createNote,
  listNotes,
  readAudioStream,
  readConfig,
  restoreBackupArchive,
  writeAudio,
  writeConfig,
} from "../../src/lib/server/storage";

async function deleteTree(target: string): Promise<void> {
  let stat;
  try {
    stat = await fs.lstat(target);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
    throw error;
  }
  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    await fs.unlink(target);
    return;
  }
  for (const entry of await fs.readdir(target)) {
    await deleteTree(path.join(target, entry));
  }
  await fs.rmdir(target);
}

async function collect(stream: Readable): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

async function archiveEntries(archive: Buffer): Promise<Map<string, Buffer>> {
  const entries = new Map<string, Buffer>();
  const extract = tar.extract();
  extract.on("entry", (header, stream, next) => {
    void collect(stream).then(
      (data) => {
        entries.set(header.name, data);
        next();
      },
      (error) => next(error)
    );
  });
  await pipeline(Readable.from(archive), createGunzip(), extract);
  return entries;
}

async function makeArchive(entries: Array<{ name: string; body: string }>) {
  const pack = tar.pack();
  const output = pack.pipe(createGzip());
  for (const entry of entries) {
    const body = Buffer.from(entry.body);
    pack.entry({ name: entry.name, type: "file", size: body.length }, body);
  }
  pack.finalize();
  return collect(output);
}

function noteInput(id: string, title: string) {
  return {
    id,
    title,
    content: `${title} content`,
    type: "transcription" as const,
    source: "upload" as const,
    audioFileName: `${title}.mp3`,
    durationSeconds: 1,
    language: "en",
    tags: ["backup"],
    metadata: {},
  };
}

test("complete backup round-trips notes, audio, and settings without a key", async () => {
  const previousHome = process.env.SCRIBER_HOME;
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "scriber-backup-test-"));
  const sourceHome = path.join(root, "source");
  const destinationHome = path.join(root, "destination");
  const firstId = "11111111-1111-4111-8111-111111111111";
  const secondId = "22222222-2222-4222-8222-222222222222";
  const extraId = "33333333-3333-4333-8333-333333333333";

  try {
    process.env.SCRIBER_HOME = sourceHome;
    await writeConfig({
      theme: "dark",
      dictionary: ["Sobat HAPE", "Scriber"],
      defaults: {
        languageCode: "id",
        diarize: true,
        numSpeakers: 2,
        tagAudioEvents: true,
      },
    });
    await createNote({
      ...noteInput(firstId, "First"),
      content: "[laughs] First content",
      metadata: {
        hasAudioEventTags: true,
        words: [
          {
            text: "[laughs]",
            start: 0,
            end: 0.2,
            type: "audio_event",
            logprob: -0.05,
          },
          { text: " ", start: 0.2, end: 0.2, type: "spacing" },
          { text: "First", start: 0.2, end: 0.6, type: "word" },
          { text: " ", start: 0.6, end: 0.6, type: "spacing" },
          { text: "content", start: 0.6, end: 1, type: "word" },
        ],
      },
    });
    await createNote(noteInput(secondId, "Second"));
    await writeAudio(firstId, Buffer.from("first-audio"), "audio/mpeg");
    await writeAudio(secondId, Buffer.from("second-audio"), "audio/mpeg");

    const { stream } = await createBackupArchive("9.9.9-test");
    const archive = await collect(stream);
    const entries = await archiveEntries(archive);
    const manifest = JSON.parse(entries.get("manifest.json")!.toString("utf8"));
    const backedUpConfig = JSON.parse(
      entries.get("config.json")!.toString("utf8")
    );
    assert.equal(manifest.format, "scriber-backup");
    assert.equal(manifest.formatVersion, 1);
    assert.equal(manifest.noteCount, 2);
    assert.equal(manifest.audioFileCount, 2);
    assert.equal(manifest.includesApiKey, false);
    assert.equal(backedUpConfig.apiKey, undefined);
    assert.equal(entries.size, 6);

    process.env.SCRIBER_HOME = destinationHome;
    await createNote(noteInput(firstId, "Existing duplicate"));
    await createNote(noteInput(extraId, "Destination only"));

    const merged = await restoreBackupArchive(Readable.from(archive), "merge");
    assert.equal(merged.notesImported, 1);
    assert.equal(merged.notesSkipped, 1);
    assert.equal((await listNotes()).length, 3);
    assert.equal((await readConfig()).theme, "dark");
    assert.deepEqual((await readConfig()).dictionary, ["Sobat HAPE", "Scriber"]);

    const secondAudio = await readAudioStream(secondId);
    assert.ok(secondAudio);
    assert.deepEqual(
      await collect(secondAudio.stream),
      Buffer.from("second-audio")
    );

    const replaced = await restoreBackupArchive(Readable.from(archive), "replace");
    assert.equal(replaced.notesImported, 2);
    assert.equal(replaced.audioImported, 2);
    assert.deepEqual(
      (await listNotes()).map((note) => note.id).sort(),
      [firstId, secondId]
    );
    const restoredConfig = await readConfig();
    assert.equal(restoredConfig.apiKey, undefined);
    assert.equal(restoredConfig.theme, "dark");
    const restoredAudioEventNote = (await listNotes()).find(
      (note) => note.id === firstId
    );
    assert.equal(restoredAudioEventNote?.metadata.words?.[0].type, "audio_event");
    assert.equal(restoredAudioEventNote?.metadata.words?.[0].logprob, -0.05);
    assert.equal(
      (await fs.stat(path.join(destinationHome, "config.json"))).mode & 0o777,
      0o600
    );
  } finally {
    if (previousHome === undefined) delete process.env.SCRIBER_HOME;
    else process.env.SCRIBER_HOME = previousHome;
    await deleteTree(root);
  }
});

test("restore rejects path traversal before changing current data", async () => {
  const previousHome = process.env.SCRIBER_HOME;
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "scriber-backup-bad-"));
  const existingId = "44444444-4444-4444-8444-444444444444";
  try {
    process.env.SCRIBER_HOME = root;
    await createNote(noteInput(existingId, "Must survive"));
    const archive = await makeArchive([
      { name: "../outside.txt", body: "unsafe" },
    ]);
    await assert.rejects(
      restoreBackupArchive(Readable.from(archive), "replace"),
      /Unsafe or invalid backup entry/
    );
    assert.deepEqual((await listNotes()).map((note) => note.id), [existingId]);
    await assert.rejects(fs.access(path.join(path.dirname(root), "outside.txt")));
  } finally {
    if (previousHome === undefined) delete process.env.SCRIBER_HOME;
    else process.env.SCRIBER_HOME = previousHome;
    await deleteTree(root);
  }
});

test("restore rejects archives that try to include an API key", async () => {
  const previousHome = process.env.SCRIBER_HOME;
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "scriber-backup-secret-"));
  try {
    process.env.SCRIBER_HOME = root;
    const archive = await makeArchive([
      {
        name: "manifest.json",
        body: JSON.stringify({
          format: "scriber-backup",
          formatVersion: 1,
          appVersion: "test",
          createdAt: new Date().toISOString(),
          noteCount: 0,
          audioFileCount: 0,
          includesApiKey: false,
        }),
      },
      { name: "config.json", body: JSON.stringify({ apiKey: "sk_forbidden" }) },
    ]);
    await assert.rejects(
      restoreBackupArchive(Readable.from(archive), "merge"),
      /must not contain an API key/
    );
    assert.equal((await readConfig()).apiKey, undefined);
  } finally {
    if (previousHome === undefined) delete process.env.SCRIBER_HOME;
    else process.env.SCRIBER_HOME = previousHome;
    await deleteTree(root);
  }
});
