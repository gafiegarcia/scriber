import { NextResponse } from "next/server";
import { Readable } from "node:stream";
import { writeAudio, readAudioStream, deleteAudio } from "@/lib/server/storage";

export const runtime = "nodejs";
export const maxDuration = 300;

type Ctx = { params: Promise<{ id: string }> };

export async function GET(_request: Request, { params }: Ctx) {
  const { id } = await params;
  const entry = await readAudioStream(id);
  if (!entry) return NextResponse.json({ error: "Audio not found" }, { status: 404 });
  // Convert the Node ReadStream into a Web ReadableStream for NextResponse
  const webStream = Readable.toWeb(entry.stream) as unknown as ReadableStream<Uint8Array>;
  return new Response(webStream, {
    headers: {
      "Content-Type": entry.mime,
      "Content-Length": String(entry.size),
      "Cache-Control": "private, max-age=31536000, immutable",
    },
  });
}

export async function PUT(request: Request, { params }: Ctx) {
  const { id } = await params;
  const contentType = request.headers.get("content-type") ?? undefined;

  if (!request.body) {
    return NextResponse.json({ error: "Missing request body" }, { status: 400 });
  }

  try {
    await writeAudio(id, request.body, contentType);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to save audio";
    return NextResponse.json({ error: message }, { status: 400 });
  }
  return NextResponse.json({ ok: true }, { status: 201 });
}

export async function DELETE(_request: Request, { params }: Ctx) {
  const { id } = await params;
  await deleteAudio(id);
  return NextResponse.json({ ok: true });
}
