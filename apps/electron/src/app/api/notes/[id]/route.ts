import { NextResponse } from "next/server";
import { readNote, updateNote, deleteNote } from "@/lib/server/storage";
import { NoteUpdateError, parseNoteUpdate } from "@/lib/core/note-update";

export const runtime = "nodejs";

type Ctx = { params: Promise<{ id: string }> };

export async function GET(_request: Request, { params }: Ctx) {
  const { id } = await params;
  const note = await readNote(id);
  if (!note) return NextResponse.json({ error: "Note not found" }, { status: 404 });
  return NextResponse.json({ note });
}

export async function PATCH(request: Request, { params }: Ctx) {
  const { id } = await params;
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }
  let patch;
  try {
    patch = parseNoteUpdate(body);
  } catch (error) {
    if (error instanceof NoteUpdateError) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    throw error;
  }
  const updated = await updateNote(id, patch);
  if (!updated) return NextResponse.json({ error: "Note not found" }, { status: 404 });
  return NextResponse.json({ note: updated });
}

export async function DELETE(_request: Request, { params }: Ctx) {
  const { id } = await params;
  const removed = await deleteNote(id);
  if (!removed) return NextResponse.json({ error: "Note not found" }, { status: 404 });
  return NextResponse.json({ ok: true });
}
