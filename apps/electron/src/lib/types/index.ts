export interface Note {
  id: string;
  title: string;
  content: string;
  type: "transcription" | "text";
  source: "recording" | "upload" | "text";
  audioFileName?: string;
  durationSeconds?: number;
  language?: string;
  tags?: string[];
  metadata: NoteMetadata;
  createdAt: string; // ISO 8601
  updatedAt: string; // ISO 8601
}

export interface NoteMetadata {
  /** Word-level timestamps from ElevenLabs Scribe v2 */
  words?: TranscriptWord[];
  /** Detected language probability */
  languageProbability?: number;
  /** Additional formats (SRT, etc.) stored as base64 */
  additionalFormats?: Record<string, string>;
  /** Whether speaker diarization was enabled for this transcription */
  hasDiarization?: boolean;
  /** Whether audio event tagging was enabled */
  hasAudioEventTags?: boolean;
}

export interface TranscriptWord {
  text: string;
  start: number;
  end: number;
  type: "word" | "punctuation" | "spacing" | "audio_event";
  speaker_id?: string;
  /** ElevenLabs per-token confidence in log space; closer to zero is stronger. */
  logprob?: number;
}

export interface TranscribeOptions {
  languageCode: string; // "auto" = auto-detect
  diarize: boolean;
  numSpeakers: number | null; // null = auto
  tagAudioEvents: boolean;
}

/** Payload for creating a new note (id and timestamps auto-generated) */
export type CreateNoteInput = Omit<Note, "id" | "createdAt" | "updatedAt">;

/** Payload for updating an existing note */
export type UpdateNoteInput = Partial<
  Pick<Note, "title" | "tags">
>;
