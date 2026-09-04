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

    /// What the list is filtered by, which trails what is in the field.
    ///
    /// The field has to stay responsive while the list catches up, the way Mail's
    /// does — typing must never lag, results may. Filtering itself was never the
    /// cost: a substring scan of two thousand short transcripts is under a
    /// millisecond. Rebuilding the list behind it is, and this is what stops that
    /// happening once per keystroke.
    ///
    /// Deleting is the case that made it necessary. Clearing a query goes from a
    /// handful of matches back to every record, so it rebuilds the most, which is
    /// why ⌘Delete and the last character were always the worst.
    @State private var activeQuery = ""

    private var filtered: [DictationRecord] {
        guard !activeQuery.isEmpty else { return records }
        return records.filter { ($0.text ?? "").localizedCaseInsensitiveContains(activeQuery) }
    }

    /// Groups the whole history by day, with no paging of any kind.
    ///
    /// One forward pass, not `Dictionary(grouping:)`. The records arrive sorted
    /// newest-first from `@Query` and `filter` keeps that order, so every day's
    /// entries are already adjacent and a day ends at the first record older than
    /// its start. That turns one `startOfDay` call per record into one per day —
    /// measured at 1.42 ms against 0.028 ms over 1,923 records — and this runs on
    /// every body pass, which means every insert while the window is open.
    ///
    /// Slices rather than arrays: `ForEach` takes them directly, so no day's
    /// records are copied out.
    private var sections: [DictationHistorySection] {
        let calendar = Calendar.autoupdatingCurrent
        let all = filtered
        var sections: [DictationHistorySection] = []
        var start = all.startIndex
        while start < all.endIndex {
            let day = calendar.startOfDay(for: all[start].createdAt)
            var end = all.index(after: start)
            while end < all.endIndex, all[end].createdAt >= day {
                end = all.index(after: end)
            }
            sections.append(DictationHistorySection(date: day, records: all[start..<end]))
            start = end
        }
        return sections
    }

    var body: some View {
        // Grouped once and asked twice. Reading `filtered.isEmpty` here and then
        // letting `historyList` group it again filtered the whole history twice
        // on every pass — the same trap `MainWindowView` calls out where it hands
        // one filtered array to both the list and the toolbar count.
        let groups = sections
        return Group {
            if records.isEmpty {
                ContentUnavailableView("No Dictations Yet", systemImage: "waveform")
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                historyList(groups)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // `task(id:)` cancels and restarts whenever the field changes, so the
        // sleep only finishes once typing stops — the whole debounce is those two
        // lines. Both directions are delayed, deleting included: it is the
        // expensive one, and a field that clears instantly while the list catches
        // up is the point rather than a compromise.
        .task(id: searchQuery) {
            try? await Task.sleep(for: DictationHistoryLayout.searchSettlingDelay)
            guard !Task.isCancelled else { return }
            activeQuery = searchQuery
        }
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
    /// What it does *not* do is suppress the separator at a section's edges —
    /// `listSectionSeparator` reaches neither — so both boundaries are named per
    /// row below.
    private func historyList(_ groups: [DictationHistorySection]) -> some View {
        List {
            ForEach(groups) { section in
                Section {
                    ForEach(section.records) { record in
                        DictationHistoryRow(record: record)
                            // Hidden at both edges of a group: the top one landed a
                            // point from the banner's own rule under a stuck day
                            // label and read as one thick rule, and a rule after a
                            // group's last entry belongs to no group. The header
                            // below describes the banner.
                            .listRowSeparator(
                                record.id == section.firstID ? .hidden : .visible,
                                edges: .top
                            )
                            .listRowSeparator(
                                record.id == section.lastID ? .hidden : .visible,
                                edges: .bottom
                            )
                            // Horizontal only. Vertical is zero deliberately: this
                            // call replaces a row's insets outright, which is what
                            // leaves the transcript's padding as the only thing
                            // sizing a row.
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0,
                                    leading: DictationHistoryLayout.contentInset,
                                    bottom: 0,
                                    trailing: DictationHistoryLayout.contentInset
                                )
                            )
                            // Left to itself a separator follows the row's leading
                            // *text*, which on a cancelled or failed row is the
                            // status badge rather than the transcript, so the rule
                            // stepped right on those rows alone. Naming both edges
                            // pins it to the row instead.
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
                        // No leading padding: a `Section` header ignores
                        // `listRowInsets` and keeps the style's own, which under
                        // `.inset` already sits slightly left of the rows it
                        // heads.
                        //
                        // Known and unfixed: the rule under a *stuck* day label is
                        // thicker than the rules between rows, and it is not a
                        // separator — which is why no separator setting has ever
                        // touched it. AppKit wraps a floating header row in a
                        // private `NSBannerView`, and that view's decoration ramps
                        // up over the row's last 4pt into a bright hairline: about
                        // three times a row separator's weight, read off a 2x
                        // capture. Only a stuck label has it. An unstuck one has no
                        // rule at all, since the one it used to have was the first
                        // row's top separator, hidden above.
                        //
                        // Nothing public reaches the banner. Measured against it
                        // and moving no pixel: `listSectionSeparator`,
                        // `listRowSeparator` and its tint on this header,
                        // `titlebarSeparatorStyle` and `toolbarStyle` in every
                        // value, a window with no toolbar, a window without
                        // `fullSizeContentView`, and `scrollEdgeEffectStyle(.hard)`
                        // — the documented switch for this exact effect, inert here
                        // on macOS 27. `NSBannerView` has no public header.
                        //
                        // Two dead ends, so they are not re-walked. `.sidebar` is
                        // the one list style that draws no banner, and it gets
                        // there by dropping sticky headers altogether rather than
                        // by styling them. And covering the strip with a background
                        // fails: the fill would have to match a `List` background
                        // that is an `NSVisualEffectView` material rather than a
                        // colour, and a solid colour renders as a black band across
                        // the label.
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // The style decides three things at once and they cannot be picked
        // separately: whether the separator preferences below are honoured, how
        // much space sits between one section and the next, and how far a day
        // label travels under the toolbar before handing over to the next.
        //
        // `.inset` is the only one that gives all three. `.automatic` ignored
        // every separator preference in this file — Apple's reference says "the
        // list style is the final arbiter of separator visibility" — and `.plain`
        // honours them but supplies no section spacing and hands a day label over
        // only once it is entirely under the toolbar, a scroll of its length
        // during which the label names the wrong day.
        //
        // Do not switch this to control a separator. Three rounds of work went
        // into rebuilding by hand what `.plain` had taken away, and all of it was
        // deleted when the style changed back.
        .listStyle(.inset)
        // No width cap here. The window itself is capped instead — `MainWindow`
        // declares it as the content's `maxWidth`, and the scene takes
        // `.windowResizability(.contentSize)` so SwiftUI enforces it — leaving the
        // list to fill the window with the scroll bar against its edge, where a
        // scroll bar belongs. Capping the list moved the bar inward and left bands
        // of bare window beside it; capping the row held only the text and let the
        // rules run past it.
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
    /// Added to a row's leading and trailing edge, and to where its separator
    /// starts and stops.
    ///
    /// **Not the distance from the window edge.** The style insets the list
    /// itself and this stacks on top: measured by comparing the two, `.inset`
    /// contributes 16 and `.plain` 8. So 16 here reads as 32 on screen, which is
    /// the measure the page had before the style changed. Re-measure on screen if
    /// the style ever moves again rather than carrying this number across.
    static let contentInset: CGFloat = 16

    /// Between the entry time and the transcript beside it.
    static let timeColumnGap: CGFloat = 20

    /// How long typing has to stop before the list is filtered again.
    ///
    /// Long enough that a word costs one rebuild rather than one per letter,
    /// short enough that it reads as the list keeping up rather than as a wait.
    /// 250 was tried first and felt like a wait; at 100 the list still skips the
    /// letters inside a word, because typing one takes longer than this.
    static let searchSettlingDelay: Duration = .milliseconds(100)

    /// A day label is a heading, not a caption, and has to read as one against a
    /// column of transcripts — clearly larger and heavier than the body text it
    /// sits above, without reaching for a document title's size.
    static let dayLabelFont: Font = .title2.weight(.bold)

    /// A row's vertical rhythm, and the pair that sets it.
    ///
    /// Both belong to the transcript rather than to the row, which is the whole
    /// trick: a row is as tall as its tallest child, so with one line of text the
    /// icon cluster won and short rows got more air than long ones. Padding the
    /// transcript makes the text the tallest child at every length.
    ///
    /// `verticalPadding` sets rows of two lines or more — two lines of transcript
    /// measure 31pt, so 31 + 2 × 14 is 59. `minimumBlockHeight` is a floor under
    /// the padded block, holding a one-line row at 54, and it is a floor rather
    /// than a two-line minimum on purpose: a two-line minimum makes one- and
    /// two-line rows exactly equal and flattens the list.
    ///
    /// Base values only. The row wraps them in `@ScaledMetric`, which needs a
    /// view's environment and cannot live on an enum — both are derived from a
    /// font measurement, so a fixed number stops lining up at another text size.
    enum Transcript {
        static let verticalPadding: CGFloat = 14
        static let minimumBlockHeight: CGFloat = 54
    }

    // No constant for the gap between days, and none placing the day label.
    // `.inset` supplies both. Declaring either here was tried and was wrong:
    // a `Section` header ignores `listRowInsets`, and the gap was reproducing
    // what the style gives for free.
}

/// One day's entries, and the few things about them a row or header needs.
///
/// The title and the boundary ids are resolved once here rather than per row
/// body: the rows ask "am I first or last in my group?" to place their
/// separators, and reading `records.first?.id` there is a SwiftData property
/// access on every pass.
private struct DictationHistorySection: Identifiable {
    let date: Date
    let records: ArraySlice<DictationRecord>
    let title: String
    let firstID: UUID?
    let lastID: UUID?

    var id: Date { date }

    init(date: Date, records: ArraySlice<DictationRecord>) {
        self.date = date
        self.records = records
        self.firstID = records.first?.id
        self.lastID = records.last?.id
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) {
            self.title = "Today"
        } else if calendar.isDateInYesterday(date) {
            self.title = "Yesterday"
        } else {
            self.title = date.formatted(.dateTime.day().month(.abbreviated).year())
        }
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

    /// The row's two vertical measurements, scaled with the reader's text size.
    /// Both are documented where their base values are, on
    /// `DictationHistoryLayout.Transcript`. The wrappers have to live here
    /// because `@ScaledMetric` needs a view's environment.
    @ScaledMetric(relativeTo: .body) private var minimumTranscriptBlockHeight =
        DictationHistoryLayout.Transcript.minimumBlockHeight

    @ScaledMetric(relativeTo: .body) private var transcriptVerticalPadding =
        DictationHistoryLayout.Transcript.verticalPadding

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
            .padding(.vertical, transcriptVerticalPadding)
            // The floor goes on the padded block, not on the text: applied to the
            // text it would be padded on top of and make every row taller.
            .frame(minHeight: minimumTranscriptBlockHeight, alignment: .leading)

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
