"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import type { TranscribeOptions } from "@/lib/types";
import { getConfig, saveConfig } from "@/lib/config-client";

const STORAGE_KEY = "scriber_transcribe_options";

const defaults: TranscribeOptions = {
  languageCode: "auto",
  diarize: false,
  numSpeakers: null,
  tagAudioEvents: false,
};

function loadLocalCache(): TranscribeOptions {
  if (typeof window === "undefined") return defaults;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return defaults;
    const parsed = { ...defaults, ...JSON.parse(raw) };
    if (parsed.languageCode === "") parsed.languageCode = "auto";
    return parsed;
  } catch {
    return defaults;
  }
}

function writeLocalCache(options: TranscribeOptions) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(options));
  } catch {
    // quota exceeded — silently ignore
  }
}

interface TranscribeOptionsContextValue {
  options: TranscribeOptions;
  updateOption: <K extends keyof TranscribeOptions>(
    key: K,
    value: TranscribeOptions[K]
  ) => void;
}

const TranscribeOptionsContext =
  createContext<TranscribeOptionsContextValue | null>(null);

export function TranscribeOptionsProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const [options, setOptions] = useState<TranscribeOptions>(loadLocalCache);

  useEffect(() => {
    let cancelled = false;
    getConfig()
      .then((cfg) => {
        if (cancelled) return;
        if (cfg.defaults) {
          setOptions(cfg.defaults);
          writeLocalCache(cfg.defaults);
        }
      })
      .catch(() => {
        // keep localStorage fallback
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const updateOption = useCallback(
    <K extends keyof TranscribeOptions>(
      key: K,
      value: TranscribeOptions[K]
    ) => {
      setOptions((prev) => {
        const next = { ...prev, [key]: value };
        writeLocalCache(next);
        saveConfig({ defaults: next }).catch((err) => {
          console.warn("Failed to persist transcribe options:", err);
        });
        return next;
      });
    },
    []
  );

  const value = useMemo(
    () => ({ options, updateOption }),
    [options, updateOption]
  );

  return (
    <TranscribeOptionsContext.Provider value={value}>
      {children}
    </TranscribeOptionsContext.Provider>
  );
}

export function useTranscribeOptions() {
  const ctx = useContext(TranscribeOptionsContext);
  if (!ctx) {
    throw new Error(
      "useTranscribeOptions must be used within TranscribeOptionsProvider"
    );
  }
  return ctx;
}
