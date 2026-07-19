"use client";

import { useRef, useState } from "react";
import { Upload, Loader2, RotateCcw, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  ACCEPT_FILE_TYPES,
  useTranscribeFile,
} from "@/lib/hooks/use-transcribe-file";
import { VoiceRecorder } from "@/components/voice-recorder";
import { TranscribeOptions } from "@/components/transcribe-options";

function formatElapsed(ms: number) {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export function TranscribeHero() {
  const inputRef = useRef<HTMLInputElement>(null);
  const {
    phase,
    uploadProgress,
    elapsedMs,
    isVideo,
    failedFile,
    handleFile,
    cancel,
    clearFailed,
    isWorking,
  } = useTranscribeFile();
  const [dragOver, setDragOver] = useState(false);

  const primaryLabel =
    phase === "uploading"
      ? uploadProgress > 0
        ? `Uploading… ${Math.floor(uploadProgress)}%`
        : "Uploading…"
      : phase === "processing"
        ? isVideo
          ? "Converting & scribing…"
          : "Scribing…"
        : phase === "saving"
          ? "Saving…"
          : "Working…";

  const showElapsed = phase === "processing";
  const showSlowHint = phase === "processing" && elapsedMs > 30_000;

  function onDrop(e: React.DragEvent<HTMLDivElement>) {
    e.preventDefault();
    setDragOver(false);
    const file = e.dataTransfer.files?.[0];
    if (file) handleFile(file);
  }

  function openPicker() {
    inputRef.current?.click();
  }

  const interactive = !isWorking && !failedFile;

  return (
    <div className="flex w-full max-w-2xl flex-col items-center gap-8">
      <input
        ref={inputRef}
        type="file"
        accept={ACCEPT_FILE_TYPES}
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) handleFile(file);
          if (inputRef.current) inputRef.current.value = "";
        }}
      />

      <div
        onDragEnter={(e) => {
          e.preventDefault();
          setDragOver(true);
        }}
        onDragOver={(e) => {
          e.preventDefault();
          setDragOver(true);
        }}
        onDragLeave={(e) => {
          e.preventDefault();
          if (e.currentTarget.contains(e.relatedTarget as Node)) return;
          setDragOver(false);
        }}
        onDrop={onDrop}
        onClick={interactive ? openPicker : undefined}
        role={interactive ? "button" : undefined}
        tabIndex={interactive ? 0 : -1}
        onKeyDown={(e) => {
          if (interactive && (e.key === "Enter" || e.key === " ")) {
            e.preventDefault();
            openPicker();
          }
        }}
        aria-label="Drop an audio file or click to choose one"
        className={`group flex h-60 w-full flex-col items-center justify-center gap-4 rounded-2xl border-2 border-dashed transition-colors ${
          dragOver
            ? "border-foreground/40 bg-foreground/5"
            : "border-border bg-card/40 hover:border-foreground/20 hover:bg-card"
        } ${interactive ? "cursor-pointer" : "cursor-default"}`}
      >
        {isWorking ? (
          <>
            <div className="flex h-14 w-14 items-center justify-center rounded-full bg-muted">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
            <div className="flex flex-col items-center gap-1">
              <p className="text-sm font-medium text-foreground">
                {primaryLabel}
                {showElapsed && (
                  <span className="ml-2 font-mono text-xs text-muted-foreground">
                    {formatElapsed(elapsedMs)}
                  </span>
                )}
              </p>
              {phase === "uploading" && (
                <div
                  className="h-1 w-40 overflow-hidden rounded-full bg-muted"
                  role="progressbar"
                  aria-valuenow={Math.floor(uploadProgress)}
                  aria-valuemin={0}
                  aria-valuemax={100}
                >
                  <div
                    className="h-full bg-foreground/60 transition-[width] duration-150 ease-out"
                    style={{ width: `${uploadProgress}%` }}
                  />
                </div>
              )}
              {showSlowHint && (
                <p className="text-xs text-muted-foreground">
                  Long recordings can take a few minutes.
                </p>
              )}
            </div>
            <button
              onClick={(e) => {
                e.stopPropagation();
                cancel();
              }}
              className="inline-flex items-center gap-1 rounded-full border border-border px-3 py-1 text-xs text-muted-foreground transition-colors hover:border-destructive hover:text-destructive"
            >
              <X className="h-3 w-3" />
              Cancel
            </button>
          </>
        ) : failedFile ? (
          <>
            <div className="flex h-14 w-14 items-center justify-center rounded-full border-2 border-destructive/30 bg-destructive/5 text-destructive">
              <RotateCcw className="h-6 w-6" />
            </div>
            <div className="text-center">
              <p className="text-sm font-medium text-destructive">
                Transcription failed
              </p>
              <p className="mt-0.5 text-xs text-muted-foreground">
                {failedFile.name}
              </p>
            </div>
            <div className="flex items-center gap-2">
              <Button
                size="sm"
                variant="outline"
                onClick={(e) => {
                  e.stopPropagation();
                  clearFailed();
                }}
              >
                Discard
              </Button>
              <Button
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  const file = failedFile;
                  clearFailed();
                  handleFile(file);
                }}
              >
                Retry
              </Button>
            </div>
          </>
        ) : (
          <>
            <div className="flex h-14 w-14 items-center justify-center rounded-full bg-muted text-muted-foreground transition-colors group-hover:bg-foreground/10 group-hover:text-foreground">
              <Upload className="h-6 w-6" />
            </div>
            <div className="text-center">
              <p className="text-base font-medium text-foreground">
                Drop an audio file or click to choose
              </p>
              <p className="mt-1 text-sm text-muted-foreground">
                Audio or video, up to 1 GB
              </p>
            </div>
          </>
        )}
      </div>

      {/* Secondary actions — or / Record / Options */}
      <div className="flex w-full flex-col items-center gap-5">
        <div className="flex w-full items-center gap-3">
          <div className="h-px flex-1 bg-border/40" />
          <span className="text-xs uppercase tracking-wider text-muted-foreground/50">
            or
          </span>
          <div className="h-px flex-1 bg-border/40" />
        </div>
        <div className="flex items-center gap-6">
          <div className="flex flex-col items-center gap-2">
            <VoiceRecorder />
            <span className="text-xs font-medium text-muted-foreground">
              Record
            </span>
          </div>
        </div>
        <TranscribeOptions />
      </div>
    </div>
  );
}
