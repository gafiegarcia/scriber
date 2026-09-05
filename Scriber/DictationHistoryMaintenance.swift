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
        // A row holding a transcript succeeded, whatever its state says. Nothing
        // writes text to a record except a transcription that finished, and the
        // audio is only released once it has, so this pair cannot describe a
        // dictation that failed or was cancelled. Rows in that shape are left
        // stranded: History offers no Retry, because there is no audio to retry.
        for record in records
        where record.transcriptionState != .succeeded
            && record.pendingAudioRelativePath == nil
            && !(record.text ?? "").isEmpty {
            record.transcriptionState = .succeeded
            record.errorMessage = nil
        }

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

    /// Removes failed and cancelled dictations that have nothing left to offer,
    /// along with any retained audio still behind them. Such a dictation earns its
    /// row by being retryable; once the recording has expired or gone missing and
    /// no transcript ever arrived, the row can only be scrolled past.
    ///
    /// - Returns: the discarded records' ids, so a caller holding one can let go.
    @discardableResult
    func discardExpiredDictations(keptFor retention: RetainedAudioRetention) -> [UUID] {
        // Never from a test build. `PendingAudio` is one real directory that
        // `--ui-testing` does not isolate while the history store under it *is*
        // in-memory, so the sweep below sees every one of Gaf's genuinely retained
        // recordings as referenced by nothing and deletes the expired ones. This
        // guard has to cover every entry point, not just the launch call site.
        guard servicesAllowed, retention != .never,
              let records = try? modelContext.fetch(FetchDescriptor<DictationRecord>()) else { return [] }

        // `nil` when the directory could not be read, which the policy needs to
        // tell apart from a directory that is genuinely empty. One listing serves
        // both passes; a file this sweep deletes below is simply gone by the time
        // the second pass tries again.
        let audioFiles = try? AudioRecorder.recoverableAudioFiles()
        let audioOnDisk = audioFiles.map { Set($0.map(\.lastPathComponent)) }

        var survivors: [DictationRecord] = []
        var discarded: [UUID] = []
        for record in records {
            // Ask about the transcript, never about the state alone. A row holding
            // text is a dictation that succeeded whatever else is stored about it,
            // and a row still transcribing has not reached an outcome — including
            // one the user is retrying right now, from the very window this sweep
            // may have been run by.
            guard record.text?.isEmpty ?? true,
                  record.transcriptionState == .failed || record.transcriptionState == .cancelled
            else {
                survivors.append(record)
                continue
            }
            let disposition = RetainedAudioRetentionPolicy.disposition(
                createdAt: record.createdAt,
                retention: retention,
                retainedAudioPath: record.pendingAudioRelativePath,
                retainedAudioExistsOnDisk: record.pendingAudioRelativePath.flatMap { path in
                    audioOnDisk.map { $0.contains(path) }
                }
            )
            switch disposition {
            case .keep:
                survivors.append(record)
                continue
            case .deleteAudioAndDiscardEntry:
                if let path = record.pendingAudioRelativePath { AudioRecorder.delete(relativePath: path) }
            case .discardEntry:
                break
            }
            discarded.append(record.id)
            modelContext.delete(record)
        }
        if !discarded.isEmpty { try? modelContext.save() }

        // Anything left that no dictation references is stale by construction,
        // including the files orphan recovery deliberately refuses to reimport.
        let referencedAudio = Set(survivors.compactMap(\.pendingAudioRelativePath))
        guard let files = audioFiles else { return discarded }
        for file in files where !referencedAudio.contains(file.lastPathComponent) {
            let createdAt = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            guard RetainedAudioRetentionPolicy.hasExpired(
                createdAt: createdAt ?? .distantPast,
                retention: retention
            ) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
        return discarded
    }
}
