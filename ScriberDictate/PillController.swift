@preconcurrency import AppKit
import Combine
import SwiftUI
#if SWIFT_PACKAGE
import ScriberDictateCore
#endif

struct DismissalCountdown: Equatable {
    let startedAt: Date?
    let remainingAtStart: TimeInterval
    let duration: TimeInterval

    var isPaused: Bool { startedAt == nil }

    func remaining(at date: Date) -> TimeInterval {
        guard let startedAt else { return remainingAtStart }
        return max(0, remainingAtStart - date.timeIntervalSince(startedAt))
    }

    func remainingFraction(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining(at: date) / duration))
    }

    func paused(at date: Date) -> DismissalCountdown {
        DismissalCountdown(startedAt: nil, remainingAtStart: remaining(at: date), duration: duration)
    }

    func resumed(at date: Date, minimumRemaining: TimeInterval) -> DismissalCountdown {
        DismissalCountdown(
            startedAt: date,
            remainingAtStart: max(remaining(at: date), minimumRemaining),
            duration: duration
        )
    }
}

@MainActor
final class PillModel: ObservableObject {
    @Published var phase: AppPhase = .idle
    @Published var dismissalCountdown: DismissalCountdown?
    var onCopy: (() -> Void)?
    var onOpen: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
}

@MainActor
final class PillController {
    let model = PillModel()
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?
    private var preferredScreen: NSScreen?
    private var currentPanelSize = NSSize(width: 300, height: 62)
    private var dismissalCountdown: DismissalCountdown?
    private var isHovering = false
    private let minimumHoverExitDismissalDelay: TimeInterval = 1.25

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 62),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: PillView(model: model))
        model.onHoverChanged = { [weak self] isHovering in self?.setHovering(isHovering) }
    }

    func update(_ phase: AppPhase) {
        clearAutoDismissal()
        let desiredSize = panelSize(for: phase)
        if desiredSize != currentPanelSize {
            panel.setContentSize(desiredSize)
            currentPanelSize = desiredSize
        }
        model.phase = phase
        switch phase {
        case .idle:
            isHovering = false
            panel.orderOut(nil)
        default:
            show()
            if let delay = dismissalDelay(for: phase) { startAutoDismissal(after: delay) }
        }
    }

    func setPreferredScreen(_ screen: NSScreen?) {
        preferredScreen = screen
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        guard dismissalCountdown != nil else { return }
        hovering ? pauseAutoDismissal() : resumeAutoDismissal()
    }

    private func startAutoDismissal(after delay: TimeInterval) {
        let countdown = DismissalCountdown(startedAt: .now, remainingAtStart: delay, duration: delay)
        dismissalCountdown = countdown
        model.dismissalCountdown = countdown
        guard !isHovering else {
            pauseAutoDismissal()
            return
        }
        scheduleAutoDismissal(after: delay)
    }

    private func pauseAutoDismissal() {
        hideTask?.cancel()
        hideTask = nil
        guard let dismissalCountdown else { return }
        let paused = dismissalCountdown.paused(at: .now)
        self.dismissalCountdown = paused
        model.dismissalCountdown = paused
    }

    private func resumeAutoDismissal() {
        guard let dismissalCountdown else { return }
        let resumed = dismissalCountdown.resumed(at: .now, minimumRemaining: minimumHoverExitDismissalDelay)
        self.dismissalCountdown = resumed
        model.dismissalCountdown = resumed
        scheduleAutoDismissal(after: resumed.remainingAtStart)
    }

    private func clearAutoDismissal() {
        hideTask?.cancel()
        hideTask = nil
        dismissalCountdown = nil
        model.dismissalCountdown = nil
    }

    private func scheduleAutoDismissal(after delay: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.finishAutoDismissal()
        }
    }

    private func finishAutoDismissal() {
        clearAutoDismissal()
        isHovering = false
        panel.orderOut(nil)
    }

    private func dismissalDelay(for phase: AppPhase) -> TimeInterval? {
        switch phase {
        case .pasted:
            1
        case .message:
            1.5
        case .dictationCopied:
            5
        case .pasteFailed, .transcriptionFailed:
            6
        default:
            nil
        }
    }

    private func panelSize(for phase: AppPhase) -> NSSize {
        switch phase {
        case .dictationCopied:
            NSSize(width: 560, height: 230)
        case .pasteFailed, .transcriptionFailed:
            NSSize(width: 430, height: 72)
        default:
            NSSize(width: 300, height: 62)
        }
    }

    private func show() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = preferredScreen ?? NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.midX - panel.frame.width / 2
        let y = frame.minY + 18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct PillView: View {
    @ObservedObject var model: PillModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
            .onHover { model.onHoverChanged?($0) }
            .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .dictationCopied(let text, let message):
            copiedResult(text: text, message: message)
        default:
            compactStatus
        }
    }

    private var compactStatus: some View {
        HStack(spacing: 12) {
            symbol
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            countdown
            actions
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func copiedResult(text: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Copied")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 8)
                countdown
                dismissButton
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            HStack {
                Spacer()
                Button("Open") { model.onOpen?() }
                    .controlSize(.regular)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    @ViewBuilder private var countdown: some View {
        if let dismissalCountdown = model.dismissalCountdown {
            DismissalCountdownView(countdown: dismissalCountdown)
        }
    }

    @ViewBuilder private var symbol: some View {
        switch model.phase {
        case .recording(_, _, let level):
            Circle().fill(.red).frame(width: 12, height: 12).scaleEffect(1 + CGFloat(max(0, level + 60)) / 160)
        case .transcribing:
            ProgressView().controlSize(.small)
        case .pasted, .dictationCopied:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .pasteFailed, .transcriptionFailed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        default:
            Image(systemName: "waveform")
        }
    }

    private var title: String {
        switch model.phase {
        case .idle: "Ready"
        case .recording(let mode, let elapsed, _): mode == .held ? "Recording · \(elapsed.formattedTimer)" : "Hands-free · \(elapsed.formattedTimer)"
        case .transcribing(let attempt, let delay):
            if attempt == 1, delay == nil { "Transcribing…" }
            else { "Retrying \(min(attempt + (delay == nil ? 0 : 1), 3))/3…" }
        case .pasted: "Pasted"
        case .dictationCopied: "Copied"
        case .pasteFailed: "Couldn't paste automatically"
        case .transcriptionFailed: "Transcription failed"
        case .message(let value): value
        }
    }

    private var subtitle: String? {
        switch model.phase {
        case .transcribing(_, let delay):
            delay.map { "Trying again in \(Int($0)) seconds" }
        case .dictationCopied(_, let message), .pasteFailed(let message), .transcriptionFailed(let message): message
        default: nil
        }
    }

    @ViewBuilder private var actions: some View {
        switch model.phase {
        case .pasteFailed:
            Button("Copy") { model.onCopy?() }.buttonStyle(.borderedProminent).controlSize(.small)
            Button("Open") { model.onOpen?() }.controlSize(.small)
            dismissButton
        case .transcriptionFailed:
            Button("Retry") { model.onRetry?() }.buttonStyle(.borderedProminent).controlSize(.small)
            Button("Open") { model.onOpen?() }.controlSize(.small)
            dismissButton
        default:
            EmptyView()
        }
    }

    private var dismissButton: some View {
        Button { model.onDismiss?() } label: { Image(systemName: "xmark") }
            .buttonStyle(.plain)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
    }
}

private struct DismissalCountdownView: View {
    let countdown: DismissalCountdown

    var body: some View {
        TimelineView(.animation) { context in
            let fraction = countdown.remainingFraction(at: context.date)
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .opacity(countdown.isPaused ? 0.55 : 1)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

private extension TimeInterval {
    var formattedTimer: String {
        let seconds = Int(self)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
