"use client";

import { useEffect, useState, useMemo, useCallback } from "react";
import { getNotes } from "@/lib/notes-client";
import type { Note } from "@/lib/types";

interface UseNotesOptions {
  search?: string;
  tag?: string;
  sort?: "newest" | "oldest" | "a-z" | "z-a";
}

interface UseNotesResult {
  notes: Note[];
  loading: boolean;
  error: string | null;
}

export function useNotes(options?: UseNotesOptions): UseNotesResult {
  const [allNotes, setAllNotes] = useState<Note[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const notes = await getNotes();
      setAllNotes(notes);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load notes");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    refresh();

    let channel: BroadcastChannel | null = null;
    try {
      channel = new BroadcastChannel("scriber-notes");
      channel.onmessage = () => {
        refresh();
      };
    } catch {
      channel = null;
    }

    const handleVisible = () => {
      if (document.visibilityState === "visible") refresh();
    };
    document.addEventListener("visibilitychange", handleVisible);

    return () => {
      channel?.close();
      document.removeEventListener("visibilitychange", handleVisible);
    };
  }, [refresh]);

  const { search, tag, sort } = options ?? {};

  const notes = useMemo(() => {
    let filtered = allNotes;

    if (tag) {
      const tagLower = tag.toLowerCase();
      filtered = filtered.filter((n) =>
        n.tags?.some((t) => t.toLowerCase() === tagLower)
      );
    }

    if (search) {
      const q = search.toLowerCase();
      filtered = filtered.filter(
        (n) =>
          n.title.toLowerCase().includes(q) ||
          n.content.toLowerCase().includes(q)
      );
    }

    if (sort === "oldest") {
      return [...filtered].reverse();
    }

    if (sort === "a-z") {
      return [...filtered].sort((a, b) => a.title.localeCompare(b.title));
    }

    if (sort === "z-a") {
      return [...filtered].sort((a, b) => b.title.localeCompare(a.title));
    }

    return filtered;
  }, [allNotes, search, tag, sort]);

  return { notes, loading, error };
}
