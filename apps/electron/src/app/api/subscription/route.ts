import { NextResponse } from "next/server";
import { readConfig } from "@/lib/server/storage";
import { fetchSubscription, type SubscriptionError } from "@/lib/core/subscription";
import { SecretStoreError } from "@/lib/server/secret-store";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  let config;
  try {
    config = await readConfig();
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
  if (!config.apiKey) {
    return NextResponse.json(
      { ok: false, error: "No API key configured" },
      { status: 400 }
    );
  }

  try {
    const subscription = await fetchSubscription(config.apiKey);
    return NextResponse.json({ ok: true, subscription });
  } catch (err) {
    const sub = err as SubscriptionError;
    return NextResponse.json(
      {
        ok: false,
        error: err instanceof Error ? err.message : "Failed to read subscription",
        scopedKey: Boolean(sub.scopedKey),
      },
      { status: 200 }
    );
  }
}
