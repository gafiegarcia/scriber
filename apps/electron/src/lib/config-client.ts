import type { TranscribeOptions } from "@/lib/types";

export interface PublicConfig {
  hasApiKey: boolean;
  apiKeyStorage: "keychain" | "config-file";
  defaults: TranscribeOptions;
  dictionary: string[];
  transcribeModel: string;
  theme: "light" | "dark" | "system";
}

export interface ConfigPatch {
  apiKey?: string;
  defaults?: TranscribeOptions;
  dictionary?: string[];
  transcribeModel?: string;
  theme?: "light" | "dark" | "system";
}

export async function getConfig(): Promise<PublicConfig> {
  const res = await fetch("/api/config");
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `Failed to load config: ${res.status}`);
  }
  return res.json();
}

export async function saveConfig(patch: ConfigPatch): Promise<PublicConfig> {
  const res = await fetch("/api/config", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `Failed to save config: ${res.status}`);
  }
  return res.json();
}

export interface KeyTestResult {
  ok: boolean;
  error?: string;
  subscription?: string | null;
}

export async function testApiKey(apiKey?: string): Promise<KeyTestResult> {
  const res = await fetch("/api/config/test", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(apiKey ? { apiKey } : {}),
  });
  if (!res.ok && res.status !== 200) {
    const body = await res.json().catch(() => ({}));
    return {
      ok: false,
      error: body.error || `Request failed: ${res.status}`,
    };
  }
  return res.json();
}

export interface SubscriptionSummary {
  tier: string;
  status: string;
  characterCount: number;
  characterLimit: number;
  nextResetUnix: number | null;
  billingPeriod: string | null;
  currency: string | null;
}

export interface SubscriptionResult {
  ok: boolean;
  subscription?: SubscriptionSummary;
  error?: string;
  scopedKey?: boolean;
}

export async function getSubscription(): Promise<SubscriptionResult> {
  const res = await fetch("/api/subscription", { cache: "no-store" });
  if (res.status === 400) {
    const body = await res.json().catch(() => ({}));
    return { ok: false, error: body.error || "No API key configured" };
  }
  if (!res.ok) return { ok: false, error: `Request failed: ${res.status}` };
  return res.json();
}
