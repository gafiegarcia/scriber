import type { ScribeResponse } from "@/lib/types/elevenlabs";

export interface JsonOutputPayload {
  text: string;
  language_code: string;
  language_probability: number;
  words: ScribeResponse["words"];
  additional_formats?: ScribeResponse["additional_formats"];
  id: string;
  noteId: string | null;
  outputs: string[];
  createdAt: string;
}

export function renderJson(payload: JsonOutputPayload): string {
  return JSON.stringify(payload, null, 2) + "\n";
}
