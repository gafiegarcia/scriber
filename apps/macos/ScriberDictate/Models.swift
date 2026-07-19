import Foundation
import SwiftData

enum TranscriptionState: String, Codable, CaseIterable, Sendable {
    case transcribing
    case succeeded
    case failed
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
