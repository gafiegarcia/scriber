"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { useRouter } from "next/navigation";
import { Mic, Square, Loader2, Send, X, RotateCcw } from "lucide-react";
import { toast } from "sonner";
import { useAudioRecorder } from "@/lib/hooks/use-audio-recorder";
import { useTranscribeOptions } from "@/lib/transcribe-options-context";
import { useDictionary } from "@/lib/dictionary-context";
import { createNote } from "@/lib/notes-client";
import { saveAudio } from "@/lib/audio-client";

const MIN_RECORDING_SECONDS = 3;

function formatDuration(seconds: number) {
  const m = Math.floor(seconds / 60)
    .toString()
    .padStart(2, "0");
  const s = (seconds % 60).toString().padStart(2, "0");
  return `${m}:${s}`;
}

export function VoiceRecorder() {
  const router = useRouter();
  const { options: transcribeOptions } = useTranscribeOptions();
  const { terms: keyterms } = useDictionary();
  const {
    isRecording,
    duration,
    audioBlob,
    error,
    startRecording,
    stopRecording,
    discardRecording,
  } = useAudioRecorder();

  const [transcribing, setTranscribing] = useState(false);
  const [lastError, setLastError] = useState<string | null>(null);
  const durationRef = useRef(duration);
  useEffect(() => { durationRef.current = duration; });
  const [stoppedDuration, setStoppedDuration] = useState(0);

  useEffect(() => {
    if (error) toast.error(error);
  }, [error]);

  // Warn before leaving while recording or transcribing
  useEffect(() => {
    if (!isRecording && !transcribing) return;
    const handleBeforeUnload = (e: BeforeUnloadEvent) => {
      e.preventDefault();
    };
    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => window.removeEventListener("beforeunload", handleBeforeUnload);
  }, [isRecording, transcribing]);

  // Capture duration when recording stops
  useEffect(() => {
    if (audioBlob) {
      setStoppedDuration(durationRef.current);
    }
  }, [audioBlob]);

  function handleDiscard() {
    discardRecording();
    setStoppedDuration(0);
    toast.info("Recording discarded");
  }

  const handleSend = useCallback(async () => {
    if (!audioBlob) return;

    if (stoppedDuration < MIN_RECORDING_SECONDS) {
      toast.error(`Recording too short (minimum ${MIN_RECORDING_SECONDS}s). Please try again.`);
      discardRecording();
      setStoppedDuration(0);
      return;
    }

    setTranscribing(true);
    setLastError(null);
    try {
      const form = new FormData();
      const ext = audioBlob.type.includes("webm") ? "webm" : "ogg";
      const file = new File([audioBlob], `recording.${ext}`, {
        type: audioBlob.type,
      });
      form.append("file", file);

      // Append transcription options
      if (transcribeOptions.languageCode && transcribeOptions.languageCode !== "auto") {
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

      const res = await fetch("/api/transcribe", {
        method: "POST",
        body: form,
      });

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(
          data.error || `Transcription failed (${res.status})`
        );
      }

      const data = await res.json();

      const noteId = crypto.randomUUID();
      const note = await createNote({
        id: noteId,
        title: `Recording ${new Date().toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" })}`,
        content: data.text,
        type: "transcription",
        source: "recording",
        durationSeconds: stoppedDuration,
        language: data.language_code,
        metadata: {
          words: data.words,
          languageProbability: data.language_probability,
          hasDiarization: transcribeOptions.diarize,
          hasAudioEventTags: transcribeOptions.tagAudioEvents,
        },
      });

      await saveAudio(note.id, audioBlob).catch((err) =>
        console.warn("Failed to save audio:", err)
      );

      toast.success("Transcription complete!");
      router.push(`/notes/${note.id}`);
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "Transcription failed";
      setLastError(message);
      toast.error(message);
    } finally {
      setTranscribing(false);
    }
  }, [audioBlob, stoppedDuration, discardRecording, router, transcribeOptions, keyterms]);

  // Transcribing state
  if (transcribing) {
    return (
      <div className="flex flex-col items-center gap-3" role="status" aria-live="polite">
        <div className="relative flex h-[72px] w-[72px] items-center justify-center">
          <div className="absolute inset-0 animate-spin rounded-full border-2 border-muted border-t-foreground" />
          <Loader2 className="h-7 w-7 animate-spin text-muted-foreground" aria-hidden="true" />
        </div>
        <span className="text-sm font-medium text-muted-foreground">
          Transcribing...
        </span>
      </div>
    );
  }

  // Error state — transcription failed, can retry or discard
  if (audioBlob && !transcribing && lastError) {
    return (
      <div className="flex flex-col items-center gap-3">
        <div className="flex h-[72px] w-[72px] items-center justify-center rounded-full border-2 border-destructive/30 bg-destructive/5">
          <RotateCcw className="h-6 w-6 text-destructive" />
        </div>
        <p className="max-w-[240px] text-center text-sm text-destructive">
          {lastError}
        </p>
        <div className="flex items-center gap-3">
          <button
            onClick={() => {
              discardRecording();
              setStoppedDuration(0);
              setLastError(null);
              toast.info("Recording discarded");
            }}
            className="flex h-10 items-center gap-1.5 rounded-full border-2 border-border px-4 text-sm text-muted-foreground transition-all active:scale-95"
          >
            <X className="h-4 w-4" />
            Discard
          </button>
          <button
            onClick={handleSend}
            className="flex h-10 items-center gap-1.5 rounded-full bg-foreground px-4 text-sm text-background shadow-lg transition-all active:scale-95"
          >
            <RotateCcw className="h-4 w-4" />
            Retry
          </button>
        </div>
      </div>
    );
  }

  // Review state — recording stopped, blob ready
  if (audioBlob && !transcribing) {
    return (
      <div className="flex flex-col items-center gap-4">
        <span className="font-mono text-base font-semibold tabular-nums text-muted-foreground">
          {formatDuration(stoppedDuration)}
        </span>
        <div className="flex items-center gap-4">
          <button
            onClick={handleDiscard}
            className="flex h-12 w-12 items-center justify-center rounded-full border-2 border-border text-muted-foreground transition-all hover:border-destructive hover:text-destructive active:scale-95"
            aria-label="Discard recording"
          >
            <X className="h-5 w-5" />
          </button>
          <button
            onClick={handleSend}
            className="flex h-14 w-14 items-center justify-center rounded-full bg-foreground text-background shadow-lg transition-all hover:brightness-110 active:scale-95"
            aria-label="Send for transcription"
          >
            <Send className="h-5 w-5" />
          </button>
        </div>
        <span className="text-xs text-muted-foreground">
          Send to transcribe or discard
        </span>
      </div>
    );
  }

  // Recording state
  if (isRecording) {
    return (
      <div className="flex flex-col items-center gap-3">
        <div className="relative">
          {/* Pulsing glow */}
          <div className="absolute -inset-3 animate-pulse rounded-full bg-red-500/20" />
          <div className="absolute -inset-1.5 animate-pulse rounded-full bg-red-500/10" style={{ animationDelay: "150ms" }} />
          <button
            onClick={stopRecording}
            className="relative flex h-[72px] w-[72px] items-center justify-center rounded-full bg-red-500 text-white shadow-xl shadow-red-500/30 transition-transform active:scale-95"
            aria-label="Stop recording"
          >
            <Square className="h-7 w-7" fill="currentColor" />
          </button>
        </div>
        <span className="font-mono text-base font-semibold tabular-nums text-red-500" role="timer" aria-live="off" aria-label={`Recording duration: ${formatDuration(duration)}`}>
          {formatDuration(duration)}
        </span>
        <button
          onClick={handleDiscard}
          className="text-xs text-muted-foreground transition-colors hover:text-destructive"
          aria-label="Cancel recording"
        >
          Cancel
        </button>
      </div>
    );
  }

  // Idle state
  return (
    <button
      onClick={startRecording}
      className="flex h-[72px] w-[72px] items-center justify-center rounded-full bg-red-500 text-white shadow-xl shadow-red-500/25 transition-all hover:shadow-red-500/40 hover:brightness-110 active:scale-95"
      aria-label="Start recording"
    >
      <Mic className="h-7 w-7" />
    </button>
  );
}
