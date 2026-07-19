"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  Search,
  ArrowDown,
  ArrowUp,
  ArrowDownAZ,
  ArrowUpZA,
  FileText,
  Mic,
  Upload,
} from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
} from "@/components/ui/select";
import { useNotes } from "@/lib/hooks/use-notes";
import { useNote } from "@/lib/hooks/use-note";
import { NoteDetail } from "@/components/note-detail";
import { NotesList } from "@/components/notes-list";
import { SCRIBER_FOCUS_SEARCH_EVENT } from "@/lib/hooks/use-keyboard-shortcuts";
import type { Note } from "@/lib/types";

type SortMode = "newest" | "oldest" | "a-z" | "z-a";

const sourceIcons = {
  recording: Mic,
  upload: Upload,
  text: FileText,
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

function NoteRow({ note, selected }: { note: Note; selected: boolean }) {
  const Icon = sourceIcons[note.source] ?? FileText;
  return (
    <Link
      href={`/notes/${note.id}`}
      aria-current={selected ? "true" : undefined}
      className={`block border-b border-border/30 px-4 py-3 transition-colors ${
        selected
          ? "bg-foreground/5"
          : "hover:bg-foreground/[0.025]"
      }`}
    >
      <div className="flex items-center gap-2">
        <Icon
          className="h-3 w-3 shrink-0 text-muted-foreground/60"
          aria-hidden="true"
        />
        <h3 className="line-clamp-1 flex-1 text-sm font-medium leading-snug">
          {note.title}
        </h3>
        <span className="shrink-0 text-[11px] text-muted-foreground/70">
          {timeAgo(note.createdAt)}
        </span>
      </div>
      <p className="mt-1 line-clamp-2 text-xs leading-relaxed text-muted-foreground">
        {note.content || "No content"}
      </p>
    </Link>
  );
}

function DesktopListPane({ selectedId }: { selectedId?: string }) {
  const [search, setSearch] = useState("");
  const [sort, setSort] = useState<SortMode>("newest");
  const [activeTag, setActiveTag] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const { notes, loading } = useNotes({
    search,
    tag: activeTag ?? undefined,
    sort,
  });

  const { notes: allNotes } = useNotes();
  const allTags = useMemo(() => {
    const tagSet = new Set<string>();
    for (const note of allNotes) {
      if (note.tags) {
        for (const tag of note.tags) tagSet.add(tag);
      }
    }
    return Array.from(tagSet).sort((a, b) => a.localeCompare(b));
  }, [allNotes]);

  useEffect(() => {
    function onFocusSearch() {
      inputRef.current?.focus();
      inputRef.current?.select();
    }
    window.addEventListener(SCRIBER_FOCUS_SEARCH_EVENT, onFocusSearch);
    return () =>
      window.removeEventListener(SCRIBER_FOCUS_SEARCH_EVENT, onFocusSearch);
  }, []);

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center justify-between gap-2 border-b border-border/40 px-4 py-3">
        <h1 className="text-base font-semibold">Notes</h1>
        <Select value={sort} onValueChange={(v) => setSort(v as SortMode)}>
          <SelectTrigger
            className="h-7 cursor-pointer gap-1.5 rounded-md border-border/60 bg-transparent px-2 text-xs text-muted-foreground [&_[data-slot=select-icon]]:hidden"
            aria-label="Sort notes"
          >
            {sort === "newest" && <ArrowDown className="h-3 w-3" />}
            {sort === "oldest" && <ArrowUp className="h-3 w-3" />}
            {sort === "a-z" && <ArrowDownAZ className="h-3 w-3" />}
            {sort === "z-a" && <ArrowUpZA className="h-3 w-3" />}
            <span>
              {sort === "newest"
                ? "Newest"
                : sort === "oldest"
                  ? "Oldest"
                  : sort === "a-z"
                    ? "A–Z"
                    : "Z–A"}
            </span>
          </SelectTrigger>
          <SelectContent className="p-1.5">
            <SelectItem value="newest" label="Newest first">
              Newest first
            </SelectItem>
            <SelectItem value="oldest" label="Oldest first">
              Oldest first
            </SelectItem>
            <SelectItem value="a-z" label="Title A-Z">
              Title A-Z
            </SelectItem>
            <SelectItem value="z-a" label="Title Z-A">
              Title Z-A
            </SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="border-b border-border/40 px-3 py-2">
        <div className="relative">
          <Search
            className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground"
            aria-hidden="true"
          />
          <input
            ref={inputRef}
            placeholder="Search…"
            aria-label="Search notes"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="h-8 w-full rounded-md border border-border/60 bg-muted/30 pl-8 pr-2 text-xs outline-none transition-colors placeholder:text-muted-foreground/60 focus:border-foreground/20 focus:bg-background"
          />
          <kbd className="pointer-events-none absolute right-2 top-1/2 hidden -translate-y-1/2 rounded bg-muted px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground/60 lg:inline-block">
            ⌘K
          </kbd>
        </div>
      </div>

      {allTags.length > 0 && (
        <div className="border-b border-border/40 px-3 py-2">
          <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
            <button
              onClick={() => setActiveTag(null)}
              className={`shrink-0 cursor-pointer rounded-full px-2.5 py-0.5 text-[11px] font-medium transition-colors ${
                activeTag === null
                  ? "bg-foreground text-background"
                  : "bg-muted text-muted-foreground hover:bg-muted/80"
              }`}
            >
              All
            </button>
            {allTags.map((tag) => (
              <button
                key={tag}
                onClick={() =>
                  setActiveTag(activeTag === tag ? null : tag)
                }
                className={`shrink-0 cursor-pointer rounded-full px-2.5 py-0.5 text-[11px] font-medium transition-colors ${
                  activeTag === tag
                    ? "bg-foreground text-background"
                    : "bg-muted text-muted-foreground hover:bg-muted/80"
                }`}
              >
                {tag}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="space-y-2 p-3">
            {[...Array(4)].map((_, i) => (
              <div
                key={i}
                className="h-14 animate-pulse rounded-md bg-muted/50"
              />
            ))}
          </div>
        ) : notes.length === 0 ? (
          <div className="flex h-full flex-col items-center justify-center gap-2 px-6 text-center">
            <p className="text-sm font-medium text-muted-foreground">
              {search || activeTag ? "No matches" : "No notes yet"}
            </p>
            <p className="text-xs text-muted-foreground/70">
              {search || activeTag
                ? "Try a different search term or filter"
                : "Record or upload audio to get started"}
            </p>
          </div>
        ) : (
          <ul>
            {notes.map((note) => (
              <li key={note.id}>
                <NoteRow note={note} selected={note.id === selectedId} />
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function DesktopEmptyState() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-3 px-6 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-full bg-muted">
        <FileText
          className="h-6 w-6 text-muted-foreground/60"
          aria-hidden="true"
        />
      </div>
      <div>
        <p className="text-sm font-medium text-muted-foreground">
          Select a note
        </p>
        <p className="mt-0.5 text-xs text-muted-foreground/70">
          Choose one from the list, or start a new transcription
        </p>
      </div>
    </div>
  );
}

function NoteLoader({ id }: { id: string }) {
  const router = useRouter();
  const { note, loading } = useNote(id);

  useEffect(() => {
    if (!loading && !note) router.replace("/notes");
  }, [loading, note, router]);

  if (loading) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
        Loading…
      </div>
    );
  }
  if (!note) return null;
  return <NoteDetail note={note} />;
}

export function NotesShell({ selectedId }: { selectedId?: string }) {
  return (
    <>
      {/* Mobile: keep existing single-pane behavior */}
      <div className="block h-full lg:hidden">
        {selectedId ? (
          <NoteLoader id={selectedId} />
        ) : (
          <div className="px-5 pb-4 pt-6">
            <NotesList />
          </div>
        )}
      </div>

      {/* Desktop: master-detail */}
      <div className="hidden h-full lg:flex">
        <aside className="flex w-80 shrink-0 flex-col border-r border-border/40">
          <DesktopListPane selectedId={selectedId} />
        </aside>
        <main className="flex-1 overflow-y-auto">
          {selectedId ? <NoteLoader id={selectedId} /> : <DesktopEmptyState />}
        </main>
      </div>
    </>
  );
}
