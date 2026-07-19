import type { ScribeWord } from "@/lib/types/elevenlabs";

const MAX_WORDS_PER_CUE = 7;
const MAX_CUE_DURATION_SEC = 5;

function formatTimestamp(seconds: number): string {
  const clamped = Math.max(0, seconds);
  const hours = Math.floor(clamped / 3600);
  const minutes = Math.floor((clamped % 3600) / 60);
  const secs = Math.floor(clamped % 60);
  const ms = Math.floor((clamped - Math.floor(clamped)) * 1000);
  return (
    `${String(hours).padStart(2, "0")}:` +
    `${String(minutes).padStart(2, "0")}:` +
    `${String(secs).padStart(2, "0")},` +
    `${String(ms).padStart(3, "0")}`
  );
}

interface Cue {
  start: number;
  end: number;
  text: string;
}

function buildCues(words: ScribeWord[]): Cue[] {
  const cues: Cue[] = [];
  let current: ScribeWord[] = [];
  let currentStart: number | null = null;
  let wordCount = 0;

  const flush = () => {
    if (current.length === 0) return;
    const start = currentStart ?? current[0].start;
    const end = current[current.length - 1].end;
    const text = current
      .map((w) => w.text)
      .join("")
      .replace(/\s+/g, " ")
      .trim();
    if (text) cues.push({ start, end, text });
    current = [];
    currentStart = null;
    wordCount = 0;
  };

  for (const w of words) {
    // Flush at phrase boundaries — when a new WORD arrives and the current
    // cue is already at the word cap or duration cap. This keeps trailing
    // punctuation attached to its preceding word instead of orphaning it
    // into a new cue.
    if (w.type === "word" && current.length > 0) {
      const spanSec = currentStart != null ? w.start - currentStart : 0;
      if (wordCount >= MAX_WORDS_PER_CUE || spanSec >= MAX_CUE_DURATION_SEC) {
        flush();
      }
    }
    // Skip leading spacing (never start a cue with whitespace)
    if (w.type === "spacing" && current.length === 0) continue;
    if (currentStart == null) currentStart = w.start;
    current.push(w);
    if (w.type === "word") wordCount += 1;
  }
  flush();
  return cues;
}

export function renderSrt(words: ScribeWord[]): string {
  const cues = buildCues(words);
  const blocks = cues.map(
    (cue, i) =>
      `${i + 1}\n${formatTimestamp(cue.start)} --> ${formatTimestamp(cue.end)}\n${cue.text}\n`
  );
  return blocks.join("\n");
}
