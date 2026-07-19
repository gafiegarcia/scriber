"use client";

import {
  useState,
  useRef,
  useEffect,
  useCallback,
  useImperativeHandle,
  forwardRef,
} from "react";
import { Play, Pause } from "lucide-react";
import { getAudio } from "@/lib/audio-client";

function formatTime(seconds: number): string {
  if (!isFinite(seconds) || isNaN(seconds)) return "-:--";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export interface AudioPlayerHandle {
  seek: (time: number) => void;
  getCurrentTime: () => number;
  getIsPlaying: () => boolean;
  togglePlayPause: () => void;
}

interface AudioPlayerProps {
  noteId: string;
  /** Called when audio is loaded (true) or not available (false) */
  onAudioAvailable?: (available: boolean) => void;
  /** Called when play state changes */
  onPlayStateChange?: (playing: boolean) => void;
}

export const AudioPlayer = forwardRef<AudioPlayerHandle, AudioPlayerProps>(
  function AudioPlayer({ noteId, onAudioAvailable, onPlayStateChange }, ref) {
    const audioRef = useRef<HTMLAudioElement>(null);
    const objectUrlRef = useRef<string | null>(null);

    const [audioSrc, setAudioSrc] = useState<string | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const [isPlaying, setIsPlaying] = useState(false);
    const [currentTime, setCurrentTime] = useState(0);
    const [duration, setDuration] = useState(0);
    const durationResolved = useRef(false);

    // Expose seek + getCurrentTime to parent via ref
    useImperativeHandle(ref, () => ({
      seek(time: number) {
        const audio = audioRef.current;
        if (!audio) return;
        audio.currentTime = time;
        setCurrentTime(time);
        if (!isPlaying) audio.play();
      },
      getCurrentTime() {
        return audioRef.current?.currentTime ?? 0;
      },
      getIsPlaying() {
        return !(audioRef.current?.paused ?? true);
      },
      togglePlayPause() {
        const audio = audioRef.current;
        if (!audio) return;
        if (audio.paused) {
          audio.play();
        } else {
          audio.pause();
        }
      },
    }), [isPlaying]);

    // Load audio blob from IndexedDB on mount
    useEffect(() => {
      let cancelled = false;

      async function loadAudio() {
        try {
          const blob = await getAudio(noteId);
          if (cancelled) return;

          if (blob) {
            const url = URL.createObjectURL(blob);
            objectUrlRef.current = url;
            setAudioSrc(url);
            onAudioAvailable?.(true);
          } else {
            onAudioAvailable?.(false);
          }
        } catch (err) {
          console.warn("Failed to load audio:", err);
          if (!cancelled) onAudioAvailable?.(false);
        } finally {
          if (!cancelled) setIsLoading(false);
        }
      }

      loadAudio();

      return () => {
        cancelled = true;
        if (objectUrlRef.current) {
          URL.revokeObjectURL(objectUrlRef.current);
          objectUrlRef.current = null;
        }
      };
    }, [noteId, onAudioAvailable]);

    // Workaround: webm/opus blobs often report Infinity duration.
    // Seeking to a very large value forces the browser to resolve the real duration.
    const resolveDuration = useCallback(() => {
      const audio = audioRef.current;
      if (!audio || durationResolved.current) return;

      if (isFinite(audio.duration) && audio.duration > 0) {
        setDuration(audio.duration);
        durationResolved.current = true;
        return;
      }

      // Force browser to discover the real duration
      audio.currentTime = 1e10;
      const onSeeked = () => {
        if (audio && isFinite(audio.duration)) {
          setDuration(audio.duration);
          durationResolved.current = true;
        }
        audio.currentTime = 0;
        audio.removeEventListener("seeked", onSeeked);
      };
      audio.addEventListener("seeked", onSeeked);
    }, []);

    const handlePlayPause = useCallback(() => {
      const audio = audioRef.current;
      if (!audio) return;

      if (isPlaying) {
        audio.pause();
      } else {
        audio.play();
      }
    }, [isPlaying]);

    const handleSeek = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
      const audio = audioRef.current;
      if (!audio) return;
      const time = parseFloat(e.target.value);
      audio.currentTime = time;
      setCurrentTime(time);
    }, []);

    // Don't render anything if loading or no audio available
    if (isLoading) return null;
    if (!audioSrc) return null;

    return (
      <div className="mx-5 mt-3 flex items-center gap-3 rounded-xl bg-muted/50 px-4 py-3">
        {/* Hidden audio element */}
        <audio
          ref={audioRef}
          src={audioSrc}
          preload="metadata"
          onLoadedMetadata={resolveDuration}
          onDurationChange={() => {
            if (audioRef.current && isFinite(audioRef.current.duration)) {
              setDuration(audioRef.current.duration);
            }
          }}
          onTimeUpdate={() => {
            if (audioRef.current) {
              setCurrentTime(audioRef.current.currentTime);
            }
          }}
          onPlay={() => { setIsPlaying(true); onPlayStateChange?.(true); }}
          onPause={() => { setIsPlaying(false); onPlayStateChange?.(false); }}
          onEnded={() => {
            setIsPlaying(false);
            setCurrentTime(0);
            onPlayStateChange?.(false);
          }}
          className="hidden"
        />

        {/* Play/Pause button */}
        <button
          onClick={handlePlayPause}
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-foreground text-background transition-all hover:brightness-110 active:scale-95"
          aria-label={isPlaying ? "Pause" : "Play"}
        >
          {isPlaying ? (
            <Pause className="h-4 w-4" fill="currentColor" />
          ) : (
            <Play className="h-4 w-4 ml-0.5" fill="currentColor" />
          )}
        </button>

        {/* Seek bar */}
        <input
          type="range"
          min={0}
          max={duration || 0}
          step={0.1}
          value={currentTime}
          onChange={handleSeek}
          className="h-1.5 flex-1 cursor-pointer appearance-none rounded-full bg-foreground/15 accent-foreground [&::-webkit-slider-thumb]:h-3.5 [&::-webkit-slider-thumb]:w-3.5 [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:bg-foreground"
          aria-label="Seek audio"
        />

        {/* Time display */}
        <span className="shrink-0 font-mono text-xs tabular-nums text-muted-foreground">
          {formatTime(currentTime)} / {formatTime(duration)}
        </span>
      </div>
    );
  }
);
