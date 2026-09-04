#if DEBUG
import Foundation
import SwiftData

/// Around 1,900 synthetic Dictation records for `--ui-testing-seed-history-large`.
///
/// For measuring history-list scrolling, which needs far more than the 23 rows
/// `UITestingHistoryFixture` curates for interface checks. No existing check uses
/// it — `AUTOMATED_CHECKS.md`'s "22 dictations" assertion belongs to the other
/// fixture and must keep passing unchanged.
///
/// These records carry no retained audio: `pendingAudioRelativePath` stays nil, so
/// `AppCoordinator.delete` skips file removal and `expireRetainedAudio` skips the
/// record, and neither can reach one of Gaf's real recordings.
@MainActor
enum UITestingLargeHistoryFixture {
    /// Shaped from the real store on 2026-09-04: 1,923 records over 45 days, with
    /// one day holding 290 of them.
    ///
    /// Keep the heavy day. Grouping walks the records in order and a single day is
    /// one unbroken run, so the longest day is what the grouping pass and the
    /// section's own layout are worst at — an evenly spread fixture never tests
    /// either.
    private static let dayCount = 45
    private static let heaviestDayRecords = 290
    private static let ordinaryDayRecords = 37

    static func seed(into context: ModelContext) {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        var index = 0

        for dayOffset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let recordsPerDay = dayOffset == 0 ? heaviestDayRecords : ordinaryDayRecords
            for slot in 0..<recordsPerDay {
                index += 1
                let hour = 23 - (slot * 24 / recordsPerDay)
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
            text: text(index: index),
            detectedLanguageCode: "en",
            transcriptionState: .succeeded,
            deliveryState: .pasted
        )
    }

    /// Row heights have to vary the way real ones do, or a list measured against
    /// this fixture answers an easier question than the real history asks. The
    /// mix follows the real store's length distribution for dictations over ten
    /// seconds: about a quarter one line, a third two, and the rest three or
    /// four, with a few long enough to be truncated.
    private static func text(index: Int) -> String {
        let sentence = "Synthetic scroll-performance entry number \(index), long enough to occupy "
            + "a line or two the way a real dictation would. "
        return switch index % 12 {
        case 0, 1, 2: "Short entry number \(index)."
        case 3, 4, 5, 6: sentence
        case 7, 8, 9, 10: String(repeating: sentence, count: 2)
        default: String(repeating: sentence, count: 4)
        }
    }

    /// Deterministic and namespaced away from `UITestingHistoryFixture`'s ids,
    /// which use the `D1C7A7E0` prefix.
    private nonisolated static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "5CA1AB1E-0000-4000-8000-%012X", index))!
    }
}
#endif
