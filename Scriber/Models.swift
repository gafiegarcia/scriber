import Foundation
import SwiftData

enum TranscriptionState: String, Codable, CaseIterable, Sendable {
    case transcribing
    case succeeded
    case failed
    case cancelled
}

enum DeliveryState: String, Codable, CaseIterable, Sendable {
    case notAttempted
    case pasted
    case pasteFailed
    case copied
}

@Model
final class DictationRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var durationSeconds: Double
    var text: String?
    var detectedLanguageCode: String?
    var transcriptionStateRaw: String
    var deliveryStateRaw: String
    var errorMessage: String?
    var pendingAudioRelativePath: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        durationSeconds: Double,
        text: String? = nil,
        detectedLanguageCode: String? = nil,
        transcriptionState: TranscriptionState = .transcribing,
        deliveryState: DeliveryState = .notAttempted,
        errorMessage: String? = nil,
        pendingAudioRelativePath: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.text = text
        self.detectedLanguageCode = detectedLanguageCode
        self.transcriptionStateRaw = transcriptionState.rawValue
        self.deliveryStateRaw = deliveryState.rawValue
        self.errorMessage = errorMessage
        self.pendingAudioRelativePath = pendingAudioRelativePath
    }

    var transcriptionState: TranscriptionState {
        get { TranscriptionState(rawValue: transcriptionStateRaw) ?? .failed }
        set { transcriptionStateRaw = newValue.rawValue }
    }

    var deliveryState: DeliveryState {
        get { DeliveryState(rawValue: deliveryStateRaw) ?? .notAttempted }
        set { deliveryStateRaw = newValue.rawValue }
    }
}

/// Everything about a deleted dictation that undo needs to rebuild it.
///
/// A plain value rather than the model: an undo action outlives the record it
/// describes, and reading a deleted SwiftData model is a trap. The recording is
/// named here but lives on disk, held by `AudioRecorder` for as long as this
/// snapshot can still be used.
struct DeletedDictation: Sendable {
    let id: UUID
    let createdAt: Date
    let durationSeconds: Double
    let text: String?
    let detectedLanguageCode: String?
    let transcriptionState: TranscriptionState
    let deliveryState: DeliveryState
    let errorMessage: String?
    let audioRelativePath: String?

    init(record: DictationRecord) {
        self.id = record.id
        self.createdAt = record.createdAt
        self.durationSeconds = record.durationSeconds
        self.text = record.text
        self.detectedLanguageCode = record.detectedLanguageCode
        self.transcriptionState = record.transcriptionState
        self.deliveryState = record.deliveryState
        self.errorMessage = record.errorMessage
        self.audioRelativePath = record.pendingAudioRelativePath
    }

    /// - Parameter keepingAudio: whether the recording was restored to where a
    ///   record expects it. When it was not, the path is dropped rather than
    ///   carried, so the row comes back without a Retry that could only fail.
    func makeRecord(keepingAudio: Bool) -> DictationRecord {
        DictationRecord(
            id: id,
            createdAt: createdAt,
            durationSeconds: durationSeconds,
            text: text,
            detectedLanguageCode: detectedLanguageCode,
            transcriptionState: transcriptionState,
            deliveryState: deliveryState,
            errorMessage: errorMessage,
            pendingAudioRelativePath: keepingAudio ? audioRelativePath : nil
        )
    }
}
