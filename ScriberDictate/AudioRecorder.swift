@preconcurrency import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case microphoneDenied
    case couldNotStart
    case notRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is required."
        case .couldNotStart: "The microphone recording could not start."
        case .notRecording: "No recording is active."
        }
    }
}

struct CompletedRecording: Sendable {
    let id: UUID
    let url: URL
    let relativePath: String
    let duration: TimeInterval
}

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var currentID: UUID?
    private(set) var currentLevel: Float = -80

    static var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start(id: UUID = UUID()) throws {
        guard Self.microphoneAuthorized else { throw AudioRecorderError.microphoneDenied }
        let directory = try Self.pendingAudioDirectory()
        let url = directory.appendingPathComponent("\(id.uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record() else { throw AudioRecorderError.couldNotStart }
        self.recorder = recorder
        startedAt = .now
        currentID = id
    }

    func updateMeter() -> Float {
        guard let recorder else { return -80 }
        recorder.updateMeters()
        currentLevel = recorder.averagePower(forChannel: 0)
        return currentLevel
    }

    func stop() throws -> CompletedRecording {
        guard let recorder, let id = currentID, let startedAt else { throw AudioRecorderError.notRecording }
        let duration = max(recorder.currentTime, Date.now.timeIntervalSince(startedAt))
        recorder.stop()
        self.recorder = nil
        self.startedAt = nil
        self.currentID = nil
        return CompletedRecording(
            id: id,
            url: recorder.url,
            relativePath: recorder.url.lastPathComponent,
            duration: duration
        )
    }

    func cancel() {
        let url = recorder?.url
        recorder?.stop()
        recorder = nil
        startedAt = nil
        currentID = nil
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    static func url(for relativePath: String) throws -> URL {
        try pendingAudioDirectory().appendingPathComponent(relativePath)
    }

    static func delete(relativePath: String) {
        guard let url = try? url(for: relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func pendingAudioDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Scriber Dictate/PendingAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
