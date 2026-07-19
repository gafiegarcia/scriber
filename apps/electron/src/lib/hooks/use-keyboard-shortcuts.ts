"use client";

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";

const FOCUS_SEARCH_EVENT = "scriber:focus-search";
let pendingFocus = false;

function dispatchFocusSearch() {
  window.dispatchEvent(new CustomEvent(FOCUS_SEARCH_EVENT));
}

type AppRouter = ReturnType<typeof useRouter>;

function isPlainLetterShortcutTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false;

  return Boolean(
    target.closest(
      [
        "input",
        "textarea",
        "select",
        "button",
        "a",
        "[contenteditable='true']",
        "[role='textbox']",
        "[role='button']",
        "[data-slot='dialog-content']",
        "[data-slot='dropdown-menu-content']",
      ].join(","),
    ),
  );
}

export function triggerNotesSearch(router: AppRouter, pathname: string) {
  if (pathname === "/notes" || pathname.startsWith("/notes/")) {
    dispatchFocusSearch();
  } else {
    pendingFocus = true;
    router.push("/notes");
  }
}

export function triggerNewTranscription(router: AppRouter, pathname: string) {
  if (pathname !== "/") {
    router.push("/");
  }
}

export function useGlobalShortcuts() {
  const pathname = usePathname();
  const router = useRouter();

  // When navigation completes after a ⌘K press, dispatch the focus event.
  // The pathname effect runs before the new route's components mount, so we
  // fire the dispatch a couple of times across event-loop ticks to bridge the
  // gap until the search input's listener is attached.
  useEffect(() => {
    if (!pendingFocus) return;
    if (pathname !== "/notes" && !pathname.startsWith("/notes/")) return;
    pendingFocus = false;
    const timers = [50, 150, 300].map((ms) =>
      setTimeout(dispatchFocusSearch, ms),
    );
    return () => timers.forEach(clearTimeout);
  }, [pathname]);

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      const isMac =
        typeof navigator !== "undefined" &&
        navigator.platform.toUpperCase().includes("MAC");
      const meta = isMac ? e.metaKey : e.ctrlKey;

      if (
        meta &&
        !e.altKey &&
        !e.shiftKey &&
        (e.key === "k" || e.key === "K")
      ) {
        e.preventDefault();
        triggerNotesSearch(router, pathname);
        return;
      }

      if (e.metaKey || e.ctrlKey || e.altKey) return;

      if (e.key === "t" || e.key === "T") {
        if (isPlainLetterShortcutTarget(e.target)) return;
        e.preventDefault();
        triggerNewTranscription(router, pathname);
      }
    }
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [pathname, router]);
}

export const SCRIBER_FOCUS_SEARCH_EVENT = FOCUS_SEARCH_EVENT;
