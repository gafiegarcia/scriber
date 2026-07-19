import { NextResponse } from "next/server";
import { readConfig } from "@/lib/server/storage";
import { transcribeFile, type TranscribeError } from "@/lib/core/transcribe";
import {
  AudioExtractError,
  VIDEO_EXTENSIONS,
  extractAudio,
  hasVideoStream,
  writeUploadToTemp,
} from "@/lib/core/audio-extract";
import { assertFfmpegAvailable } from "@/lib/core/ffmpeg-runtime";
import { SecretStoreError } from "@/lib/server/secret-store";
import fs from "node:fs/promises";
import path from "node:path";

export const runtime = "nodejs";

// Allow up to 500MB uploads (ElevenLabs supports up to 3GB).
// Bumped to 600s so multi-hour video conversions don't time out alongside
// transcription on the same request.
export const maxDuration = 600;

function isTranscribeError(err: unknown): err is TranscribeError {
  return (
    err instanceof Error &&
    typeof (err as TranscribeError).status === "number" &&
    typeof (err as TranscribeError).retryable === "boolean"
  );
}

function isVideoUpload(file: File): boolean {
  if (file.type && file.type.startsWith("video/")) return true;
  const ext = path.extname(file.name).slice(1).toLowerCase();
  return VIDEO_EXTENSIONS.has(ext);
}

export async function POST(request: Request) {
  let config;
  try {
    config = await readConfig();
  } catch (error) {
    console.error("[scriber] Failed to read stored API key:", error);
    return NextResponse.json(
      {
        error:
          error instanceof SecretStoreError
            ? error.message
            : "Failed to read the stored API key",
        retryable: true,
        ...(error instanceof SecretStoreError ? { code: error.code } : {}),
      },
      { status: error instanceof SecretStoreError ? 503 : 500 }
    );
  }
  const apiKey = config.apiKey;
  if (!apiKey) {
    return NextResponse.json(
      {
        error: "No ElevenLabs API key configured. Add one in Settings → API Key.",
        retryable: false,
      },
      { status: 400 }
    );
  }

  const formData = await request.formData();
  const file = formData.get("file") as File | null;
  if (!file || file.size === 0) {
    return NextResponse.json(
      { error: "No file provided or file is empty", retryable: false },
      { status: 400 }
    );
  }

  const languageCode = formData.get("language_code");
  const diarize = formData.get("diarize") === "true";
  const numSpeakersRaw = formData.get("num_speakers");
  const tagAudioEvents = formData.get("tag_audio_events") === "true";
  const keyterms = formData
    .getAll("keyterms")
    .filter((term): term is string => typeof term === "string");

  let cleanupInput: (() => Promise<void>) | null = null;
  let cleanupOutput: (() => Promise<void>) | null = null;
  let convertedAudioBase64: string | null = null;
  let convertedFilename: string | null = null;

  try {
    let sendInput: { file: File } | { buffer: Buffer; filename: string; mime: string };

    if (isVideoUpload(file)) {
      try {
        assertFfmpegAvailable();
      } catch (err) {
        return NextResponse.json(
          {
            error: err instanceof Error ? err.message : "Video support unavailable",
            retryable: false,
          },
          { status: 400 }
        );
      }

      const written = await writeUploadToTemp(file);
      cleanupInput = written.cleanup;

      const isVideo = await hasVideoStream(written.path);
      if (isVideo) {
        const extracted = await extractAudio(written.path);
        cleanupOutput = extracted.cleanup;
        const audioBuffer = await fs.readFile(extracted.outputPath);
        convertedAudioBase64 = audioBuffer.toString("base64");
        convertedFilename = file.name.replace(/\.[^.]+$/, "") + ".m4a";
        sendInput = {
          buffer: audioBuffer,
          filename: convertedFilename,
          mime: "audio/mp4",
        };
      } else {
        // Audio-in-video-container: pass the original bytes through.
        sendInput = { file };
      }
    } else {
      sendInput = { file };
    }

    const result = await transcribeFile(sendInput, {
      apiKey,
      model: config.transcribeModel || "scribe_v2",
      languageCode: typeof languageCode === "string" ? languageCode : undefined,
      diarize,
      numSpeakers:
        diarize && typeof numSpeakersRaw === "string" && numSpeakersRaw.trim()
          ? Number.parseInt(numSpeakersRaw, 10)
          : null,
      tagAudioEvents,
      keyterms,
    });

    return NextResponse.json({
      text: result.text,
      language_code: result.language_code,
      language_probability: result.language_probability,
      words: result.words,
      additional_formats: result.additional_formats,
      ...(convertedAudioBase64
        ? {
            convertedAudio: {
              base64: convertedAudioBase64,
              mime: "audio/mp4",
              filename: convertedFilename,
            },
          }
        : {}),
    });
  } catch (err) {
    if (err instanceof AudioExtractError) {
      console.error("Audio extraction failed:", err.stderr);
      return NextResponse.json(
        {
          error:
            "Could not extract audio from this video — the file may be corrupt or use an unsupported codec.",
          retryable: false,
        },
        { status: 400 }
      );
    }
    if (isTranscribeError(err)) {
      return NextResponse.json(
        { error: err.message, retryable: err.retryable },
        { status: err.status }
      );
    }
    console.error("Unexpected transcription failure:", err);
    return NextResponse.json(
      { error: "Transcription failed unexpectedly", retryable: true },
      { status: 500 }
    );
  } finally {
    await cleanupInput?.();
    await cleanupOutput?.();
  }
}
