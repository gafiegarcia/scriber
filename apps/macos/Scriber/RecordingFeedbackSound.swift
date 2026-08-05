import AppKit

enum RecordingFeedbackCue: Equatable, Sendable {
    case recordingStarted
    case terminalFailure
    case cancellationOrCopyFallback
}

@MainActor
protocol RecordingFeedbackSoundPlaying: AnyObject {
    func play(_ cue: RecordingFeedbackCue)
    func stop()
}

@MainActor
final class RecordingFeedbackSoundPlayer: RecordingFeedbackSoundPlaying {
    private let startSound: NSSound?
    private let cancellationOrCopyFallbackSound: NSSound?

    init(volume: Float = 0.55) {
        startSound = NSSound(named: NSSound.Name("Blow"))
        cancellationOrCopyFallbackSound = NSSound(named: NSSound.Name("Tink"))
        startSound?.volume = volume
        cancellationOrCopyFallbackSound?.volume = volume
    }

    // Known and unfixed: on a built-in speaker that has idled a few seconds the cue
    // can pop. It is the amplifier powering back up under the sound — a system-wide
    // macOS behaviour any app triggers, not Scriber's doing. Scheduling playback a
    // warm-up ahead of the amplifier hides it, and fading a cue out avoids the click of
    // cutting one that is still playing — but the warm-up adds lag to a cue that fires
    // on every dictation, a worse trade than the rare pop, so cues play immediately and
    // take both hits.
    func play(_ cue: RecordingFeedbackCue) {
        stop()
        switch cue {
        case .recordingStarted:
            _ = startSound?.play()
        case .terminalFailure:
            // The user's own system alert sound, at their alert volume. The new-style
            // alert sounds (Boop, Pong, …) live outside /System/Library/Sounds and are
            // not loadable by name, so leave it to AppKit to play the current choice.
            NSSound.beep()
        case .cancellationOrCopyFallback:
            _ = cancellationOrCopyFallbackSound?.play()
        }
    }

    func stop() {
        startSound?.stop()
        cancellationOrCopyFallbackSound?.stop()
    }
}
