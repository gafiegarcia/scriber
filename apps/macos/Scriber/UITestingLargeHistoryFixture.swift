#if DEBUG
import Foundation
import SwiftData

/// Several hundred synthetic Dictation records for `--ui-testing-seed-history-large`.
///
/// `UITestingHistoryFixture` is hand-curated for interface checks and stays that
/// way; this fixture exists only to make history-list scrolling performance
/// reproducible and measurable, which needs a history far longer than 23 rows.
/// Not used by any existing check — `AUTOMATED_CHECKS.md`'s "22 dictations"
/// assertion depends on the other fixture and must keep passing unchanged.
///
/// Follows the same invariants as `UITestingHistoryFixture`: audio filenames stay
/// namespaced `ui-testing-fixture-*.m4a` so `AppCoordinator.delete` can never
/// touch a real recording, and no entry is older than the 30-day retention
/// window `expireRetainedAudio` enforces.
@MainActor
enum UITestingLargeHistoryFixture {
    private static let dayCount = 29
    private static let recordsPerDay = 14

    static func seed(into context: ModelContext) {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        var index = 0

        for dayOffset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            for slot in 0..<recordsPerDay {
                index += 1
                let hour = 23 - (slot * (24 / recordsPerDay))
                let minute = (index * 7) % 60
                let createdAt = calendar.date(
                    bySettingHour: max(hour, 0),
                    minute: minute,
                    second: 0,
                    of: day
                ) ?? day
                context.insert(record(index: index, createdAt: createdAt))
            }
        }

        try? context.save()
    }

    private static func record(index: Int, createdAt: Date) -> DictationRecord {
        DictationRecord(
            id: id(index),
            createdAt: createdAt,
            durationSeconds: Double(3 + (index % 40)),
            text: "Synthetic scroll-performance entry number \(index), long enough to " +
                "occupy a couple of lines the way a real dictation would.",
            detectedLanguageCode: "en",
            transcriptionState: .succeeded,
            deliveryState: .pasted
        )
    }

    /// Deterministic and namespaced away from `UITestingHistoryFixture`'s ids,
    /// which use the `D1C7A7E0` prefix.
    private nonisolated static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "5CA1AB1E-0000-4000-8000-%012X", index))!
    }
}
#endif
