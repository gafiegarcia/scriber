"use client";

import { FileUpload } from "@/components/file-upload";
import { VoiceRecorder } from "@/components/voice-recorder";
import { TranscribeOptions } from "@/components/transcribe-options";
import { TranscribeHero } from "@/components/transcribe-hero";

export default function HomePage() {
  return (
    <>
      {/* Mobile layout */}
      <div className="flex min-h-full flex-col items-center justify-center gap-6 px-5 py-6 lg:hidden">
        <p className="max-w-[300px] text-center text-base leading-relaxed text-muted-foreground">
          Record or upload audio to create notes instantly
        </p>

        <div className="flex items-end gap-8">
          <div className="flex flex-col items-center gap-2.5">
            <FileUpload />
            <span className="text-sm font-medium text-muted-foreground/70">
              Upload
            </span>
          </div>

          <div className="flex flex-col items-center gap-3">
            <VoiceRecorder />
            <span className="text-sm font-medium text-muted-foreground/70">
              Record
            </span>
          </div>
        </div>

        <TranscribeOptions />
      </div>

      {/* Desktop layout */}
      <div className="hidden min-h-full flex-col items-center justify-center gap-10 px-8 py-10 lg:flex lg:overflow-y-auto">
        <TranscribeHero />
      </div>
    </>
  );
}
