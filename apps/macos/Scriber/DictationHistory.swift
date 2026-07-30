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

    /// Broken out of the `List` builder deliberately. Inlining the row insets,
    /// separator, group background, and context menu in one closure pushed the
    /// expression past the type checker's budget. The row applies those itself
    /// now — it has to, because its hover state drives the group background and
    /// only a view can hold that state — so this is left working out where the
    /// entry sits in its group.
    @ViewBuilder
    private func row(_ record: DictationRecord, at index: Int, of count: Int) -> some View {
        DictationHistoryRow(
            record: record,
            isFirst: index == 0,
            isLast: index == count - 1,
            onCopyConfirmed: showCopyToast
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Dictations Yet",
                    systemImage: "waveform",
                    description: Text("Your completed dictations and retryable failures will appear here.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                List {
                    ForEach(sections) { section in
                        // Emitted as an ordinary row rather than a `Section` header.
                        // A real header draws a rule beneath itself that neither
                        // `listRowSeparator` nor the macOS-unavailable
                        // `listSectionSeparator` removes, and it fixes its own
                        // padding, which left the enlarged label cramped.
                        Text(section.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.top, 26)
                            .padding(.bottom, 14)
                            // Exactly the card inset, so the label's leading edge
                            // lines up with the card edge below it.
                            .listRowInsets(EdgeInsets(
                                top: 0,
                                leading: DictationHistoryGroupBackground.horizontalInset,
                                bottom: 0,
                                trailing: DictationHistoryGroupBackground.horizontalInset
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        ForEach(Array(section.records.enumerated()), id: \.element.id) { pair in
                            row(pair.element, at: pair.offset, of: section.records.count)
                        }
                    }
                }
                // `.plain` rather than `.inset`: the card inset is drawn by the row
                // background now, and `.inset` would add its own on top of it.
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(maxWidth: MainPageLayout.maxContentWidth, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if copyToastVisible {
                HistoryCopyToast()
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("dictation-history-view")
        .onDisappear {
            copyToastTask?.cancel()
            copyToastTask = nil
            copyToastVisible = false
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

private struct DictationHistoryGroupBackground: View {
    let isFirst: Bool
    let isLast: Bool

    /// Opened up from 10 to sit with the circular controls inside the card. A
    /// tight corner next to a circle reads as two different design languages in
    /// one row.
    private let radius: CGFloat = 16

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? radius : 0,
            bottomLeadingRadius: isLast ? radius : 0,
            bottomTrailingRadius: isLast ? radius : 0,
            topTrailingRadius: isFirst ? radius : 0,
            // The squircle, which is what macOS actually draws — `.circular`
            // joins a straight edge to a circular arc and the join is visible at
            // this radius.
            style: .continuous
        )
    }

    /// Distance from the window edge to the card edge, and the Dictation page's
    /// horizontal rhythm generally — the count row and the warning banner take it
    /// too, so every leading edge on the page lines up.
    ///
    /// Lives here rather than on the `List`, because padding the List moves its
    /// scroll indicator inward too and leaves the scroll bar floating away from
    /// the window edge.
    static let horizontalInset: CGFloat = 32

    /// Padding inside the card, between its edge and the row's content.
    ///
    /// Small on purpose. The card already stands 32pt off the window edge, and
    /// stacking a generous inset inside that put the entry time and the trailing
    /// controls in the middle of an empty margin — the eye read the gap before
    /// it read the row. This is the breathing room the fill needs to not clip
    /// its content, and nothing beyond it.
    static let contentInset: CGFloat = 8

    var body: some View {
        shape
            .fill(.clear)
            .overlay {
                // The mask keeps the continuous outer corners from `shape`, draws
                // the vertical outline on every slice, and exposes exactly one
                // bottom stroke per row. Adjacent rows therefore share one
                // hairline rather than stacking two borders.
                shape
                    .stroke(.separator, lineWidth: 0.5)
                    .mask(outlineMask)
            }
            .padding(.horizontal, Self.horizontalInset)
    }

    private var outlineMask: some View {
        ZStack {
            HStack(spacing: 0) {
                Rectangle().frame(width: 2)
                Spacer(minLength: 0)
                Rectangle().frame(width: 2)
            }
            VStack(spacing: 0) {
                if isFirst { Rectangle().frame(height: radius + 1) }
                Spacer(minLength: 0)
                Rectangle().frame(height: isLast ? radius + 1 : 2)
            }
        }
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
    let isFirst: Bool
    let isLast: Bool
    let onCopyConfirmed: () -> Void

    @State private var confirmDelete = false

    /// Transcript size. Larger than `.body`, which read as small next to the
    /// generous type Flow uses for the same content.
    fileprivate static let transcriptPointSize: CGFloat = 14
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
                    .font(.system(size: Self.transcriptPointSize))
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
        .padding(.vertical, 4)
        // Full-width within the card. Insetting past the time column left the
        // time visually unseparated from the entry above it.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        // Leading/trailing clear the card inset first, then add the padding
        // inside the card, which is deliberately tight.
        .listRowInsets(EdgeInsets(
            top: 10,
            leading: DictationHistoryGroupBackground.horizontalInset
                + DictationHistoryGroupBackground.contentInset,
            bottom: 10,
            trailing: DictationHistoryGroupBackground.horizontalInset
                + DictationHistoryGroupBackground.contentInset
        ))
        // The card and the gaps between groups carry the grouping. Row rules
        // inside a bordered card only added a second, competing division.
        .listRowSeparator(.hidden)
        .listRowBackground(DictationHistoryGroupBackground(isFirst: isFirst, isLast: isLast))
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
