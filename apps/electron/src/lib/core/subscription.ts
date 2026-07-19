const ENDPOINT = "https://api.elevenlabs.io/v1/user/subscription";

export interface Subscription {
  tier: string;
  status: string;
  characterCount: number;
  characterLimit: number;
  nextResetUnix: number | null;
  billingPeriod: string | null;
  currency: string | null;
}

export interface SubscriptionError extends Error {
  status: number;
  /** True when the key authenticates but lacks scope to read /v1/user/subscription. */
  scopedKey?: boolean;
}

function makeError(message: string, status: number, scopedKey = false): SubscriptionError {
  const err = new Error(message) as SubscriptionError;
  err.status = status;
  if (scopedKey) err.scopedKey = true;
  return err;
}

/**
 * Fetch the user's ElevenLabs subscription summary. The same credit pool
 * (`character_count` / `character_limit`) covers Scribe STT usage even though
 * the field is named for TTS — that's the unit the dashboard exposes.
 */
export async function fetchSubscription(apiKey: string): Promise<Subscription> {
  let res: Response;
  try {
    res = await fetch(ENDPOINT, { headers: { "xi-api-key": apiKey } });
  } catch {
    throw makeError("Could not reach ElevenLabs", 502);
  }

  if (res.status === 401 || res.status === 403) {
    const body = await res.text().catch(() => "");
    const lower = body.toLowerCase();
    const looksScoped =
      lower.includes("permission") ||
      lower.includes("scope") ||
      lower.includes("missing") ||
      lower.includes("forbidden") ||
      lower.includes("not allowed") ||
      lower.includes("insufficient");
    if (looksScoped) {
      throw makeError(
        "This API key doesn't have permission to read subscription info.",
        res.status,
        true
      );
    }
    throw makeError("Invalid API key", res.status);
  }

  if (!res.ok) {
    throw makeError(`ElevenLabs responded with ${res.status}`, res.status);
  }

  const data = (await res.json().catch(() => null)) as Record<string, unknown> | null;
  if (!data || typeof data !== "object") {
    throw makeError("Unexpected response from ElevenLabs", 502);
  }

  return {
    tier: typeof data.tier === "string" ? data.tier : "unknown",
    status: typeof data.status === "string" ? data.status : "unknown",
    characterCount: typeof data.character_count === "number" ? data.character_count : 0,
    characterLimit: typeof data.character_limit === "number" ? data.character_limit : 0,
    nextResetUnix:
      typeof data.next_character_count_reset_unix === "number"
        ? data.next_character_count_reset_unix
        : null,
    billingPeriod:
      typeof data.billing_period === "string" ? data.billing_period : null,
    currency: typeof data.currency === "string" ? data.currency : null,
  };
}
