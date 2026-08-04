import AVFAudio
import Foundation

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
    /// The built-in speaker's amplifier powers down a few seconds after the last sound
    /// and can pop on the way back up. Preparing the player starts the output device at
    /// once while the cue itself is scheduled this far ahead, so a cold amplifier settles
    /// during silence instead of during the waveform. The sounds cannot cover this
    /// themselves: none in `/System/Library/Sounds` begins with more than 25ms of silence.
    /// Tune by ear — too short brings the pop back, too long makes the cue feel late.
    private static let deviceWarmUp: TimeInterval = 0.05

    /// Stopping a playing sound outright leaves a step discontinuity that clicks. Short
    /// enough that a cue replacing another still reads as immediate.
    private static let fadeOut: TimeInterval = 0.02

    private let volume: Float
    private let players: [RecordingFeedbackCue: AVAudioPlayer]
    private var playing: AVAudioPlayer?

    init(volume: Float = 0.55) {
        self.volume = volume
        var loaded: [RecordingFeedbackCue: AVAudioPlayer] = [:]
        for (cue, name): (RecordingFeedbackCue, String) in [
            (.recordingStarted, "Blow"),
            (.terminalFailure, "Bottle"),
            (.cancellationOrCopyFallback, "Morse")
        ] {
            let url = URL(filePath: "/System/Library/Sounds/\(name).aiff")
            guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.volume = volume
            loaded[cue] = player
        }
        players = loaded
    }

    func play(_ cue: RecordingFeedbackCue) {
        guard let player = players[cue] else { return }
        if let playing, playing !== player { fadeOutAndStop(playing) }
        player.stop()
        player.volume = volume
        player.currentTime = 0
        player.prepareToPlay()
        player.play(atTime: player.deviceCurrentTime + Self.deviceWarmUp)
        playing = player
    }

    func stop() {
        guard let playing else { return }
        fadeOutAndStop(playing)
        self.playing = nil
    }

    private func fadeOutAndStop(_ player: AVAudioPlayer) {
        guard player.isPlaying else {
            player.stop()
            return
        }
        player.setVolume(0, fadeDuration: Self.fadeOut)
        Task { [volume] in
            try? await Task.sleep(for: .seconds(Self.fadeOut))
            player.stop()
            player.volume = volume
        }
    }
}
