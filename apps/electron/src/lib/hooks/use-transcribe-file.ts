"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { useTranscribeOptions } from "@/lib/transcribe-options-context";
import { useDictionary } from "@/lib/dictionary-context";
import { createNote } from "@/lib/notes-client";
import { saveAudio } from "@/lib/audio-client";
import type { TranscriptWord } from "@/lib/types";

export const ACCEPT_FILE_TYPES =
  "audio/*,video/*,.mp3,.mp4,.m4a,.wav,.webm,.ogg,.flac,.aac,.wma,.opus,.mov,.mkv,.m4v,.avi";

const VIDEO_EXTENSIONS = new Set(["mp4", "mov", "mkv", "webm", "m4v", "avi"]);
const MAX_FILE_SIZE = 1 * 1024 * 1024 * 1024; // 1 GB
const WARN_FILE_SIZE = 100 * 1024 * 1024; // 100 MB

export type TranscribePhase =
  | "idle"
  | "uploading"
  | "processing"
  | "saving";

function formatFileSize(bytes: number) {
  if (bytes >= 1024 * 1024 * 1024)
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(0)} MB`;
  return `${(bytes / 1024).toFixed(0)} KB`;
}

function isVideoFile(file: File) {
  if (file.type && file.type.startsWith("video/")) return true;
  const ext = file.name.split(".").pop()?.toLowerCase() ?? "";
  return VIDEO_EXTENSIONS.has(ext);
}

function base64ToBlob(base64: string, mime: string): Blob {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return new Blob([bytes], { type: mime });
}

type XhrUploadHandlers = {
  onUploadProgress?: (pct: number) => void;
  onUploadComplete?: () => void;
};

// fetch() doesn't expose upload progress events, so we use XHR for the
// transcribe POST. This lets us tell the user "the file has reached the
// server, now ElevenLabs is processing" instead of one undifferentiated spin.
function xhrUpload(
  url: string,
  formData: FormData,
  signal: AbortSignal,
  handlers: XhrUploadHandlers
): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(new DOMException("Aborted", "AbortError"));
      return;
    }
    const xhr = new XMLHttpRequest();
    xhr.open("POST", url);

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && handlers.onUploadProgress) {
        handlers.onUploadProgress((e.loaded / e.total) * 100);
      }
    };
    xhr.upload.onload = () => handlers.onUploadComplete?.();

    xhr.onload = () => resolve({ status: xhr.status, body: xhr.responseText });
    xhr.onerror = () => reject(new TypeError("Network error"));
    xhr.onabort = () => reject(new DOMException("Aborted", "AbortError"));

    const onAbort = () => xhr.abort();
    signal.addEventListener("abort", onAbort, { once: true });

    xhr.send(formData);
  });
}

export function useTranscribeFile() {
  const router = useRouter();
  const { options: transcribeOptions } = useTranscribeOptions();
  const { terms: keyterms } = useDictionary();
  const abortRef = useRef<AbortController | null>(null);
  const [phase, setPhase] = useState<TranscribePhase>("idle");
  const [uploadProgress, setUploadProgress] = useState(0);
  const [activeFile, setActiveFile] = useState<File | null>(null);
  const [startedAt, setStartedAt] = useState<number | null>(null);
  const [elapsedMs, setElapsedMs] = useState(0);
  const [failedFile, setFailedFile] = useState<File | null>(null);

  // Tick a clock while a job is in flight so the UI can show a real-time
  // elapsed counter. Long ElevenLabs jobs otherwise look frozen.
  useEffect(() => {
    if (startedAt === null) return;
    const id = setInterval(() => {
      setElapsedMs(Date.now() - startedAt);
    }, 250);
    return () => clearInterval(id);
  }, [startedAt]);

  function cancel() {
    abortRef.current?.abort();
    abortRef.current = null;
    setPhase("idle");
    setUploadProgress(0);
    setActiveFile(null);
    setStartedAt(null);
    setElapsedMs(0);
    toast.info("Upload cancelled");
  }

  async function handleFile(file: File) {
    if (file.size > MAX_FILE_SIZE) {
      toast.error(
        `File too large (${formatFileSize(file.size)}). Maximum is 1 GB.`
      );
      return;
    }

    if (file.size > WARN_FILE_SIZE) {
      toast.info(
        `Large file (${formatFileSize(file.size)}) — upload may take a while.`
      );
    }

    abortRef.current = new AbortController();
    setActiveFile(file);
    setPhase("uploading");
    setUploadProgress(0);
    setElapsedMs(0);
    setStartedAt(Date.now());
    setFailedFile(null);

    try {
      const form = new FormData();
      form.append("file", file);

      if (
        transcribeOptions.languageCode &&
        transcribeOptions.languageCode !== "auto"
      ) {
        form.append("language_code", transcribeOptions.languageCode);
      }
      if (transcribeOptions.diarize) {
        form.append("diarize", "true");
        if (transcribeOptions.numSpeakers) {
          form.append("num_speakers", transcribeOptions.numSpeakers.toString());
        }
      }
      if (transcribeOptions.tagAudioEvents) {
        form.append("tag_audio_events", "true");
      }
      for (const term of keyterms) {
        form.append("keyterms", term);
      }

      const { status, body } = await xhrUpload(
        "/api/transcribe",
        form,
        abortRef.current.signal,
        {
          onUploadProgress: (pct) => setUploadProgress(pct),
          // upload.onload fires when bytes are fully sent; the server is now
          // either converting video and/or waiting on ElevenLabs.
          onUploadComplete: () => {
            setUploadProgress(100);
            setPhase("processing");
          },
        }
      );

      if (status < 200 || status >= 300) {
        const data = body ? (JSON.parse(body) as { error?: string }) : {};
        throw new Error(data.error || `Transcription failed (${status})`);
      }

      const data = JSON.parse(body) as {
        text: string;
        language_code?: string;
        language_probability?: number;
        words?: TranscriptWord[];
        additional_formats?: Record<string, string>;
        convertedAudio?: { base64: string; mime: string };
      };

      setPhase("saving");

      const noteId = crypto.randomUUID();
      const note = await createNote({
        id: noteId,
        title: file.name.replace(/\.[^.]+$/, ""),
        content: data.text,
        type: "transcription",
        source: "upload",
        audioFileName: file.name,
        language: data.language_code,
        metadata: {
          words: data.words,
          languageProbability: data.language_probability,
          ...(data.additional_formats && {
            additionalFormats: data.additional_formats,
          }),
          hasDiarization: transcribeOptions.diarize,
          hasAudioEventTags: transcribeOptions.tagAudioEvents,
        },
      });

      const audioPayload: Blob | File = data.convertedAudio
        ? base64ToBlob(data.convertedAudio.base64, data.convertedAudio.mime)
        : file;
      await saveAudio(note.id, audioPayload).catch((err) =>
        console.warn("Failed to save audio:", err)
      );

      toast.success("Transcription complete!");
      router.push(`/notes/${note.id}`);
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") return;
      const message =
        err instanceof Error ? err.message : "Transcription failed";
      setFailedFile(file);
      toast.error(message, {
        action: {
          label: "Retry",
          onClick: () => {
            setFailedFile(null);
            handleFile(file);
          },
        },
        duration: 8000,
      });
    } finally {
      abortRef.current = null;
      setPhase("idle");
      setUploadProgress(0);
      setActiveFile(null);
      setStartedAt(null);
      setElapsedMs(0);
    }
  }

  return {
    phase,
    uploadProgress,
    elapsedMs,
    activeFile,
    isVideo: activeFile ? isVideoFile(activeFile) : false,
    failedFile,
    handleFile,
    cancel,
    clearFailed: () => setFailedFile(null),
    isWorking: phase !== "idle",
  };
}
