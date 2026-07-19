"use client";

import { createContext, useContext, useEffect, useState } from "react";
import { getConfig, saveConfig } from "@/lib/config-client";

type Theme = "light" | "dark" | "system";

interface ThemeContextValue {
  theme: Theme;
  setTheme: (theme: Theme) => void;
}

const STORAGE_KEY = "scriber_theme";

function loadLocalCache(): Theme {
  if (typeof window === "undefined") return "system";
  return (localStorage.getItem(STORAGE_KEY) as Theme) ?? "system";
}

function writeLocalCache(theme: Theme) {
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch {
    // quota exceeded — silently ignore
  }
}

const ThemeContext = createContext<ThemeContextValue>({
  theme: "system",
  setTheme: () => {},
});

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(loadLocalCache);

  useEffect(() => {
    const root = document.documentElement;
    if (theme === "system") {
      root.classList.toggle("dark", window.matchMedia("(prefers-color-scheme: dark)").matches);
    } else {
      root.classList.toggle("dark", theme === "dark");
    }
  }, [theme]);

  // Pull authoritative value from config.json on mount AND whenever this tab
  // regains focus — so instances on other ports see each other's changes.
  useEffect(() => {
    let cancelled = false;

    async function sync() {
      try {
        const cfg = await getConfig();
        if (cancelled) return;
        const serverTheme: Theme = cfg.theme ?? "system";
        setThemeState(serverTheme);
        writeLocalCache(serverTheme);
      } catch (err) {
        console.warn("Failed to sync theme from server:", err);
      }
    }

    sync();

    function onFocus() {
      sync();
    }
    function onVisibility() {
      if (document.visibilityState === "visible") sync();
    }
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      cancelled = true;
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  function setTheme(next: Theme) {
    setThemeState(next);
    writeLocalCache(next);
    saveConfig({ theme: next }).catch((err) => {
      console.warn("Failed to persist theme:", err);
    });
  }

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  return useContext(ThemeContext);
}
