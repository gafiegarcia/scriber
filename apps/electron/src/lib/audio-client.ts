/**
 * Audio API client. Replaces audio-db.ts (IndexedDB).
 * Stores audio on the local filesystem via /api/audio/[id].
 */

export async function saveAudio(noteId: string, blob: Blob): Promise<void> {
  const res = await fetch(`/api/audio/${encodeURIComponent(noteId)}`, {
    method: "PUT",
    headers: { "Content-Type": blob.type || "application/octet-stream" },
    body: blob,
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `Failed to save audio: ${res.status}`);
  }
}

export async function getAudio(noteId: string): Promise<Blob | null> {
  const res = await fetch(`/api/audio/${encodeURIComponent(noteId)}`);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Failed to read audio: ${res.status}`);
  return await res.blob();
}

export async function deleteAudio(noteId: string): Promise<void> {
  const res = await fetch(`/api/audio/${encodeURIComponent(noteId)}`, {
    method: "DELETE",
  });
  if (!res.ok && res.status !== 404) {
    throw new Error(`Failed to delete audio: ${res.status}`);
  }
}

export async function deleteAllAudio(): Promise<void> {
  // With filesystem storage, deleting a note also deletes its audio.
  // This is here for API parity with the old IndexedDB module and is a no-op.
}
