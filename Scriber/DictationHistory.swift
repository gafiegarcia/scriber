import AppKit
import SwiftData
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

struct DictationHistoryView: View {
    /// Already filtered to what the workspace shows; the window owns that filter
    /// so its toolbar count cannot disagree with this list.
    ///
    /// No `@EnvironmentObject` here. This view reads nothing off `AppRuntime`,
    /// and holding one anyway subscribed it to every coordinator publish — a
    /// phase change re-evaluated the whole history for nothing.
    let records: [DictationRecord]
    let searchQuery: String

    private var filtered: [DictationRecord] {
        guard !searchQuery.isEmpty else { return records }
        return records.filter { ($0.text ?? "").localizedCaseInsensitiveContains(searchQuery) }
    }

    /// Groups the whole history by day, with no paging of any kind. `List` builds
    /// only the rows near the viewport and reuses them as they scroll away, so
    /// handing it every record costs about what handing it sixty used to.
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
                ContentUnavailableView("No Dictations Yet", systemImage: "waveform")
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                historyList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("dictation-history-view")
    }

    /// A `List`, which is `NSTableView` underneath on macOS: it builds only the
    /// rows near the viewport and reuses them as they scroll away, so a history
    /// of any length costs the same to show.
    ///
    /// **Do not hand-draw what this already draws.** `List` supplies the row
    /// separators — including suppressing the one after a section's last row —
    /// and makes a `Section` header stick to the top of the scroll area on its
    /// way past, which is the Apple Notes behaviour Scriber used to approximate
    /// with a titlebar strip and a preference key tracking every card's offset.
    /// All of that is deleted. Adding a divider, a card, or a day label back here
    /// draws a second one on top of the framework's.
    private var historyList: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.records) { record in
                        DictationHistoryRow(record: record)
                    }
                }
            }
        }
    }

}

/// What is left of the page's geometry now that `List` owns the rest.
///
/// The card metrics, the page background, the width cap, the day-label inset and
/// the gap between days all went with the cards and the titlebar strip: `List`
/// supplies its own insets, background, separators and sticky headers. Add a
/// constant back only when the framework's own value has been looked at on screen
/// and rejected — not to reproduce the old page from memory.
enum DictationHistoryLayout {
    /// Leading padding on a row, between the list's own inset and the entry time.
    static let contentInset: CGFloat = 16

    /// Top and bottom padding on a row. A shade under `contentInset`, because a
    /// row is as tall as its transcript and only the short ones are bounded by
    /// this number at all.
    static let rowVerticalInset: CGFloat = 14

    /// Between the entry time and the transcript beside it.
    static let timeColumnGap: CGFloat = 20
}

/// One day group as a single card: one shape, one outline, one rule between
/// neighbouring rows.
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
    @EnvironmentObject private var toasts: ToastPresenter

    @State private var confirmDelete = false

    fileprivate static let timePointSize: CGFloat = 13

    /// Two-digit hour so every entry's time is the same width — `08.30` lines
    /// up under `10.30` instead of hanging a digit short. The locale still
    /// chooses the separator, the 12- or 24-hour clock, and any day-period
    /// suffix; only the padding is forced.
    fileprivate static let timeFormat = Date.FormatStyle()
        .hour(.twoDigits(amPM: .abbreviated))
        .minute(.twoDigits)

    /// Exactly as wide as the widest time this locale can render. A hardcoded width
    /// is either too loose or too tight — `16.26` is five characters, while a
    /// 12-hour locale produces `11:59 PM` — so measure `timeFormat`'s own output.
    /// Keep it in step with `timePointSize`: measuring a size the label does not
    /// render at is how this silently starts clipping.
    fileprivate static let timeColumnWidth: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(ofSize: timePointSize, weight: .regular)
        let calendar = Calendar.autoupdatingCurrent
        // Late-evening and late-morning both, so the measurement covers whichever
        // of the 24-hour and 12-hour renderings this locale uses, including its
        // day-period suffix.
        let candidates = [DateComponents(hour: 23, minute: 59), DateComponents(hour: 11, minute: 59)]
        let widest = candidates
            .compactMap { calendar.date(from: $0) }
            .map { $0.formatted(timeFormat) }
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 44
        return ceil(widest)
    }()

    private var timeColumnWidth: CGFloat { Self.timeColumnWidth }

    private var isRetrying: Bool {
        runtime.coordinator.retryingRecordID == record.id
    }

    var body: some View {
        HStack(alignment: .center, spacing: DictationHistoryLayout.timeColumnGap) {
            Text(record.createdAt.formatted(Self.timeFormat))
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

            // A group rather than three more children of the row's HStack, which
            // spaces its columns by `timeColumnGap` — meant to separate the time
            // from the transcript, not one button from the next. Retry leads so
            // copy and the overflow menu land on the same two x positions in every
            // row; trailing a variable-width button shifts both on the rows with one.
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
                // Dropping it on a failed row leaves the overflow menu alone under
                // a column of two controls, which reads as a rendering fault.
                Button(action: copy) {
                    Image(systemName: "doc.on.doc")
                        // Not a hardcoded accent colour: an explicit
                        // `foregroundStyle` overrides the dimming `.disabled`
                        // applies, leaving a dead button a confident blue.
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

                // Known and accepted: a `Menu` keeps the width of its disclosure
                // indicator even under `.menuIndicator(.hidden)`, so the hover
                // background — which wraps the control — sits slightly right of
                // the glyph. Three attempts to correct that from outside the
                // control failed; the offset lives inside it. Do not spend a
                // fourth on it.
                Menu {
                    // Confirmed, and with the ellipsis that says so: a transcript
                    // is not recoverable, and this is the item reached by mis-aiming.
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
        .padding(.vertical, DictationHistoryLayout.rowVerticalInset)
        // Do not add a row hover state or click-to-copy. A whole-row copy target
        // and selectable text inside it cannot both be honest: selectable text
        // hit-tests first, so clicking the transcript selects while clicking the
        // space beside it copies. Doing it properly means giving up
        // `textSelection`, or hosting the row in AppKit where a click and a drag
        // can be told apart before either is committed.
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
        // On the row rather than on either menu: a `confirmationDialog` attached
        // inside a menu's content closure goes with the menu when it closes, so it
        // never gets presented.
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

    /// Dimmed here rather than by `.disabled`, which cannot dim a colour the view
    /// sets itself. Plain `.secondary` is not enough — it lands level with the
    /// row's quietest text, so a dead copy button still reads as live.
    private var copyTint: Color {
        return canCopy ? .accentColor : Color.secondary.opacity(0.4)
    }

    /// Both the button and context-menu route report through the page-level
    /// toast, so acknowledgement does not change this row's layout.
    private func copy() {
        guard canCopy else { return }
        runtime.coordinator.copy(record)
        toasts.post(.transcriptCopied())
    }

    private var rowText: String {
        if let text = record.text, !text.isEmpty { return text }
        return record.errorMessage ?? "Transcription failed."
    }
}

/// Hover feedback for the borderless icon controls in a history row. `.borderless`
/// draws no background in any state, so these give no sign they are controls until
/// clicked, and the padding is what gives a 16pt glyph a target to aim at.
///
/// Keep the fill near the threshold of visible: anything heavier parks a grey box
/// in a quiet row and the eye catches the box rather than the transcript.
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
