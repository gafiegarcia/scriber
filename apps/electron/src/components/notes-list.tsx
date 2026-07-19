"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Search, Mic, ArrowDownAZ, ArrowUpZA, ArrowDown, ArrowUp } from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
} from "@/components/ui/select";
import { NoteCard } from "@/components/note-card";
import { useNotes } from "@/lib/hooks/use-notes";
import { SCRIBER_FOCUS_SEARCH_EVENT } from "@/lib/hooks/use-keyboard-shortcuts";

export function NotesList() {
  const [search, setSearch] = useState("");
  const [activeTag, setActiveTag] = useState<string | null>(null);
  const [sort, setSort] = useState<"newest" | "oldest" | "a-z" | "z-a">("newest");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    function onFocusSearch() {
      inputRef.current?.focus();
      inputRef.current?.select();
    }
    window.addEventListener(SCRIBER_FOCUS_SEARCH_EVENT, onFocusSearch);
    return () =>
      window.removeEventListener(SCRIBER_FOCUS_SEARCH_EVENT, onFocusSearch);
  }, []);

  const { notes, loading } = useNotes({
    search,
    tag: activeTag ?? undefined,
    sort,
  });

  // Derive tags from the real-time notes data (unfiltered)
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

  return (
    <div className="flex flex-col gap-4">
      {/* Heading + Sort */}
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold tracking-tight">Notes</h1>
        <Select value={sort} onValueChange={(v) => setSort(v as typeof sort)}>
          <SelectTrigger className="h-8 cursor-pointer gap-1.5 rounded-lg border-border/60 bg-muted/30 px-2.5 text-xs text-muted-foreground [&_[data-slot=select-icon]]:hidden" aria-label="Sort notes">
            {sort === "newest" && <ArrowDown className="h-3.5 w-3.5" />}
            {sort === "oldest" && <ArrowUp className="h-3.5 w-3.5" />}
            {sort === "a-z" && <ArrowDownAZ className="h-3.5 w-3.5" />}
            {sort === "z-a" && <ArrowUpZA className="h-3.5 w-3.5" />}
            <span>{sort === "newest" ? "Newest" : sort === "oldest" ? "Oldest" : sort === "a-z" ? "A–Z" : "Z–A"}</span>
          </SelectTrigger>
          <SelectContent className="p-1.5">
            <SelectItem value="newest" label="Newest first">Newest first</SelectItem>
            <SelectItem value="oldest" label="Oldest first">Oldest first</SelectItem>
            <SelectItem value="a-z" label="Title A-Z">Title A-Z</SelectItem>
            <SelectItem value="z-a" label="Title Z-A">Title Z-A</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
        <input
          ref={inputRef}
          placeholder="Search notes..."
          aria-label="Search notes"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="h-12 w-full rounded-xl border border-border/60 bg-muted/30 pl-10 pr-4 text-sm outline-none transition-colors placeholder:text-muted-foreground focus:border-foreground/20 focus:bg-background"
        />
      </div>

      {/* Tag filter */}
      {allTags.length > 0 && (
        <div className="no-scrollbar flex gap-2 overflow-x-auto">
          <button
            onClick={() => setActiveTag(null)}
            className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium transition-colors ${
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
              onClick={() => setActiveTag(activeTag === tag ? null : tag)}
              className={`shrink-0 rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                activeTag === tag
                  ? "bg-foreground text-background"
                  : "bg-muted text-muted-foreground hover:bg-muted/80"
              }`}
            >
              {tag}
            </button>
          ))}
        </div>
      )}

      {/* List */}
      {loading ? (
        <div className="space-y-3">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="h-20 animate-pulse rounded-xl bg-muted/50" />
          ))}
        </div>
      ) : notes.length === 0 ? (
        <div className="flex flex-col items-center gap-3 py-20 text-center">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-muted">
            <Mic className="h-7 w-7 text-muted-foreground" aria-hidden="true" />
          </div>
          <div>
            <p className="text-base font-medium text-muted-foreground">
              {search || activeTag ? "No results found" : "No notes yet"}
            </p>
            <p className="mt-1 text-sm text-muted-foreground">
              {search || activeTag
                ? "Try a different search term or filter"
                : "Record or upload audio to get started"}
            </p>
          </div>
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {notes.map((note) => (
            <NoteCard key={note.id} note={note} highlight={search} />
          ))}
        </div>
      )}
    </div>
  );
}
