"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from "react";
import { getConfig, testApiKey } from "@/lib/config-client";

export type KeyStatus =
  | "unchecked"
  | "missing"
  | "invalid"
  | "unavailable"
  | "valid";

interface KeyStatusContextValue {
  status: KeyStatus;
  error: string | null;
  recheck: () => Promise<void>;
}

const KeyStatusContext = createContext<KeyStatusContextValue | null>(null);

export function KeyStatusProvider({ children }: { children: React.ReactNode }) {
  const [status, setStatus] = useState<KeyStatus>("unchecked");
  const [error, setError] = useState<string | null>(null);

  const recheck = useCallback(async () => {
    try {
      const cfg = await getConfig();
      if (!cfg.hasApiKey) {
        setStatus("missing");
        setError(null);
        return;
      }
      const result = await testApiKey();
      if (result.ok) {
        setStatus("valid");
        setError(null);
      } else {
        setStatus("invalid");
        setError(result.error || "Key validation failed");
      }
    } catch (err) {
      setStatus("unavailable");
      setError(
        err instanceof Error ? err.message : "Secure key storage is unavailable"
      );
      console.warn("[scriber] key status check failed:", err);
    }
  }, []);

  useEffect(() => {
    // Fire-and-forget probe of the API key on mount; setState happens after `await`.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    recheck();
  }, [recheck]);

  return (
    <KeyStatusContext.Provider value={{ status, error, recheck }}>
      {children}
    </KeyStatusContext.Provider>
  );
}

export function useKeyStatus() {
  const ctx = useContext(KeyStatusContext);
  if (!ctx) {
    throw new Error("useKeyStatus must be used within KeyStatusProvider");
  }
  return ctx;
}
