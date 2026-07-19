import type { Note, CreateNoteInput, UpdateNoteInput } from "@/lib/types";

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `Request failed: ${res.status}`);
  }
  return (await res.json()) as T;
}

function notifyChange(id?: string) {
  if (typeof window === "undefined") return;
  try {
    const channel = new BroadcastChannel("scriber-notes");
    channel.postMessage({ type: "changed", id });
    channel.close();
  } catch {
    // Older browsers without BroadcastChannel — ignore
  }
}

export async function createNote(input: CreateNoteInput & { id: string }): Promise<Note> {
  const { note } = await request<{ note: Note }>("/api/notes", {
    method: "POST",
    body: JSON.stringify(input),
  });
  notifyChange(note.id);
  return note;
}

export async function getNotes(options?: {
  search?: string;
  tag?: string;
  sort?: "newest" | "oldest";
}): Promise<Note[]> {
  const { notes } = await request<{ notes: Note[] }>("/api/notes");

  let filtered = notes;

  if (options?.tag) {
    const tag = options.tag.toLowerCase();
    filtered = filtered.filter((n) => n.tags?.some((t) => t.toLowerCase() === tag));
  }

  if (options?.search) {
    const q = options.search.toLowerCase();
    filtered = filtered.filter(
      (n) =>
        n.title.toLowerCase().includes(q) ||
        n.content.toLowerCase().includes(q)
    );
  }

  if (options?.sort === "oldest") {
    filtered = [...filtered].reverse();
  }

  return filtered;
}

export async function getNote(noteId: string): Promise<Note | null> {
  try {
    const { note } = await request<{ note: Note }>(
      `/api/notes/${encodeURIComponent(noteId)}`
    );
    return note;
  } catch {
    return null;
  }
}

export async function updateNote(
  noteId: string,
  data: UpdateNoteInput
): Promise<Note | null> {
  try {
    const { note } = await request<{ note: Note }>(
      `/api/notes/${encodeURIComponent(noteId)}`,
      {
        method: "PATCH",
        body: JSON.stringify(data),
      }
    );
    notifyChange(noteId);
    return note;
  } catch {
    return null;
  }
}

export async function deleteNote(noteId: string): Promise<void> {
  await request(`/api/notes/${encodeURIComponent(noteId)}`, { method: "DELETE" });
  notifyChange(noteId);
}

export async function deleteAllNotes(): Promise<void> {
  const notes = await getNotes();
  await Promise.all(notes.map((n) => deleteNote(n.id)));
  notifyChange();
}

export async function getAllTags(): Promise<string[]> {
  const notes = await getNotes();
  const tagSet = new Set<string>();
  for (const note of notes) {
    for (const tag of note.tags ?? []) tagSet.add(tag);
  }
  return Array.from(tagSet).sort((a, b) => a.localeCompare(b));
}

export async function exportAllNotes(): Promise<string> {
  const notes = await getNotes();
  return JSON.stringify(notes, null, 2);
}

export async function importNotes(
  json: string
): Promise<{ imported: number; skipped: number }> {
  let incoming: unknown[];
  try {
    incoming = JSON.parse(json);
  } catch {
    throw new Error("Invalid JSON file");
  }

  if (!Array.isArray(incoming)) {
    throw new Error("Expected a JSON array of notes");
  }

  const existing = await getNotes();
  const existingIds = new Set(existing.map((n) => n.id));

  let imported = 0;
  let skipped = 0;

  for (const item of incoming) {
    const raw = item as Record<string, unknown>;
    if (!raw.title || !raw.content || !raw.createdAt) {
      skipped++;
      continue;
    }
    const id = (raw.id as string) || crypto.randomUUID();
    if (existingIds.has(id)) {
      skipped++;
      continue;
    }

    const input: CreateNoteInput & { id: string } = {
      id,
      title: String(raw.title),
      content: String(raw.content),
      type: (raw.type as Note["type"]) ?? "text",
      source: (raw.source as Note["source"]) ?? "text",
      audioFileName: raw.audioFileName as string | undefined,
      durationSeconds: raw.durationSeconds as number | undefined,
      language: raw.language as string | undefined,
      tags: (raw.tags as string[]) ?? [],
      metadata: (raw.metadata as Note["metadata"]) ?? {},
    };

    try {
      await createNote(input);
      imported++;
    } catch {
      skipped++;
    }
  }

  notifyChange();
  return { imported, skipped };
}
