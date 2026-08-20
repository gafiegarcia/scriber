@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os
#if SWIFT_PACKAGE
import ScriberCore
#endif

enum AudioRecorderError: LocalizedError {
    case microphoneDenied
    case inputUnavailable(String)
    case couldNotStart
    case notRecording
    case didNotFinish

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
        case .didNotFinish:
            "The microphone recording did not finish."
        }
    }
}

enum MicrophonePermissionState: String, Equatable {
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

    static func recoverableAudioFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: pendingAudioDirectory(),
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.localizedCaseInsensitiveCompare("m4a") == .orderedSame }
    }

    static func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url),
              file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private static func pendingAudioDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Scriber/PendingAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class CaptureBackend: NSObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.gafiegarcia.scriber.audio-capture")

    /// Closes capture sessions away from `queue`, in the order they were retired.
    private static let teardownQueue = DispatchQueue(label: "com.gafiegarcia.scriber.audio-teardown")
    private var session: AVCaptureSession?
    private var dataOutput: AVCaptureAudioDataOutput?
    private var fileOutput: AVCaptureAudioFileOutput?
    /// How long to wait for AVFoundation to report a file output finishing before
    /// giving up on it. A stop that is never reported would otherwise leave the
    /// recording on the books for the rest of the session, and every later start
    /// would be refused. Generous, because a real finish only finalizes a file.
    private static let finishReportTimeout: DispatchTimeInterval = .seconds(5)

    /// The ordering rules, which carry their own tests. This class owns only what
    /// needs AVFoundation to answer.
    private var lifecycle = RecorderLifecycle()
    private var recordingURL: URL?
    private var startedAt: Date?
    /// The only capture state read from off `queue`: the meter polls it ten times
    /// a second, and a `queue.sync` for it would queue behind a session opening.
    /// `maximumPeakLevel` stays queue-owned because nothing outside reads it.
    private let currentLevel = OSAllocatedUnfairLock(initialState: Float(-160))
    private var maximumPeakLevel: Float = -160
    /// When the microphone last sent anything at all, so a stream that goes silent
    /// mid-recording can be told from a recording that simply ends quietly.
    private var stopContinuation: CheckedContinuation<CompletedRecording, Error>?

    func startRecording(id: UUID, directory: URL, selection: AudioInputSelection) throws {
        try queue.sync {
            // Reads `recordingURL` and `stopContinuation` while they still describe
            // the superseded recording, which the assignments below then replace.
            if case .supersedeThenStart = lifecycle.start(id) { abandonSupersededRecording() }
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

            recordingURL = url
            startedAt = .now
            currentLevel.withLock { $0 = -160 }
            maximumPeakLevel = -160
            session = capture.session
            dataOutput = capture.dataOutput
            fileOutput = output

            capture.session.startRunning()
            output.startRecording(to: url, outputFileType: .m4a, recordingDelegate: self)
        }
    }

    func startMonitoring(selection: AudioInputSelection) throws {
        try queue.sync {
            guard lifecycle.activeRecording == nil else { return }
            tearDownSession()
            let capture = try makeSession(selection: selection, fileOutput: nil)
            currentLevel.withLock { $0 = -160 }
            maximumPeakLevel = -160
            session = capture.session
            dataOutput = capture.dataOutput
            capture.session.startRunning()
        }
    }

    func stopMonitoring() {
        queue.sync {
            guard lifecycle.activeRecording == nil else { return }
            tearDownSession()
        }
    }

    func latestLevel() -> Float {
        currentLevel.withLock { $0 }
    }

    func stopRecording() async throws -> CompletedRecording {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let fileOutput = self.fileOutput, self.stopContinuation == nil,
                      case .stop(let id) = self.lifecycle.stop() else {
                    continuation.resume(throwing: AudioRecorderError.notRecording)
                    return
                }
                self.stopContinuation = continuation
                fileOutput.stopRecording()
                self.scheduleFinishWatchdog(for: id)
            }
        }
    }

    func cancelRecording() {
        queue.async {
            switch self.lifecycle.cancel() {
            case .stop(let id):
                guard let fileOutput = self.fileOutput else {
                    // On the books with no output left to stop, which nothing else
                    // would clear.
                    self.abandonSupersededRecording()
                    self.lifecycle = RecorderLifecycle()
                    self.tearDownSession()
                    return
                }
                fileOutput.stopRecording()
                self.scheduleFinishWatchdog(for: id)
            case .nothingToStop:
                // A stop already in flight resolves this recording, and its own
                // watchdog covers it. With nothing recording, only a monitoring
                // session can be left over.
                if self.lifecycle.activeRecording == nil { self.tearDownSession() }
            }
        }
    }

    /// Drops the recording the lifecycle has already moved past, so the capture
    /// stack keeps no trace of it.
    private func abandonSupersededRecording() {
        let url = recordingURL
        let continuation = stopContinuation
        recordingURL = nil
        startedAt = nil
        stopContinuation = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        continuation?.resume(throwing: CancellationError())
    }

    /// A file output that never began writing can finish without AVFoundation ever
    /// calling the delegate, and a session that fails at runtime never gets there at
    /// all. Either way the stop is never reported, so nothing would clear the
    /// recording and every later start would be refused for the rest of the session.
    private func scheduleFinishWatchdog(for id: UUID) {
        queue.asyncAfter(deadline: .now() + Self.finishReportTimeout) { [weak self] in
            guard let self, case .discard = lifecycle.timedOut(id) else { return }
            let continuation = stopContinuation
            // The file stays for the orphan sweep to judge; it is the only copy of
            // whatever was captured, and this path cannot tell whether it is usable.
            recordingURL = nil
            startedAt = nil
            stopContinuation = nil
            tearDownSession()
            continuation?.resume(throwing: AudioRecorderError.didNotFinish)
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
        let closing = session
        session = nil
        dataOutput = nil
        fileOutput = nil
        currentLevel.withLock { $0 = -160 }
        guard let closing, closing.isRunning else { return }
        // `stopRunning` asks the main thread to acknowledge the capture graph
        // stopping and waits for the answer. Called here it would hold this queue
        // while the main thread is blocked waiting for this same queue — the app
        // freezes with the pill mid-flight. Nothing below reads the session again,
        // so it can close on its own time.
        Self.teardownQueue.async { closing.stopRunning() }
    }

    private func finishRecording(url: URL, error: Error?) {
        // A superseded recording still reports itself finishing, and its file is the
        // only thing that identifies it. Resolving on that report would clear the
        // bookkeeping of whichever recording is running now, leaving the recorder
        // sure it is idle with the microphone open.
        guard recordingURL == url, let current = lifecycle.activeRecording else { return }
        let outcome = lifecycle.finished(current)
        let startedAt = startedAt
        let duration = max(fileOutput?.recordedDuration.seconds ?? 0, startedAt.map { Date.now.timeIntervalSince($0) } ?? 0)
        let peak = maximumPeakLevel
        let continuation = stopContinuation

        recordingURL = nil
        self.startedAt = nil
        stopContinuation = nil
        tearDownSession()

        if case .discard = outcome {
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

        guard case .deliver(let id) = outcome, startedAt != nil else {
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
        currentLevel.withLock { $0 = channels.map(\.averagePowerLevel).max() ?? -160 }
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
