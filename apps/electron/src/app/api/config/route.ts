import { NextResponse } from "next/server";
import {
  getApiKeyStorageKind,
  readConfig,
  writeConfig,
  type ScriberConfig,
} from "@/lib/server/storage";
import { SecretStoreError } from "@/lib/server/secret-store";

export const runtime = "nodejs";

const ALLOWED_CONFIG_KEYS = new Set([
  "apiKey",
  "defaults",
  "dictionary",
  "transcribeModel",
  "theme",
]);

function validatePatch(value: unknown): value is Partial<ScriberConfig> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const patch = value as Record<string, unknown>;
  if (Object.keys(patch).some((key) => !ALLOWED_CONFIG_KEYS.has(key))) {
    return false;
  }
  if ("apiKey" in patch && typeof patch.apiKey !== "string") return false;
  if (
    "dictionary" in patch &&
    (!Array.isArray(patch.dictionary) ||
      !patch.dictionary.every((term) => typeof term === "string"))
  ) {
    return false;
  }
  if (
    "transcribeModel" in patch &&
    typeof patch.transcribeModel !== "string"
  ) {
    return false;
  }
  if (
    "theme" in patch &&
    patch.theme !== "light" &&
    patch.theme !== "dark" &&
    patch.theme !== "system"
  ) {
    return false;
  }
  if ("defaults" in patch) {
    const defaults = patch.defaults;
    if (!defaults || typeof defaults !== "object" || Array.isArray(defaults)) {
      return false;
    }
    const options = defaults as Record<string, unknown>;
    const allowedOptions = new Set([
      "languageCode",
      "diarize",
      "numSpeakers",
      "tagAudioEvents",
    ]);
    if (
      Object.keys(options).some((key) => !allowedOptions.has(key)) ||
      typeof options.languageCode !== "string" ||
      typeof options.diarize !== "boolean" ||
      (options.numSpeakers !== null &&
        (!Number.isInteger(options.numSpeakers) ||
          (options.numSpeakers as number) <= 0)) ||
      typeof options.tagAudioEvents !== "boolean"
    ) {
      return false;
    }
  }
  return true;
}

export async function GET() {
  try {
    const config = await readConfig();
    return NextResponse.json({
      hasApiKey: Boolean(config.apiKey),
      apiKeyStorage: getApiKeyStorageKind(),
      defaults: config.defaults,
      dictionary: config.dictionary,
      transcribeModel: config.transcribeModel,
      theme: config.theme,
    });
  } catch (error) {
    console.error("[scriber] Failed to read config:", error);
    return NextResponse.json(
      {
        error:
          error instanceof SecretStoreError
            ? error.message
            : "Failed to read Scriber settings",
        ...(error instanceof SecretStoreError ? { code: error.code } : {}),
      },
      { status: error instanceof SecretStoreError ? 503 : 500 }
    );
  }
}

export async function PATCH(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!validatePatch(body)) {
    return NextResponse.json(
      { error: "Invalid config patch" },
      { status: 400 }
    );
  }
  const patch = body;

  try {
    const updated = await writeConfig(patch);
    return NextResponse.json({
      hasApiKey: Boolean(updated.apiKey),
      apiKeyStorage: getApiKeyStorageKind(),
      defaults: updated.defaults,
      dictionary: updated.dictionary,
      transcribeModel: updated.transcribeModel,
      theme: updated.theme,
    });
  } catch (error) {
    console.error("[scriber] Failed to write config:", error);
    return NextResponse.json(
      {
        error:
          error instanceof SecretStoreError
            ? error.message
            : "Failed to save Scriber settings",
        ...(error instanceof SecretStoreError ? { code: error.code } : {}),
      },
      { status: error instanceof SecretStoreError ? 503 : 500 }
    );
  }
}
