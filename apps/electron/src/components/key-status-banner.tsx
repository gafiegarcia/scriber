"use client";

import Link from "next/link";
import { AlertTriangle } from "lucide-react";
import { useKeyStatus } from "@/lib/key-status-context";

export function KeyStatusBanner() {
  const { status, error } = useKeyStatus();

  if (
    status !== "invalid" &&
    status !== "missing" &&
    status !== "unavailable"
  ) {
    return null;
  }

  const message =
    status === "missing"
      ? "No ElevenLabs API key configured — transcription is disabled."
      : status === "unavailable"
        ? error || "Scriber can't access secure key storage — transcription is disabled."
        : error
        ? `ElevenLabs key isn't working: ${error}`
        : "Your ElevenLabs API key isn't working — transcription is disabled.";

  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-destructive/30 bg-destructive/10 px-5 py-2 text-xs text-destructive">
      <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
      <span className="flex-1">{message}</span>
      <Link
        href="/settings"
        className="whitespace-nowrap font-medium underline underline-offset-2 hover:no-underline"
      >
        Configure
      </Link>
    </div>
  );
}
