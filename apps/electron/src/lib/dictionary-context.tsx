"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import { getConfig, saveConfig } from "@/lib/config-client";

const STORAGE_KEY = "scriber_dictionary";
const MAX_TERMS = 1000; // ElevenLabs limit
const MAX_TERM_LENGTH = 50; // ElevenLabs limit

function loadLocalCache(): string[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeLocalCache(terms: string[]) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(terms));
  } catch {
    // quota exceeded — silently ignore
  }
}

interface DictionaryContextValue {
  terms: string[];
  addTerm: (term: string) => boolean;
  removeTerm: (term: string) => void;
  clearTerms: () => void;
}

const DictionaryContext = createContext<DictionaryContextValue | null>(null);

export function DictionaryProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const [terms, setTerms] = useState<string[]>(() => loadLocalCache());

  useEffect(() => {
    let cancelled = false;
    getConfig()
      .then((cfg) => {
        if (cancelled) return;
        if (Array.isArray(cfg.dictionary)) {
          setTerms(cfg.dictionary);
          writeLocalCache(cfg.dictionary);
        }
      })
      .catch(() => {
        // keep localStorage fallback already applied above
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const persist = useCallback((next: string[]) => {
    writeLocalCache(next);
    saveConfig({ dictionary: next }).catch((err) => {
      console.warn("Failed to persist dictionary:", err);
    });
  }, []);

  const addTerm = useCallback(
    (raw: string): boolean => {
      const term = raw.trim();
      if (!term || term.length > MAX_TERM_LENGTH) return false;

      let added = false;
      setTerms((prev) => {
        if (prev.includes(term) || prev.length >= MAX_TERMS) return prev;
        const next = [...prev, term].sort((a, b) => a.localeCompare(b));
        persist(next);
        added = true;
        return next;
      });
      return added;
    },
    [persist]
  );

  const removeTerm = useCallback(
    (term: string) => {
      setTerms((prev) => {
        const next = prev.filter((t) => t !== term);
        persist(next);
        return next;
      });
    },
    [persist]
  );

  const clearTerms = useCallback(() => {
    setTerms([]);
    persist([]);
  }, [persist]);

  const value = useMemo(
    () => ({ terms, addTerm, removeTerm, clearTerms }),
    [terms, addTerm, removeTerm, clearTerms]
  );

  return (
    <DictionaryContext.Provider value={value}>
      {children}
    </DictionaryContext.Provider>
  );
}

export function useDictionary() {
  const ctx = useContext(DictionaryContext);
  if (!ctx) {
    throw new Error(
      "useDictionary must be used within DictionaryProvider"
    );
  }
  return ctx;
}
