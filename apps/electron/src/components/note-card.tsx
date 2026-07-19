"use client";

import Link from "next/link";
import { Mic, Upload, FileText, ChevronRight } from "lucide-react";
import type { Note } from "@/lib/types";

const sourceIcons = {
  recording: Mic,
  upload: Upload,
  text: FileText,
} as const;

const sourceLabels = {
  recording: "Recording",
  upload: "Upload",
  text: "Text",
} as const;

function timeAgo(iso: string) {
  const diff = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return "Just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

function HighlightText({ text, highlight }: { text: string; highlight?: string }) {
  if (!highlight || !highlight.trim()) return <>{text}</>;
  const regex = new RegExp(`(${highlight.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi");
  const parts = text.split(regex);
  return (
    <>
      {parts.map((part, i) =>
        regex.test(part) ? (
          <mark key={i} className="rounded-sm bg-yellow-200/60 dark:bg-yellow-500/30">
            {part}
          </mark>
        ) : (
          part
        )
      )}
    </>
  );
}

export function NoteCard({ note, highlight }: { note: Note; highlight?: string }) {
  const Icon = sourceIcons[note.source] ?? FileText;
  const label = sourceLabels[note.source] ?? "Note";
  const wordCount = note.content.trim() === "" ? 0 : note.content.trim().split(/\s+/).length;

  return (
    <Link
      href={`/notes/${note.id}`}
      className="group block rounded-2xl border border-border/60 bg-card p-4 transition-all active:scale-[0.98] hover:border-border hover:shadow-sm"
    >
      {/* Source badge + time */}
      <div className="mb-3 flex items-center gap-1.5">
        <div className="flex items-center gap-1 rounded-full bg-muted px-2.5 py-0.5">
          <Icon className="h-3 w-3 text-muted-foreground" aria-hidden="true" />
          <span className="text-xs font-medium text-muted-foreground">
            {label}
          </span>
        </div>
        <span className="ml-auto text-xs text-muted-foreground">
          {timeAgo(note.createdAt)}
        </span>
      </div>

      {/* Title */}
      <h3 className="line-clamp-1 text-base font-semibold leading-snug">
        <HighlightText text={note.title} highlight={highlight} />
      </h3>

      {/* Preview */}
      <p className="mt-1.5 line-clamp-2 text-sm leading-relaxed text-muted-foreground">
        <HighlightText text={note.content} highlight={highlight} />
      </p>

      {/* Tags */}
      {note.tags && note.tags.length > 0 && (
        <div className="mt-2 flex flex-wrap items-center gap-1">
          {note.tags.slice(0, 3).map((tag) => (
            <span
              key={tag}
              className="rounded-full bg-foreground/10 px-2 py-0.5 text-[11px] font-medium text-foreground/60"
            >
              {tag}
            </span>
          ))}
          {note.tags.length > 3 && (
            <span className="text-[11px] text-muted-foreground">
              +{note.tags.length - 3}
            </span>
          )}
        </div>
      )}

      {/* Footer */}
      <div className="mt-3 flex items-center justify-between">
        <span className="text-sm text-muted-foreground">
          {wordCount} words
          {note.language && note.language !== "auto" && (
            <> &middot; {note.language.toUpperCase()}</>
          )}
        </span>
        <ChevronRight className="h-4 w-4 text-muted-foreground/60 transition-transform group-hover:translate-x-0.5" aria-hidden="true" />
      </div>
    </Link>
  );
}
