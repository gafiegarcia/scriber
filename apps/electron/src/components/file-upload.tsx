"use client";

import { useRef } from "react";
import { Upload, Loader2, RotateCcw } from "lucide-react";
import {
  ACCEPT_FILE_TYPES,
  useTranscribeFile,
} from "@/lib/hooks/use-transcribe-file";

export function FileUpload() {
  const inputRef = useRef<HTMLInputElement>(null);
  const {
    phase,
    uploadProgress,
    isVideo,
    failedFile,
    handleFile,
    cancel,
    clearFailed,
    isWorking,
  } = useTranscribeFile();

  const workingLabel =
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

  return (
    <>
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

      {isWorking ? (
        <button
          onClick={cancel}
          className="flex h-14 w-14 items-center justify-center rounded-full border-2 border-border bg-muted/50 transition-colors hover:border-destructive hover:bg-destructive/10"
          aria-label={`${workingLabel} — tap to cancel`}
          title={`${workingLabel} — tap to cancel`}
        >
          {phase === "uploading" && uploadProgress > 0 ? (
            <span className="text-xs font-medium tabular-nums text-muted-foreground">
              {Math.floor(uploadProgress)}%
            </span>
          ) : (
            <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
          )}
        </button>
      ) : failedFile ? (
        <button
          onClick={() => {
            clearFailed();
            handleFile(failedFile);
          }}
          className="flex h-14 w-14 items-center justify-center rounded-full border-2 border-destructive/30 bg-destructive/5 text-destructive transition-all active:scale-95"
          aria-label="Retry upload"
          title={`Retry: ${failedFile.name}`}
        >
          <RotateCcw className="h-5 w-5" />
        </button>
      ) : (
        <button
          onClick={() => inputRef.current?.click()}
          className="flex h-14 w-14 items-center justify-center rounded-full border-2 border-border bg-background text-muted-foreground transition-all hover:border-foreground/30 hover:text-foreground active:scale-95"
          aria-label="Upload audio file"
        >
          <Upload className="h-5 w-5" />
        </button>
      )}
    </>
  );
}
