"use client";

import {
  Users,
  AudioLines,
  ChevronDown,
  ChevronUp,
  Languages,
  Search,
  Check,
  ChevronRight,
  SlidersHorizontal,
} from "lucide-react";
import { useMemo, useRef, useState } from "react";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useTranscribeOptions } from "@/lib/transcribe-options-context";

/**
 * All 99 languages supported by ElevenLabs Scribe v2.
 * Uses ISO 639-1 (2-letter) codes where available, ISO 639-3 (3-letter) otherwise.
 */
const LANGUAGES: readonly { code: string; label: string }[] = [
  { code: "af", label: "Afrikaans" },
  { code: "am", label: "Amharic" },
  { code: "ar", label: "Arabic" },
  { code: "hy", label: "Armenian" },
  { code: "as", label: "Assamese" },
  { code: "ast", label: "Asturian" },
  { code: "az", label: "Azerbaijani" },
  { code: "be", label: "Belarusian" },
  { code: "bn", label: "Bengali" },
  { code: "bs", label: "Bosnian" },
  { code: "bg", label: "Bulgarian" },
  { code: "my", label: "Burmese" },
  { code: "yue", label: "Cantonese" },
  { code: "ca", label: "Catalan" },
  { code: "ceb", label: "Cebuano" },
  { code: "ny", label: "Chichewa" },
  { code: "zh", label: "Chinese (Mandarin)" },
  { code: "hr", label: "Croatian" },
  { code: "cs", label: "Czech" },
  { code: "da", label: "Danish" },
  { code: "nl", label: "Dutch" },
  { code: "en", label: "English" },
  { code: "et", label: "Estonian" },
  { code: "fil", label: "Filipino" },
  { code: "fi", label: "Finnish" },
  { code: "fr", label: "French" },
  { code: "ff", label: "Fulah" },
  { code: "gl", label: "Galician" },
  { code: "lg", label: "Ganda" },
  { code: "ka", label: "Georgian" },
  { code: "de", label: "German" },
  { code: "el", label: "Greek" },
  { code: "gu", label: "Gujarati" },
  { code: "ha", label: "Hausa" },
  { code: "he", label: "Hebrew" },
  { code: "hi", label: "Hindi" },
  { code: "hu", label: "Hungarian" },
  { code: "is", label: "Icelandic" },
  { code: "ig", label: "Igbo" },
  { code: "id", label: "Bahasa Indonesia" },
  { code: "ga", label: "Irish" },
  { code: "it", label: "Italian" },
  { code: "ja", label: "Japanese" },
  { code: "jv", label: "Javanese" },
  { code: "kea", label: "Kabuverdianu" },
  { code: "kn", label: "Kannada" },
  { code: "kk", label: "Kazakh" },
  { code: "km", label: "Khmer" },
  { code: "ko", label: "Korean" },
  { code: "ku", label: "Kurdish" },
  { code: "ky", label: "Kyrgyz" },
  { code: "lo", label: "Lao" },
  { code: "lv", label: "Latvian" },
  { code: "ln", label: "Lingala" },
  { code: "lt", label: "Lithuanian" },
  { code: "luo", label: "Luo" },
  { code: "lb", label: "Luxembourgish" },
  { code: "mk", label: "Macedonian" },
  { code: "ms", label: "Malay" },
  { code: "ml", label: "Malayalam" },
  { code: "mt", label: "Maltese" },
  { code: "mi", label: "Maori" },
  { code: "mr", label: "Marathi" },
  { code: "mn", label: "Mongolian" },
  { code: "ne", label: "Nepali" },
  { code: "nso", label: "Northern Sotho" },
  { code: "no", label: "Norwegian" },
  { code: "oc", label: "Occitan" },
  { code: "or", label: "Odia" },
  { code: "ps", label: "Pashto" },
  { code: "fa", label: "Persian" },
  { code: "pl", label: "Polish" },
  { code: "pt", label: "Portuguese" },
  { code: "pa", label: "Punjabi" },
  { code: "ro", label: "Romanian" },
  { code: "ru", label: "Russian" },
  { code: "sr", label: "Serbian" },
  { code: "sn", label: "Shona" },
  { code: "sd", label: "Sindhi" },
  { code: "sk", label: "Slovak" },
  { code: "sl", label: "Slovenian" },
  { code: "so", label: "Somali" },
  { code: "es", label: "Spanish" },
  { code: "sw", label: "Swahili" },
  { code: "sv", label: "Swedish" },
  { code: "tg", label: "Tajik" },
  { code: "ta", label: "Tamil" },
  { code: "te", label: "Telugu" },
  { code: "th", label: "Thai" },
  { code: "tr", label: "Turkish" },
  { code: "uk", label: "Ukrainian" },
  { code: "umb", label: "Umbundu" },
  { code: "ur", label: "Urdu" },
  { code: "uz", label: "Uzbek" },
  { code: "vi", label: "Vietnamese" },
  { code: "cy", label: "Welsh" },
  { code: "wo", label: "Wolof" },
  { code: "xh", label: "Xhosa" },
  { code: "zu", label: "Zulu" },
];

/** Look up display label for a language code */
function getLanguageLabel(code: string): string {
  if (code === "auto") return "Auto-detect (Recommended)";
  return LANGUAGES.find((l) => l.code === code)?.label ?? code;
}

const SPEAKER_COUNTS = [
  { value: "auto", label: "Auto" },
  { value: "2", label: "2" },
  { value: "3", label: "3" },
  { value: "4", label: "4" },
  { value: "5", label: "5" },
  { value: "6", label: "6" },
] as const;

/** Searchable language picker dialog */
function LanguagePicker({
  value,
  onChange,
}: {
  value: string;
  onChange: (code: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  const filtered = useMemo(() => {
    if (!search.trim()) return LANGUAGES;
    const q = search.toLowerCase();
    return LANGUAGES.filter(
      (l) =>
        l.label.toLowerCase().includes(q) || l.code.toLowerCase().includes(q)
    );
  }, [search]);

  const isAuto = value === "auto";

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="flex items-center gap-1.5 rounded-lg border border-input bg-transparent px-2.5 py-1.5 text-sm transition-colors hover:bg-muted/50"
      >
        <span className="max-w-32 truncate">{getLanguageLabel(value)}</span>
        <ChevronRight className="h-3.5 w-3.5 text-muted-foreground" />
      </button>

      <Dialog
        open={open}
        onOpenChange={(nextOpen) => {
          setOpen(nextOpen);
          if (!nextOpen) setSearch("");
        }}
      >
        <DialogContent
          className="flex max-h-[70dvh] flex-col sm:max-w-sm"
          showCloseButton={false}
        >
          <DialogHeader>
            <DialogTitle>Language</DialogTitle>
          </DialogHeader>

          {/* Search */}
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input
              ref={inputRef}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search languages..."
              className="h-10 w-full rounded-lg border border-input bg-muted/30 pl-9 pr-3 text-sm outline-none placeholder:text-muted-foreground/40 focus:border-foreground/20"
              autoFocus
            />
          </div>

          {/* List */}
          <div className="-mx-4 flex-1 overflow-y-auto">
            {/* Auto-detect (Recommended) option */}
            {!search.trim() && (
              <button
                onClick={() => {
                  onChange("auto");
                  setOpen(false);
                  setSearch("");
                }}
                className={`flex w-full items-center justify-between px-5 py-2.5 text-sm transition-colors ${
                  isAuto
                    ? "bg-foreground/5 font-medium text-foreground"
                    : "text-foreground/80 active:bg-muted"
                }`}
              >
                Auto-detect (Recommended)
                {isAuto && <Check className="h-4 w-4 text-foreground" />}
              </button>
            )}

            {!search.trim() && (
              <div className="mx-5 border-b border-border/40" />
            )}

            {filtered.length === 0 ? (
              <p className="px-5 py-8 text-center text-sm text-muted-foreground/60">
                No languages found
              </p>
            ) : (
              filtered.map((lang) => {
                const selected = value === lang.code;
                return (
                  <button
                    key={lang.code}
                    onClick={() => {
                      onChange(lang.code);
                      setOpen(false);
                      setSearch("");
                    }}
                    className={`flex w-full items-center justify-between px-5 py-2.5 text-sm transition-colors ${
                      selected
                        ? "bg-foreground/5 font-medium text-foreground"
                        : "text-foreground/80 active:bg-muted"
                    }`}
                  >
                    {lang.label}
                    {selected && (
                      <Check className="h-4 w-4 text-foreground" />
                    )}
                  </button>
                );
              })
            )}
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}

/** Speakers + Sounds options (no language — language lives in Settings) */
function HomeOptionsPanel() {
  const { options, updateOption } = useTranscribeOptions();

  return (
    <div className="flex flex-col gap-4 rounded-xl border border-border/60 bg-card px-4 py-4">
      {/* Identify Speakers */}
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-sm">
            <Users className="h-4 w-4 text-muted-foreground" />
            <span className="font-medium">Identify Speakers</span>
          </div>
          <Switch
            checked={options.diarize}
            onCheckedChange={(val) => updateOption("diarize", val)}
            size="sm"
          />
        </div>
        {options.diarize && (
          <div className="ml-6 flex items-center justify-between gap-3">
            <span className="text-xs text-muted-foreground">
              How many speakers?
            </span>
            <Select
              value={options.numSpeakers?.toString() ?? "auto"}
              onValueChange={(val) =>
                updateOption(
                  "numSpeakers",
                  val === "auto" ? null : parseInt(val as string, 10)
                )
              }
            >
              <SelectTrigger size="sm">
                <SelectValue>
                  {(v: string) =>
                    SPEAKER_COUNTS.find((s) => s.value === v)?.label ?? v
                  }
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                {SPEAKER_COUNTS.map(({ value, label }) => (
                  <SelectItem key={value} value={value} label={label}>
                    {label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}
      </div>

      {/* Tag Sounds */}
      <div className="flex flex-col gap-1">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-sm">
            <AudioLines className="h-4 w-4 text-muted-foreground" />
            <span className="font-medium">Tag Sounds</span>
          </div>
          <Switch
            checked={options.tagAudioEvents}
            onCheckedChange={(val) => updateOption("tagAudioEvents", val)}
            size="sm"
          />
        </div>
        <span className="ml-6 text-xs text-muted-foreground/70">
          Labels laughter, music, applause, etc.
        </span>
      </div>
    </div>
  );
}

/** Full options panel with all controls (for Settings page) */
function FullOptionsPanel() {
  const { options, updateOption } = useTranscribeOptions();

  return (
    <div className="flex flex-col gap-4 rounded-xl border border-border/60 bg-card px-4 py-4">
      {/* Language */}
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2 text-sm">
          <Languages className="h-4 w-4 text-muted-foreground" />
          <span className="font-medium">Language</span>
        </div>
        <LanguagePicker
          value={options.languageCode}
          onChange={(code) => updateOption("languageCode", code)}
        />
      </div>

      {/* Identify Speakers */}
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-sm">
            <Users className="h-4 w-4 text-muted-foreground" />
            <span className="font-medium">Identify Speakers</span>
          </div>
          <Switch
            checked={options.diarize}
            onCheckedChange={(val) => updateOption("diarize", val)}
            size="sm"
          />
        </div>
        {options.diarize && (
          <div className="ml-6 flex items-center justify-between gap-3">
            <span className="text-xs text-muted-foreground">
              How many speakers?
            </span>
            <Select
              value={options.numSpeakers?.toString() ?? "auto"}
              onValueChange={(val) =>
                updateOption(
                  "numSpeakers",
                  val === "auto" ? null : parseInt(val as string, 10)
                )
              }
            >
              <SelectTrigger size="sm">
                <SelectValue>
                  {(v: string) =>
                    SPEAKER_COUNTS.find((s) => s.value === v)?.label ?? v
                  }
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                {SPEAKER_COUNTS.map(({ value, label }) => (
                  <SelectItem key={value} value={value} label={label}>
                    {label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        )}
      </div>

      {/* Tag Sounds */}
      <div className="flex flex-col gap-1">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-sm">
            <AudioLines className="h-4 w-4 text-muted-foreground" />
            <span className="font-medium">Tag Sounds</span>
          </div>
          <Switch
            checked={options.tagAudioEvents}
            onCheckedChange={(val) => updateOption("tagAudioEvents", val)}
            size="sm"
          />
        </div>
        <span className="ml-6 text-xs text-muted-foreground/70">
          Labels laughter, music, applause, etc.
        </span>
      </div>
    </div>
  );
}

/**
 * Transcription options — shown on the home/transcribe page.
 * Only shows Speakers + Sounds (language is in Settings).
 * No chips/badges when collapsed.
 */
export function TranscribeOptions() {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="flex w-full max-w-sm flex-col gap-2">
      <button
        onClick={() => setExpanded((prev) => !prev)}
        className="mx-auto flex items-center gap-1.5 rounded-full border border-border/60 bg-card px-3.5 py-1.5 text-xs font-medium text-muted-foreground transition-colors active:scale-[0.97]"
      >
        <SlidersHorizontal className="h-3.5 w-3.5" />
        Options
        {expanded ? (
          <ChevronUp className="h-3 w-3" />
        ) : (
          <ChevronDown className="h-3 w-3" />
        )}
      </button>
      {expanded && <HomeOptionsPanel />}
    </div>
  );
}

/** Export getLanguageLabel for use in other components */
export { getLanguageLabel };

/** Standalone options panel for use in Settings page (always expanded, no collapse) */
export function TranscribeOptionsSettings() {
  return <FullOptionsPanel />;
}
