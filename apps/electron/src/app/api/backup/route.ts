import { NextResponse } from "next/server";
import { Readable } from "node:stream";
import pkg from "../../../../package.json";
import {
  createBackupArchive,
  restoreBackupArchive,
  type RestoreMode,
} from "@/lib/server/storage";
import { SecretStoreError } from "@/lib/server/secret-store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 600;

export async function GET() {
  try {
    const { stream, manifest } = await createBackupArchive(pkg.version);
    const date = manifest.createdAt.slice(0, 10);
    return new Response(
      Readable.toWeb(stream) as unknown as ReadableStream<Uint8Array>,
      {
        headers: {
          "Content-Type": "application/gzip",
          "Content-Disposition": `attachment; filename="scriber-backup-${date}.tar.gz"`,
          "Cache-Control": "private, no-store",
        },
      }
    );
  } catch (error) {
    console.error("[scriber] Backup creation failed:", error);
    return NextResponse.json(
      {
        error:
          error instanceof SecretStoreError
            ? error.message
            : "Could not create the Scriber backup",
      },
      { status: error instanceof SecretStoreError ? 503 : 500 }
    );
  }
}

export async function POST(request: Request) {
  if (!request.body) {
    return NextResponse.json({ error: "Missing backup file" }, { status: 400 });
  }
  const requestedMode = new URL(request.url).searchParams.get("mode");
  if (requestedMode !== "merge" && requestedMode !== "replace") {
    return NextResponse.json(
      { error: "Restore mode must be merge or replace" },
      { status: 400 }
    );
  }

  try {
    const source = Readable.fromWeb(
      request.body as unknown as import("node:stream/web").ReadableStream<Uint8Array>
    );
    const result = await restoreBackupArchive(
      source,
      requestedMode as RestoreMode
    );
    return NextResponse.json(result);
  } catch (error) {
    console.error("[scriber] Backup restore failed:", error);
    return NextResponse.json(
      {
        error:
          error instanceof SecretStoreError
            ? error.message
            : error instanceof Error
              ? error.message
              : "Could not restore this backup",
      },
      { status: error instanceof SecretStoreError ? 503 : 400 }
    );
  }
}
