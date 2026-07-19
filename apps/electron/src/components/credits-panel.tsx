"use client";

import { useCallback, useEffect, useState } from "react";
import { AlertCircle, HelpCircle, Loader2, RefreshCw } from "lucide-react";
import { Popover } from "@base-ui/react/popover";
import { getSubscription, type SubscriptionSummary } from "@/lib/config-client";

type State =
  | { kind: "loading" }
  | { kind: "ok"; data: SubscriptionSummary }
  | { kind: "error"; message: string; scopedKey?: boolean };

const numberFmt = new Intl.NumberFormat();

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
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export function CreditsPanel() {
  const [state, setState] = useState<State>({ kind: "loading" });

  const applyResult = useCallback((res: Awaited<ReturnType<typeof getSubscription>>) => {
    if (res.ok && res.subscription) {
      setState({ kind: "ok", data: res.subscription });
    } else {
      setState({
        kind: "error",
        message: res.error || "Failed to load credits",
        scopedKey: res.scopedKey,
      });
    }
  }, []);

  const refresh = useCallback(async () => {
    setState({ kind: "loading" });
    applyResult(await getSubscription());
  }, [applyResult]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const res = await getSubscription();
      if (!cancelled) applyResult(res);
    })();
    return () => {
      cancelled = true;
    };
  }, [applyResult]);

  return (
    <div className="flex flex-col gap-2.5 rounded-lg border border-border bg-muted/30 px-3 py-2.5 text-sm">
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          Credits
        </span>
        <button
          type="button"
          onClick={refresh}
          disabled={state.kind === "loading"}
          className="inline-flex items-center gap-1 text-xs text-muted-foreground underline underline-offset-2 hover:text-foreground disabled:opacity-50"
        >
          {state.kind === "loading" ? (
            <Loader2 className="h-3 w-3 animate-spin" />
          ) : (
            <RefreshCw className="h-3 w-3" />
          )}
          {state.kind === "loading" ? "Refreshing" : "Refresh"}
        </button>
      </div>

      {state.kind === "loading" && (
        <p className="text-xs text-muted-foreground/70">Loading…</p>
      )}

      {state.kind === "error" && state.scopedKey && (
        <div className="flex items-start gap-1.5 text-xs text-muted-foreground/80">
          <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground/60" />
          <span>
            Stored key is scope-restricted — credits hidden.
            <ScopedKeyHelp />
          </span>
        </div>
      )}

      {state.kind === "error" && !state.scopedKey && (
        <div className="flex items-start gap-1.5 text-xs text-destructive">
          <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
          <span>{state.message}</span>
        </div>
      )}

      {state.kind === "ok" && <CreditsBody data={state.data} />}
    </div>
  );
}

function ScopedKeyHelp() {
  return (
    <Popover.Root>
      <Popover.Trigger
        render={(props) => (
          <button
            type="button"
            aria-label="What does scope-restricted mean?"
            {...props}
            className="ml-1 inline-flex h-3.5 w-3.5 translate-y-0.5 items-center justify-center rounded-full text-muted-foreground/60 hover:text-foreground"
          >
            <HelpCircle className="h-3.5 w-3.5" />
          </button>
        )}
      />
      <Popover.Portal>
        <Popover.Positioner side="top" sideOffset={6} align="end">
          <Popover.Popup className="z-50 max-w-xs rounded-lg border border-border bg-popover px-3 py-2.5 text-xs text-popover-foreground shadow-lg ring-1 ring-foreground/5 outline-none data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95">
            Transcription still works. To show credits here, create a new
            ElevenLabs API key with{" "}
            <span className="font-medium text-foreground">User: Read</span>{" "}
            permission and paste it below.
          </Popover.Popup>
        </Popover.Positioner>
      </Popover.Portal>
    </Popover.Root>
  );
}

function CreditsBody({ data }: { data: SubscriptionSummary }) {
  const { tier, characterCount, characterLimit, nextResetUnix, status } = data;
  const used = characterCount;
  const limit = characterLimit;
  const remaining = Math.max(0, limit - used);
  const pct = limit > 0 ? Math.min(100, Math.round((used / limit) * 100)) : 0;
  const resetLabel = formatResetDate(nextResetUnix);

  return (
    <>
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-foreground">{formatTier(tier)}</span>
        <span className="font-mono text-xs tabular-nums text-muted-foreground">
          {numberFmt.format(remaining)} / {numberFmt.format(limit)} left
        </span>
      </div>

      <div
        className="h-1.5 w-full overflow-hidden rounded-full bg-foreground/10"
        role="progressbar"
        aria-label="Credits used"
        aria-valuenow={pct}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        <div
          className="h-full rounded-full bg-foreground/40 transition-[width] duration-200"
          style={{ width: `${pct}%` }}
        />
      </div>

      <div className="flex items-center justify-between text-[11px] text-muted-foreground/80">
        <span>{numberFmt.format(used)} used this period</span>
        {resetLabel && <span>Resets {resetLabel}</span>}
      </div>

      {status && status !== "active" && status !== "free" && status !== "trialing" && (
        <p className="text-[11px] text-destructive/80">Status: {status}</p>
      )}
    </>
  );
}
