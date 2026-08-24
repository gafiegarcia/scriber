#if DEBUG
import Foundation
import SwiftData

/// Deterministic Dictation history for `--ui-testing-seed-history`.
///
/// Four invariants, each a way to get this wrong that the call site does not show:
///
/// 1. **Audio filenames stay namespaced `ui-testing-fixture-*.m4a`.**
///    `pendingAudioRelativePath` is a real path, `PendingAudio` is one directory
///    that `--ui-testing` does **not** isolate, and `AppCoordinator.delete` calls
///    `AudioRecorder.delete` unconditionally. A name that cannot collide with a
///    real `<uuid>.m4a` makes that a no-op rather than a deletion in Gaf's own
///    directory.
/// 2. **No entry is older than the 30-day retention period**, or
///    `expireRetainedAudio` rewrites `errorMessage` and clears audio paths under a
///    check in progress. Its `servicesAllowed` gate is belt and braces; do not
///    depend on it.
/// 3. **Every field combination is one the app itself can produce.** Success sets
///    `text` and clears the audio path; failure leaves `text` nil, sets
///    `errorMessage`, and keeps the path; cancellation is always textless; a
///    `.copied` delivery arises only from the paste fallback, leaving an
///    `errorMessage` on an otherwise succeeded record. **No code path produces a
///    failed or cancelled record with text**, which is why copy is always
///    unavailable on those rows.
/// 4. **Today's rows use fixed wall-clock times**, so a run before 18:42 shows a
///    few timestamps in the future. Times computed from `.now` either drift out of
///    step with the table below or collapse into each other just after midnight,
///    losing the deterministic sort. Nothing checked here needs a past timestamp.
///
/// No idempotence guard: the container is new in every process and `AppRuntime`
/// builds once, so `seed` runs at most once per launch.
@MainActor
enum UITestingHistoryFixture {
    /// 23 records over four day groups, of which **22 render** — entry 06 is
    /// in-flight and `DictationHistoryView.visibleRecords` must filter it out. If
    /// the header reads 23 dictations, that filter has regressed.
    ///
    /// Authored newest-first, matching the view's reverse sort, so this list reads
    /// in the same order as the screen.
    private static let entries: [Entry] = [
        // ── Today ────────────────────────────────────────────────────────────
        // Long enough to hit the row's 4-line limit: the truncation case, the
        // drag-to-select target, and the tall row the sticky header scrolls past.
        Entry(
            index: 1, dayOffset: 0, hour: 18, minute: 42, duration: 47.6,
            text: """
                So the plan for the Tokopedia batch is three hero angles per SKU, \
                then the macro pass on the texture and the seams, and I want the \
                turntable shot last because that is the one that eats the most \
                time and I would rather lose it than lose a hero. Lighting stays \
                where it is from this morning, the big softbox camera left and the \
                strip as a rim on the right, but I need to flag the background \
                because it is picking up a green cast from the wall. If the client \
                comes back asking for lifestyle frames as well, that is a second \
                day and it should be quoted as one rather than squeezed into this.
                """,
            state: .succeeded, delivery: .pasted
        ),
        // The single-line copy check: presenting the page-level toast must not
        // change this row's height.
        Entry(
            index: 2, dayOffset: 0, hour: 17, minute: 15, duration: 3.4,
            text: "Remember to charge both camera batteries before the shoot tomorrow.",
            state: .succeeded, delivery: .pasted
        ),
        // Failed *with* retained audio, so it shows Retry…
        Entry(
            index: 3, dayOffset: 0, hour: 16, minute: 3, duration: 12.8,
            errorMessage: "ElevenLabs is temporarily unavailable.",
            state: .failed, audioFileName: "ui-testing-fixture-service-unavailable.m4a"
        ),
        // …and immediately below it, failed *without* audio, so it shows none.
        // Adjacent on purpose: copy and the overflow must land on the same two x
        // positions in both rows, which is the whole point of Retry leading, and
        // that only reads at a glance when the two cases are neighbours.
        Entry(
            index: 4, dayOffset: 0, hour: 15, minute: 58, duration: 8.1,
            errorMessage: "The retained recording is no longer available.",
            state: .failed
        ),
        Entry(
            index: 5, dayOffset: 0, hour: 14, minute: 21, duration: 5.9,
            errorMessage: "Cancelled before transcription.",
            state: .cancelled, audioFileName: "ui-testing-fixture-cancelled.m4a"
        ),
        // Must never appear. Not a placeholder: this is the assertion that an
        // in-flight dictation stays out of the list until its outcome lands.
        Entry(
            index: 6, dayOffset: 0, hour: 13, minute: 12, duration: 2.2,
            state: .transcribing, audioFileName: "ui-testing-fixture-in-flight.m4a"
        ),
        // The copied-delivery case, carrying the message the paste fallback
        // actually leaves behind on a record that transcribed fine.
        Entry(
            index: 7, dayOffset: 0, hour: 11, minute: 7, duration: 6.3,
            text: "Ask Rina whether the seamless white cyc is free on Thursday afternoon.",
            errorMessage: "No editable text box was focused.",
            state: .succeeded, delivery: .copied
        ),
        Entry(
            index: 8, dayOffset: 0, hour: 9, minute: 35, duration: 14.2,
            text: """
                Two lines' worth: the invoice for last month's product batch still \
                has not gone out, and I should send it before the end of the week.
                """,
            state: .succeeded, delivery: .pasted
        ),

        // ── Yesterday ────────────────────────────────────────────────────────
        Entry(
            index: 9, dayOffset: 1, hour: 21, minute: 4, duration: 18.7,
            text: """
                Finished the array methods section tonight. Map and filter make \
                sense now, reduce still does not, so tomorrow is reduce and \
                nothing else until it sticks.
                """,
            state: .succeeded, delivery: .pasted
        ),
        Entry(
            index: 10, dayOffset: 1, hour: 19, minute: 47, duration: 2.8,
            text: "Order more gaffer tape.",
            state: .succeeded, delivery: .pasted
        ),
        // Em dash, quotes, and a colon, so search and text selection have
        // something with punctuation in it to work against.
        Entry(
            index: 11, dayOffset: 1, hour: 18, minute: 30, duration: 22.4,
            text: """
                Client feedback, verbatim: "the third angle feels flat — can we get \
                more separation from the background?" Which means the rim light is \
                too soft and too close. Move it back a metre and drop the diffusion \
                to a single layer, then reshoot only that angle.
                """,
            errorMessage: "No text box was focused to paste into.",
            state: .succeeded, delivery: .copied
        ),
        // A failed entry in a group that is not the top one, so Retry has to be
        // checked somewhere the first card is not doing the work.
        Entry(
            index: 12, dayOffset: 1, hour: 16, minute: 52, duration: 31.5,
            errorMessage: "The request timed out.",
            state: .failed, audioFileName: "ui-testing-fixture-timeout.m4a"
        ),
        // Diacritics and a non-English language code, so search is exercised
        // against text that is not plain ASCII.
        Entry(
            index: 13, dayOffset: 1, hour: 13, minute: 19, duration: 7.1,
            text: "Necesito revisar la iluminación antes de la próxima sesión.",
            languageCode: "es", state: .succeeded, delivery: .pasted
        ),
        Entry(
            index: 14, dayOffset: 1, hour: 8, minute: 58, duration: 4.5,
            text: "Coffee, then the storyboard for the Shopee spot.",
            state: .succeeded, delivery: .pasted
        ),

        // ── Three days ago: the first dated day label ────────────────────────
        Entry(
            index: 15, dayOffset: 3, hour: 20, minute: 11, duration: 16.9,
            text: """
                The b-roll checklist is worth writing down properly: hero, macro, \
                texture, turntable, in-hand, and one wide with the packaging.
                """,
            state: .succeeded, delivery: .pasted
        ),
        // Cancelled *without* audio, so the orange Cancelled label is checked in
        // the state where Retry is absent as well as the state where it is not.
        Entry(
            index: 16, dayOffset: 3, hour: 17, minute: 26, duration: 1.8,
            errorMessage: "The retained recording is no longer available.",
            state: .cancelled
        ),
        // Second tall row, deliberately mid-scroll rather than at a card edge.
        Entry(
            index: 17, dayOffset: 3, hour: 15, minute: 4, duration: 38.2,
            text: """
                Note to self about the freeCodeCamp project: the reason the counter \
                kept resetting was that I was declaring the variable inside the \
                loop, so every pass built a new one and threw the old value away. \
                Moving it above the loop fixed it in one line. The lesson is less \
                about the syntax and more about noticing when something resets \
                exactly as often as the block runs, because that is the tell.
                """,
            state: .succeeded, delivery: .pasted
        ),
        Entry(
            index: 18, dayOffset: 3, hour: 12, minute: 38, duration: 5.2,
            text: "Back up yesterday's cards to the working drive and the archive.",
            errorMessage: "No editable text box was focused.",
            state: .succeeded, delivery: .copied
        ),
        Entry(
            index: 19, dayOffset: 3, hour: 9, minute: 12, duration: 3.7,
            text: "Ask about the lens rental for next week.",
            state: .succeeded, delivery: .pasted
        ),

        // ── Six days ago: the second dated day label ─────────────────────────
        Entry(
            index: 20, dayOffset: 6, hour: 22, minute: 40, duration: 11.4,
            text: """
                Shot list came in under time today, which never happens. Write down \
                why while it is fresh: everything was pre-lit before the product \
                arrived.
                """,
            state: .succeeded, delivery: .pasted
        ),
        Entry(
            index: 21, dayOffset: 6, hour: 16, minute: 15, duration: 9.6,
            errorMessage: "ElevenLabs rejected this API key. Check that it is correct and enabled.",
            state: .failed, audioFileName: "ui-testing-fixture-authentication.m4a"
        ),
        Entry(
            index: 22, dayOffset: 6, hour: 11, minute: 48, duration: 4.1,
            text: "Follow up on the invoice from the Studio Delapan batch.",
            errorMessage: "No editable text box was focused.",
            state: .succeeded, delivery: .copied
        ),
        // Last row of the last card, so the group background's bottom rounded
        // corners have something short sitting on them.
        Entry(
            index: 23, dayOffset: 6, hour: 8, minute: 5, duration: 2.1,
            text: "Buy oat milk.",
            state: .succeeded, delivery: .pasted
        )
    ]

    /// Inserts the fixture and saves once.
    ///
    /// The explicit save is what makes the rows visible to `@Query`'s *first*
    /// fetch rather than at whatever later point `mainContext` would autosave, and
    /// it matches how `AppCoordinator` writes everywhere else.
    static func seed(into context: ModelContext) {
        let calendar = Calendar.autoupdatingCurrent
        for entry in entries {
            context.insert(entry.makeRecord(calendar: calendar))
        }
        try? context.save()
    }

    /// One row of the table above.
    private struct Entry {
        let index: Int
        let dayOffset: Int
        let hour: Int
        let minute: Int
        let duration: Double
        var text: String?
        var errorMessage: String?
        var languageCode: String?
        let state: TranscriptionState
        var delivery: DeliveryState = .notAttempted
        var audioFileName: String?

        init(
            index: Int,
            dayOffset: Int,
            hour: Int,
            minute: Int,
            duration: Double,
            text: String? = nil,
            errorMessage: String? = nil,
            languageCode: String? = nil,
            state: TranscriptionState,
            delivery: DeliveryState = .notAttempted,
            audioFileName: String? = nil
        ) {
            self.index = index
            self.dayOffset = dayOffset
            self.hour = hour
            self.minute = minute
            self.duration = duration
            self.text = text
            self.errorMessage = errorMessage
            self.languageCode = languageCode
            self.state = state
            self.delivery = delivery
            self.audioFileName = audioFileName
        }

        func makeRecord(calendar: Calendar) -> DictationRecord {
            DictationRecord(
                id: UITestingHistoryFixture.id(index),
                createdAt: UITestingHistoryFixture.date(
                    dayOffset: dayOffset,
                    hour: hour,
                    minute: minute,
                    calendar: calendar
                ),
                durationSeconds: duration,
                text: text,
                detectedLanguageCode: languageCode ?? (text == nil ? nil : "en"),
                transcriptionState: state,
                deliveryState: delivery,
                errorMessage: errorMessage,
                pendingAudioRelativePath: audioFileName
            )
        }
    }

    /// Stable identifiers, so a record keeps the same identity across launches and
    /// a check can name the entry it is about.
    ///
    /// Force-unwrapped on purpose: a `?? UUID()` fallback would silently destroy
    /// the determinism this exists for. The only way to reach nil is to break the
    /// format string, which should fail loudly on the first seeded launch.
    /// `nonisolated` because it is pure and `Entry.makeRecord` is not main-actor.
    private nonisolated static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "D1C7A7E0-0000-4000-8000-%012X", index))!
    }

    /// Uses `Calendar.autoupdatingCurrent`, the same calendar
    /// `DictationHistoryView.sections` groups with, so the fixture's day
    /// boundaries and the view's can never disagree.
    private nonisolated static func date(
        dayOffset: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        let today = calendar.startOfDay(for: .now)
        let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
#endif
