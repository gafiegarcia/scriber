export type RestoreMode = "merge" | "replace";

export interface RestoreResult {
  mode: RestoreMode;
  notesImported: number;
  notesSkipped: number;
  audioImported: number;
  audioSkipped: number;
  settingsRestored: true;
}

export function downloadBackup() {
  const link = document.createElement("a");
  link.href = "/api/backup";
  link.click();
}

export async function restoreBackup(
  file: File,
  mode: RestoreMode
): Promise<RestoreResult> {
  const response = await fetch(`/api/backup?mode=${mode}`, {
    method: "POST",
    headers: { "Content-Type": "application/gzip" },
    body: file,
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || `Restore failed: ${response.status}`);
  }
  const result = (await response.json()) as RestoreResult;
  try {
    const channel = new BroadcastChannel("scriber-notes");
    channel.postMessage({ type: "changed" });
    channel.close();
  } catch {
    // Older browsers without BroadcastChannel — the reload below still syncs.
  }
  return result;
}
