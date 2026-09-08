import AppKit

enum DictationFeedbackCue: Equatable, Sendable {
    case dictationStarted
    /// Every ending that is not a transcript arriving where it was asked for:
    /// a recording or transcription that failed, a cancellation, no signal, no
    /// words, a paste that fell back to the clipboard.
    case dictationDidNotLand
}

@MainActor
protocol DictationFeedbackSoundPlaying: AnyObject {
    func play(_ cue: DictationFeedbackCue)
    func fadeOut()
    func stop()
}

@MainActor
final class DictationFeedbackSoundPlayer: DictationFeedbackSoundPlaying {
    private let startSound: NSSound?
    private let volume: Float
    private var fade: Task<Void, Never>?

    init(volume: Float = 0.55) {
        self.volume = volume
        startSound = NSSound(named: NSSound.Name("Frog"))
        startSound?.volume = volume
    }

    // Known and unfixed: on a built-in speaker that has idled a few seconds the cue
    // can pop. It is the amplifier powering back up under the sound — a system-wide
    // macOS behaviour any app triggers, not Scriber's doing. Scheduling playback a
    // warm-up ahead of the amplifier hides it, and fading a cue out avoids the click of
    // cutting one that is still playing — but the warm-up adds lag to a cue that fires
    // on every dictation, a worse trade than the rare pop, so cues play immediately and
    // take both hits.
    func play(_ cue: DictationFeedbackCue) {
        stop()
        switch cue {
        case .dictationStarted:
            _ = startSound?.play()
        case .dictationDidNotLand:
            // The user's own system alert sound, at their alert volume. The new-style
            // alert sounds (Boop, Pong, …) live outside /System/Library/Sounds and are
            // not loadable by name, so leave it to AppKit to play the current choice.
            //
            // Do not: name a sound here instead. A hard-coded Tink was the second cue
            // until it was retired, and it read as correct only because Tink is the
            // macOS default: anyone who had chosen a different alert sound got Scriber's
            // Tink anyway, and choosing a different alert sound is often choosing away
            // from that one. Naming any sound overrides an answer the user has given.
            NSSound.beep()
        }
    }

    /// Retires a cue that is still playing without the click of cutting it dead.
    /// A press too short to be a dictation ends while the start cue is still in its
    /// attack, and stopping there is the loudest thing Scriber can do.
    ///
    /// Only the start cue can be caught mid-flight. `NSSound.beep()` hands the alert
    /// to AppKit and keeps nothing to fade, which costs nothing: no ending cue has a
    /// later event to be cut off by.
    func fadeOut() {
        guard let startSound, startSound.isPlaying else { return }
        fade?.cancel()
        fade = Task { @MainActor [weak self] in
            let steps = 8
            for step in stride(from: steps - 1, through: 0, by: -1) {
                guard !Task.isCancelled, let self else { return }
                startSound.volume = volume * Float(step) / Float(steps)
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard !Task.isCancelled, let self else { return }
            startSound.stop()
            startSound.volume = volume
        }
    }

    func stop() {
        fade?.cancel()
        fade = nil
        startSound?.stop()
        startSound?.volume = volume
    }
}
