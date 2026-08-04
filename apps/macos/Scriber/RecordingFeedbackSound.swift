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
        cancellationOrCopyFallbackSound = NSSound(named: NSSound.Name("Morse"))
        startSound?.volume = volume
        cancellationOrCopyFallbackSound?.volume = volume
    }

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
