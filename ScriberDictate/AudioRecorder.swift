@preconcurrency import AVFoundation
import CoreAudio
import Foundation
#if SWIFT_PACKAGE
import ScriberDictateCore
#endif

enum AudioRecorderError: LocalizedError {
    case microphoneDenied
    case inputUnavailable(String)
    case couldNotStart
    case notRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required."
        case .inputUnavailable(let name):
            "The selected microphone “\(name)” is unavailable."
        case .couldNotStart:
            "The microphone recording could not start."
        case .notRecording:
            "No recording is active."
        }
    }
}

enum MicrophonePermissionState: Equatable {
    case notDetermined
    case allowed
    case denied
}

struct CompletedRecording: Sendable {
    let id: UUID
    let url: URL
    let relativePath: String
    let duration: TimeInterval
    let maximumPeakLevel: Float

    var detectedSignal: Bool {
        AudioSignal.isDetected(decibels: maximumPeakLevel)
    }
}

@MainActor
final class AudioRecorder {
    private let backend = CaptureBackend()

    static var microphoneAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var microphoneAuthorized: Bool {
        microphoneAuthorizationStatus == .authorized
    }

    static var microphonePermissionState: MicrophonePermissionState {
        switch microphoneAuthorizationStatus {
        case .authorized:
            .allowed
        case .notDetermined:
            .notDetermined
        default:
            .denied
        }
    }

    static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func availableInputDevices() -> [AudioInputDeviceDescriptor] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
            .map { device in
                AudioInputDeviceDescriptor(
                    id: device.uniqueID,
                    name: device.localizedName,
                    isBuiltIn: UInt32(bitPattern: device.transportType) == kAudioDeviceTransportTypeBuiltIn
                )
            }
            .sorted { lhs, rhs in
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func start(id: UUID = UUID(), selection: AudioInputSelection) throws {
        guard Self.microphoneAuthorized else { throw AudioRecorderError.microphoneDenied }
        let directory = try Self.pendingAudioDirectory()
        try backend.startRecording(id: id, directory: directory, selection: selection)
    }

    func startMonitoring(selection: AudioInputSelection) throws {
        guard Self.microphoneAuthorized else { throw AudioRecorderError.microphoneDenied }
        try backend.startMonitoring(selection: selection)
    }

    func stopMonitoring() {
        backend.stopMonitoring()
    }

    func updateMeter() -> Float {
        backend.latestLevel()
    }

    func stop() async throws -> CompletedRecording {
        try await backend.stopRecording()
    }

    func cancel() {
        backend.cancelRecording()
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

private final class CaptureBackend: NSObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.gafiegarcia.scriber-dictate.audio-capture")
    private var session: AVCaptureSession?
    private var dataOutput: AVCaptureAudioDataOutput?
    private var fileOutput: AVCaptureAudioFileOutput?
    private var recordingID: UUID?
    private var startedAt: Date?
    private var currentLevel: Float = -160
    private var maximumPeakLevel: Float = -160
    private var stopContinuation: CheckedContinuation<CompletedRecording, Error>?
    private var discardRecording = false

    func startRecording(id: UUID, directory: URL, selection: AudioInputSelection) throws {
        try queue.sync {
            guard recordingID == nil else { throw AudioRecorderError.couldNotStart }
            tearDownSession()

            let output = AVCaptureAudioFileOutput()
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let capture = try makeSession(selection: selection, fileOutput: output)
            let url = directory.appendingPathComponent("\(id.uuidString).m4a")

            recordingID = id
            startedAt = .now
            currentLevel = -160
            maximumPeakLevel = -160
            discardRecording = false
            session = capture.session
            dataOutput = capture.dataOutput
            fileOutput = output

            capture.session.startRunning()
            output.startRecording(to: url, outputFileType: .m4a, recordingDelegate: self)
        }
    }

    func startMonitoring(selection: AudioInputSelection) throws {
        try queue.sync {
            guard recordingID == nil else { return }
            tearDownSession()
            let capture = try makeSession(selection: selection, fileOutput: nil)
            currentLevel = -160
            maximumPeakLevel = -160
            session = capture.session
            dataOutput = capture.dataOutput
            capture.session.startRunning()
        }
    }

    func stopMonitoring() {
        queue.sync {
            guard recordingID == nil else { return }
            tearDownSession()
        }
    }

    func latestLevel() -> Float {
        queue.sync { currentLevel }
    }

    func stopRecording() async throws -> CompletedRecording {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let fileOutput = self.fileOutput,
                      self.recordingID != nil,
                      self.stopContinuation == nil else {
                    continuation.resume(throwing: AudioRecorderError.notRecording)
                    return
                }
                self.stopContinuation = continuation
                fileOutput.stopRecording()
            }
        }
    }

    func cancelRecording() {
        queue.async {
            guard let fileOutput = self.fileOutput, self.recordingID != nil else {
                self.tearDownSession()
                return
            }
            self.discardRecording = true
            fileOutput.stopRecording()
        }
    }

    private func makeSession(
        selection: AudioInputSelection,
        fileOutput: AVCaptureAudioFileOutput?
    ) throws -> (session: AVCaptureSession, dataOutput: AVCaptureAudioDataOutput) {
        let device: AVCaptureDevice
        switch selection {
        case .automatic:
            guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
                throw AudioRecorderError.inputUnavailable("System Default")
            }
            device = defaultDevice
        case .device(let id, let name):
            guard let selectedDevice = AVCaptureDevice(uniqueID: id) else {
                throw AudioRecorderError.inputUnavailable(name)
            }
            device = selectedDevice
        }

        let input = try AVCaptureDeviceInput(device: device)
        let dataOutput = AVCaptureAudioDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: queue)
        let session = AVCaptureSession()
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(dataOutput) else {
            session.commitConfiguration()
            throw AudioRecorderError.couldNotStart
        }
        session.addInput(input)
        session.addOutput(dataOutput)
        if let fileOutput {
            guard session.canAddOutput(fileOutput) else {
                session.commitConfiguration()
                throw AudioRecorderError.couldNotStart
            }
            session.addOutput(fileOutput)
        }
        session.commitConfiguration()
        return (session, dataOutput)
    }

    private func tearDownSession() {
        dataOutput?.setSampleBufferDelegate(nil, queue: nil)
        if session?.isRunning == true { session?.stopRunning() }
        session = nil
        dataOutput = nil
        fileOutput = nil
        currentLevel = -160
    }

    private func finishRecording(url: URL, error: Error?) {
        let id = recordingID
        let startedAt = startedAt
        let duration = max(fileOutput?.recordedDuration.seconds ?? 0, startedAt.map { Date.now.timeIntervalSince($0) } ?? 0)
        let peak = maximumPeakLevel
        let continuation = stopContinuation
        let shouldDiscard = discardRecording

        recordingID = nil
        self.startedAt = nil
        stopContinuation = nil
        discardRecording = false
        tearDownSession()

        if shouldDiscard {
            try? FileManager.default.removeItem(at: url)
            continuation?.resume(throwing: CancellationError())
            return
        }

        if let error {
            let recordingSucceeded = (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
            if !recordingSucceeded {
                continuation?.resume(throwing: error)
                return
            }
        }

        guard let id, startedAt != nil else {
            continuation?.resume(throwing: AudioRecorderError.notRecording)
            return
        }
        continuation?.resume(returning: CompletedRecording(
            id: id,
            url: url,
            relativePath: url.lastPathComponent,
            duration: duration,
            maximumPeakLevel: peak
        ))
    }
}

extension CaptureBackend: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let channels = connection.audioChannels
        guard !channels.isEmpty else { return }
        currentLevel = channels.map(\.averagePowerLevel).max() ?? -160
        let peak = channels.map(\.peakHoldLevel).max() ?? -160
        maximumPeakLevel = max(maximumPeakLevel, peak)
    }
}

extension CaptureBackend: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        queue.async {
            self.finishRecording(url: outputFileURL, error: error)
        }
    }
}
