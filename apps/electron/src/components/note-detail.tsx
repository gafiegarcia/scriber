"use client";

import { useState, useEffect, useMemo, useRef, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  ArrowLeft,
  Copy,
  Trash2,
  Check,
  Pencil,
  Download,
  Tag,
  X,
  Plus,
  EllipsisVertical,
  ChevronDown,
} from "lucide-react";
import { toast } from "sonner";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubTrigger,
  DropdownMenuSubContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useNotes } from "@/lib/hooks/use-notes";
import { updateNote, deleteNote } from "@/lib/notes-client";
import { toTxt, toTxtWithMeta, toPlainMarkdown, toSrt, toMarkdown, downloadFile } from "@/lib/export";
import { DiarizedTranscript } from "@/components/diarized-transcript";
import { deleteAudio } from "@/lib/audio-client";
import { AudioPlayer, type AudioPlayerHandle } from "@/components/audio-player";
import { SyncedTranscript } from "@/components/synced-transcript";
import { SelectionToolbar } from "@/components/selection-toolbar";
import type { Note } from "@/lib/types";


function formatDate(iso: string) {
  return new Date(iso).toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
}


export function NoteDetail({ note }: { note: Note }) {
  const router = useRouter();

  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(note.title);
  const [copied, setCopied] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);

  // Resync the title draft when the note changes externally (e.g. another tab),
  // but only when not actively editing. https://react.dev/reference/react/useState#storing-information-from-previous-renders
  const [prevTitle, setPrevTitle] = useState(note.title);
  if (note.title !== prevTitle) {
    setPrevTitle(note.title);
    if (!editing) setTitle(note.title);
  }

  const [tagInput, setTagInput] = useState("");
  const [showTagInput, setShowTagInput] = useState(false);

  // Transcript container ref for selection toolbar
  const transcriptRef = useRef<HTMLDivElement>(null);

  // Audio sync state for word-level highlighting
  const audioPlayerRef = useRef<AudioPlayerHandle>(null);
  const [hasAudio, setHasAudio] = useState(false);
  const [isAudioPlaying, setIsAudioPlaying] = useState(false);

  const getTime = useCallback(() => {
    return audioPlayerRef.current?.getCurrentTime() ?? 0;
  }, []);

  // Spacebar toggles play/pause (skip when user is typing in an input)
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.code !== "Space" || !hasAudio) return;

      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || (e.target as HTMLElement)?.isContentEditable) {
        return;
      }

      e.preventDefault();
      audioPlayerRef.current?.togglePlayPause();
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [hasAudio]);

  const handleWordClick = useCallback((time: number) => {
    audioPlayerRef.current?.seek(time);
  }, []);

  // Derive existing tags from all notes (for autocomplete suggestions)
  const { notes: allNotes } = useNotes();
  const existingTags = useMemo(() => {
    const tagSet = new Set<string>();
    for (const n of allNotes) {
      if (n.tags) for (const t of n.tags) tagSet.add(t);
    }
    return Array.from(tagSet).sort((a, b) => a.localeCompare(b));
  }, [allNotes]);

  const wordCount = note.content.trim() === "" ? 0 : note.content.trim().split(/\s+/).length;
  const hasTimestamps = (note.metadata?.words?.length ?? 0) > 0;

  async function handleAddTag(value: string) {
    const tag = value.trim().toLowerCase();
    if (!tag) return;
    const currentTags = note.tags ?? [];
    if (currentTags.includes(tag)) {
      setTagInput("");
      return;
    }
    await updateNote(note.id, { tags: [...currentTags, tag] });
    setTagInput("");
  }

  async function handleRemoveTag(tag: string) {
    await updateNote(note.id, {
      tags: (note.tags ?? []).filter((t) => t !== tag),
    });
  }

  async function handleSaveTitle() {
    const trimmed = title.trim() || "Untitled Note";
    await updateNote(note.id, { title: trimmed });
    setEditing(false);
  }

  async function handleCopy() {
    await navigator.clipboard.writeText(note.content);
    setCopied(true);
    toast.success("Copied to clipboard");
    setTimeout(() => setCopied(false), 2000);
  }

  async function handleCopyAs(format: string) {
    let text: string;
    let label: string;
    switch (format) {
      case "txt":
        text = toTxt(note);
        label = "plain text";
        break;
      case "txt-meta":
        text = toTxtWithMeta(note);
        label = "text with metadata";
        break;
      case "md":
        text = toPlainMarkdown(note);
        label = "Markdown";
        break;
      case "md-meta":
        text = toMarkdown(note);
        label = "Markdown with metadata";
        break;
      case "srt":
        text = toSrt(note);
        label = "SRT subtitles";
        break;
      default:
        return;
    }
    await navigator.clipboard.writeText(text);
    setCopied(true);
    toast.success(`Copied as ${label}`);
    setTimeout(() => setCopied(false), 2000);
  }

  function handleExport(format: string) {
    const baseName =
      note.title.replace(/[^a-zA-Z0-9-_ ]/g, "").trim() || "note";
    const ext = format.startsWith("txt") ? "txt" : format.startsWith("md") ? "md" : format;
    switch (format) {
      case "txt":
        downloadFile(toTxt(note), `${baseName}.txt`, "text/plain");
        break;
      case "txt-meta":
        downloadFile(toTxtWithMeta(note), `${baseName}.txt`, "text/plain");
        break;
      case "md":
        downloadFile(toPlainMarkdown(note), `${baseName}.md`, "text/markdown");
        break;
      case "md-meta":
        downloadFile(toMarkdown(note), `${baseName}.md`, "text/markdown");
        break;
      case "srt":
        downloadFile(toSrt(note), `${baseName}.srt`, "application/x-subrip");
        break;
    }
    toast.success(`Exported as .${ext}`);
  }

  async function handleDelete() {
    deleteAudio(note.id).catch(console.warn);
    await deleteNote(note.id);
    toast.success("Note deleted");
    router.push("/notes");
  }

  return (
    <div className="flex flex-col">
      {/* Sticky header: back + title + ⋯ menu */}
      <div className="sticky top-0 z-10 flex items-center gap-2 border-b border-border/40 bg-background/80 px-3 py-3 backdrop-blur-lg">
        <button
          onClick={() => router.push("/notes")}
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-muted active:scale-95 lg:hidden"
          aria-label="Back to notes"
        >
          <ArrowLeft className="h-5 w-5" />
        </button>

        {editing ? (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              handleSaveTitle();
            }}
            className="flex flex-1 items-center gap-2"
          >
            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              autoFocus
              onBlur={() => handleSaveTitle()}
              className="flex-1 rounded-lg border border-border bg-muted/50 px-3 py-1.5 text-base font-semibold outline-none focus:border-foreground/20"
            />
          </form>
        ) : (
          <button
            onClick={() => setEditing(true)}
            className="group flex flex-1 items-center gap-2 overflow-hidden text-left"
          >
            <h1 className="truncate text-base font-semibold">{note.title}</h1>
            <Pencil className="h-3.5 w-3.5 shrink-0 text-muted-foreground/50 transition-colors group-hover:text-muted-foreground" />
          </button>
        )}

        {/* ⋯ menu: Export + Delete */}
        <DropdownMenu>
          <DropdownMenuTrigger
            render={
              <button className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-muted active:scale-95" aria-label="More actions" />
            }
          >
            <EllipsisVertical className="h-5 w-5" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="min-w-48 p-1.5">
            <DropdownMenuSub>
              <DropdownMenuSubTrigger className="py-2.5">
                <Download className="h-4 w-4" />
                Export
              </DropdownMenuSubTrigger>
              <DropdownMenuSubContent className="min-w-52 p-1.5">
                <DropdownMenuItem className="py-2.5" onClick={() => handleExport("txt")}>
                  Plain Text (.txt)
                </DropdownMenuItem>
                <DropdownMenuItem className="py-2.5" onClick={() => handleExport("txt-meta")}>
                  Text + metadata (.txt)
                </DropdownMenuItem>
                <DropdownMenuItem className="py-2.5" onClick={() => handleExport("md")}>
                  Markdown (.md)
                </DropdownMenuItem>
                <DropdownMenuItem className="py-2.5" onClick={() => handleExport("md-meta")}>
                  Markdown + metadata (.md)
                </DropdownMenuItem>
                {hasTimestamps && (
                  <DropdownMenuItem className="py-2.5" onClick={() => handleExport("srt")}>
                    Subtitles (.srt)
                  </DropdownMenuItem>
                )}
              </DropdownMenuSubContent>
            </DropdownMenuSub>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              className="py-2.5"
              variant="destructive"
              onClick={() => setDeleteOpen(true)}
            >
              <Trash2 className="h-4 w-4" />
              Delete note
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>

        {/* Delete confirmation dialog (controlled) */}
        <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete this note?</AlertDialogTitle>
              <AlertDialogDescription>
                This action cannot be undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction onClick={handleDelete}>
                Delete
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </div>

      {/* Metadata line */}
      <p className="px-5 pt-3 text-xs text-muted-foreground">
        {formatDate(note.createdAt)}
        {` · ${wordCount} words`}
        {note.language && note.language !== "auto" && ` · ${note.language.toUpperCase()}`}
      </p>

      {/* Tags */}
      <div className="flex flex-wrap items-center gap-1.5 px-5 pt-3">
        {(note.tags ?? []).map((tag) => (
          <span
            key={tag}
            className="inline-flex items-center gap-1 rounded-full bg-foreground/10 px-2.5 py-0.5 text-xs font-medium text-foreground/70"
          >
            <Tag className="h-3 w-3" />
            {tag}
            <button
              onClick={() => handleRemoveTag(tag)}
              className="ml-0.5 rounded-full p-0.5 transition-colors hover:bg-foreground/10"
              aria-label={`Remove tag ${tag}`}
            >
              <X className="h-2.5 w-2.5" />
            </button>
          </span>
        ))}
        {showTagInput ? (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              handleAddTag(tagInput);
            }}
            className="inline-flex"
          >
            <input
              value={tagInput}
              onChange={(e) => setTagInput(e.target.value)}
              onBlur={() => {
                if (tagInput.trim()) handleAddTag(tagInput);
                setShowTagInput(false);
              }}
              onKeyDown={(e) => {
                if (e.key === "," && tagInput.trim()) {
                  e.preventDefault();
                  handleAddTag(tagInput);
                }
                if (e.key === "Escape") {
                  setTagInput("");
                  setShowTagInput(false);
                }
              }}
              placeholder="add tag"
              autoFocus
              list="tag-suggestions"
              className="h-6 w-24 rounded-full border border-border bg-muted/30 px-2.5 text-xs outline-none placeholder:text-muted-foreground/40 focus:border-foreground/20"
            />
            <datalist id="tag-suggestions">
              {existingTags
                .filter((t) => !(note.tags ?? []).includes(t))
                .map((t) => (
                  <option key={t} value={t} />
                ))}
            </datalist>
          </form>
        ) : (
          <button
            onClick={() => setShowTagInput(true)}
            className="inline-flex items-center gap-1 rounded-full border border-dashed border-border px-2.5 py-0.5 text-xs text-muted-foreground/50 transition-colors hover:border-foreground/30 hover:text-muted-foreground"
          >
            <Plus className="h-3 w-3" />
            tag
          </button>
        )}
      </div>

      {/* Copy the read-only transcript in the user's preferred format. */}
      <div className="flex items-center gap-2 px-5 pt-4">
        {/* Split copy button */}
        <div className="inline-flex items-center rounded-lg border border-border">
          <button
            onClick={handleCopy}
            className="inline-flex h-9 items-center gap-1.5 rounded-l-lg px-3 text-sm transition-colors hover:bg-muted active:scale-[0.97]"
          >
            {copied ? (
              <Check className="h-3.5 w-3.5" />
            ) : (
              <Copy className="h-3.5 w-3.5" />
            )}
            {copied ? "Copied" : "Copy"}
          </button>
          <div className="h-5 w-px bg-border" />
          <DropdownMenu>
            <DropdownMenuTrigger
              render={
                <button
                  className="inline-flex h-9 w-9 items-center justify-center rounded-r-lg transition-colors hover:bg-muted active:scale-[0.97]"
                  aria-label="Copy as..."
                />
              }
            >
              <ChevronDown className="h-3.5 w-3.5" />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start" className="min-w-52 p-1.5">
              <DropdownMenuItem className="py-2.5" onClick={() => handleCopyAs("txt")}>
                Plain Text
              </DropdownMenuItem>
              <DropdownMenuItem className="py-2.5" onClick={() => handleCopyAs("txt-meta")}>
                Text with metadata
              </DropdownMenuItem>
              <DropdownMenuItem className="py-2.5" onClick={() => handleCopyAs("md")}>
                Markdown
              </DropdownMenuItem>
              <DropdownMenuItem className="py-2.5" onClick={() => handleCopyAs("md-meta")}>
                Markdown with metadata
              </DropdownMenuItem>
              {hasTimestamps && (
                <DropdownMenuItem className="py-2.5" onClick={() => handleCopyAs("srt")}>
                  SRT subtitles
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

      </div>

      {/* Audio player — sticky below header so it stays reachable during long transcripts */}
      <div className={hasAudio ? "sticky top-16 z-10 bg-background/80 backdrop-blur-lg" : ""}>
        <AudioPlayer
          ref={audioPlayerRef}
          noteId={note.id}
          onAudioAvailable={setHasAudio}
          onPlayStateChange={setIsAudioPlaying}
        />
      </div>

      {/* Transcript content */}
      <div className="px-5 pb-6 pt-5">
        <div className="mx-auto max-w-prose">
          <div ref={transcriptRef} className="relative">
            <SelectionToolbar containerRef={transcriptRef} />
            {hasAudio && hasTimestamps ? (
              <SyncedTranscript
                words={note.metadata.words!}
                getTime={getTime}
                isPlaying={isAudioPlaying}
                hasDiarization={!!note.metadata?.hasDiarization}
                onWordClick={handleWordClick}
              />
            ) : note.metadata?.hasDiarization &&
              note.metadata.words?.some((w) => w.speaker_id) ? (
              <DiarizedTranscript words={note.metadata.words!} />
            ) : (
              <div className="whitespace-pre-wrap text-base leading-[1.8] text-foreground/90">
                {note.content}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
