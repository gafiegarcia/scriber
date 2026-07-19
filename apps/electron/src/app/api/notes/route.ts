import { NextResponse } from "next/server";
import { listNotes, createNote } from "@/lib/server/storage";
import type { CreateNoteInput } from "@/lib/types";

export const runtime = "nodejs";

export async function GET() {
  const notes = await listNotes();
  return NextResponse.json({ notes });
}

export async function POST(request: Request) {
  let body: (CreateNoteInput & { id: string }) | null = null;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!body || !body.id || body.title == null || body.content == null) {
    return NextResponse.json(
      { error: "Missing required fields: id, title, content" },
      { status: 400 }
    );
  }

  const note = await createNote(body);
  return NextResponse.json({ note }, { status: 201 });
}
