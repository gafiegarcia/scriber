"use client";

import { useEffect, useState, useCallback } from "react";
import { getNote } from "@/lib/notes-client";
import type { Note } from "@/lib/types";

interface UseNoteResult {
  note: Note | null;
  loading: boolean;
  error: string | null;
}

export function useNote(noteId: string | null): UseNoteResult {
  const [note, setNote] = useState<Note | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    if (!noteId) {
      setNote(null);
      setLoading(false);
      return;
    }
    try {
      const n = await getNote(noteId);
      setNote(n);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load note");
    } finally {
      setLoading(false);
    }
  }, [noteId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    refresh();

    let channel: BroadcastChannel | null = null;
    try {
      channel = new BroadcastChannel("scriber-notes");
      channel.onmessage = (event: MessageEvent) => {
        const id = event.data?.id;
        if (!id || id === noteId) refresh();
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
  }, [refresh, noteId]);

  return { note, loading, error };
}
