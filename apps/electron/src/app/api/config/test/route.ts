import { NextResponse } from "next/server";
import { readConfig } from "@/lib/server/storage";
import { SecretStoreError } from "@/lib/server/secret-store";

export const runtime = "nodejs";

export async function POST(request: Request) {
  let key: string | undefined;
  try {
    const body = await request.json();
    key = typeof body?.apiKey === "string" ? body.apiKey : undefined;
  } catch {
    // no-op — fall through to stored key
  }

  if (!key) {
    try {
      const config = await readConfig();
      key = config.apiKey;
    } catch (error) {
      console.error("[scriber] Failed to read stored API key:", error);
      return NextResponse.json(
        {
          ok: false,
          error:
            error instanceof SecretStoreError
              ? error.message
              : "Failed to read the stored API key",
          ...(error instanceof SecretStoreError ? { code: error.code } : {}),
        },
        { status: error instanceof SecretStoreError ? 503 : 500 }
      );
    }
  }

  if (!key) {
    return NextResponse.json(
      { ok: false, error: "No API key provided or configured" },
      { status: 400 }
    );
  }

  try {
    const res = await fetch("https://api.elevenlabs.io/v1/user", {
      headers: { "xi-api-key": key },
    });
    if (res.status === 401 || res.status === 403) {
      // ElevenLabs returns 401/403 when the key is valid but scoped too
      // narrowly to call /v1/user (e.g. STT-only keys). Distinguish by
      // looking for permission/scope-related language in the body.
      const text = await res.text().catch(() => "");
      console.warn(`[scriber] /v1/user ${res.status} — body: ${text.slice(0, 400)}`);
      const lower = text.toLowerCase();
      const looksScoped =
        lower.includes("permission") ||
        lower.includes("scope") ||
        lower.includes("missing") ||
        lower.includes("forbidden") ||
        lower.includes("not allowed") ||
        lower.includes("insufficient");
      if (looksScoped) {
        return NextResponse.json({
          ok: true,
          subscription: null,
          scopedKey: true,
        });
      }
      return NextResponse.json(
        { ok: false, error: "Invalid API key" },
        { status: 200 }
      );
    }
    if (!res.ok) {
      return NextResponse.json(
        { ok: false, error: `ElevenLabs responded with ${res.status}` },
        { status: 200 }
      );
    }
    const data = await res.json().catch(() => ({}));
    return NextResponse.json({
      ok: true,
      subscription: data?.subscription?.tier ?? null,
    });
  } catch {
    return NextResponse.json(
      { ok: false, error: "Could not reach ElevenLabs" },
      { status: 200 }
    );
  }
}
