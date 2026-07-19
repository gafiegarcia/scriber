import type { ScribeResponse } from "@/lib/types/elevenlabs";

const MAX_RETRIES = 2;
const INITIAL_BACKOFF_MS = 1000;
const ELEVENLABS_ENDPOINT = "https://api.elevenlabs.io/v1/speech-to-text";

export interface TranscribeRunOptions {
  apiKey: string;
  model?: string;
  languageCode?: string;
  diarize?: boolean;
  numSpeakers?: number | null;
  tagAudioEvents?: boolean;
  keyterms?: string[];
}

export type TranscribeInput =
  | { file: File }
  | { buffer: Buffer; filename: string; mime: string };

export interface TranscribeError extends Error {
  retryable: boolean;
  status: number;
}

function isRetryable(status: number): boolean {
  return status >= 500 || status === 429;
}

function parseElevenLabsError(
  status: number,
  body: string
): { message: string; retryable: boolean } {
  try {
    const parsed = JSON.parse(body);
    const detail =
      parsed?.detail?.message || parsed?.detail || parsed?.error || parsed?.message;
    if (detail && typeof detail === "string") {
      if (status === 429) {
        return {
          message: "Rate limit exceeded — please wait a moment and try again",
          retryable: true,
        };
      }
      if (status === 401 || status === 403) {
        return {
          message: "API authentication failed — check your ElevenLabs API key",
          retryable: false,
        };
      }
      if (status === 400) return { message: `Invalid request: ${detail}`, retryable: false };
      if (status === 413) {
        return { message: "File too large for the transcription service", retryable: false };
      }
      return { message: detail, retryable: isRetryable(status) };
    }
  } catch {
    // fall through to status-only mapping
  }
  if (status === 429) {
    return {
      message: "Rate limit exceeded — please wait a moment and try again",
      retryable: true,
    };
  }
  if (status === 401 || status === 403) {
    return { message: "API authentication failed", retryable: false };
  }
  if (status === 413) {
    return { message: "File too large for the transcription service", retryable: false };
  }
  if (status >= 500) {
    return { message: "Transcription service is temporarily unavailable", retryable: true };
  }
  return { message: `Transcription failed (${status})`, retryable: false };
}

function sleep(ms: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

function toTranscribeError(
  message: string,
  retryable: boolean,
  status: number
): TranscribeError {
  const err = new Error(message) as TranscribeError;
  err.retryable = retryable;
  err.status = status;
  return err;
}

function toBlobAndFilename(input: TranscribeInput): { blob: Blob; filename: string } {
  if ("file" in input) {
    return { blob: input.file, filename: input.file.name };
  }
  const blob = new Blob([new Uint8Array(input.buffer)], { type: input.mime });
  return { blob, filename: input.filename };
}

/**
 * Call ElevenLabs Scribe v2 with retry + backoff for transient failures.
 * Throws a `TranscribeError` (with `retryable` and `status`) on terminal failure.
 */
export async function transcribeFile(
  input: TranscribeInput,
  opts: TranscribeRunOptions
): Promise<ScribeResponse> {
  const { blob, filename } = toBlobAndFilename(input);

  const form = new FormData();
  form.append("file", blob, filename);
  form.append("model_id", opts.model || "scribe_v2");
  form.append("timestamps_granularity", "word");

  if (opts.languageCode && opts.languageCode !== "auto") {
    form.append("language_code", opts.languageCode);
  }
  if (opts.diarize) {
    form.append("diarize", "true");
    if (opts.numSpeakers != null) {
      form.append("num_speakers", String(opts.numSpeakers));
    }
  }
  if (opts.tagAudioEvents) {
    form.append("tag_audio_events", "true");
  }
  for (const term of opts.keyterms ?? []) {
    const trimmed = term.trim();
    if (trimmed) form.append("keyterms", trimmed);
  }

  let lastError: { message: string; retryable: boolean; status: number } | null = null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    if (attempt > 0) {
      const backoff = INITIAL_BACKOFF_MS * Math.pow(2, attempt - 1);
      console.error(`Retry attempt ${attempt}/${MAX_RETRIES} after ${backoff}ms`);
      await sleep(backoff);
    }

    try {
      const response = await fetch(ELEVENLABS_ENDPOINT, {
        method: "POST",
        headers: { "xi-api-key": opts.apiKey },
        body: form,
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error(
          `ElevenLabs API error (attempt ${attempt + 1}):`,
          response.status,
          errorText
        );
        const parsed = parseElevenLabsError(response.status, errorText);
        lastError = {
          ...parsed,
          status: response.status >= 500 ? 502 : response.status,
        };
        if (parsed.retryable && attempt < MAX_RETRIES) continue;
        throw toTranscribeError(parsed.message, parsed.retryable, lastError.status);
      }

      return (await response.json()) as ScribeResponse;
    } catch (err) {
      if (err instanceof Error && "status" in err && "retryable" in err) {
        throw err;
      }
      console.error(`Transcription request failed (attempt ${attempt + 1}):`, err);
      lastError = {
        message: "Failed to reach transcription service",
        retryable: true,
        status: 502,
      };
      if (attempt < MAX_RETRIES) continue;
    }
  }

  throw toTranscribeError(
    lastError?.message || "Transcription failed after retries",
    lastError?.retryable ?? true,
    lastError?.status ?? 502
  );
}
