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
    private let failureSound: NSSound?
    private let cancellationOrCopyFallbackSound: NSSound?

    init(volume: Float = 0.55) {
        startSound = NSSound(named: NSSound.Name("Frog"))
        failureSound = NSSound(named: NSSound.Name("Bottle"))
        cancellationOrCopyFallbackSound = NSSound(named: NSSound.Name("Morse"))
        startSound?.volume = volume
        failureSound?.volume = volume
        cancellationOrCopyFallbackSound?.volume = volume
    }

    func play(_ cue: RecordingFeedbackCue) {
        stop()
        switch cue {
        case .recordingStarted:
            _ = startSound?.play()
        case .terminalFailure:
            _ = failureSound?.play()
        case .cancellationOrCopyFallback:
            _ = cancellationOrCopyFallbackSound?.play()
        }
    }

    func stop() {
        startSound?.stop()
        failureSound?.stop()
        cancellationOrCopyFallbackSound?.stop()
    }
}

@MainActor
final class NoopRecordingFeedbackSoundPlayer: RecordingFeedbackSoundPlaying {
    func play(_ cue: RecordingFeedbackCue) {}
    func stop() {}
}
