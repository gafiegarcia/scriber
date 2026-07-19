"use client";

import { useMemo } from "react";
import type { TranscriptWord } from "@/lib/types";

const SPEAKER_COLORS = [
  "text-blue-600 dark:text-blue-400",
  "text-emerald-600 dark:text-emerald-400",
  "text-purple-600 dark:text-purple-400",
  "text-amber-600 dark:text-amber-400",
  "text-rose-600 dark:text-rose-400",
  "text-cyan-600 dark:text-cyan-400",
  "text-orange-600 dark:text-orange-400",
  "text-indigo-600 dark:text-indigo-400",
];

interface SpeakerSegment {
  speakerId: string;
  label: string;
  colorClass: string;
  text: string;
}

function buildSegments(words: TranscriptWord[]): SpeakerSegment[] {
  const speakerMap = new Map<string, { label: string; colorClass: string }>();
  let speakerIndex = 0;

  function getSpeaker(id: string) {
    let info = speakerMap.get(id);
    if (!info) {
      const letter = String.fromCharCode(65 + speakerIndex); // A, B, C...
      info = {
        label: `Speaker ${letter}`,
        colorClass: SPEAKER_COLORS[speakerIndex % SPEAKER_COLORS.length],
      };
      speakerMap.set(id, info);
      speakerIndex++;
    }
    return info;
  }

  const segments: SpeakerSegment[] = [];
  let currentId = "";
  let currentText = "";

  for (const word of words) {
    const id = word.speaker_id ?? "unknown";

    if (id !== currentId && currentText) {
      const info = getSpeaker(currentId);
      segments.push({
        speakerId: currentId,
        label: info.label,
        colorClass: info.colorClass,
        text: currentText.trim(),
      });
      currentText = "";
    }

    currentId = id;
    currentText += word.text;
  }

  // Push last segment
  if (currentText.trim()) {
    const info = getSpeaker(currentId);
    segments.push({
      speakerId: currentId,
      label: info.label,
      colorClass: info.colorClass,
      text: currentText.trim(),
    });
  }

  return segments;
}

export function DiarizedTranscript({ words }: { words: TranscriptWord[] }) {
  const segments = useMemo(() => buildSegments(words), [words]);

  return (
    <div className="space-y-3">
      {segments.map((segment, i) => (
        <div key={i}>
          <span className={`text-sm font-semibold ${segment.colorClass}`}>
            {segment.label}
          </span>
          <p className="mt-0.5 text-base leading-[1.8] text-foreground/90">
            {segment.text}
          </p>
        </div>
      ))}
    </div>
  );
}
