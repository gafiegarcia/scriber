import AppKit
import SwiftData
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
#endif

enum MainSection: Hashable { case dictation, settings }

struct SearchDictationHistoryActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var searchDictationHistoryAction: (() -> Void)? {
        get { self[SearchDictationHistoryActionKey.self] }
        set { self[SearchDictationHistoryActionKey.self] = newValue }
    }
}

private enum KeySaveFeedback {
    case saved
    case failed(String)

    var message: String {
        switch self {
        case .saved: "API key verified with ElevenLabs and saved in your Mac login Keychain."
        case .failed(let message): message
        }
    }

    var systemImage: String {
        switch self {
        case .saved: "checkmark.shield.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .saved: .green
        case .failed: .red
        }
    }
}

struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: AppRuntime
    @State private var section: MainSection? = .dictation
    @FocusState private var sidebarFocused: Bool
    @FocusState private var dictationSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Dictation", systemImage: "clock.arrow.circlepath")
                    .tag(MainSection.dictation)
                    .accessibilityIdentifier("sidebar-dictation")
                Label("Settings", systemImage: "gearshape")
                    .tag(MainSection.settings)
                    .accessibilityIdentifier("sidebar-settings")
            }
            .accessibilityIdentifier("main-sidebar")
            .navigationTitle("Scriber")
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
            .focused($sidebarFocused)
            // The sidebar toggle is deliberately the one AppKit supplies.
            //
            // Replacing it to attach a tooltip was tried and reverted: a custom
            // `ToolbarItem` cannot be put where the real one goes. AppKit gives
            // the toggle its own slot above the sidebar, beside the window
            // controls, and there is no public placement that names that slot —
            // `.navigation` is the closest and it still lands in the detail
            // column's leading edge, next to the page title. Every native app
            // with a sidebar puts the control over the sidebar, so a tooltip is
            // not worth moving it. If the tooltip is wanted later it has to come
            // from reaching the supplied `NSToolbarItem` and setting `toolTip`
            // on it, not from a second control.
        } detail: {
            Group {
                switch section ?? .dictation {
                case .dictation: DictationHistoryView(searchFocused: $dictationSearchFocused)
                case .settings:
                    SettingsView(
                        onShortcutConfigurationCaptureChanged: runtime.coordinator.setShortcutConfigurationCaptureActive
                    )
                }
            }
            .navigationTitle(section == .settings ? "Settings" : "Dictation")
        }
        .frame(minWidth: 760, minHeight: 520)
        .focusedSceneValue(\.searchDictationHistoryAction, focusDictationSearch)
        .onAppear {
            applyMainWindowRequest(runtime.coordinator.mainWindowRequest)
            openOnboardingIfNeeded()
            focusSidebarIfAppropriate()
        }
        .onChange(of: runtime.preferences.onboardingComplete) { _, _ in openOnboardingIfNeeded() }
        .onChange(of: runtime.coordinator.mainWindowRequest) { _, request in
            applyMainWindowRequest(request)
        }
    }

    private func applyMainWindowRequest(_ request: MainWindowRequest?) {
        guard let request else { return }
        section = request.destination == .dictation ? .dictation : .settings
    }

    private func focusSidebarIfAppropriate() {
        switch runtime.coordinator.mainWindowRequest?.destination {
        case .apiKey, .usage, .microphone, .permissions:
            return
        case .dictation, .settings, nil:
            DispatchQueue.main.async { sidebarFocused = true }
        }
    }

    private func focusDictationSearch() {
        section = .dictation
        DispatchQueue.main.async { dictationSearchFocused = true }
    }

    private func openOnboardingIfNeeded() {
        guard !runtime.preferences.onboardingComplete else { return }
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "onboarding")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        Group {
            Button("Open Scriber") { openMain(destination: .dictation) }
            Button("Settings") { openMain(destination: .settings) }
            if runtime.preferences.onboardingComplete {
                if !runtime.coordinator.permissionReadiness.isReady {
                    Divider()
                    Button { openMain(destination: .permissions) } label: {
                        Label("Permissions Required…", systemImage: "exclamationmark.triangle.fill")
                    }
                }
                let credentials = runtime.coordinator.credentialReadiness
                if !credentials.isReady {
                    Divider()
                    Button {
                        openMain(destination: credentials.resolvesInUsageSettings ? .usage : .apiKey)
                    } label: {
                        Label("\(credentials.title)…", systemImage: "exclamationmark.triangle.fill")
                    }
                }
            }
            Divider()
            shortcutHint(
                "Hold to Dictate: \(runtime.preferences.holdShortcut.displayName)",
                isEnabled: runtime.preferences.holdShortcutEnabled
            )
            shortcutHint(
                "Hands-free Toggle: \(runtime.preferences.toggleShortcut.displayName)",
                isEnabled: runtime.preferences.toggleShortcutEnabled
            )
            Divider()
            Button("Quit Scriber") { NSApp.terminate(nil) }
        }
        .onAppear {
            runtime.coordinator.startServices()
            if !runtime.preferences.onboardingComplete { openOnboarding() }
        }
    }

    private func shortcutHint(_ title: String, isEnabled: Bool) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .strikethrough(!isEnabled)
    }

    private func openOnboarding() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "onboarding")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openMain(destination: MainWindowDestination) {
        runtime.coordinator.selectMainWindowDestination(destination)
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

}

struct DictationHistoryView: View {
    /// `.searchable` cannot right-align a hint or hide it on focus, so the
    /// shortcut is appended to the prompt. `ScriberUITests` locates the search
    /// field by this exact string and must be updated alongside it.
    static let searchPrompt = "Search past transcripts (⌘F)"

    @EnvironmentObject private var runtime: AppRuntime
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    let searchFocused: FocusState<Bool>.Binding
    @State private var search = ""
    @State private var confirmClear = false
    @State private var stickyDayTitle: String?

    /// The `List`'s own frame, so a day label's `minY` inside it reads as
    /// distance below the top of the visible list rather than distance down the
    /// scrolled content.
    fileprivate static let scrollSpace = "dictation-history-scroll"

    /// A record is inserted before its transcription starts, so that an interrupted
    /// job keeps its audio and can be recovered at the next launch. Until the
    /// outcome is known there is nothing truthful to show for it — the row would
    /// read "Transcription failed." purely because no text or error exists yet — so
    /// in-flight dictations stay out of the list. A record the user explicitly
    /// retried is exempt: it was already on screen and keeps its "Retrying" label.
    private var visibleRecords: [DictationRecord] {
        records.filter {
            $0.transcriptionState != .transcribing
                || runtime.coordinator.retryingRecordID == $0.id
        }
    }

    private var filtered: [DictationRecord] {
        guard !search.isEmpty else { return visibleRecords }
        return visibleRecords.filter { ($0.text ?? "").localizedCaseInsensitiveContains(search) }
    }

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
        DictationHistoryRow(record: record, isFirst: index == 0, isLast: index == count - 1)
    }

    /// Warnings sit above everything, directly under the title and search row.
    ///
    /// They used to sit between the count row and the list, which put the one
    /// thing on the page that needs acting on below the one thing that does not.
    @ViewBuilder
    private var recoveryBanners: some View {
        if runtime.preferences.onboardingComplete {
            if !runtime.coordinator.permissionReadiness.isReady {
                RecoveryBanner(
                    title: "Dictation is unavailable",
                    message: runtime.coordinator.permissionReadiness.recoveryMessage,
                    actionTitle: "Review Permissions",
                    identifier: "permission-recovery-banner"
                ) {
                    runtime.coordinator.selectMainWindowDestination(.permissions)
                }
                Divider()
            }
            // Setup can complete and then stop being sufficient. A revoked or
            // replaced key leaves Scriber silently non-functional otherwise.
            let credentials = runtime.coordinator.credentialReadiness
            if !credentials.isReady {
                RecoveryBanner(
                    title: credentials.title,
                    message: credentials.recoveryMessage,
                    actionTitle: credentials.resolvesInUsageSettings ? "View Usage" : "Update Key",
                    identifier: "credential-recovery-banner"
                ) {
                    runtime.coordinator.selectMainWindowDestination(
                        credentials.resolvesInUsageSettings ? .usage : .apiKey
                    )
                }
                Divider()
            }
        }
    }

    /// The count row, which now also carries the current day.
    ///
    /// The day label only appears once that day's own label has scrolled up
    /// under this row. At rest the list's first label sits directly below, and
    /// printing the same word twice a few points apart reads as a mistake rather
    /// than as a header. The empty string keeps the row's height fixed so the
    /// list does not shift down the moment the user starts scrolling.
    private var historyHeader: some View {
        HStack(spacing: 12) {
            Text(stickyDayTitle ?? " ")
                .font(.title3.weight(.semibold))
                .opacity(stickyDayTitle == nil ? 0 : 1)
                .contentTransition(.opacity)
                .accessibilityHidden(stickyDayTitle == nil)

            Spacer(minLength: 12)

            Text("\(visibleRecords.count) \(visibleRecords.count == 1 ? "dictation" : "dictations")")
                .foregroundStyle(.secondary)
            TrailingAlignedMenuButton(
                systemImage: "ellipsis.circle",
                help: "Dictation history actions",
                isEnabled: !visibleRecords.isEmpty,
                items: [
                    TrailingAlignedMenuButton.Item(title: "Clear Dictation History…") {
                        confirmClear = true
                    }
                ]
            )
            .frame(width: 24, height: 24)
            .accessibilityIdentifier("dictation-history-actions")
        }
        .padding(.horizontal, DictationHistoryGroupBackground.horizontalInset)
        .padding(.vertical, 14)
        .animation(.easeInOut(duration: 0.18), value: stickyDayTitle)
    }

    var body: some View {
        VStack(spacing: 0) {
            recoveryBanners

            historyHeader

            Divider()

            if visibleRecords.isEmpty {
                ContentUnavailableView(
                    "No Dictations Yet",
                    systemImage: "waveform",
                    description: Text("Your completed dictations and retryable failures will appear here.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
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
                            .background(DayLabelAnchor(title: section.title))
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
                .coordinateSpace(.named(Self.scrollSpace))
                .onPreferenceChange(DayLabelAnchorKey.self) { anchors in
                    // Anchors arrive in list order, newest day first, so the last
                    // one that has crossed the top is the day the rows under the
                    // header belong to. None having crossed means the list is at
                    // rest at the top and its own first label is doing the job.
                    stickyDayTitle = anchors.last { $0.minY <= 0 }?.title
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("dictation-history-view")
        .searchable(text: $search, prompt: DictationHistoryView.searchPrompt)
        .searchFocused(searchFocused)
        .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { runtime.coordinator.clearDictationHistory(visibleRecords) }
        } message: {
            Text("This permanently removes transcripts and any retained failed recordings.")
        }
    }
}

/// Where one day label currently sits relative to the top of the visible list.
private struct DayLabelPosition: Equatable {
    let title: String
    let minY: CGFloat
}

private struct DayLabelAnchorKey: PreferenceKey {
    static let defaultValue: [DayLabelPosition] = []

    static func reduce(value: inout [DayLabelPosition], nextValue: () -> [DayLabelPosition]) {
        value.append(contentsOf: nextValue())
    }
}

/// Reports a day label's position so the header row can pick the label up as it
/// scrolls out of sight.
///
/// A transparent background rather than a wrapper, so measuring the label costs
/// it none of its own layout.
private struct DayLabelAnchor: View {
    let title: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: DayLabelAnchorKey.self,
                value: [DayLabelPosition(
                    title: title,
                    minY: proxy.frame(in: .named(DictationHistoryView.scrollSpace)).minY
                )]
            )
        }
    }
}

private struct RecoveryBanner: View {
    let title: String
    let message: String
    let actionTitle: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .accessibilityIdentifier(identifier)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        // Matches the history List's own horizontal padding, so the banner's
        // rounded edge lines up with the day cards below it.
        .padding(.horizontal, DictationHistoryGroupBackground.horizontalInset)
        .padding(.vertical, 12)
    }
}

/// A trailing-edge overflow button whose menu opens toward the leading edge.
///
/// SwiftUI's `Menu` offers no control over which edge its popup grows from, so a
/// control near the window's trailing edge spills its menu outside the window and
/// only flips once it would leave the *screen*. Hosting an `NSMenu` lets the menu
/// be positioned explicitly, with its trailing edge aligned to the button's.
private struct TrailingAlignedMenuButton: NSViewRepresentable {
    struct Item {
        let title: String
        let action: () -> Void
    }

    let systemImage: String
    let help: String
    let isEnabled: Bool
    let items: [Item]

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.present(_:)))
        button.isBordered = false
        button.bezelStyle = .accessoryBar
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: help)
        button.toolTip = help
        // Assign only on a real change. `NSControl.setEnabled:` invalidates the
        // window's key-view loop, and AppKit rebuilds it by asking this button's
        // hosting view for its responder node — a read of the SwiftUI attribute
        // graph from inside the same update pass that is setting this property.
        // That re-entry is a graph cycle, and AttributeGraph spins on it forever
        // at 100% CPU — any pill appearing while this header updates used to wedge
        // the app. Deferring the write by a main-actor turn is what breaks the
        // re-entry; the change check alone is not enough, because the first real
        // write still cycles. It only spares the redundant writes.
        if button.isEnabled != isEnabled {
            let enabled = isEnabled
            Task { @MainActor in button.isEnabled = enabled }
        }
        button.target = context.coordinator
        button.action = #selector(Coordinator.present(_:))
        context.coordinator.items = items
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items)
    }

    final class Coordinator: NSObject {
        var items: [Item]

        init(items: [Item]) {
            self.items = items
        }

        @objc func present(_ sender: NSButton) {
            let menu = NSMenu()
            for (index, item) in items.enumerated() {
                let menuItem = NSMenuItem(title: item.title, action: #selector(invoke(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = index
                menu.addItem(menuItem)
            }
            // `menu.size` forces the menu to lay out, which is what makes the
            // trailing alignment exact rather than an estimate. The button is not
            // flipped, so its `minY` is the bottom edge and the menu drops below it.
            let origin = NSPoint(x: sender.bounds.maxX - menu.size.width, y: sender.bounds.minY)
            menu.popUp(positioning: nil, at: origin, in: sender)
        }

        @objc private func invoke(_ sender: NSMenuItem) {
            guard items.indices.contains(sender.tag) else { return }
            items[sender.tag].action()
        }
    }
}

/// Draws one day group as a single rounded card. Each row paints its own slice,
/// so only the group's outermost corners are rounded and the rows in between
/// join into one continuous shape.
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
    static let contentInset: CGFloat = 20

    var body: some View {
        // Fill only, no border. Each row draws its own slice of the group, so a
        // stroked border put a line on every interior row's top and bottom edge —
        // reintroducing exactly the separators the card was meant to replace.
        // The fill has to carry the shape alone, so it is a fixed tint rather than
        // a system background colour: `controlBackgroundColor` over
        // `windowBackgroundColor` is nearly identical in dark mode.
        shape
            .fill(Color.primary.opacity(0.06))
            // Drawn here rather than through `listRowSeparator`, which spans the
            // whole row and would run past the card onto the page. This one is
            // clipped to the card and crosses the full width, including under the
            // time, so an entry is divided from the one above it rather than
            // having its timestamp float free.
            .overlay(alignment: .bottom) {
                if !isLast {
                    // Hairline. A full point renders as two device pixels on a
                    // Retina display, which is heavier than the card needs.
                    Rectangle()
                        .fill(.separator)
                        .frame(height: 0.5)
                }
            }
            .padding(.horizontal, Self.horizontalInset)
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

    @State private var didCopy = false
    @State private var copiedFeedback: Task<Void, Never>?

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
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        // Not a hardcoded accent colour. An explicit
                        // `foregroundStyle` overrides the dimming `.disabled`
                        // would otherwise apply, so the button on a failed entry
                        // stayed a confident blue while refusing to do anything.
                        .foregroundStyle(copyTint)
                        // Both axes, not just the width. `checkmark` is shorter
                        // than `doc.on.doc`, and on a single-line entry the icon
                        // is the tallest thing in the row — so sizing only the
                        // width left the row collapsing a couple of points at
                        // the moment of the copy and springing back after.
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(!canCopy)
                .help(canCopy ? "Copy transcription" : "Nothing to copy")
                .accessibilityLabel(didCopy ? "Copied" : "Copy transcription")

                // A button-styled menu draws its background around its own
                // content, so the background and the glyph cannot disagree about
                // where the centre is. `.borderlessButton` drew nothing, which is
                // what forced a hand-drawn background around a control wider than
                // its glyph and started three rounds of off-centre highlights.
                // The destructive role earns nothing visible here and is kept
                // for what it means rather than how it looks. **macOS does not
                // tint destructive menu items red** — that is an iOS behaviour,
                // and Finder's "Move to Trash", Mail's "Delete", and Photos'
                // "Delete" are all plain. Forcing it means an `NSMenuItem` with
                // a red `attributedTitle`, which stays red when the item is
                // highlighted and the highlight fills with the accent colour.
                // An earlier comment here claimed the red was lost by moving to
                // `NSMenu`; it was never there to lose.
                Menu {
                    Button("Delete", role: .destructive) { runtime.coordinator.delete(record) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .menuIndicator(.hidden)
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
            Button("Delete", role: .destructive) { runtime.coordinator.delete(record) }
        }
    }

    private var canCopy: Bool {
        guard let text = record.text else { return false }
        return !text.isEmpty
    }

    /// `.secondary` where there is nothing to copy, so the control reads as
    /// unavailable. `.disabled` cannot dim a colour the view sets itself.
    private var copyTint: Color {
        if didCopy { return .green }
        return canCopy ? .accentColor : .secondary
    }

    /// Clicking a row is silent otherwise — the transcript reaches the clipboard
    /// with nothing on screen to say so — so the copy button doubles as the
    /// acknowledgement whichever route was taken to get here.
    private func copy() {
        guard canCopy else { return }
        runtime.coordinator.copy(record)
        didCopy = true
        copiedFeedback?.cancel()
        copiedFeedback = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }

    private var rowText: String {
        if let text = record.text, !text.isEmpty { return text }
        return record.errorMessage ?? "Transcription failed."
    }
}

private extension DictationRecord {
    var isRetryable: Bool {
        transcriptionState == .failed || transcriptionState == .cancelled
    }
}

struct SettingsView: View {
    @EnvironmentObject private var runtime: AppRuntime
    let onShortcutConfigurationCaptureChanged: (Bool) -> Void
    @State private var apiKey = ""
    @State private var keyFeedback: KeySaveFeedback?
    @State private var isCheckingAPIKey = false
    @State private var newKeyterm = ""
    @State private var message: String?
    @FocusState private var apiKeyFieldFocused: Bool
    @State private var activeShortcutRecorderID: String?

    init(onShortcutConfigurationCaptureChanged: @escaping (Bool) -> Void = { _ in }) {
        self.onShortcutConfigurationCaptureChanged = onShortcutConfigurationCaptureChanged
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
            Section("General") {
                ShortcutRecorderView(
                    title: "Hold to Dictate",
                    identifier: "hold",
                    isEnabled: $runtime.preferences.holdShortcutEnabled,
                    chord: $runtime.preferences.holdShortcut,
                    activeRecorderID: $activeShortcutRecorderID,
                    conflictingChord: runtime.preferences.toggleShortcutEnabled ? runtime.preferences.toggleShortcut : nil,
                    isCaptureAllowed: !runtime.coordinator.phase.isBusy
                )
                ShortcutRecorderView(
                    title: "Hands-free Toggle",
                    identifier: "toggle",
                    isEnabled: $runtime.preferences.toggleShortcutEnabled,
                    chord: $runtime.preferences.toggleShortcut,
                    activeRecorderID: $activeShortcutRecorderID,
                    conflictingChord: runtime.preferences.holdShortcutEnabled ? runtime.preferences.holdShortcut : nil,
                    isCaptureAllowed: !runtime.coordinator.phase.isBusy
                )
                Text("Modifier-only chords are supported. Press Escape while recording a binding to cancel.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at Login", isOn: Binding(
                    get: { runtime.preferences.launchAtLoginRequested },
                    set: { enabled in
                        do { try runtime.coordinator.setLaunchAtLogin(enabled) }
                        catch { message = error.localizedDescription }
                    }
                ))
                Toggle("Show in Menu Bar", isOn: $runtime.preferences.showInMenuBar)
                Toggle("Show app in Dock", isOn: $runtime.preferences.showAppInDock)
                    .accessibilityIdentifier("show-app-in-dock-toggle")
            }
            .onChange(of: activeShortcutRecorderID) { _, activeRecorderID in
                onShortcutConfigurationCaptureChanged(activeRecorderID != nil)
            }
            .onChange(of: runtime.coordinator.phase.isBusy) { _, isBusy in
                if isBusy { activeShortcutRecorderID = nil }
            }
            Section("Feedback") {
                Toggle(
                    "Play recording feedback sounds",
                    isOn: $runtime.preferences.playRecordingFeedbackSounds
                )
                .accessibilityIdentifier("recording-feedback-sounds-toggle")

                Toggle(
                    "Mute other audio while recording",
                    isOn: $runtime.preferences.muteOtherAudioWhileRecording
                )
                .accessibilityIdentifier("mute-other-audio-toggle")
                Text("Other apps keep playing silently and become audible again when recording stops. Calls and notification sounds are also silenced. Scriber never records or saves system audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let status = runtime.coordinator.otherAudioMuteStatus {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(status.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("other-audio-mute-status")
                        Button("Open Privacy & Security") {
                            runtime.coordinator.openSystemAudioPrivacySettings()
                        }
                        .font(.caption)
                    }
                }
            }
            Section("ElevenLabs") {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField(
                        text: $apiKey,
                        prompt: Text(
                            runtime.preferences.apiKeyConfigured
                                ? "Enter a new API key to replace the stored key"
                                : "Paste your ElevenLabs API key"
                        )
                    ) {
                        Text("ElevenLabs API key")
                    }
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .disabled(isCheckingAPIKey)
                        .focused($apiKeyFieldFocused)
                        .onSubmit(submitAPIKey)
                        .id(MainWindowDestination.apiKey)
                    HStack {
                        Button(action: submitAPIKey) {
                            if isCheckingAPIKey {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking…")
                                }
                            } else {
                                Text("Save API Key")
                            }
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSubmitAPIKey)
                        if let keyFeedback {
                            Label(keyFeedback.message, systemImage: keyFeedback.systemImage)
                                .font(.caption)
                                .foregroundStyle(keyFeedback.color)
                                .lineLimit(2)
                                .accessibilityIdentifier("api-key-save-feedback")
                        } else if apiKey.isEmpty {
                            apiKeyStatusLabel
                        }
                        Spacer(minLength: 0)
                    }
                }
                subscriptionUsageView
                    .id(MainWindowDestination.usage)
            }
            Section("Dictation") {
                Picker("Language", selection: $runtime.preferences.languageCode) {
                    Text("Automatic").tag("auto")
                    Text("English").tag("en")
                    Text("Indonesian").tag("id")
                }
                Toggle("Remove filler words and false starts", isOn: $runtime.preferences.noVerbatim)
                HStack {
                    TextField("Name or term", text: $newKeyterm)
                    Button("Add") { addKeyterm() }.disabled(newKeyterm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(runtime.preferences.keyterms, id: \.self) { term in
                    HStack { Text(term); Spacer(); Button { removeKeyterm(term) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain) }
                }
                Text("ElevenLabs applies an additional usage charge when keyterms are sent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dictation History") {
                Toggle(
                    "Delete unused recordings after 30 days",
                    isOn: $runtime.preferences.deletesExpiredRetainedAudio
                )
                .accessibilityIdentifier("delete-expired-audio-toggle")
                Text("Failed and cancelled dictations keep their audio so you can retry them. Transcripts and history entries are always kept; only the unused recording is removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Permissions and Input") {
                PermissionStatusRow(
                    title: "Accessibility",
                    systemImage: "keyboard",
                    allowed: runtime.coordinator.accessibilityGranted
                ) {
                    if !runtime.coordinator.accessibilityGranted {
                        Button("Allow") { runtime.coordinator.refreshPermissions(promptForAccessibility: true) }
                    }
                }
                // The section's first row rather than the `Section`: a scroll
                // target on the Section lands on its header, which a grouped
                // Form insets away from the content it names.
                .id(MainWindowDestination.permissions)

                PermissionStatusRow(
                    title: "Microphone",
                    systemImage: "mic",
                    allowed: runtime.coordinator.microphoneGranted
                ) {
                    microphonePermissionButton
                }
                MicrophonePicker()
                    .id(MainWindowDestination.microphone)
            }
            if let message { Text(message).foregroundStyle(.secondary) }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("settings-view")
            .padding()
            .onAppear {
                apiKey = ""
                runtime.coordinator.refreshPermissions(promptForAccessibility: false)
                applyMainWindowRequest(runtime.coordinator.mainWindowRequest, proxy: proxy)
            }
            .onChange(of: runtime.coordinator.mainWindowRequest) { _, request in
                applyMainWindowRequest(request, proxy: proxy)
            }
            .onChange(of: apiKey) { _, newValue in
                if !newValue.isEmpty { keyFeedback = nil }
            }
            .onDisappear {
                activeShortcutRecorderID = nil
                onShortcutConfigurationCaptureChanged(false)
            }
        }
    }

    private var canSubmitAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCheckingAPIKey
    }

    private func submitAPIKey() {
        guard canSubmitAPIKey else { return }
        Task { await saveKey() }
    }

    private func applyMainWindowRequest(_ request: MainWindowRequest?, proxy: ScrollViewProxy) {
        guard let request else { return }
        switch request.destination {
        case .apiKey:
            proxy.scrollTo(MainWindowDestination.apiKey, anchor: .top)
            DispatchQueue.main.async { apiKeyFieldFocused = true }
        case .usage:
            apiKeyFieldFocused = false
            proxy.scrollTo(MainWindowDestination.usage, anchor: .center)
        case .microphone:
            apiKeyFieldFocused = false
            proxy.scrollTo(MainWindowDestination.microphone, anchor: .center)
        case .permissions:
            apiKeyFieldFocused = false
            // `.top`, not `.center`: this is the last section in the pane, so
            // there is nothing below it to centre against and the scroll view
            // clamps at its end either way.
            proxy.scrollTo(MainWindowDestination.permissions, anchor: .top)
        case .dictation, .settings:
            apiKeyFieldFocused = false
        }
    }

    private func saveKey() async {
        guard !isCheckingAPIKey else { return }
        isCheckingAPIKey = true
        defer { isCheckingAPIKey = false }
        do {
            try await runtime.coordinator.validateAndSaveAPIKey(apiKey)
            keyFeedback = .saved
            apiKey = ""
        } catch {
            keyFeedback = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder private var apiKeyStatusLabel: some View {
        if runtime.preferences.apiKeyConfigured {
            switch runtime.preferences.apiKeyValidity {
            case .valid:
                Label("Verified", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
            case .invalid:
                Label("Invalid", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .unchecked:
                Label("Stored in Login Keychain", systemImage: "shield")
            }
        }
    }

    @ViewBuilder private var subscriptionUsageView: some View {
        if runtime.preferences.apiKeyValidity == .valid {
            if let usage = runtime.preferences.subscriptionUsage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("ElevenLabs credits", systemImage: "gauge.with.dots.needle.33percent")
                        Spacer()
                        Text("\(usage.remainingCredits.formatted()) of \(usage.totalCredits.formatted()) remaining")
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(usage.remainingCredits), total: Double(max(usage.totalCredits, 1)))
                        .tint(usage.remainingCredits == 0 ? .orange : .accentColor)
                    HStack {
                        Text(usage.tier.capitalized + " plan")
                        if let resetAt = usage.resetAt {
                            Text("· Resets \(resetAt.formatted(date: .abbreviated, time: .shortened))")
                        }
                        Text("· Updated \(usage.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        Spacer()
                        Button {
                            Task { await runtime.coordinator.refreshSubscriptionUsage() }
                        } label: {
                            if runtime.coordinator.isRefreshingSubscriptionUsage {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(runtime.coordinator.isRefreshingSubscriptionUsage)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if usage.remainingCredits == 0, usage.canExtendCredits {
                        Text("Included credits are depleted, but ElevenLabs reports that extended usage is available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if runtime.coordinator.subscriptionUsageUnavailable {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Speech-to-Text access verified", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(runtime.coordinator.subscriptionUsageError ?? "Credit usage is unavailable for this API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await runtime.coordinator.refreshSubscriptionUsage() }
                    } label: {
                        if runtime.coordinator.isRefreshingSubscriptionUsage {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Text("Retry Credit Usage")
                        }
                    }
                    .disabled(runtime.coordinator.isRefreshingSubscriptionUsage)
                }
            }
        }
    }

    private func addKeyterm() {
        do {
            let validated = try ScribeClient.validateKeyterms(runtime.preferences.keyterms + [newKeyterm])
            runtime.preferences.keyterms = validated
            newKeyterm = ""
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func removeKeyterm(_ term: String) {
        runtime.preferences.keyterms.removeAll { $0 == term }
    }

    @ViewBuilder private var microphonePermissionButton: some View {
        if !runtime.coordinator.microphoneGranted {
            switch runtime.coordinator.microphonePermissionState {
            case .notDetermined:
                Button("Allow") { Task { await runtime.coordinator.requestMicrophone() } }
            case .denied:
                Button("Open Settings") { runtime.coordinator.openMicrophoneSettings() }
            case .allowed:
                EmptyView()
            }
        }
    }
}

struct OnboardingView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var runtime: AppRuntime
    @State private var apiKey = ""
    @State private var keyFeedback: KeySaveFeedback?
    @State private var isCheckingAPIKey = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Scriber").font(.largeTitle.bold())
                Text("Hold Fn to dictate. Your audio goes only to ElevenLabs, and your history stays on this Mac.")
                    .foregroundStyle(.secondary)
            }
            GroupBox("1. ElevenLabs API key") {
                VStack(alignment: .leading, spacing: 12) {
                    SecureField(
                        runtime.preferences.apiKeyConfigured
                            ? "Enter a new API key to replace the stored key"
                            : "xi-api-key",
                        text: $apiKey
                    )
                        .textFieldStyle(.roundedBorder)
                        .disabled(isCheckingAPIKey)
                        .onSubmit(submitAPIKey)
                    HStack(spacing: 12) {
                        Button(action: submitAPIKey) {
                            if isCheckingAPIKey {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking…")
                                }
                            } else {
                                Text("Save Key")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSubmitAPIKey)

                        if let keyFeedback {
                            Label(keyFeedback.message, systemImage: keyFeedback.systemImage)
                                .font(.caption)
                                .foregroundStyle(keyFeedback.color)
                                .lineLimit(2)
                        } else if apiKey.isEmpty, runtime.preferences.apiKeyConfigured {
                            switch runtime.preferences.apiKeyValidity {
                            case .valid:
                                Label("Verified", systemImage: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                            case .invalid:
                                Label("Invalid", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            case .unchecked:
                                Label("Stored in Login Keychain", systemImage: "shield")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            GroupBox("2. Microphone") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        PermissionLabel(
                            title: "Microphone",
                            systemImage: "mic",
                            allowed: runtime.coordinator.microphoneGranted
                        )
                        Spacer()
                        microphonePermissionButton
                    }

                    MicrophonePicker()

                    if runtime.coordinator.microphoneGranted {
                        VStack(alignment: .leading, spacing: 10) {
                            AudioLevelWaveform(level: runtime.coordinator.microphoneTestLevel)
                                .frame(height: 42)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Label(
                                AudioSignal.isDetected(decibels: runtime.coordinator.microphoneTestLevel)
                                    ? "Audio signal detected"
                                    : "Speak to test your microphone",
                                systemImage: AudioSignal.isDetected(decibels: runtime.coordinator.microphoneTestLevel)
                                    ? "waveform.badge.mic"
                                    : "waveform"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                AudioSignal.isDetected(decibels: runtime.coordinator.microphoneTestLevel)
                                    ? Color.green
                                    : Color.secondary
                            )
                        }
                    }

                    if let microphoneTestError = runtime.coordinator.microphoneTestError {
                        Label(microphoneTestError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            GroupBox("3. Accessibility") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        PermissionLabel(
                            title: "Accessibility",
                            systemImage: "keyboard",
                            allowed: runtime.coordinator.accessibilityGranted
                        )
                        Spacer()
                        if !runtime.coordinator.accessibilityGranted {
                            Button("Allow") { runtime.coordinator.refreshPermissions(promptForAccessibility: true) }
                        }
                    }
                    Text("Accessibility lets Scriber watch global shortcuts and insert text into the app you were using.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "Mute other audio while recording",
                    isOn: $runtime.preferences.muteOtherAudioWhileRecording
                )
                Text("Other apps continue playing silently while you dictate. macOS may ask for System Audio Recording access; Scriber never records or saves that audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Launch Scriber when I log in", isOn: $runtime.preferences.launchAtLoginRequested)
                Text("Defaults: Hold \(runtime.preferences.holdShortcut.displayName) · Toggle \(runtime.preferences.toggleShortcut.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
            HStack {
                Spacer()
                Button("Finish Setup") { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isCheckingAPIKey
                            || !runtime.preferences.apiKeyConfigured
                            || runtime.preferences.apiKeyValidity != .valid
                            || !runtime.coordinator.microphoneGranted
                            || !runtime.coordinator.accessibilityGranted
                    )
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .padding(32)
        .frame(width: 640)
        .onAppear {
            guard !runtime.preferences.onboardingComplete else {
                dismissWindow(id: "onboarding")
                return
            }
            apiKey = ""
            runtime.coordinator.refreshPermissions(promptForAccessibility: false)
            if runtime.coordinator.microphoneGranted { runtime.coordinator.startMicrophoneTest() }
        }
        .onDisappear { runtime.coordinator.stopMicrophoneTest() }
        .onChange(of: runtime.coordinator.microphoneGranted) { _, allowed in
            if allowed {
                runtime.coordinator.startMicrophoneTest()
            } else {
                runtime.coordinator.stopMicrophoneTest()
            }
        }
        .onChange(of: runtime.preferences.audioInputSelection) { _, _ in
            if runtime.coordinator.microphoneGranted { runtime.coordinator.startMicrophoneTest() }
        }
        .onChange(of: apiKey) { _, newValue in
            if !newValue.isEmpty { keyFeedback = nil }
        }
    }

    private var canSubmitAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCheckingAPIKey
    }

    private func submitAPIKey() {
        guard canSubmitAPIKey else { return }
        Task { await saveKey() }
    }

    private func finish() {
        runtime.coordinator.stopMicrophoneTest()
        if runtime.preferences.launchAtLoginRequested {
            do { try runtime.coordinator.setLaunchAtLogin(true) }
            catch { self.error = "Setup finished, but Launch at Login could not be enabled: \(error.localizedDescription)" }
        }
        runtime.preferences.onboardingComplete = true
        runtime.coordinator.startServices()
        dismissWindow(id: "onboarding")
        Task { @MainActor in
            // Let the onboarding window finish closing before restoring the
            // already-created main window to its default Dictation destination.
            await Task.yield()
            runtime.coordinator.openMainWindow()
        }
    }

    private func saveKey() async {
        guard !isCheckingAPIKey else { return }
        isCheckingAPIKey = true
        defer { isCheckingAPIKey = false }
        do {
            try await runtime.coordinator.validateAndSaveAPIKey(apiKey)
            keyFeedback = .saved
            apiKey = ""
            error = nil
        } catch {
            keyFeedback = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder private var microphonePermissionButton: some View {
        if !runtime.coordinator.microphoneGranted {
            switch runtime.coordinator.microphonePermissionState {
            case .notDetermined:
                Button("Allow") { Task { await runtime.coordinator.requestMicrophone() } }
            case .denied:
                Button("Open Settings") { runtime.coordinator.openMicrophoneSettings() }
            case .allowed:
                EmptyView()
            }
        }
    }
}

private struct PermissionLabel: View {
    let title: String
    let systemImage: String
    let allowed: Bool

    var body: some View {
        Label(
            allowed ? "\(title) allowed" : "\(title) required",
            systemImage: allowed ? "checkmark.circle.fill" : systemImage
        )
        .foregroundStyle(allowed ? Color.green : Color.primary)
    }
}

private struct PermissionStatusRow<Actions: View>: View {
    let title: String
    let systemImage: String
    let allowed: Bool
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack {
            PermissionLabel(title: title, systemImage: systemImage, allowed: allowed)
            Spacer()
            actions
        }
    }
}

private struct MicrophonePicker: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        Picker("Input", selection: $runtime.preferences.audioInputSelection) {
            Text("Automatic (System Default)")
                .tag(AudioInputSelection.automatic)
            ForEach(runtime.coordinator.audioInputDevices) { device in
                Text(device.isBuiltIn ? "\(device.name) (Built-in)" : device.name)
                    .tag(AudioInputSelection.device(id: device.id, name: device.name))
            }
            if let unavailableSelection {
                Text("\(unavailableSelection.name) (Unavailable)")
                    .tag(AudioInputSelection.device(id: unavailableSelection.id, name: unavailableSelection.name))
            }
        }
    }

    private var unavailableSelection: (id: String, name: String)? {
        guard case .device(let id, let name) = runtime.preferences.audioInputSelection,
              !runtime.coordinator.audioInputDevices.contains(where: { $0.id == id }) else { return nil }
        return (id, name)
    }
}
