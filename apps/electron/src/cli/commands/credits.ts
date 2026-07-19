import { parseArgs } from "node:util";

import { readConfig } from "@/lib/server/storage";
import { fetchSubscription, type SubscriptionError } from "@/lib/core/subscription";

const HELP = `
scriber credits — show remaining ElevenLabs credits for the configured key.

USAGE
  scriber credits [options]

OPTIONS
      --json                 Print the raw subscription JSON to stdout.
  -q, --quiet                Print only the "used / limit" line to stdout.
  -h, --help                 Show this help.

EXIT CODES
  0  ok
  1  no API key configured / usage error
  2  ElevenLabs request failed
`.trimStart();

const numberFmt = new Intl.NumberFormat("en-US");

class UsageError extends Error {}

function formatTier(tier: string): string {
  if (!tier) return "Unknown";
  return tier
    .split(/[_\s]+/)
    .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
    .join(" ");
}

function formatResetDate(unix: number | null): string | null {
  if (!unix) return null;
  const date = new Date(unix * 1000);
  if (Number.isNaN(date.getTime())) return null;
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function bar(pct: number, width = 20): string {
  const filled = Math.max(0, Math.min(width, Math.round((pct / 100) * width)));
  return "▇".repeat(filled) + "░".repeat(width - filled);
}

export async function runCreditsCommand(argv: string[]): Promise<void> {
  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      options: {
        json: { type: "boolean" },
        quiet: { type: "boolean", short: "q" },
        help: { type: "boolean", short: "h" },
      },
      allowPositionals: false,
      strict: true,
    });
  } catch (err) {
    process.stderr.write(`${(err as Error).message}\n`);
    process.exit(1);
  }

  if (parsed.values.help) {
    process.stdout.write(HELP);
    process.exit(0);
  }

  try {
    const config = await readConfig();
    if (!config.apiKey) {
      throw new UsageError(
        "No ElevenLabs API key configured.\n" +
          "Run `scriber` (the web app) and set your key under Settings → API Key."
      );
    }

    const sub = await fetchSubscription(config.apiKey);

    if (parsed.values.json) {
      process.stdout.write(JSON.stringify(sub, null, 2) + "\n");
      process.exit(0);
    }

    const used = sub.characterCount;
    const limit = sub.characterLimit;
    const remaining = Math.max(0, limit - used);
    const pct = limit > 0 ? Math.min(100, Math.round((used / limit) * 100)) : 0;
    const resetLabel = formatResetDate(sub.nextResetUnix);

    if (parsed.values.quiet) {
      process.stdout.write(
        `${numberFmt.format(remaining)} / ${numberFmt.format(limit)} credits left\n`
      );
      process.exit(0);
    }

    const tierLabel = `${formatTier(sub.tier)}${sub.status ? ` (${sub.status})` : ""}`;

    const lines = [
      "ElevenLabs subscription",
      `  Tier       ${tierLabel}`,
      `  Used       ${numberFmt.format(used)} / ${numberFmt.format(limit)} credits  ${bar(pct)}  ${pct}%`,
      `  Remaining  ${numberFmt.format(remaining)}`,
    ];
    if (resetLabel) lines.push(`  Resets     ${resetLabel}`);
    if (sub.billingPeriod) {
      lines.push(`  Billing    ${sub.billingPeriod.replace(/_/g, " ")}`);
    }
    process.stdout.write(lines.join("\n") + "\n");
    process.exit(0);
  } catch (err) {
    if (err instanceof UsageError) {
      process.stderr.write(`${err.message}\n`);
      process.exit(1);
    }
    const sub = err as Partial<SubscriptionError>;
    if (err instanceof Error && typeof sub.status === "number") {
      process.stderr.write(`Could not read subscription: ${err.message}\n`);
      process.exit(2);
    }
    process.stderr.write(
      `Unexpected error: ${err instanceof Error ? err.stack || err.message : String(err)}\n`
    );
    process.exit(1);
  }
}
