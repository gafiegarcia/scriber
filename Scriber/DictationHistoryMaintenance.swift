import Foundation
import SwiftData

@MainActor
final class DictationHistoryMaintenance {
    private let modelContext: ModelContext
    private let servicesAllowed: Bool

    init(modelContext: ModelContext, servicesAllowed: Bool) {
        self.modelContext = modelContext
        self.servicesAllowed = servicesAllowed
    }

    func recoverPersistedAndOrphanedRecords() {
        guard let records = try? modelContext.fetch(FetchDescriptor<DictationRecord>()) else { return }
        for record in records where record.transcriptionState == .transcribing {
            record.transcriptionState = .failed
            record.errorMessage = record.pendingAudioRelativePath == nil
                ? "The app stopped before this dictation completed, and no retryable audio remains."
                : "The app stopped before this dictation completed. Retry when ready."
        }

        // Removing a transcribed recording can fail, leaving the file behind after its
        // record reference was cleared. Such a file must not be reimported: it would
        // upsert over a succeeded dictation and destroy the saved transcript.
        let referencedAudio = Set(records.compactMap(\.pendingAudioRelativePath))
        let knownRecordIDs = Set(records.map(\.id))
        if let files = try? AudioRecorder.recoverableAudioFiles() {
            for file in files {
                let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) ?? UUID()
                guard OrphanedAudioImportPolicy.shouldImport(
                    recordingID: id,
                    relativePath: file.lastPathComponent,
                    knownRecordIDs: knownRecordIDs,
                    referencedAudioPaths: referencedAudio
                ) else { continue }
                modelContext.insert(DictationRecord(
                    id: id,
                    createdAt: values?.creationDate ?? values?.contentModificationDate ?? .now,
                    durationSeconds: AudioRecorder.duration(of: file),
                    transcriptionState: .failed,
                    errorMessage: "Recovered after Scriber could not save this recording. Retry when ready.",
                    pendingAudioRelativePath: file.lastPathComponent
                ))
            }
        }
        try? modelContext.save()
    }

    /// Removes retained dictation audio older than the retention period.
    ///
    /// Only the recording goes. The history row, its transcript, and why it failed
    /// are preserved, so the user keeps the record of what happened and loses only
    /// the ability to retry a month-old dictation.
    func expireRetainedAudio(ifEnabled isEnabled: Bool) {
        // Never from a test build. `PendingAudio` is a single real directory that
        // `--ui-testing` does not isolate, while the history store under it *is*
        // in-memory — so the orphan sweep below sees every one of Gaf's genuinely
        // retained recordings as referenced by nothing and deletes the expired
        // ones. The launch call site is already gated; the retention-preference
        // sink is not, so this guard must cover every entry point.
        //
        // `servicesAllowed` is true in Release, so shipped behaviour is unchanged.
        guard servicesAllowed, isEnabled,
              let records = try? modelContext.fetch(FetchDescriptor<DictationRecord>()) else { return }

        var didExpireRecord = false
        for record in records {
            guard let relativePath = record.pendingAudioRelativePath,
                  RetainedAudioRetentionPolicy.hasExpired(createdAt: record.createdAt) else { continue }
            AudioRecorder.delete(relativePath: relativePath)
            record.pendingAudioRelativePath = nil
            record.errorMessage = RetainedAudioRetentionPolicy.expiredMessage(
                appendingTo: record.errorMessage
            )
            didExpireRecord = true
        }
        if didExpireRecord { try? modelContext.save() }

        // Anything left that no dictation references is stale by construction,
        // including the files orphan recovery deliberately refuses to reimport.
        let referencedAudio = Set(records.compactMap(\.pendingAudioRelativePath))
        guard let files = try? AudioRecorder.recoverableAudioFiles() else { return }
        for file in files where !referencedAudio.contains(file.lastPathComponent) {
            let createdAt = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            guard RetainedAudioRetentionPolicy.hasExpired(createdAt: createdAt ?? .distantPast) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
