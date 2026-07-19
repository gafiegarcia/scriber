"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { PenLine } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogTrigger,
} from "@/components/ui/dialog";
import { createNote } from "@/lib/notes-client";

export function TextInput() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");

  async function handleSave() {
    const trimmedContent = content.trim();
    if (!trimmedContent) {
      toast.error("Please enter some text");
      return;
    }

    const note = await createNote({
      id: crypto.randomUUID(),
      title: title.trim() || `Note ${new Date().toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" })}`,
      content: trimmedContent,
      type: "text",
      source: "text",
      metadata: {},
    });

    setOpen(false);
    setTitle("");
    setContent("");
    toast.success("Note saved!");
    router.push(`/notes/${note.id}`);
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={
          <button
            className="flex h-14 w-14 items-center justify-center rounded-full border-2 border-border bg-background text-muted-foreground transition-all hover:border-foreground/30 hover:text-foreground active:scale-95"
            aria-label="Type or paste text"
          />
        }
      >
        <PenLine className="h-5 w-5" />
      </DialogTrigger>

      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>New Text Note</DialogTitle>
        </DialogHeader>

        <div className="flex flex-col gap-3">
          <input
            placeholder="Title (optional)"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            className="h-10 w-full rounded-lg border border-border bg-muted/30 px-3 text-sm outline-none placeholder:text-muted-foreground/40 focus:border-foreground/20 focus:bg-background"
          />
          <textarea
            placeholder="Type or paste your text here..."
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={6}
            autoFocus
            className="w-full resize-none rounded-lg border border-border bg-muted/30 p-3 text-sm leading-relaxed outline-none placeholder:text-muted-foreground/40 focus:border-foreground/20 focus:bg-background"
          />
        </div>

        <DialogFooter>
          <Button
            onClick={handleSave}
            disabled={!content.trim()}
            className="w-full sm:w-auto"
          >
            Save Note
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
