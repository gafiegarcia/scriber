"use client";

import { useEffect, useRef, useState } from "react";
import {
  Moon,
  Sun,
  Monitor,
  Download,
  Upload,
  Trash2,
  Palette,
  Database,
  Info,
  Mic,
  BookOpen,
  Plus,
  X,
  KeyRound,
} from "lucide-react";
import { toast } from "sonner";
import pkg from "../../../package.json";
import { Button } from "@/components/ui/button";
import { useDictionary } from "@/lib/dictionary-context";
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
import { useTheme } from "@/components/theme-provider";
import { TranscribeOptionsSettings } from "@/components/transcribe-options";
import { ApiKeySettings } from "@/components/api-key-settings";
import { useNotes } from "@/lib/hooks/use-notes";
import { deleteAllNotes } from "@/lib/notes-client";
import { deleteAllAudio } from "@/lib/audio-client";
import {
  downloadBackup,
  restoreBackup,
  type RestoreMode,
} from "@/lib/backup-client";

const themes = [
  { value: "light" as const, label: "Light", icon: Sun },
  { value: "dark" as const, label: "Dark", icon: Moon },
  { value: "system" as const, label: "System", icon: Monitor },
];

type SectionId =
  | "appearance"
  | "api-key"
  | "transcription"
  | "dictionary"
  | "data"
  | "about";

const SECTIONS: { id: SectionId; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { id: "appearance", label: "Appearance", icon: Palette },
  { id: "api-key", label: "API Key", icon: KeyRound },
  { id: "transcription", label: "Transcription", icon: Mic },
  { id: "dictionary", label: "Dictionary", icon: BookOpen },
  { id: "data", label: "Data", icon: Database },
  { id: "about", label: "About", icon: Info },
];

function getSectionScrollTop(container: HTMLElement, section: HTMLElement) {
  const sectionTop =
    container.scrollTop +
    section.getBoundingClientRect().top -
    container.getBoundingClientRect().top;
  const scrollMarginTop = Number.parseFloat(
    window.getComputedStyle(section).scrollMarginTop
  );

  return sectionTop - (Number.isFinite(scrollMarginTop) ? scrollMarginTop : 0);
}

function SettingsSection({
  id,
  icon: Icon,
  title,
  children,
}: {
  id: SectionId;
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  children: React.ReactNode;
}) {
  const sectionId = `settings-${id}`;

  return (
    <section
      id={sectionId}
      aria-labelledby={`${sectionId}-title`}
      className="scroll-mt-6 rounded-2xl border border-border/60 bg-card"
    >
      <div className="flex items-center gap-2.5 px-5 pt-4 pb-3">
        <Icon aria-hidden="true" className="h-4.5 w-4.5 text-muted-foreground" />
        <h2 id={`${sectionId}-title`} className="text-base font-semibold">
          {title}
        </h2>
      </div>
      <div className="px-5 pb-5">{children}</div>
    </section>
  );
}

export default function SettingsPage() {
  const { theme, setTheme } = useTheme();
  const { notes } = useNotes();
  const noteCount = notes.length;
  const { terms, addTerm, removeTerm, clearTerms } = useDictionary();
  const [newTerm, setNewTerm] = useState("");
  const backupInputRef = useRef<HTMLInputElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const [deleting, setDeleting] = useState(false);
  const [restoreFile, setRestoreFile] = useState<File | null>(null);
  const [restoring, setRestoring] = useState(false);
  const [activeId, setActiveId] = useState<SectionId>("appearance");

  useEffect(() => {
    const container = contentRef.current;
    if (!container) return;

    let animationFrame = 0;

    const syncActiveSection = () => {
      cancelAnimationFrame(animationFrame);
      animationFrame = requestAnimationFrame(() => {
        const hasScrollableOverflow =
          container.scrollHeight > container.clientHeight + 8;
        const nearBottom =
          hasScrollableOverflow &&
          container.scrollHeight - container.scrollTop - container.clientHeight < 8;
        let nextActiveId = nearBottom
          ? SECTIONS[SECTIONS.length - 1].id
          : SECTIONS[0].id;

        if (!nearBottom) {
          const activationLine =
            container.getBoundingClientRect().top +
            Math.min(120, container.clientHeight * 0.2);

          for (const { id } of SECTIONS) {
            const section = document.getElementById(`settings-${id}`);
            if (!section || section.getBoundingClientRect().top > activationLine) {
              break;
            }
            nextActiveId = id;
          }
        }

        setActiveId((current) =>
          current === nextActiveId ? current : nextActiveId
        );
      });
    };

    const initialId = window.location.hash.replace("#settings-", "") as SectionId;
    const initialSection = SECTIONS.some(({ id }) => id === initialId)
      ? document.getElementById(`settings-${initialId}`)
      : null;

    if (initialSection) {
      container.scrollTo({
        top: getSectionScrollTop(container, initialSection),
        behavior: "auto",
      });
    }

    syncActiveSection();
    container.addEventListener("scroll", syncActiveSection, { passive: true });
    window.addEventListener("resize", syncActiveSection);

    return () => {
      cancelAnimationFrame(animationFrame);
      container.removeEventListener("scroll", syncActiveSection);
      window.removeEventListener("resize", syncActiveSection);
    };
  }, []);

  function handleSectionNavigation(
    event: React.MouseEvent<HTMLAnchorElement>,
    id: SectionId
  ) {
    event.preventDefault();
    const section = document.getElementById(`settings-${id}`);
    const container = contentRef.current;
    if (!section || !container) return;

    setActiveId(id);
    container.scrollTo({
      top: getSectionScrollTop(container, section),
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
        ? "auto"
        : "smooth",
    });
    window.history.replaceState(null, "", `#settings-${id}`);
  }

  async function handleRestore(mode: RestoreMode) {
    if (!restoreFile) return;
    setRestoring(true);
    try {
      const result = await restoreBackup(restoreFile, mode);
      toast.success(
        `Restored ${result.notesImported} note${result.notesImported !== 1 ? "s" : ""} and ${result.audioImported} audio file${result.audioImported !== 1 ? "s" : ""}${result.notesSkipped + result.audioSkipped > 0 ? ` (${result.notesSkipped + result.audioSkipped} existing items skipped)` : ""}`
      );
      setRestoreFile(null);
      window.setTimeout(() => window.location.reload(), 700);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Restore failed");
    } finally {
      setRestoring(false);
    }
  }

  async function handleDeleteAll() {
    setDeleting(true);
    try {
      await deleteAllNotes();
      await deleteAllAudio().catch(console.warn);
      toast.success("All notes deleted");
    } catch {
      toast.error("Failed to delete notes");
    } finally {
      setDeleting(false);
    }
  }

  return (
    <div className="h-full lg:flex">
      {/* Desktop sub-sidebar */}
      <aside className="hidden w-56 shrink-0 flex-col border-r border-border/40 lg:flex">
        <div className="px-4 py-4">
          <h1 className="text-base font-semibold">Settings</h1>
        </div>
        <nav aria-label="Settings sections" className="flex flex-col gap-0.5 px-2">
          {SECTIONS.map(({ id, label, icon: Icon }) => {
            const active = activeId === id;
            return (
              <a
                key={id}
                href={`#settings-${id}`}
                onClick={(event) => handleSectionNavigation(event, id)}
                aria-current={active ? "location" : undefined}
                className={`flex h-8 items-center gap-2 rounded-md px-2 text-sm transition-colors ${
                  active
                    ? "bg-foreground/10 text-foreground"
                    : "text-muted-foreground hover:bg-foreground/5 hover:text-foreground"
                }`}
              >
                <Icon aria-hidden="true" className="h-4 w-4" />
                {label}
              </a>
            );
          })}
        </nav>
      </aside>

      {/* Content */}
      <div
        ref={contentRef}
        className="flex flex-col gap-4 px-5 pb-6 pt-6 lg:flex-1 lg:overflow-y-auto lg:px-8 lg:pb-10 lg:pt-6"
      >
        <h1 className="mb-1 text-2xl font-bold tracking-tight lg:hidden">Settings</h1>

        <div className="mx-auto flex w-full flex-col gap-4 lg:max-w-2xl lg:gap-7">
          {/* Appearance */}
          <SettingsSection
            id="appearance"
            icon={Palette}
            title="Appearance"
          >
            <p className="mb-3 text-sm text-muted-foreground/70">
              Choose your preferred theme
            </p>
            <div className="flex gap-2">
              {themes.map(({ value, label, icon: Icon }) => (
                <button
                  key={value}
                  onClick={() => setTheme(value)}
                  className={`flex flex-1 flex-col items-center gap-1.5 rounded-xl border-2 px-3 py-3.5 text-sm font-medium transition-all ${
                    theme === value
                      ? "border-foreground bg-foreground/5 text-foreground"
                      : "border-border/60 text-muted-foreground hover:border-border active:scale-[0.98]"
                  }`}
                >
                  <Icon className="h-5 w-5" />
                  {label}
                </button>
              ))}
            </div>
          </SettingsSection>

          {/* API Key */}
          <SettingsSection
            id="api-key"
            icon={KeyRound}
            title="API Key"
          >
            <ApiKeySettings />
          </SettingsSection>

          {/* Transcription */}
          <SettingsSection
            id="transcription"
            icon={Mic}
            title="Transcription"
          >
            <p className="mb-3 text-sm text-muted-foreground/70">
              Configure language, speaker detection, and sound tagging
            </p>
            <TranscribeOptionsSettings />
          </SettingsSection>

          {/* Dictionary */}
          <SettingsSection
            id="dictionary"
            icon={BookOpen}
            title="Dictionary"
          >
            <p className="mb-3 text-sm text-muted-foreground/70">
              Key terms sent to ElevenLabs to improve transcription accuracy.
              Select text in any transcript or add terms here.
            </p>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                if (!newTerm.trim()) return;
                const added = addTerm(newTerm);
                if (added) {
                  toast.success(`Added "${newTerm.trim()}" to dictionary`);
                  setNewTerm("");
                } else {
                  toast.info("Term already exists or is invalid");
                }
              }}
              className="mb-3 flex gap-2"
            >
              <input
                value={newTerm}
                onChange={(e) => setNewTerm(e.target.value)}
                placeholder="Add a key term..."
                maxLength={50}
                className="h-10 flex-1 rounded-xl border border-border bg-muted/30 px-3 text-sm outline-none placeholder:text-muted-foreground/40 focus:border-foreground/20"
              />
              <Button
                type="submit"
                variant="outline"
                size="sm"
                className="h-10 rounded-xl"
                disabled={!newTerm.trim()}
              >
                <Plus className="mr-1.5 h-3.5 w-3.5" />
                Add
              </Button>
            </form>
            {terms.length > 0 ? (
              <div className="flex flex-wrap gap-1.5">
                {terms.map((term) => (
                  <span
                    key={term}
                    className="inline-flex items-center gap-1 rounded-full bg-foreground/10 px-2.5 py-1 text-xs font-medium text-foreground/70"
                  >
                    {term}
                    <button
                      onClick={() => {
                        removeTerm(term);
                        toast.success(`Removed "${term}" from dictionary`);
                      }}
                      className="ml-0.5 rounded-full p-0.5 transition-colors hover:bg-foreground/10"
                      aria-label={`Remove ${term}`}
                    >
                      <X className="h-2.5 w-2.5" />
                    </button>
                  </span>
                ))}
              </div>
            ) : (
              <p className="text-xs text-muted-foreground/50">
                No key terms yet. Add terms to help the transcription engine
                recognize names, jargon, or uncommon words.
              </p>
            )}
            {terms.length > 0 && (
              <button
                onClick={() => {
                  clearTerms();
                  toast.success("Dictionary cleared");
                }}
                className="mt-3 text-xs text-destructive/70 transition-colors hover:text-destructive"
              >
                Clear all terms
              </button>
            )}
          </SettingsSection>

          {/* Data */}
          <SettingsSection
            id="data"
            icon={Database}
            title="Data"
          >
            <p className="mb-3 text-sm text-muted-foreground/70">
              {noteCount} note{noteCount !== 1 ? "s" : ""} stored locally in ~/.scriber/
            </p>
            <p className="mb-3 text-xs text-muted-foreground/60">
              Backups include notes, audio, dictionary, and settings. Your API
              key stays in secure storage and is never included.
            </p>
            <div className="flex flex-col gap-2">
              <Button
                variant="outline"
                size="sm"
                className="h-10 justify-start rounded-xl text-sm"
                onClick={() => {
                  downloadBackup();
                  toast.success("Backup download started");
                }}
              >
                <Download className="mr-2 h-4 w-4" />
                Download Complete Backup
              </Button>

              <input
                ref={backupInputRef}
                type="file"
                accept=".gz,.tgz,application/gzip"
                className="hidden"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) setRestoreFile(file);
                  if (backupInputRef.current) backupInputRef.current.value = "";
                }}
              />
              <Button
                variant="outline"
                size="sm"
                className="h-10 justify-start rounded-xl text-sm"
                onClick={() => backupInputRef.current?.click()}
                disabled={restoring}
              >
                <Upload className="mr-2 h-4 w-4" />
                {restoring ? "Restoring…" : "Restore Backup…"}
              </Button>

              <AlertDialog
                open={Boolean(restoreFile)}
                onOpenChange={(open) => {
                  if (!open && !restoring) setRestoreFile(null);
                }}
              >
                <AlertDialogContent>
                  <AlertDialogHeader>
                    <AlertDialogTitle>Restore this Scriber backup?</AlertDialogTitle>
                    <AlertDialogDescription>
                      Merge keeps your current notes and skips duplicates. Replace
                      removes current notes and audio, then restores the backup
                      exactly. Settings are restored either way; your API key is
                      never changed.
                    </AlertDialogDescription>
                  </AlertDialogHeader>
                  <AlertDialogFooter>
                    <AlertDialogCancel disabled={restoring}>Cancel</AlertDialogCancel>
                    <AlertDialogAction
                      disabled={restoring}
                      onClick={() => handleRestore("merge")}
                    >
                      Merge
                    </AlertDialogAction>
                    <AlertDialogAction
                      disabled={restoring}
                      onClick={() => handleRestore("replace")}
                      className="bg-destructive text-white hover:bg-destructive/90"
                    >
                      Replace All
                    </AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>

              <AlertDialog>
                <AlertDialogTrigger
                  render={
                    <Button
                      variant="outline"
                      size="sm"
                      className="h-10 justify-start rounded-xl text-sm text-destructive hover:text-destructive"
                      disabled={deleting}
                    />
                  }
                >
                  <Trash2 className="mr-2 h-4 w-4" />
                  {deleting ? "Deleting..." : "Delete All Notes"}
                </AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader>
                    <AlertDialogTitle>Delete all notes?</AlertDialogTitle>
                    <AlertDialogDescription>
                      This will permanently delete all {noteCount} note
                      {noteCount !== 1 ? "s" : ""}. This cannot be undone.
                    </AlertDialogDescription>
                  </AlertDialogHeader>
                  <AlertDialogFooter>
                    <AlertDialogCancel>Cancel</AlertDialogCancel>
                    <AlertDialogAction onClick={handleDeleteAll}>
                      Delete All
                    </AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            </div>
          </SettingsSection>

          {/* About */}
          <SettingsSection
            id="about"
            icon={Info}
            title="About"
          >
            <div className="space-y-1.5 text-sm text-muted-foreground/70">
              <p>
                <span className="font-medium text-muted-foreground">Scriber</span>{" "}
                v{pkg.version}
              </p>
              <p>Voice transcription powered by ElevenLabs Scribe v2</p>
            </div>
          </SettingsSection>
        </div>
      </div>
    </div>
  );
}
