import type { UpdateNoteInput } from "@/lib/types";

const ALLOWED_FIELDS = new Set(["title", "tags"]);
const READ_ONLY_FIELDS = new Set(["content", "metadata"]);

export class NoteUpdateError extends Error {}

export function parseNoteUpdate(value: unknown): UpdateNoteInput {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new NoteUpdateError("Invalid note update");
  }

  const input = value as Record<string, unknown>;
  const keys = Object.keys(input);
  if (keys.some((key) => READ_ONLY_FIELDS.has(key))) {
    throw new NoteUpdateError(
      "Transcript content and timing metadata are read-only; copy or export the transcript to edit it elsewhere."
    );
  }
  const unsupported = keys.find((key) => !ALLOWED_FIELDS.has(key));
  if (unsupported) {
    throw new NoteUpdateError(`Unsupported note field: ${unsupported}`);
  }
  if (keys.length === 0) {
    throw new NoteUpdateError("Note update is empty");
  }

  const patch: UpdateNoteInput = {};
  if ("title" in input) {
    if (typeof input.title !== "string" || input.title.trim().length === 0) {
      throw new NoteUpdateError("Note title must be a non-empty string");
    }
    patch.title = input.title;
  }
  if ("tags" in input) {
    if (!Array.isArray(input.tags) || !input.tags.every((tag) => typeof tag === "string")) {
      throw new NoteUpdateError("Note tags must be an array of strings");
    }
    patch.tags = input.tags;
  }
  return patch;
}
