/** ElevenLabs Scribe v2 transcription response */
export interface ScribeResponse {
  language_code: string;
  language_probability: number;
  text: string;
  words: ScribeWord[];
  additional_formats?: ScribeAdditionalFormat[];
}

export interface ScribeWord {
  text: string;
  start: number;
  end: number;
  type: "word" | "punctuation" | "spacing" | "audio_event";
  speaker_id?: string;
  logprob?: number;
}

export interface ScribeAdditionalFormat {
  requested_format: string;
  file_extension: string;
  content_type: string;
  is_base64_encoded: boolean;
  content: string;
}
