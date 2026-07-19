"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AlertTriangle, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";

const CHECK_INTERVAL_MS = 5_000;
const CHECK_TIMEOUT_MS = 2_000;
const FAILURE_THRESHOLD = 2;

async function probeHealth() {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), CHECK_TIMEOUT_MS);

  try {
    const res = await fetch("/api/health", {
      cache: "no-store",
      signal: controller.signal,
    });
    if (!res.ok) return false;
    const body = (await res.json().catch(() => null)) as { app?: string } | null;
    return body?.app === "scriber";
  } catch {
    return false;
  } finally {
    window.clearTimeout(timeout);
  }
}

export function ServerStatusBanner() {
  const [online, setOnline] = useState(true);
  const [checking, setChecking] = useState(false);
  const failedChecks = useRef(0);

  const updateStatus = useCallback((healthy: boolean) => {
    if (healthy) {
      failedChecks.current = 0;
      setOnline(true);
      return;
    }

    failedChecks.current += 1;
    if (failedChecks.current >= FAILURE_THRESHOLD) {
      setOnline(false);
    }
  }, []);

  const checkSilently = useCallback(async () => {
    updateStatus(await probeHealth());
  }, [updateStatus]);

  const check = useCallback(async () => {
    setChecking(true);
    try {
      await checkSilently();
    } finally {
      setChecking(false);
    }
  }, [checkSilently]);

  useEffect(() => {
    const initial = window.setTimeout(() => {
      void checkSilently();
    }, 0);

    const interval = window.setInterval(() => {
      void checkSilently();
    }, CHECK_INTERVAL_MS);

    function checkWhenVisible() {
      if (document.visibilityState === "visible") {
        void checkSilently();
      }
    }

    window.addEventListener("online", checkSilently);
    document.addEventListener("visibilitychange", checkWhenVisible);

    return () => {
      window.clearTimeout(initial);
      window.clearInterval(interval);
      window.removeEventListener("online", checkSilently);
      document.removeEventListener("visibilitychange", checkWhenVisible);
    };
  }, [checkSilently]);

  if (online) return null;

  return (
    <div className="flex shrink-0 items-center gap-2 border-b border-destructive/30 bg-destructive/10 px-5 py-2 text-xs text-destructive">
      <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
      <span className="flex-1">
        Scriber server is offline. Run <code>scriber</code> or{" "}
        <code>npm run dev</code>, then check again.
      </span>
      <Button
        type="button"
        variant="destructive"
        size="xs"
        onClick={check}
        disabled={checking}
      >
        <RefreshCw className={checking ? "animate-spin" : undefined} />
        Check
      </Button>
    </div>
  );
}
