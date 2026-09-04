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
    /// separators, and makes a `Section` header stick to the top of the scroll
    /// area on its way past — the Apple Notes behaviour Scriber used to
    /// approximate with a titlebar strip and a preference key tracking every
    /// card's offset. All of that is deleted. Adding a divider, a card, or a day
    /// label back here draws a second one on top of the framework's.
    ///
    /// What it does *not* do is suppress the separator at a section's edges. Both
    /// boundaries are named on the rows below, because `listSectionSeparator` was
    /// tried here and changed nothing.
    private var historyList: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.records) { record in
                        DictationHistoryRow(record: record)
                            // The gap between one group and the next hangs off the
                            // last row above it, because a pinned header's height
                            // is the list's to set and nothing put inside one
                            // changes it. Padding rather than a bottom row inset:
                            // a row's height comes from its content, which is the
                            // same reason the transcript's padding is what sizes
                            // an ordinary row. The inset was tried here and
                            // produced no gap at all.
                            .padding(
                                .bottom,
                                record.id == section.records.last?.id
                                    ? DictationHistoryLayout.groupSpacing
                                    : 0
                            )
                            // `List` draws a separator on every row including a
                            // section's first and last, and `listSectionSeparator`
                            // does not reach either — it was tried here and
                            // changed nothing. So both boundaries are named per
                            // row, and both are hidden.
                            //
                            // Top, because the rule under a day label is the
                            // header's job below and this one doubled it: a stuck
                            // header draws its own bottom edge, so at the top of
                            // the list there were two rules a point apart, and
                            // only there. Bottom, because a rule after a group's
                            // last entry belongs to no group.
                            .listRowSeparator(
                                record.id == section.records.first?.id ? .hidden : .visible,
                                edges: .top
                            )
                            .listRowSeparator(
                                record.id == section.records.last?.id ? .hidden : .visible,
                                edges: .bottom
                            )
                            // Insets rather than padding for the horizontal
                            // measurement, so the separators come in with the
                            // content — padding leaves them running to the window
                            // edge and into the scroll bar. Vertical is zero
                            // deliberately: this call replaces a row's insets
                            // outright, which is what makes the transcript's own
                            // padding the only thing sizing a row.
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0,
                                    leading: DictationHistoryLayout.contentInset,
                                    bottom: 0,
                                    trailing: DictationHistoryLayout.contentInset
                                )
                            )
                            // A row inset moves where a separator starts, not
                            // where it ends: without this the rules run past the
                            // content and into the scroll bar. The trailing end
                            // needs naming separately.
                            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                            .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
                    }
                } header: {
                    Text(section.title)
                        .font(DictationHistoryLayout.dayLabelFont)
                        // A heading, so it carries the same weight of ink as the
                        // transcripts under it. A list header defaults to
                        // secondary, which read as a caption at this size.
                        .foregroundStyle(.primary)
                        // Padding, not `listRowInsets`. A `Section` header ignores
                        // row insets outright — the rows beside it honour the same
                        // call — so this is the only way to move the label off the
                        // list's own edge. Its own inset is about 8pt, so this is
                        // the difference that brings it level with the rows.
                        .padding(.leading, DictationHistoryLayout.dayLabelLeadingPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // Named rather than left to `.automatic`, and not for looks. Apple's
        // reference says of both `listRowSeparator` and `listSectionSeparator`:
        // "the list style is the final arbiter of separator visibility." Under
        // `.automatic` every separator preference in this file was ignored.
        // `.plain` also brings no inset of its own, so the width is ours to set.
        .listStyle(.plain)
        // No width cap here. The window itself is capped instead — see
        // `fitMainWindow` — so the list fills it and the scroll bar stays against
        // the window edge where a scroll bar belongs. Capping the list moved the
        // bar inward and left bands of bare window beside it; capping the row
        // held only the text and let the rules run past it.
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
    /// Wider than Settings. They used to match, back when Settings was a page in
    /// this same window; it is its own window now, so the transcript column is
    /// free to be as wide as it reads well at.
    static let maxContentWidth: CGFloat = 800

    /// From the window edge to a row's content and to a day label, and where the
    /// row separators start and stop.
    ///
    /// Measured against Notes, which holds its group labels about 16pt off the
    /// pane edge. The row has slack to give: the gap between a transcript and the
    /// copy button beside it is elastic, so widening this narrows the row without
    /// costing the transcript a line.
    static let contentInset: CGFloat = 24

    /// Between the entry time and the transcript beside it.
    static let timeColumnGap: CGFloat = 20

    /// Above a day label, separating it from the group before it. No rule marks
    /// that boundary any more, so this gap is the only thing that does.
    static let groupSpacing: CGFloat = 40

    /// A day label is a heading, not a caption, and has to read as one against a
    /// column of transcripts — clearly larger and heavier than the body text it
    /// sits above, without reaching for a document title's size.
    static let dayLabelFont: Font = .title2.weight(.bold)

    /// Added to the list's own leading inset to place a day label.
    ///
    /// A `Section` header ignores `listRowInsets`, so it keeps that inset — about
    /// 8pt — however far the rows beside it are moved. This is the difference,
    /// not the total, and it is not `contentInset`: the label sits *left* of the
    /// rows it heads, the way a Finder sidebar heading sits left of its rows, and
    /// its ceiling is the leading edge of the window's close button. Past that it
    /// reads as hanging off the window rather than off the list.
    static let dayLabelLeadingPadding: CGFloat = 8

    // No vertical row padding constant. `List` already pads a row, and adding to
    // it is what put too much air between a transcript and the rule under it.
    // Measure the framework's spacing on screen before reaching for a number.
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

    /// A floor under the transcript column *after* its padding, so a one-line
    /// entry cannot collapse to the height of the icons beside it.
    ///
    /// A floor, not a two-line minimum, and the difference is the whole point. A
    /// minimum of two lines makes one-line and two-line rows exactly equal —
    /// a two-line transcript fills it precisely — which flattened the rhythm the
    /// old page had. A floor below two lines lets a two-line row rise past it.
    ///
    /// Measured at 54pt for a one-line row, which is what the old card layout
    /// produced by accident: its floor was the icon cluster, 26pt of glyph and
    /// hover target inside 14pt of row padding.
    fileprivate static let minimumTranscriptBlockHeight: CGFloat = 54

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
            // On the transcript, not on the row, and that distinction is the
            // whole fix. A row is as tall as its tallest child: with one line of
            // transcript the icon cluster was taller, so the row grew around the
            // text and left more air above and below it than a three-line row
            // got. Padding the row keeps that difference and moves it; padding
            // the transcript makes the text the tallest child at every length,
            // so this number *is* the gap to the separator in every row.
            //
            // Which means it only works while the padded transcript stays taller
            // than `RowIconHover`'s 24pt, which the two-line minimum guarantees
            // on its own.
            //
            // 10. This number sets the height of rows with two lines or more and
            // nothing else: a one-line row is held by the floor below, so raising
            // this opens up the long rows without touching the short ones. That
            // only became true once the floor replaced the two-line minimum —
            // before it, raising this moved every row together.
            //
            // 14, and it is arithmetic rather than taste: the row insets above
            // zero out every other vertical measurement, two lines of transcript
            // measure 31pt, and 31 + 2 × 14 is the 60pt a two-line row wants.
            .padding(.vertical, 14)
            // After the padding, so the floor is on the padded block rather than
            // on the text inside it — a floor applied to the text would be
            // padded on top of and make every row taller than it reads.
            .frame(minHeight: Self.minimumTranscriptBlockHeight, alignment: .leading)

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
            // 4 rather than 5, so a 16pt glyph's target is 24pt and a one-line
            // transcript with its own padding is taller. The row's height has to
            // come from the text or its spacing goes uneven — see the note on
            // that padding.
            .padding(4)
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
