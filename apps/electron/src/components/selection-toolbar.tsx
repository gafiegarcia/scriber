"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { BookPlus, Check } from "lucide-react";
import { toast } from "sonner";
import { useDictionary } from "@/lib/dictionary-context";

interface SelectionToolbarProps {
  /** The container element to listen for selections in */
  containerRef: React.RefObject<HTMLElement | null>;
}

export function SelectionToolbar({ containerRef }: SelectionToolbarProps) {
  const { addTerm, terms } = useDictionary();
  const [selection, setSelection] = useState<{
    text: string;
    rect: DOMRect;
  } | null>(null);
  const toolbarRef = useRef<HTMLDivElement>(null);
  const [justAdded, setJustAdded] = useState(false);

  const handleSelectionChange = useCallback(() => {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.rangeCount) {
      // Small delay to allow click on toolbar button before clearing
      setTimeout(() => {
        const currentSel = window.getSelection();
        if (!currentSel || currentSel.isCollapsed) {
          setSelection(null);
          setJustAdded(false);
        }
      }, 200);
      return;
    }

    const text = sel.toString().trim();
    if (!text) {
      setSelection(null);
      return;
    }

    // Check that selection is within our container
    const container = containerRef.current;
    if (!container) return;

    const range = sel.getRangeAt(0);
    if (!container.contains(range.commonAncestorContainer)) return;

    const rect = range.getBoundingClientRect();
    setSelection({ text, rect });
    setJustAdded(false);
  }, [containerRef]);

  useEffect(() => {
    document.addEventListener("selectionchange", handleSelectionChange);
    return () => {
      document.removeEventListener("selectionchange", handleSelectionChange);
    };
  }, [handleSelectionChange]);

  const handleAdd = useCallback(() => {
    if (!selection) return;

    const text = selection.text;
    if (text.length > 50) {
      toast.error("Key term must be 50 characters or less");
      return;
    }

    if (terms.includes(text)) {
      toast.info(`"${text}" is already in your dictionary`);
      return;
    }

    const added = addTerm(text);
    if (added) {
      setJustAdded(true);
      toast.success(`Added "${text}" to dictionary`);
    }
  }, [selection, addTerm, terms]);

  if (!selection) return null;

  // Position the toolbar above the selection
  const top = selection.rect.top - 44;
  const left = selection.rect.left + selection.rect.width / 2;

  return (
    <div
      ref={toolbarRef}
      className="fixed z-50 -translate-x-1/2 animate-in fade-in slide-in-from-bottom-1 duration-150"
      style={{ top, left }}
    >
      <div className="flex items-center gap-1 rounded-lg border border-border/60 bg-popover px-1.5 py-1 shadow-lg">
        <button
          onMouseDown={(e) => {
            e.preventDefault(); // Prevent selection from clearing
            handleAdd();
          }}
          className={`flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors ${
            justAdded
              ? "text-emerald-600 dark:text-emerald-400"
              : "text-popover-foreground hover:bg-muted"
          }`}
        >
          {justAdded ? (
            <Check className="h-3.5 w-3.5" />
          ) : (
            <BookPlus className="h-3.5 w-3.5" />
          )}
          {justAdded ? "Added" : "Add to Dictionary"}
        </button>
      </div>
      {/* Arrow pointing down */}
      <div className="flex justify-center">
        <div className="h-2 w-2 rotate-45 border-b border-r border-border/60 bg-popover -mt-1" />
      </div>
    </div>
  );
}
