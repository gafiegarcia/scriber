"use client";

import { useState } from "react";
import { createPortal } from "react-dom";
import { PowerOff, Loader2 } from "lucide-react";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";

export function ExitButton() {
  const [stopping, setStopping] = useState(false);
  const [stopped, setStopped] = useState(false);

  async function handleExit() {
    setStopping(true);
    try {
      await fetch("/api/shutdown", { method: "POST" });
    } catch {
      // ignore — server may have already shut down
    }
    window.close();
    setStopped(true);
  }

  if (stopped) {
    // createPortal renders at document.body, escaping the backdrop-filter
    // containing block on DesktopSidebar that would otherwise confine a
    // position:fixed child to the sidebar column instead of the full viewport.
    return createPortal(
      <div className="fixed inset-0 z-[100] flex flex-col items-center justify-center gap-3 bg-background px-6 text-center">
        <div className="flex h-12 w-12 items-center justify-center rounded-full bg-foreground/10">
          <PowerOff className="h-6 w-6 text-foreground/70" />
        </div>
        <h1 className="text-xl font-semibold">Scriber stopped</h1>
        <p className="max-w-sm text-sm text-muted-foreground">
          You can close this tab now.
        </p>
        <p className="max-w-sm text-sm text-muted-foreground">
          To start Scriber again, run{" "}
          <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">
            scriber
          </code>{" "}
          in your terminal.
        </p>
      </div>,
      document.body
    );
  }

  return (
    <AlertDialog>
      <AlertDialogTrigger
        render={
          <button
            type="button"
            disabled={stopping}
            aria-label="Exit Scriber"
            title="Exit Scriber"
            className="inline-flex h-9 items-center gap-1.5 rounded-full px-3 text-sm font-medium text-destructive/70 transition-colors hover:bg-destructive/10 hover:text-destructive focus-visible:bg-destructive/10 focus-visible:text-destructive focus-visible:outline-2 focus-visible:outline-destructive disabled:pointer-events-none disabled:opacity-50"
          />
        }
      >
        {stopping ? (
          <>
            <Loader2 className="h-4 w-4 animate-spin" />
            <span>Stopping...</span>
          </>
        ) : (
          <>
            <PowerOff className="h-4 w-4" />
            <span>Exit Scriber</span>
          </>
        )}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Stop Scriber?</AlertDialogTitle>
          <AlertDialogDescription>
            This closes the local server running in your terminal. Your notes
            and audio stay safe on disk. You&apos;ll need to run{" "}
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
              scriber
            </code>{" "}
            again to use the app.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction onClick={handleExit}>
            Stop Scriber
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
