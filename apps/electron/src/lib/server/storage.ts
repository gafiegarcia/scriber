import "server-only";

import fs from "node:fs/promises";
import { createWriteStream, createReadStream, type ReadStream } from "node:fs";
import crypto from "node:crypto";
import path from "node:path";
import os from "node:os";
import { pipeline } from "node:stream/promises";
import { Readable } from "node:stream";
import { createGzip, createGunzip } from "node:zlib";
import * as tar from "tar-stream";
import type { Note, CreateNoteInput, UpdateNoteInput, TranscribeOptions } from "@/lib/types";
import {
  createMacOsKeychainApiKeyStore,
  usesMacOsKeychain,
  type ApiKeySecretStore,
} from "@/lib/server/secret-store";

export { getApiKeyStorageKind } from "@/lib/server/secret-store";

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

function home() {
  return process.env.SCRIBER_HOME || path.join(os.homedir(), ".scriber");
}

const NOTES_DIR = () => path.join(home(), "notes");
const AUDIO_DIR = () => path.join(home(), "audio");
const CONFIG_PATH = () => path.join(home(), "config.json");

async function ensureDirs() {
  await fs.mkdir(NOTES_DIR(), { recursive: true });
  await fs.mkdir(AUDIO_DIR(), { recursive: true });
}

// ---------------------------------------------------------------------------
// Filename derivation
// ---------------------------------------------------------------------------

function shortId(id: string): string {
  return id.replace(/-/g, "").slice(0, 8);
}

function timestampFromIso(iso: string): string {
  // 2026-04-20T14:30:00.123Z → 2026-04-20T14-30-00
  return iso.slice(0, 19).replace(/:/g, "-");
}

function noteFilename(note: Pick<Note, "id" | "createdAt">): string {
  return `${timestampFromIso(note.createdAt)}_${shortId(note.id)}.json`;
}

function slugify(s: string): string {
  return s
    .toLowerCase()
    .replace(/\.[^.]+$/, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
}

function audioFilename(
  note: Pick<Note, "id" | "createdAt" | "audioFileName" | "source">,
  ext: string
): string {
  const base = `${timestampFromIso(note.createdAt)}_${shortId(note.id)}`;
  if (note.source === "upload" && note.audioFileName) {
    const slug = slugify(note.audioFileName);
    if (slug) return `${base}__${slug}.${ext}`;
  }
  return `${base}.${ext}`;
}

async function findNoteFile(id: string): Promise<string | null> {
  await ensureDirs();
  const short = shortId(id);
  const entries = await fs.readdir(NOTES_DIR());
  const matches = entries.filter((e) => e.endsWith(`_${short}.json`));
  if (matches.length === 0) return null;
  if (matches.length === 1) return path.join(NOTES_DIR(), matches[0]);
  // Collision: disambiguate by reading files and matching full id
  for (const m of matches) {
    const full = path.join(NOTES_DIR(), m);
    try {
      const data = JSON.parse(await fs.readFile(full, "utf8"));
      if (data.id === id) return full;
    } catch {
      // Skip unreadable files
    }
  }
  return null;
}

async function findAudioFile(id: string): Promise<string | null> {
  await ensureDirs();
  const short = shortId(id);
  const entries = await fs.readdir(AUDIO_DIR());
  // Audio filenames: <timestamp>_<shortid>[__<slug>].<ext>
  const match = entries.find((e) => {
    const namePart = e.split("__")[0].replace(/\.[^.]+$/, "");
    return namePart.endsWith(`_${short}`);
  });
  return match ? path.join(AUDIO_DIR(), match) : null;
}

// ---------------------------------------------------------------------------
// Atomic writes
// ---------------------------------------------------------------------------

async function atomicWrite(target: string, data: string | Buffer) {
  const parent = path.dirname(target);
  await fs.mkdir(parent, { recursive: true, mode: 0o700 });
  await fs.chmod(parent, 0o700);
  const tmp = `${target}.${process.pid}.${crypto.randomUUID()}.tmp`;
  try {
    await fs.writeFile(tmp, data, { mode: 0o600 });
    await fs.rename(tmp, target);
    await fs.chmod(target, 0o600);
  } catch (error) {
    await fs.unlink(tmp).catch(() => {});
    throw error;
  }
}

async function atomicCopy(source: string, target: string) {
  const parent = path.dirname(target);
  await fs.mkdir(parent, { recursive: true, mode: 0o700 });
  await fs.chmod(parent, 0o700);
  const tmp = `${target}.${process.pid}.${crypto.randomUUID()}.tmp`;
  try {
    await pipeline(
      createReadStream(source),
      createWriteStream(tmp, { mode: 0o600 })
    );
    await fs.rename(tmp, target);
  } catch (error) {
    await fs.unlink(tmp).catch(() => {});
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

export interface ScriberConfig {
  apiKey?: string;
  defaults?: TranscribeOptions;
  dictionary?: string[];
  transcribeModel?: string;
  theme?: "light" | "dark" | "system";
}

const DEFAULT_CONFIG: ScriberConfig = {
  defaults: {
    languageCode: "auto",
    diarize: false,
    numSpeakers: null,
    tagAudioEvents: false,
  },
  dictionary: [],
  transcribeModel: "scribe_v2",
  theme: "system",
};

interface ConfigFileState {
  config: ScriberConfig;
  apiKey?: string;
  hasApiKeyField: boolean;
}

export interface ConfigStore {
  read(): Promise<ScriberConfig>;
  write(patch: Partial<ScriberConfig>): Promise<ScriberConfig>;
}

async function readConfigFile(configPath: string): Promise<ConfigFileState> {
  try {
    const raw = await fs.readFile(configPath, "utf8");
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("Scriber config.json must contain a JSON object");
    }
    const typed = parsed as ScriberConfig;
    const hasApiKeyField = Object.hasOwn(typed, "apiKey");
    const apiKey =
      typeof typed.apiKey === "string" && typed.apiKey.trim()
        ? typed.apiKey.trim()
        : undefined;
    const config = { ...typed };
    delete config.apiKey;
    return { config, apiKey, hasApiKeyField };
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      return { config: {}, hasApiKeyField: false };
    }
    throw err;
  }
}

export function createConfigStore(options: {
  configPath: string;
  secretStore: ApiKeySecretStore | null;
}): ConfigStore {
  const { configPath, secretStore } = options;
  let operationQueue: Promise<void> = Promise.resolve();
  let pendingRead: Promise<ScriberConfig> | undefined;

  function serialized<T>(operation: () => Promise<T>): Promise<T> {
    const result = operationQueue.then(operation, operation);
    operationQueue = result.then(
      () => undefined,
      () => undefined
    );
    return result;
  }

  async function persist(config: ScriberConfig) {
    await atomicWrite(configPath, JSON.stringify(config, null, 2));
  }

  async function readUnlocked(): Promise<ScriberConfig> {
    const file = await readConfigFile(configPath);
    const base = { ...DEFAULT_CONFIG, ...file.config };

    if (!secretStore) {
      return { ...base, ...(file.apiKey ? { apiKey: file.apiKey } : {}) };
    }

    const storedKey = await secretStore.read();
    if (storedKey) {
      // Keychain is authoritative. Remove any stale plaintext field left by an
      // older release, even if it contains a different or empty value.
      if (file.hasApiKeyField) await persist(file.config);
      return { ...base, apiKey: storedKey };
    }

    if (file.apiKey) {
      // One-time migration is deliberately ordered Keychain first, file
      // second: an interrupted migration may briefly leave two copies, but it
      // can never erase the only copy of the key.
      await secretStore.write(file.apiKey);
      await persist(file.config);
      return { ...base, apiKey: file.apiKey };
    }

    if (file.hasApiKeyField) await persist(file.config);
    return base;
  }

  async function writeUnlocked(
    patch: Partial<ScriberConfig>
  ): Promise<ScriberConfig> {
    const current = await readUnlocked();
    const patchesApiKey = Object.hasOwn(patch, "apiKey");
    const patchedKey =
      patchesApiKey && typeof patch.apiKey === "string" && patch.apiKey.trim()
        ? patch.apiKey.trim()
        : undefined;
    const next: ScriberConfig = { ...current, ...patch };

    if (secretStore) {
      if (patchesApiKey) {
        if (patchedKey) await secretStore.write(patchedKey);
        else await secretStore.delete();
      }
      delete next.apiKey;
      await persist(next);
      const effectiveKey = patchesApiKey ? patchedKey : current.apiKey;
      return { ...next, ...(effectiveKey ? { apiKey: effectiveKey } : {}) };
    }

    if (patchesApiKey) {
      if (patchedKey) next.apiKey = patchedKey;
      else delete next.apiKey;
    }
    await persist(next);
    return next;
  }

  function readSerialized(): Promise<ScriberConfig> {
    // Several providers request config during the same initial render. Share
    // that operation so a locked Keychain produces one prompt/error, not one
    // per HTTP request. Later, deliberate retries still start a fresh read.
    if (pendingRead) return pendingRead;
    const currentRead = serialized(readUnlocked);
    pendingRead = currentRead;
    const clear = () => {
      if (pendingRead === currentRead) pendingRead = undefined;
    };
    void currentRead.then(clear, clear);
    return currentRead;
  }

  return {
    read: readSerialized,
    write: (patch) => serialized(() => writeUnlocked(patch)),
  };
}

let cachedDefaultConfigStore:
  | { profileHome: string; store: ConfigStore }
  | undefined;

function defaultConfigStore(): ConfigStore {
  const profileHome = home();
  if (cachedDefaultConfigStore?.profileHome !== profileHome) {
    cachedDefaultConfigStore = {
      profileHome,
      store: createConfigStore({
        configPath: CONFIG_PATH(),
        secretStore: usesMacOsKeychain()
          ? createMacOsKeychainApiKeyStore(profileHome)
          : null,
      }),
    };
  }
  return cachedDefaultConfigStore.store;
}

export async function readConfig(): Promise<ScriberConfig> {
  return defaultConfigStore().read();
}

export async function writeConfig(
  patch: Partial<ScriberConfig>
): Promise<ScriberConfig> {
  return defaultConfigStore().write(patch);
}

// ---------------------------------------------------------------------------
// Complete backup / restore
// ---------------------------------------------------------------------------

const BACKUP_FORMAT = "scriber-backup";
const BACKUP_FORMAT_VERSION = 1;
const MAX_BACKUP_ENTRIES = 100_000;
const MAX_BACKUP_UNCOMPRESSED_BYTES = 200 * 1024 * 1024 * 1024;
const MAX_METADATA_ENTRY_BYTES = 5 * 1024 * 1024;
const MAX_NOTE_ENTRY_BYTES = 50 * 1024 * 1024;
const MAX_AUDIO_ENTRY_BYTES = 10 * 1024 * 1024 * 1024;

export type RestoreMode = "merge" | "replace";

export interface BackupManifest {
  format: typeof BACKUP_FORMAT;
  formatVersion: typeof BACKUP_FORMAT_VERSION;
  appVersion: string;
  createdAt: string;
  noteCount: number;
  audioFileCount: number;
  includesApiKey: false;
}

export interface RestoreResult {
  mode: RestoreMode;
  notesImported: number;
  notesSkipped: number;
  audioImported: number;
  audioSkipped: number;
  settingsRestored: true;
}

interface BackupFile {
  name: string;
  fullPath: string;
  size: number;
  mtime: Date;
}

interface ValidatedRestore {
  stagingDir: string;
  config: Partial<ScriberConfig>;
  notes: Array<{ file: BackupFile; note: Note }>;
  audio: BackupFile[];
}

async function listRegularFiles(
  dir: string,
  filter: (name: string) => boolean = () => true
): Promise<BackupFile[]> {
  const names = (await fs.readdir(dir)).filter(filter).sort();
  const files: BackupFile[] = [];
  for (const name of names) {
    const fullPath = path.join(dir, name);
    const stat = await fs.lstat(fullPath);
    if (!stat.isFile()) {
      throw new Error(`Cannot back up non-file entry: ${name}`);
    }
    files.push({ name, fullPath, size: stat.size, mtime: stat.mtime });
  }
  return files;
}

function addBufferToArchive(
  pack: tar.Pack,
  name: string,
  buffer: Buffer
): Promise<void> {
  return new Promise((resolve, reject) => {
    pack.entry(
      { name, type: "file", size: buffer.length, mode: 0o600 },
      buffer,
      (error) => (error ? reject(error) : resolve())
    );
  });
}

async function addFileToArchive(
  pack: tar.Pack,
  archivePath: string,
  file: BackupFile
) {
  const entry = pack.entry({
    name: archivePath,
    type: "file",
    size: file.size,
    mode: 0o600,
    mtime: file.mtime,
  });
  await pipeline(createReadStream(file.fullPath), entry);
}

export async function createBackupArchive(appVersion: string): Promise<{
  stream: Readable;
  manifest: BackupManifest;
}> {
  await ensureDirs();
  const [configWithSecret, notes, audio] = await Promise.all([
    readConfig(),
    listRegularFiles(NOTES_DIR(), (name) => name.endsWith(".json")),
    listRegularFiles(AUDIO_DIR()),
  ]);
  const config = { ...configWithSecret };
  delete config.apiKey;

  const manifest: BackupManifest = {
    format: BACKUP_FORMAT,
    formatVersion: BACKUP_FORMAT_VERSION,
    appVersion,
    createdAt: new Date().toISOString(),
    noteCount: notes.length,
    audioFileCount: audio.length,
    includesApiKey: false,
  };

  const pack = tar.pack();
  const output = pack.pipe(createGzip({ level: 6 }));

  void (async () => {
    try {
      await addBufferToArchive(
        pack,
        "manifest.json",
        Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`)
      );
      await addBufferToArchive(
        pack,
        "config.json",
        Buffer.from(`${JSON.stringify(config, null, 2)}\n`)
      );
      for (const file of notes) {
        await addFileToArchive(pack, `notes/${file.name}`, file);
      }
      for (const file of audio) {
        await addFileToArchive(pack, `audio/${file.name}`, file);
      }
      pack.finalize();
    } catch (error) {
      pack.destroy(error instanceof Error ? error : new Error("Backup failed"));
    }
  })();

  return { stream: output, manifest };
}

function validArchivePath(name: string): boolean {
  if (
    !name ||
    name.length > 300 ||
    name.includes("\\") ||
    name.startsWith("/") ||
    path.posix.normalize(name) !== name
  ) {
    return false;
  }
  if (name === "manifest.json" || name === "config.json") return true;
  return /^notes\/[^/]+\.json$/.test(name) || /^audio\/[^/]+$/.test(name);
}

function maxEntrySize(name: string): number {
  if (name === "manifest.json" || name === "config.json") {
    return MAX_METADATA_ENTRY_BYTES;
  }
  if (name.startsWith("notes/")) return MAX_NOTE_ENTRY_BYTES;
  return MAX_AUDIO_ENTRY_BYTES;
}

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

async function extractBackupToStaging(
  source: Readable
): Promise<string> {
  await fs.mkdir(home(), { recursive: true, mode: 0o700 });
  await fs.chmod(home(), 0o700);
  const stagingDir = path.join(home(), `.restore-${crypto.randomUUID()}`);
  await fs.mkdir(path.join(stagingDir, "notes"), {
    recursive: true,
    mode: 0o700,
  });
  await fs.mkdir(path.join(stagingDir, "audio"), {
    recursive: true,
    mode: 0o700,
  });

  const seen = new Set<string>();
  let entryCount = 0;
  let totalBytes = 0;
  const extract = tar.extract();

  extract.on("entry", (header, entry, next) => {
    void (async () => {
      const name = header.name;
      const size = header.size ?? 0;
      entryCount += 1;
      totalBytes += size;

      if (
        entryCount > MAX_BACKUP_ENTRIES ||
        totalBytes > MAX_BACKUP_UNCOMPRESSED_BYTES
      ) {
        throw new Error("Backup is too large");
      }
      if (
        header.type !== "file" ||
        !validArchivePath(name) ||
        seen.has(name) ||
        !Number.isSafeInteger(size) ||
        size < 0 ||
        size > maxEntrySize(name)
      ) {
        throw new Error(`Unsafe or invalid backup entry: ${name || "(unnamed)"}`);
      }
      seen.add(name);

      const destination = path.join(stagingDir, ...name.split("/"));
      await pipeline(entry, createWriteStream(destination, { mode: 0o600 }));
      const written = await fs.stat(destination);
      if (written.size !== size) {
        throw new Error(`Truncated backup entry: ${name}`);
      }
    })().then(
      () => next(),
      (error) => {
        entry.resume();
        next(error);
      }
    );
  });

  try {
    await pipeline(source, createGunzip(), extract);
    return stagingDir;
  } catch (error) {
    await deleteTree(stagingDir).catch(() => {});
    throw error;
  }
}

async function readJsonObject(file: string, label: string) {
  let parsed: unknown;
  try {
    parsed = JSON.parse(await fs.readFile(file, "utf8"));
  } catch {
    throw new Error(`${label} is missing or invalid JSON`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`${label} must contain a JSON object`);
  }
  return parsed as Record<string, unknown>;
}

function isValidNote(input: unknown): input is Note {
  if (!input || typeof input !== "object" || Array.isArray(input)) return false;
  const value = input as Record<string, unknown>;
  const metadata = value.metadata;
  if (
    typeof value.id !== "string" ||
    !value.id ||
    value.id.length > 128 ||
    typeof value.title !== "string" ||
    typeof value.content !== "string" ||
    (value.type !== "transcription" && value.type !== "text") ||
    (value.source !== "recording" &&
      value.source !== "upload" &&
      value.source !== "text") ||
    typeof value.createdAt !== "string" ||
    Number.isNaN(Date.parse(value.createdAt)) ||
    typeof value.updatedAt !== "string" ||
    Number.isNaN(Date.parse(value.updatedAt)) ||
    !metadata ||
    typeof metadata !== "object" ||
    Array.isArray(metadata)
  ) {
    return false;
  }
  if (
    value.tags !== undefined &&
    (!Array.isArray(value.tags) ||
      !value.tags.every((tag) => typeof tag === "string"))
  ) {
    return false;
  }
  if (
    value.audioFileName !== undefined &&
    typeof value.audioFileName !== "string"
  ) {
    return false;
  }
  if (
    value.durationSeconds !== undefined &&
    (typeof value.durationSeconds !== "number" ||
      !Number.isFinite(value.durationSeconds) ||
      value.durationSeconds < 0)
  ) {
    return false;
  }
  if (value.language !== undefined && typeof value.language !== "string") {
    return false;
  }

  const words = (metadata as Record<string, unknown>).words;
  if (
    words !== undefined &&
    (!Array.isArray(words) ||
      !words.every(
        (word) =>
          word &&
          typeof word === "object" &&
          typeof word.text === "string" &&
          typeof word.start === "number" &&
          Number.isFinite(word.start) &&
          typeof word.end === "number" &&
          Number.isFinite(word.end) &&
          (word.type === "word" ||
            word.type === "punctuation" ||
            word.type === "spacing" ||
            word.type === "audio_event") &&
          (word.speaker_id === undefined || typeof word.speaker_id === "string") &&
          (word.logprob === undefined ||
            (typeof word.logprob === "number" && Number.isFinite(word.logprob)))
      ))
  ) {
    return false;
  }
  return true;
}

function restoredConfig(value: Record<string, unknown>): Partial<ScriberConfig> {
  if (Object.hasOwn(value, "apiKey")) {
    throw new Error("Backup must not contain an API key");
  }
  const config: Partial<ScriberConfig> = {};
  if (value.defaults !== undefined) {
    const defaults = value.defaults as Record<string, unknown>;
    if (
      !defaults ||
      typeof defaults !== "object" ||
      Array.isArray(defaults) ||
      typeof defaults.languageCode !== "string" ||
      typeof defaults.diarize !== "boolean" ||
      (defaults.numSpeakers !== null &&
        (!Number.isInteger(defaults.numSpeakers) ||
          (defaults.numSpeakers as number) <= 0)) ||
      typeof defaults.tagAudioEvents !== "boolean"
    ) {
      throw new Error("Backup contains invalid transcription settings");
    }
    config.defaults = defaults as unknown as TranscribeOptions;
  }
  if (value.dictionary !== undefined) {
    if (
      !Array.isArray(value.dictionary) ||
      !value.dictionary.every((term) => typeof term === "string")
    ) {
      throw new Error("Backup contains an invalid dictionary");
    }
    config.dictionary = value.dictionary;
  }
  if (value.transcribeModel !== undefined) {
    if (typeof value.transcribeModel !== "string") {
      throw new Error("Backup contains an invalid transcription model");
    }
    config.transcribeModel = value.transcribeModel;
  }
  if (value.theme !== undefined) {
    if (
      value.theme !== "light" &&
      value.theme !== "dark" &&
      value.theme !== "system"
    ) {
      throw new Error("Backup contains an invalid theme");
    }
    config.theme = value.theme;
  }
  return config;
}

async function validateStaging(stagingDir: string): Promise<ValidatedRestore> {
  const manifest = await readJsonObject(
    path.join(stagingDir, "manifest.json"),
    "Backup manifest"
  );
  if (
    manifest.format !== BACKUP_FORMAT ||
    manifest.formatVersion !== BACKUP_FORMAT_VERSION ||
    manifest.includesApiKey !== false
  ) {
    throw new Error("Unsupported or invalid Scriber backup format");
  }
  const config = restoredConfig(
    await readJsonObject(path.join(stagingDir, "config.json"), "Backup config")
  );
  const noteFiles = await listRegularFiles(
    path.join(stagingDir, "notes"),
    (name) => name.endsWith(".json")
  );
  const audio = await listRegularFiles(path.join(stagingDir, "audio"));
  if (
    manifest.noteCount !== noteFiles.length ||
    manifest.audioFileCount !== audio.length
  ) {
    throw new Error("Backup manifest counts do not match its contents");
  }

  const notes: ValidatedRestore["notes"] = [];
  const ids = new Set<string>();
  for (const file of noteFiles) {
    const raw = await readJsonObject(file.fullPath, `Note ${file.name}`);
    if (!isValidNote(raw) || ids.has(raw.id)) {
      throw new Error(`Backup contains an invalid or duplicate note: ${file.name}`);
    }
    ids.add(raw.id);
    notes.push({ file, note: raw });
  }
  return { stagingDir, config, notes, audio };
}

function audioShortId(filename: string): string | undefined {
  const beforeSlug = filename.split("__")[0].replace(/\.[^.]+$/, "");
  return beforeSlug.match(/_([a-f0-9]{8})$/i)?.[1]?.toLowerCase();
}

async function mergeRestore(restore: ValidatedRestore): Promise<RestoreResult> {
  await ensureDirs();
  const existing = await listNotes();
  const existingIds = new Set(existing.map((note) => note.id));
  const createdTargets: string[] = [];
  const backupIdByShort = new Map(
    restore.notes.map(({ note }) => [shortId(note.id).toLowerCase(), note.id])
  );
  let notesImported = 0;
  let notesSkipped = 0;
  let audioImported = 0;
  let audioSkipped = 0;

  try {
    for (const { file, note } of restore.notes) {
      const target = path.join(NOTES_DIR(), file.name);
      const targetExists = await fs.access(target).then(
        () => true,
        () => false
      );
      if (existingIds.has(note.id) || targetExists) {
        notesSkipped += 1;
        continue;
      }
      await atomicCopy(file.fullPath, target);
      createdTargets.push(target);
      existingIds.add(note.id);
      notesImported += 1;
    }

    for (const file of restore.audio) {
      const short = audioShortId(file.name);
      const noteId = short ? backupIdByShort.get(short) : undefined;
      const target = path.join(AUDIO_DIR(), file.name);
      const targetExists = noteId
        ? Boolean(await findAudioFile(noteId))
        : await fs.access(target).then(
            () => true,
            () => false
          );
      if (targetExists) {
        audioSkipped += 1;
        continue;
      }
      await atomicCopy(file.fullPath, target);
      createdTargets.push(target);
      audioImported += 1;
    }

    await writeConfig(restore.config);
  } catch (error) {
    for (const target of createdTargets.reverse()) {
      await fs.unlink(target).catch(() => {});
    }
    throw error;
  }

  return {
    mode: "merge",
    notesImported,
    notesSkipped,
    audioImported,
    audioSkipped,
    settingsRestored: true,
  };
}

async function replaceRestore(restore: ValidatedRestore): Promise<RestoreResult> {
  await ensureDirs();
  const suffix = crypto.randomUUID();
  const oldNotes = path.join(home(), `.restore-previous-notes-${suffix}`);
  const oldAudio = path.join(home(), `.restore-previous-audio-${suffix}`);
  const stagedNotes = path.join(restore.stagingDir, "notes");
  const stagedAudio = path.join(restore.stagingDir, "audio");
  let movedOldNotes = false;
  let movedOldAudio = false;
  let installedNotes = false;
  let installedAudio = false;

  try {
    await fs.rename(NOTES_DIR(), oldNotes);
    movedOldNotes = true;
    await fs.rename(AUDIO_DIR(), oldAudio);
    movedOldAudio = true;
    await fs.rename(stagedNotes, NOTES_DIR());
    installedNotes = true;
    await fs.rename(stagedAudio, AUDIO_DIR());
    installedAudio = true;
    await writeConfig(restore.config);
  } catch (error) {
    if (installedAudio) {
      await fs.rename(AUDIO_DIR(), stagedAudio).catch(() => {});
    }
    if (installedNotes) {
      await fs.rename(NOTES_DIR(), stagedNotes).catch(() => {});
    }
    if (movedOldAudio) {
      await fs.rename(oldAudio, AUDIO_DIR()).catch(() => {});
    }
    if (movedOldNotes) {
      await fs.rename(oldNotes, NOTES_DIR()).catch(() => {});
    }
    throw error;
  }

  await deleteTree(oldNotes).catch(() => {});
  await deleteTree(oldAudio).catch(() => {});
  return {
    mode: "replace",
    notesImported: restore.notes.length,
    notesSkipped: 0,
    audioImported: restore.audio.length,
    audioSkipped: 0,
    settingsRestored: true,
  };
}

export async function restoreBackupArchive(
  source: Readable,
  mode: RestoreMode
): Promise<RestoreResult> {
  if (mode !== "merge" && mode !== "replace") {
    throw new Error("Restore mode must be merge or replace");
  }
  const stagingDir = await extractBackupToStaging(source);
  try {
    const restore = await validateStaging(stagingDir);
    return mode === "replace"
      ? await replaceRestore(restore)
      : await mergeRestore(restore);
  } finally {
    await deleteTree(stagingDir).catch(() => {});
  }
}

// ---------------------------------------------------------------------------
// Notes CRUD
// ---------------------------------------------------------------------------

export async function listNotes(): Promise<Note[]> {
  await ensureDirs();
  const entries = await fs.readdir(NOTES_DIR());
  const notes: Note[] = [];
  for (const entry of entries) {
    if (!entry.endsWith(".json")) continue;
    try {
      const raw = await fs.readFile(path.join(NOTES_DIR(), entry), "utf8");
      notes.push(JSON.parse(raw) as Note);
    } catch {
      // Skip unreadable entries
    }
  }
  // Newest first by createdAt
  notes.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
  return notes;
}

export async function readNote(id: string): Promise<Note | null> {
  const file = await findNoteFile(id);
  if (!file) return null;
  try {
    const raw = await fs.readFile(file, "utf8");
    return JSON.parse(raw) as Note;
  } catch {
    return null;
  }
}

export async function createNote(input: CreateNoteInput & { id: string }): Promise<Note> {
  const now = new Date().toISOString();
  const note: Note = {
    ...input,
    tags: input.tags ?? [],
    metadata: input.metadata ?? {},
    createdAt: now,
    updatedAt: now,
  };
  await atomicWrite(
    path.join(NOTES_DIR(), noteFilename(note)),
    JSON.stringify(note, null, 2)
  );
  return note;
}

export async function updateNote(
  id: string,
  patch: UpdateNoteInput
): Promise<Note | null> {
  const file = await findNoteFile(id);
  if (!file) return null;
  const raw = await fs.readFile(file, "utf8");
  const existing = JSON.parse(raw) as Note;
  const updated: Note = {
    ...existing,
    ...patch,
    updatedAt: new Date().toISOString(),
  };
  // Filename is derived from createdAt + id — both stable — so we overwrite in place
  await atomicWrite(file, JSON.stringify(updated, null, 2));
  return updated;
}

export async function deleteNote(id: string): Promise<boolean> {
  const file = await findNoteFile(id);
  if (!file) return false;
  await fs.unlink(file);
  await deleteAudio(id).catch(() => {
    // Non-fatal: audio may not exist
  });
  return true;
}

// ---------------------------------------------------------------------------
// Audio
// ---------------------------------------------------------------------------

function extensionFromMime(mime?: string): string {
  if (!mime) return "bin";
  if (mime.includes("webm")) return "webm";
  if (mime.includes("ogg")) return "ogg";
  if (mime.includes("mp4") || mime.includes("m4a")) return "m4a";
  if (mime.includes("mpeg") || mime.includes("mp3")) return "mp3";
  if (mime.includes("wav")) return "wav";
  if (mime.includes("flac")) return "flac";
  return "bin";
}

export async function writeAudio(
  id: string,
  body: ReadableStream<Uint8Array> | Buffer,
  mime?: string
): Promise<void> {
  // Delete any existing audio for this id (extension may differ)
  const existing = await findAudioFile(id);
  if (existing) await fs.unlink(existing).catch(() => {});

  const note = await readNote(id);
  if (!note) throw new Error(`Cannot save audio: note ${id} not found`);

  const ext = extensionFromMime(mime);
  const filename = audioFilename(note, ext);
  const target = path.join(AUDIO_DIR(), filename);
  await fs.mkdir(AUDIO_DIR(), { recursive: true });

  const tmp = `${target}.${process.pid}.${Date.now()}.tmp`;
  const out = createWriteStream(tmp);

  if (Buffer.isBuffer(body)) {
    await fs.writeFile(tmp, body);
  } else {
    await pipeline(Readable.fromWeb(body as unknown as import("node:stream/web").ReadableStream<Uint8Array>), out);
  }
  await fs.rename(tmp, target);
}

export async function readAudioStream(
  id: string
): Promise<{ stream: ReadStream; mime: string; size: number } | null> {
  const file = await findAudioFile(id);
  if (!file) return null;
  const stat = await fs.stat(file);
  const ext = path.extname(file).slice(1).toLowerCase();
  const mimeMap: Record<string, string> = {
    webm: "audio/webm",
    ogg: "audio/ogg",
    m4a: "audio/mp4",
    mp3: "audio/mpeg",
    wav: "audio/wav",
    flac: "audio/flac",
  };
  return {
    stream: createReadStream(file),
    mime: mimeMap[ext] || "application/octet-stream",
    size: stat.size,
  };
}

export async function deleteAudio(id: string): Promise<void> {
  const file = await findAudioFile(id);
  if (file) await fs.unlink(file);
}
