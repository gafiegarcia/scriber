"use client";

import { useState, useRef, useEffect, useMemo, useCallback, forwardRef, memo } from "react";
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

const SPEAKER_BG_COLORS = [
  "bg-blue-500/20",
  "bg-emerald-500/20",
  "bg-purple-500/20",
  "bg-amber-500/20",
  "bg-rose-500/20",
  "bg-cyan-500/20",
  "bg-orange-500/20",
  "bg-indigo-500/20",
];

interface SpeakerInfo {
  label: string;
  colorClass: string;
  bgClass: string;
}

interface SpeakerSegment {
  speakerId: string;
  info: SpeakerInfo;
  words: TranscriptWord[];
}

function buildSpeakerMap(words: TranscriptWord[]): Map<string, SpeakerInfo> {
  const map = new Map<string, SpeakerInfo>();
  let index = 0;
  for (const word of words) {
    const id = word.speaker_id ?? "unknown";
    if (!map.has(id)) {
      const letter = String.fromCharCode(65 + index);
      map.set(id, {
        label: `Speaker ${letter}`,
        colorClass: SPEAKER_COLORS[index % SPEAKER_COLORS.length],
        bgClass: SPEAKER_BG_COLORS[index % SPEAKER_BG_COLORS.length],
      });
      index++;
    }
  }
  return map;
}

function buildSegments(
  words: TranscriptWord[],
  speakerMap: Map<string, SpeakerInfo>
): SpeakerSegment[] {
  const segments: SpeakerSegment[] = [];
  let currentId = "";
  let currentWords: TranscriptWord[] = [];

  for (const word of words) {
    const id = word.speaker_id ?? "unknown";
    if (id !== currentId && currentWords.length > 0) {
      segments.push({
        speakerId: currentId,
        info: speakerMap.get(currentId)!,
        words: currentWords,
      });
      currentWords = [];
    }
    currentId = id;
    currentWords.push(word);
  }

  if (currentWords.length > 0) {
    segments.push({
      speakerId: currentId,
      info: speakerMap.get(currentId)!,
      words: currentWords,
    });
  }

  return segments;
}

/** Find the index of the word being spoken at `time` using binary search. */
function findActiveWord(words: TranscriptWord[], time: number): number {
  let lo = 0;
  let hi = words.length - 1;
  let result = -1;

  while (lo <= hi) {
    const mid = (lo + hi) >>> 1;
    if (words[mid].start <= time) {
      result = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }

  // No end-time check — keep the word highlighted until the next word starts.
  return result;
}

// ─── Hook: poll audio time at 60fps, only re-render on word change ───────────

function useActiveWordIndex(
  words: TranscriptWord[],
  getTime: () => number,
  isPlaying: boolean
): number {
  const [activeIndex, setActiveIndex] = useState(-1);
  const lastIndexRef = useRef(-1);

  useEffect(() => {
    if (!isPlaying) return;

    let raf: number;

    function tick() {
      const time = getTime();
      const idx = findActiveWord(words, time);
      if (idx !== lastIndexRef.current) {
        lastIndexRef.current = idx;
        setActiveIndex(idx);
      }
      raf = requestAnimationFrame(tick);
    }

    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [words, getTime, isPlaying]);

  // When not playing, do a single check (e.g. after seek while paused).
  // Reading from the audio element (an external system) is the trigger for this state update.
  useEffect(() => {
    if (isPlaying) return;
    const time = getTime();
    const idx = findActiveWord(words, time);
    if (idx !== lastIndexRef.current) {
      lastIndexRef.current = idx;
      setActiveIndex(idx);
    }
  }, [words, getTime, isPlaying]);

  return activeIndex;
}

// ─── Word span ───────────────────────────────────────────────────────────────

interface WordSpanProps {
  word: TranscriptWord;
  isActive: boolean;
  onClick?: (time: number) => void;
  activeBg?: string;
}

const WordSpan = memo(forwardRef<HTMLSpanElement, WordSpanProps>(
  function WordSpan({ word, isActive, onClick, activeBg }, ref) {
    // Punctuation and spacing don't need to be interactive. Audio events have
    // real spans and should seek/highlight like spoken words.
    if (word.type !== "word" && word.type !== "audio_event") {
      return <span>{word.text}</span>;
    }

    return (
      <span
        ref={ref}
        onClick={() => onClick?.(word.start)}
        className={`cursor-pointer rounded-sm ${
          word.type === "audio_event" ? "italic text-muted-foreground " : ""
        }${
          isActive
            ? activeBg ?? "bg-yellow-300/60 dark:bg-yellow-500/30 text-foreground"
            : "hover:bg-foreground/5"
        }`}
      >
        {word.text}
      </span>
    );
  }
));

// ─── Main component ──────────────────────────────────────────────────────────

interface SyncedTranscriptProps {
  words: TranscriptWord[];
  /** Returns current playback time — called at 60fps during playback */
  getTime: () => number;
  /** Whether audio is currently playing */
  isPlaying: boolean;
  hasDiarization: boolean;
  onWordClick?: (time: number) => void;
}

export function SyncedTranscript({
  words,
  getTime,
  isPlaying,
  hasDiarization,
  onWordClick,
}: SyncedTranscriptProps) {
  const activeRef = useRef<HTMLSpanElement>(null);
  const lastScrolledIndex = useRef(-1);

  const activeIndex = useActiveWordIndex(words, getTime, isPlaying);

  // Auto-scroll to keep active word visible
  useEffect(() => {
    if (activeIndex < 0 || activeIndex === lastScrolledIndex.current) return;
    lastScrolledIndex.current = activeIndex;

    activeRef.current?.scrollIntoView({
      behavior: "smooth",
      block: "nearest",
    });
  }, [activeIndex]);

  const handleClick = useCallback(
    (start: number) => {
      onWordClick?.(start);
    },
    [onWordClick]
  );

  // Diarized view
  if (hasDiarization && words.some((w) => w.speaker_id)) {
    return (
      <DiarizedSyncView
        words={words}
        activeIndex={activeIndex}
        activeRef={activeRef}
        onWordClick={handleClick}
      />
    );
  }

  // Non-diarized view
  return (
    <div className="text-base leading-[1.8] text-foreground/90">
      {words.map((word, i) => (
        <WordSpan
          key={i}
          word={word}
          isActive={i === activeIndex}
          ref={i === activeIndex ? activeRef : undefined}
          onClick={handleClick}
        />
      ))}
    </div>
  );
}

// ─── Diarized sync view ──────────────────────────────────────────────────────

function DiarizedSyncView({
  words,
  activeIndex,
  activeRef,
  onWordClick,
}: {
  words: TranscriptWord[];
  activeIndex: number;
  activeRef: React.RefObject<HTMLSpanElement | null>;
  onWordClick: (time: number) => void;
}) {
  const speakerMap = useMemo(() => buildSpeakerMap(words), [words]);
  const segments = useMemo(
    () => buildSegments(words, speakerMap),
    [words, speakerMap]
  );

  const segmentOffsets = useMemo(() => {
    const offsets: number[] = [];
    let acc = 0;
    for (const s of segments) {
      offsets.push(acc);
      acc += s.words.length;
    }
    return offsets;
  }, [segments]);

  return (
    <div className="space-y-3">
      {segments.map((segment, segIdx) => {
        const segmentStart = segmentOffsets[segIdx];

        return (
          <div key={segIdx}>
            <span className={`text-sm font-semibold ${segment.info.colorClass}`}>
              {segment.info.label}
            </span>
            <p className="mt-0.5 text-base leading-[1.8] text-foreground/90">
              {segment.words.map((word, wi) => {
                const globalIdx = segmentStart + wi;
                return (
                  <WordSpan
                    key={wi}
                    word={word}
                    isActive={globalIdx === activeIndex}
                    ref={globalIdx === activeIndex ? activeRef : undefined}
                    onClick={onWordClick}
                    activeBg={`${segment.info.bgClass} text-foreground`}
                  />
                );
              })}
            </p>
          </div>
        );
      })}
    </div>
  );
}
