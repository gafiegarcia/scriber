import type { Note, TranscriptWord } from "./types";

/** Generate plain text export */
export function toTxt(note: Note): string {
  const body = buildDiarizedText(note) ?? note.content;
  return `${note.title}\n\n${body}\n`;
}

/** Generate plain text export with metadata */
export function toTxtWithMeta(note: Note): string {
  const body = buildDiarizedText(note) ?? note.content;
  const meta = buildMetaLines(note);
  return `${note.title}\n\n${body}\n\n---\n${meta.join("\n")}\n`;
}

/** Generate plain Markdown export (no metadata) */
export function toPlainMarkdown(note: Note): string {
  const body = buildDiarizedMarkdown(note) ?? note.content;
  return `# ${note.title}\n\n${body}\n`;
}

/** Generate Markdown export with metadata */
export function toMarkdown(note: Note): string {
  const body = buildDiarizedMarkdown(note) ?? note.content;
  const meta = buildMetaLines(note);
  return `# ${note.title}\n\n${body}\n\n---\n*${meta.join(" | ")}*\n`;
}

/** Generate SRT subtitle format from word-level timestamps */
export function toSrt(note: Note): string {
  const words = note.metadata?.words;
  if (!words || words.length === 0) {
    // Fallback: single entry with the full text
    return `1\n00:00:00,000 --> 00:00:10,000\n${note.content}\n`;
  }

  const hasSpeakers =
    note.metadata?.hasDiarization && words.some((w) => w.speaker_id);

  // Group words into segments (~10 words each, also break on speaker change)
  const segments = groupWordsIntoSegments(words, 10, hasSpeakers ?? false);

  return segments
    .map((seg, i) => {
      const start = formatSrtTime(seg.start);
      const end = formatSrtTime(seg.end);
      const prefix = seg.speakerLabel ? `[${seg.speakerLabel}] ` : "";
      return `${i + 1}\n${start} --> ${end}\n${prefix}${seg.text}\n`;
    })
    .join("\n");
}

interface Segment {
  text: string;
  start: number;
  end: number;
  speakerLabel?: string;
}

function getSpeakerLabel(
  speakerId: string,
  speakerMap: Map<string, string>
): string {
  let label = speakerMap.get(speakerId);
  if (!label) {
    label = `Speaker ${String.fromCharCode(65 + speakerMap.size)}`;
    speakerMap.set(speakerId, label);
  }
  return label;
}

function groupWordsIntoSegments(
  words: TranscriptWord[],
  maxWords: number,
  breakOnSpeaker: boolean
): Segment[] {
  const segments: Segment[] = [];
  const speakerMap = new Map<string, string>();
  let current: TranscriptWord[] = [];
  let currentSpeaker: string | undefined;

  function flush() {
    if (current.length === 0) return;
    const seg: Segment = {
      text: current.map((c) => c.text).join(" "),
      start: current[0].start,
      end: current[current.length - 1].end,
    };
    if (breakOnSpeaker && currentSpeaker) {
      seg.speakerLabel = getSpeakerLabel(currentSpeaker, speakerMap);
    }
    segments.push(seg);
    current = [];
  }

  for (const w of words) {
    if (w.type !== "word" && w.type !== "audio_event") continue;

    // Break on speaker change
    if (breakOnSpeaker && w.speaker_id !== currentSpeaker && current.length > 0) {
      flush();
    }

    currentSpeaker = w.speaker_id;
    current.push(w);

    if (current.length >= maxWords) {
      flush();
    }
  }

  flush();
  return segments;
}

/** Build speaker-labeled plain text from diarized words */
function buildDiarizedText(note: Note): string | null {
  if (!note.metadata?.hasDiarization || !note.metadata.words?.some((w) => w.speaker_id)) {
    return null;
  }

  const words = note.metadata.words;
  const speakerMap = new Map<string, string>();
  const paragraphs: string[] = [];
  let currentId = "";
  let currentText = "";

  for (const word of words) {
    const id = word.speaker_id ?? "unknown";
    if (id !== currentId && currentText) {
      const label = getSpeakerLabel(currentId, speakerMap);
      paragraphs.push(`${label}: ${currentText.trim()}`);
      currentText = "";
    }
    currentId = id;
    currentText += word.text;
  }
  if (currentText.trim()) {
    const label = getSpeakerLabel(currentId, speakerMap);
    paragraphs.push(`${label}: ${currentText.trim()}`);
  }

  return paragraphs.join("\n\n");
}

/** Build speaker-labeled markdown from diarized words */
function buildDiarizedMarkdown(note: Note): string | null {
  if (!note.metadata?.hasDiarization || !note.metadata.words?.some((w) => w.speaker_id)) {
    return null;
  }

  const words = note.metadata.words;
  const speakerMap = new Map<string, string>();
  const paragraphs: string[] = [];
  let currentId = "";
  let currentText = "";

  for (const word of words) {
    const id = word.speaker_id ?? "unknown";
    if (id !== currentId && currentText) {
      const label = getSpeakerLabel(currentId, speakerMap);
      paragraphs.push(`**${label}:** ${currentText.trim()}`);
      currentText = "";
    }
    currentId = id;
    currentText += word.text;
  }
  if (currentText.trim()) {
    const label = getSpeakerLabel(currentId, speakerMap);
    paragraphs.push(`**${label}:** ${currentText.trim()}`);
  }

  return paragraphs.join("\n\n");
}

function buildMetaLines(note: Note): string[] {
  const lines: string[] = [];
  lines.push(`Transcribed on ${new Date(note.createdAt).toLocaleString()}`);
  const wordCount = note.content.trim() === "" ? 0 : note.content.trim().split(/\s+/).length;
  lines.push(`${wordCount} words`);
  if (note.durationSeconds != null) {
    const m = Math.floor(note.durationSeconds / 60);
    const s = Math.round(note.durationSeconds % 60);
    lines.push(m > 0 ? `${m}m ${s}s` : `${s}s`);
  }
  if (note.language && note.language !== "auto") {
    lines.push(note.language.toUpperCase());
  }
  return lines;
}

function formatSrtTime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  const ms = Math.round((seconds % 1) * 1000);
  return `${pad(h)}:${pad(m)}:${pad(s)},${ms.toString().padStart(3, "0")}`;
}

function pad(n: number): string {
  return n.toString().padStart(2, "0");
}

/** Trigger a file download in the browser */
export function downloadFile(
  content: string,
  filename: string,
  mimeType: string
) {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
