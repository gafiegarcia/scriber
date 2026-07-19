import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { parseArgs } from "node:util";

import { transcribeFile, type TranscribeError } from "@/lib/core/transcribe";
import {
  extractAudio,
  hasVideoStream,
  VIDEO_EXTENSIONS,
  AudioExtractError,
} from "@/lib/core/audio-extract";
import { assertFfmpegAvailable } from "@/lib/core/ffmpeg-runtime";
import {
  readConfig,
  createNote,
  writeAudio,
} from "@/lib/server/storage";
import type { NoteMetadata, TranscribeOptions } from "@/lib/types";
import type { ScribeResponse, ScribeWord } from "@/lib/types/elevenlabs";

import { renderJson, type JsonOutputPayload } from "../formatters/json";
import { renderSrt } from "../formatters/srt";
import { renderMarkdown } from "../formatters/md";
import { renderTxt } from "../formatters/txt";

const HELP = `
scriber transcribe — send an audio (or video) file to ElevenLabs Scribe v2 and print the JSON result.

USAGE
  scriber transcribe <file> [options]

INPUT
  Audio: .mp3 .m4a .mp4 .wav .webm .ogg .flac
  Video: .mov .mp4 .mkv .webm .m4v .avi   (video track is stripped via ffmpeg
                                           before transcription; only the
                                           extracted audio is stored)

OUTPUT
  JSON is always written to stdout. Progress and errors go to stderr.

OPTIONS
  -o, --output <path...>     One or more output file paths; extension picks format
                             (.json | .srt | .md | .txt). Repeat -o to add paths.
      --no-store             Skip the default ~/.scriber/ Note + audio copy.
      --language <code>      BCP-47 code, or "auto" (overrides config default).
      --diarize              Enable speaker diarization.
      --num-speakers <n>     Speaker count hint (requires --diarize).
      --tag-audio-events     Tag non-speech events (laughter, music, ...).
      --keyterm <term>       Add a keyterm (repeatable; appended to config dict).
      --no-keyterms          Disable all keyterms for this run.
      --title <text>         Note title override (default: input basename).
  -q, --quiet                Suppress stderr progress output.
  -h, --help                 Show this help.

EXAMPLES
  scriber transcribe interview.mp3
  scriber transcribe interview.mp3 -o interview.json interview.srt
  scriber transcribe interview.mp3 --diarize --num-speakers 2 --no-store
`.trimStart();

const SUPPORTED_INPUT_EXTS = new Set([
  // audio
  "mp3",
  "m4a",
  "mp4",
  "wav",
  "webm",
  "ogg",
  "flac",
  // video (converted to .m4a before transcription)
  "mov",
  "mkv",
  "m4v",
  "avi",
]);

const SUPPORTED_OUTPUT_EXTS = new Set(["json", "srt", "md", "txt"]);

const MIME_BY_EXT: Record<string, string> = {
  mp3: "audio/mpeg",
  m4a: "audio/mp4",
  mp4: "audio/mp4",
  wav: "audio/wav",
  webm: "audio/webm",
  ogg: "audio/ogg",
  flac: "audio/flac",
  // Video extensions resolve here only after conversion swaps the working
  // path/ext to .m4a; the entries are kept so inferMime() doesn't reject
  // the ORIGINAL filename's extension on the way in.
  mov: "audio/mp4",
  mkv: "audio/mp4",
  m4v: "audio/mp4",
  avi: "audio/mp4",
};

interface ParsedInvocation {
  input: string;
  outputs: string[];
  noStore: boolean;
  language?: string;
  diarize?: boolean;
  numSpeakers?: number;
  tagAudioEvents?: boolean;
  keyterms: string[];
  noKeyterms: boolean;
  title?: string;
  quiet: boolean;
}

class UsageError extends Error {}

function splitOutputsFromArgv(argv: string[]): {
  outputs: string[];
  rest: string[];
} {
  const outputs: string[] = [];
  const rest: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    const tok = argv[i];
    if (tok === "-o" || tok === "--output") {
      // Consume following tokens until the next flag (starts with "-")
      // or end of argv. Requires at least one target.
      let j = i + 1;
      let collected = 0;
      while (j < argv.length && !argv[j].startsWith("-")) {
        outputs.push(argv[j]);
        j += 1;
        collected += 1;
      }
      if (collected === 0) {
        throw new UsageError(`${tok} requires at least one file path.`);
      }
      i = j - 1;
    } else {
      rest.push(tok);
    }
  }
  return { outputs, rest };
}

function parseInvocation(argv: string[]): ParsedInvocation {
  const { outputs, rest } = splitOutputsFromArgv(argv);

  let parsed;
  try {
    parsed = parseArgs({
      args: rest,
      options: {
        "no-store": { type: "boolean" },
        language: { type: "string" },
        diarize: { type: "boolean" },
        "num-speakers": { type: "string" },
        "tag-audio-events": { type: "boolean" },
        keyterm: { type: "string", multiple: true },
        "no-keyterms": { type: "boolean" },
        title: { type: "string" },
        quiet: { type: "boolean", short: "q" },
        help: { type: "boolean", short: "h" },
      },
      allowPositionals: true,
      strict: true,
    });
  } catch (err) {
    throw new UsageError((err as Error).message);
  }

  if (parsed.values.help) {
    process.stdout.write(HELP);
    process.exit(0);
  }

  if (parsed.positionals.length === 0) {
    throw new UsageError("Missing input file. See `scriber transcribe --help`.");
  }
  if (parsed.positionals.length > 1) {
    throw new UsageError(
      `Batch input is not supported yet. Got ${parsed.positionals.length} files: ${parsed.positionals.join(", ")}`
    );
  }

  let numSpeakers: number | undefined;
  const rawNumSpeakers = parsed.values["num-speakers"];
  if (rawNumSpeakers != null) {
    const n = Number.parseInt(rawNumSpeakers, 10);
    if (!Number.isInteger(n) || n < 1) {
      throw new UsageError(`--num-speakers must be a positive integer (got "${rawNumSpeakers}")`);
    }
    numSpeakers = n;
  }

  return {
    input: parsed.positionals[0],
    outputs,
    noStore: Boolean(parsed.values["no-store"]),
    language: parsed.values.language,
    diarize: parsed.values.diarize,
    numSpeakers,
    tagAudioEvents: parsed.values["tag-audio-events"],
    keyterms: (parsed.values.keyterm as string[] | undefined) ?? [],
    noKeyterms: Boolean(parsed.values["no-keyterms"]),
    title: parsed.values.title,
    quiet: Boolean(parsed.values.quiet),
  };
}

function extOf(p: string): string {
  return path.extname(p).slice(1).toLowerCase();
}

function validateOutputs(outputs: string[]): void {
  for (const target of outputs) {
    const ext = extOf(target);
    if (!ext) {
      throw new UsageError(
        `Output "${target}" has no extension. Supported: .json, .srt, .md, .txt`
      );
    }
    if (!SUPPORTED_OUTPUT_EXTS.has(ext)) {
      throw new UsageError(
        `Unsupported output format ".${ext}" for "${target}". Supported: .json, .srt, .md, .txt`
      );
    }
  }
}

function inferMime(inputPath: string): { ext: string; mime: string } {
  const ext = extOf(inputPath);
  if (!SUPPORTED_INPUT_EXTS.has(ext)) {
    throw new UsageError(
      `Unsupported audio extension ".${ext}". Supported: ${Array.from(SUPPORTED_INPUT_EXTS).map((e) => "." + e).join(", ")}`
    );
  }
  return { ext, mime: MIME_BY_EXT[ext] };
}

function computeDurationSeconds(words: ScribeWord[]): number | undefined {
  if (!words.length) return undefined;
  const last = words[words.length - 1];
  if (typeof last.end !== "number" || !Number.isFinite(last.end)) return undefined;
  return Math.round(last.end * 100) / 100;
}

function additionalFormatsToRecord(
  formats: ScribeResponse["additional_formats"]
): Record<string, string> | undefined {
  if (!formats || formats.length === 0) return undefined;
  const out: Record<string, string> = {};
  for (const f of formats) {
    if (typeof f.requested_format === "string" && typeof f.content === "string") {
      out[f.requested_format] = f.content;
    }
  }
  return Object.keys(out).length > 0 ? out : undefined;
}

async function atomicWriteFile(target: string, content: string): Promise<void> {
  await fs.mkdir(path.dirname(path.resolve(target)), { recursive: true });
  const tmp = `${target}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tmp, content);
  await fs.rename(tmp, target);
}

export async function runTranscribeCommand(argv: string[]): Promise<void> {
  let invocation: ParsedInvocation;
  try {
    invocation = parseInvocation(argv);
  } catch (err) {
    if (err instanceof UsageError) {
      process.stderr.write(`${err.message}\n`);
      process.exit(1);
    }
    throw err;
  }

  const log = (msg: string) => {
    if (!invocation.quiet) process.stderr.write(`${msg}\n`);
  };

  let cleanupConversion: (() => Promise<void>) | null = null;

  try {
    validateOutputs(invocation.outputs);

    const absInput = path.resolve(invocation.input);
    const stat = await fs.stat(absInput).catch(() => null);
    if (!stat || !stat.isFile()) {
      process.stderr.write(`Input not found: ${invocation.input}\n`);
      process.exit(1);
    }

    // Validate the original extension first (gives a clean error for `.flv`,
    // `.aiff`, etc. before we even check the API key).
    inferMime(absInput);

    const config = await readConfig();
    const apiKey = config.apiKey;
    if (!apiKey) {
      process.stderr.write(
        "No ElevenLabs API key configured.\n" +
          "Run `scriber` (the web app) and set your key under Settings → API Key.\n"
      );
      process.exit(1);
    }

    const configDefaults: TranscribeOptions = config.defaults ?? {
      languageCode: "auto",
      diarize: false,
      numSpeakers: null,
      tagAudioEvents: false,
    };

    const languageCode =
      invocation.language !== undefined ? invocation.language : configDefaults.languageCode;
    const diarize =
      invocation.diarize !== undefined ? invocation.diarize : configDefaults.diarize;
    const numSpeakers =
      invocation.numSpeakers !== undefined
        ? invocation.numSpeakers
        : configDefaults.numSpeakers;
    const tagAudioEvents =
      invocation.tagAudioEvents !== undefined
        ? invocation.tagAudioEvents
        : configDefaults.tagAudioEvents;

    const keyterms = invocation.noKeyterms
      ? []
      : [...(config.dictionary ?? []), ...invocation.keyterms];

    const originalBasename = path.basename(absInput);
    const originalExt = extOf(absInput);
    const title = invocation.title ?? originalBasename.replace(/\.[^.]+$/, "");

    let buffer: Buffer;
    let sendMime: string;
    let sendFilename: string;

    if (VIDEO_EXTENSIONS.has(originalExt)) {
      assertFfmpegAvailable();
      const isVideo = await hasVideoStream(absInput);
      if (isVideo) {
        log(`Converting ${originalBasename} to audio (.m4a, mono 48kHz)…`);
        const { outputPath, cleanup } = await extractAudio(absInput);
        cleanupConversion = cleanup;
        buffer = await fs.readFile(outputPath);
        sendMime = "audio/mp4";
        sendFilename = originalBasename.replace(/\.[^.]+$/, "") + ".m4a";
      } else {
        // Audio-in-video-container (e.g. iPhone Voice Memo .mp4): pass through.
        buffer = await fs.readFile(absInput);
        sendMime = MIME_BY_EXT[originalExt];
        sendFilename = originalBasename;
      }
    } else {
      buffer = await fs.readFile(absInput);
      sendMime = MIME_BY_EXT[originalExt];
      sendFilename = originalBasename;
    }

    log(
      `Transcribing ${sendFilename} (${(buffer.length / (1024 * 1024)).toFixed(1)}MB)...`
    );

    const result = await transcribeFile(
      { buffer, filename: sendFilename, mime: sendMime },
      {
        apiKey,
        model: config.transcribeModel || "scribe_v2",
        languageCode,
        diarize,
        numSpeakers,
        tagAudioEvents,
        keyterms,
      }
    );

    log(
      `Transcription complete (${result.language_code}, ${Math.round(
        result.language_probability * 100
      )}% confidence, ${result.words.length} words).`
    );

    const id = crypto.randomUUID();
    const createdAt = new Date().toISOString();
    const durationSeconds = computeDurationSeconds(result.words);
    const additionalFormats = additionalFormatsToRecord(result.additional_formats);

    let noteId: string | null = null;
    if (!invocation.noStore) {
      const metadata: NoteMetadata = {
        words: result.words,
        languageProbability: result.language_probability,
        hasDiarization: Boolean(diarize),
        hasAudioEventTags: Boolean(tagAudioEvents),
        ...(additionalFormats ? { additionalFormats } : {}),
      };

      const note = await createNote({
        id,
        title,
        content: result.text,
        type: "transcription",
        source: "upload",
        audioFileName: originalBasename,
        ...(durationSeconds != null ? { durationSeconds } : {}),
        language: result.language_code,
        tags: [],
        metadata,
      });
      await writeAudio(note.id, buffer, sendMime);
      noteId = note.id;
      log(`Note saved: ${note.id} (~/.scriber/notes/)`);
    }

    const writtenOutputs: string[] = [];
    const jsonPayload: JsonOutputPayload = {
      text: result.text,
      language_code: result.language_code,
      language_probability: result.language_probability,
      words: result.words,
      ...(additionalFormats ? { additional_formats: result.additional_formats } : {}),
      id,
      noteId,
      outputs: [],
      createdAt,
    };

    if (invocation.outputs.length > 0) {
      for (const target of invocation.outputs) {
        const ext = extOf(target);
        const abs = path.resolve(target);
        switch (ext) {
          case "json": {
            const payloadForFile: JsonOutputPayload = {
              ...jsonPayload,
              outputs: invocation.outputs.map((p) => path.resolve(p)),
            };
            await atomicWriteFile(abs, renderJson(payloadForFile));
            break;
          }
          case "srt":
            await atomicWriteFile(abs, renderSrt(result.words));
            break;
          case "md":
            await atomicWriteFile(
              abs,
              renderMarkdown(result.text, {
                language: result.language_code,
                languageProbability: result.language_probability,
                durationSeconds,
                createdAt,
                title,
              })
            );
            break;
          case "txt":
            await atomicWriteFile(abs, renderTxt(result.text));
            break;
        }
        writtenOutputs.push(abs);
        log(`Wrote: ${abs}`);
      }
    }

    jsonPayload.outputs = writtenOutputs;
    process.stdout.write(renderJson(jsonPayload));
    await cleanupConversion?.();
    process.exit(0);
  } catch (err) {
    await cleanupConversion?.();
    if (err instanceof UsageError) {
      process.stderr.write(`${err.message}\n`);
      process.exit(1);
    }
    if (err instanceof AudioExtractError) {
      process.stderr.write(
        `Could not extract audio from this video — the file may be corrupt or use an unsupported codec.\n${err.stderr ? `\nffmpeg stderr:\n${err.stderr}\n` : ""}`
      );
      process.exit(2);
    }
    const asTranscribe = err as Partial<TranscribeError>;
    if (
      err instanceof Error &&
      typeof asTranscribe.status === "number" &&
      typeof asTranscribe.retryable === "boolean"
    ) {
      process.stderr.write(`Transcription failed: ${err.message}\n`);
      process.exit(2);
    }
    process.stderr.write(
      `Unexpected error: ${err instanceof Error ? err.stack || err.message : String(err)}\n`
    );
    process.exit(1);
  }
}
