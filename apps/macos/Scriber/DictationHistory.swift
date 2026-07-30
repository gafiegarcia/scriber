import AppKit
import SwiftData
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

struct DictationHistoryView: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Already filtered to what the workspace shows; the window owns that filter
    /// so its toolbar count cannot disagree with this list.
    let records: [DictationRecord]
    let searchQuery: String
    @State private var copyToastVisible = false
    @State private var copyToastTask: Task<Void, Never>?

    private var filtered: [DictationRecord] {
        guard !searchQuery.isEmpty else { return records }
        return records.filter { ($0.text ?? "").localizedCaseInsensitiveContains(searchQuery) }
    }

    /// Known and unfixed: this regroups every record on each body evaluation.
    /// Only worth revisiting if a large history makes it measurable.
    private var sections: [DictationHistorySection] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { date in
            DictationHistorySection(date: date, records: grouped[date] ?? [])
        }
    }

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Dictations Yet",
                    systemImage: "waveform",
                    description: Text("Your completed dictations and retryable failures will appear here.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                historyList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if copyToastVisible {
                HistoryCopyToast()
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .accessibilityIdentifier("dictation-history-view")
        .onDisappear {
            copyToastTask?.cancel()
            copyToastTask = nil
            copyToastVisible = false
        }
    }

    /// A `ScrollView` rather than a `List`, so the day headers can pin below the
    /// toolbar and the rest of the page can scroll under its glass. The width cap
    /// sits on the content and not on the scroll view, which keeps the scroll
    /// indicator against the window edge where it belongs.
    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        DictationDayCard(records: section.records, onCopyConfirmed: showCopyToast)
                            .padding(.bottom, DictationHistoryLayout.groupSpacing)
                    } header: {
                        DictationDayHeader(title: section.title)
                    }
                }
            }
            .frame(maxWidth: DictationHistoryLayout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DictationHistoryLayout.horizontalInset)
            .padding(.bottom, 24)
        }
    }

    private func showCopyToast() {
        copyToastTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            copyToastVisible = true
        }
        copyToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.16)) {
                copyToastVisible = false
            }
            copyToastTask = nil
        }
    }
}

private struct HistoryCopyToast: View {
    var body: some View {
        Label("Transcript copied", systemImage: "checkmark")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().stroke(.separator, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            .allowsHitTesting(false)
            .accessibilityIdentifier("dictation-copy-toast")
    }
}

enum DictationHistoryLayout {
    /// Wider than Settings. They used to match, back when Settings was a page in
    /// this same window; it is its own window now, so the transcript column is
    /// free to be as wide as it reads well at.
    static let maxContentWidth: CGFloat = 800

    /// Distance from the window edge to the card edge, and the page's horizontal
    /// rhythm generally.
    static let horizontalInset: CGFloat = 32

    /// Padding inside the card, between its edge and the row's content.
    ///
    /// Small on purpose. The card already stands well off the window edge, and
    /// stacking a generous inset inside that put the entry time and the trailing
    /// controls in the middle of an empty margin — the eye read the gap before it
    /// read the row.
    static let contentInset: CGFloat = 12

    static let cardCornerRadius: CGFloat = 16

    /// The gap that separates one day from the next.
    static let groupSpacing: CGFloat = 28
}

/// The day a group belongs to, pinned while that group is on screen.
///
/// Opaque rather than glass. Translucent, the rows sliding behind it ghost
/// through the label — and it sits directly beneath a toolbar that is already
/// blurring the same content, so a second translucent surface reads as a
/// rendering artefact rather than as a header.
private struct DictationDayHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(nsColor: .windowBackgroundColor), in: .capsule)
            .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One day group as a single card: one shape, one outline, one rule between
/// neighbouring rows.
private struct DictationDayCard: View {
    let records: [DictationRecord]
    let onCopyConfirmed: () -> Void

    private var shape: RoundedRectangle {
        // The squircle, which is what macOS actually draws — `.circular` joins a
        // straight edge to a circular arc and the join is visible at this radius.
        RoundedRectangle(cornerRadius: DictationHistoryLayout.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(records) { record in
                DictationHistoryRow(record: record, onCopyConfirmed: onCopyConfirmed)
                if record.id != records.last?.id {
                    Divider().padding(.horizontal, DictationHistoryLayout.contentInset)
                }
            }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
    }
}

private struct DictationHistorySection: Identifiable {
    let date: Date
    let records: [DictationRecord]

    var id: Date { date }

    var title: String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private struct DictationHistoryRow: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Bindable var record: DictationRecord
    let onCopyConfirmed: () -> Void

    @State private var confirmDelete = false

    fileprivate static let timePointSize: CGFloat = 13

    /// Exactly as wide as the widest time this locale can render, and no wider.
    ///
    /// A hardcoded width is either too loose — parking slack beside every short
    /// time — or too tight for locales that do not use a 24-hour clock: `16.26`
    /// is five characters here, while a 12-hour locale produces `11:59 PM`.
    /// Measuring the formatter's own output covers both. Kept in step with
    /// `timePointSize`; measuring a different size than the label renders is how
    /// this silently starts clipping.
    fileprivate static let timeColumnWidth: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(ofSize: timePointSize, weight: .regular)
        let calendar = Calendar.autoupdatingCurrent
        // Late-evening and late-morning both, so the measurement covers whichever
        // of the 24-hour and 12-hour renderings this locale uses, including its
        // day-period suffix.
        let candidates = [DateComponents(hour: 23, minute: 59), DateComponents(hour: 11, minute: 59)]
        let widest = candidates
            .compactMap { calendar.date(from: $0) }
            .map { $0.formatted(date: .omitted, time: .shortened) }
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 44
        return ceil(widest)
    }()

    private var timeColumnWidth: CGFloat { Self.timeColumnWidth }

    private var isRetrying: Bool {
        runtime.coordinator.retryingRecordID == record.id
    }

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: Self.timePointSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: timeColumnWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(rowText)
                    .lineLimit(4)
                    .textSelection(.enabled)
                // Duration is gone. A dictation's length is not something the user
                // came here for — the transcript is — and it cost every row a
                // second line even when there was nothing else to report.
                Group {
                    if isRetrying {
                        Label("Retrying", systemImage: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                    } else if record.transcriptionState == .cancelled {
                        Label("Cancelled", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.orange)
                    } else if record.transcriptionState == .failed {
                        Label("Failed", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }

            Spacer(minLength: 12)

            // One group, tight, and Retry first.
            //
            // These used to be three separate children of the row's own HStack,
            // which spaces its columns 28 apart — a gap meant to separate the
            // time from the transcript, not to separate a button from the button
            // beside it. Grouping them lets the controls sit together at 8 while
            // the row keeps its wide columns.
            //
            // Retry leads so that copy and the overflow menu land on the same
            // two x positions in every row. Trailing a variable-width button
            // onto the end would have shifted them both on the rows that have
            // one, which is exactly the misalignment this ordering avoids.
            HStack(spacing: 8) {
                if isRetrying {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 48)
                } else if record.isRetryable, record.pendingAudioRelativePath != nil {
                    // Regular size: at `.small` the button looked undersized once
                    // the transcript grew to 14pt and the rows opened up around it.
                    Button("Retry") { runtime.coordinator.retry(record) }
                        .buttonStyle(.bordered)
                        .disabled(runtime.coordinator.phase.isBusy)
                }

                // Shown on every entry, including the ones with nothing to copy.
                // A failed row used to drop the button entirely, which left its
                // overflow menu sitting alone under a column of two controls and
                // read as a rendering fault rather than as an absence.
                Button(action: copy) {
                    Image(systemName: "doc.on.doc")
                        // Not a hardcoded accent colour. An explicit
                        // `foregroundStyle` overrides the dimming `.disabled`
                        // would otherwise apply, so the button on a failed entry
                        // stayed a confident blue while refusing to do anything.
                        .foregroundStyle(copyTint)
                        // Both axes keep the glyph and its hover target aligned
                        // with the other row controls on entries of every height.
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .modifier(RowIconHover())
                .disabled(!canCopy)
                .help(canCopy ? "Copy transcription" : "Nothing to copy")
                .accessibilityLabel("Copy transcription")

                // The plain SwiftUI menu, on purpose, with its default popup
                // placement. The AppKit replacement that used to be here dropped
                // its menu trailing-aligned and centred its glyph exactly, but
                // it anchored the popup badly enough that the alignment was not
                // worth the control. Built-in behaviour is the better default
                // even where it is less precise.
                //
                // Known and accepted: a `Menu` keeps the width of its disclosure
                // indicator even under `.menuIndicator(.hidden)`, so the hover
                // background — which wraps the control — sits slightly right of
                // the glyph. Three attempts to correct that from outside the
                // control failed; the offset lives inside it. Do not spend a
                // fourth on it.
                Menu {
                    // Confirmed, and with the ellipsis that says so.
                    //
                    // Clearing the whole history has always asked first while
                    // deleting a single entry happened instantly, which is
                    // backwards: clearing everything is a decision you arrive at,
                    // and deleting one entry is the one you reach by mis-aiming a
                    // menu. A transcript is not recoverable — there is no undo for
                    // this and no trash to fish it out of — so the cheap dialog is
                    // worth more here than on the bulk action.
                    Button("Delete…", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .modifier(RowIconHover())
                .help("More actions")
                .accessibilityLabel("More actions")
            }
        }
        .padding(.horizontal, DictationHistoryLayout.contentInset)
        .padding(.vertical, 12)
        // No row hover state and no click-to-copy. Both were built and removed
        // the same day, and the reason is worth keeping so they are not rebuilt
        // the same way: a whole-row copy target and selectable text inside it
        // cannot both be honest. Selectable text hit-tests first, so clicking
        // the transcript — the obvious place to aim — selected instead of
        // copying, while clicking the empty space beside it copied. Learning
        // that a row-wide affordance excludes the one thing on the row you would
        // click is worse than not offering it. The row hover went with it: it
        // advertised a target that did not exist, and it could not cover the
        // gaps between entries, so the highlight dropped out as the pointer
        // crossed from one row to the next.
        //
        // Wispr Flow does make this work. Doing it properly means giving up
        // `textSelection` on the transcript, or hosting the row in AppKit where
        // a click and a drag can be told apart before either is committed.
        // Neither is worth it for a second route to a button that is right there.
        .contextMenu {
            if canCopy {
                Button("Copy", action: copy)
            }
            if record.isRetryable, record.pendingAudioRelativePath != nil {
                Button("Retry") { runtime.coordinator.retry(record) }
            }
            Divider()
            // Same confirmation as the overflow menu's. Two routes to the same
            // irreversible action must not disagree about whether it asks first.
            Button("Delete…", role: .destructive) { confirmDelete = true }
        }
        // On the row rather than on either menu. A `confirmationDialog` attached
        // inside a menu's content closure goes with the menu when it closes, so
        // the dialog never gets presented; the row outlives both menus and is
        // what both of them set `confirmDelete` on.
        .confirmationDialog(
            "Delete this dictation?",
            isPresented: $confirmDelete
        ) {
            Button("Delete", role: .destructive) { runtime.coordinator.delete(record) }
        } message: {
            Text("This permanently removes the transcript and any recording kept for retry.")
        }
    }

    private var canCopy: Bool {
        guard let text = record.text else { return false }
        return !text.isEmpty
    }

    /// `.secondary` where there is nothing to copy, so the control reads as
    /// unavailable. `.disabled` cannot dim a colour the view sets itself.
    /// `.secondary` is not muted enough to read as unavailable. On a card that
    /// is itself a light fill, it renders close to the transcript's own colour,
    /// so a copy button with nothing to copy still looked live. This has to sit
    /// clearly below the row's quietest text, not level with it.
    private var copyTint: Color {
        return canCopy ? .accentColor : Color.secondary.opacity(0.4)
    }

    /// Both the button and context-menu route report through the page-level
    /// toast, so acknowledgement does not change this row's layout.
    private func copy() {
        guard canCopy else { return }
        runtime.coordinator.copy(record)
        onCopyConfirmed()
    }

    private var rowText: String {
        if let text = record.text, !text.isEmpty { return text }
        return record.errorMessage ?? "Transcription failed."
    }
}

/// Hover feedback for the borderless icon controls in a history row.
///
/// `.borderless` draws no background at all, in any state, so these controls
/// give no sign they are controls until they are clicked. The padding is part
/// of the treatment rather than decoration around it: it is what gives a 16pt
/// glyph a click target big enough to aim at.
///
/// The fill is deliberately near the threshold of visible. It only has to say
/// the pointer is on a control; anything heavier parks a grey box in a quiet
/// row and the eye catches the box rather than the transcript.
private struct RowIconHover: ViewModifier {
    private static let fill: Double = 0.055

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? Self.fill : 0))
            )
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private extension DictationRecord {
    var isRetryable: Bool {
        transcriptionState == .failed || transcriptionState == .cancelled
    }
}
