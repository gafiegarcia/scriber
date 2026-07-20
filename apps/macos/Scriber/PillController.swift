@preconcurrency import AppKit
import Combine
import SwiftUI
#if SWIFT_PACKAGE
import ScriberCore
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
    var onOpenAPIKeySettings: (() -> Void)?
    var onOpenUsageSettings: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
}

@MainActor
final class PillController {
    let model = PillModel()
    private let panel: NSPanel
    private let glassView: NSGlassEffectView
    private var autoDismissTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var preferredScreen: NSScreen?
    private var currentPanelSize = NSSize(width: 300, height: 62)
    private var dismissalCountdown: DismissalCountdown?
    private var isHovering = false
    private let minimumHoverExitDismissalDelay: TimeInterval = 1.25
    private let presentationDuration: TimeInterval = 0.18

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 62),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        glassView = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 62))
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // SwiftUI glass only has this transparent panel's empty content to sample.
        // AppKit clear glass can instead refract the window beneath this overlay.
        let hostingView = NSHostingView(rootView: PillView(model: model))
        hostingView.frame = glassView.bounds
        hostingView.autoresizingMask = [.width, .height]
        glassView.autoresizingMask = [.width, .height]
        glassView.style = .clear
        glassView.cornerRadius = currentPanelSize.height / 2
        glassView.tintColor = nil
        glassView.effectIsInteractive = true
        glassView.contentView = hostingView
        panel.contentView = glassView
        model.onHoverChanged = { [weak self] isHovering in self?.setHovering(isHovering) }
    }

    func update(_ phase: AppPhase) {
        clearAutoDismissal()
        guard phase != .idle else {
            isHovering = false
            hide(clearPhaseWhenFinished: true)
            return
        }

        let desiredSize = panelSize(for: phase)
        if desiredSize != currentPanelSize {
            panel.setContentSize(desiredSize)
            currentPanelSize = desiredSize
        }
        glassView.cornerRadius = glassCornerRadius(for: phase, size: desiredSize)
        model.phase = phase
        show()
        if !autoDismissalDisabledForUITesting,
           let delay = dismissalDelay(for: phase) {
            startAutoDismissal(after: delay)
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
        autoDismissTask?.cancel()
        autoDismissTask = nil
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
        autoDismissTask?.cancel()
        autoDismissTask = nil
        dismissalCountdown = nil
        model.dismissalCountdown = nil
    }

    private func scheduleAutoDismissal(after delay: TimeInterval) {
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.finishAutoDismissal()
        }
    }

    private func finishAutoDismissal() {
        clearAutoDismissal()
        isHovering = false
        hide(clearPhaseWhenFinished: false)
    }

    private func dismissalDelay(for phase: AppPhase) -> TimeInterval? {
        switch phase {
        case .pasted:
            1
        case .message:
            1.5
        case .dictationCopied:
            5
        case .apiKeyInvalid, .apiCreditsExhausted, .pasteFailed, .transcriptionFailed:
            6
        default:
            nil
        }
    }

    private func panelSize(for phase: AppPhase) -> NSSize {
        switch phase {
        case .dictationCopied(let text, _):
            copiedResultSize(for: text)
        case .apiKeyInvalid, .apiCreditsExhausted:
            NSSize(width: 470, height: 72)
        case .pasteFailed, .transcriptionFailed:
            NSSize(width: 430, height: 72)
        default:
            NSSize(width: 300, height: 62)
        }
    }

    private func copiedResultSize(for text: String) -> NSSize {
        let width: CGFloat = 560
        let previewFont = NSFont.systemFont(ofSize: 15)
        let previewWidth = width - 44 // Matches copiedResult's horizontal padding.
        let lineHeight = ceil(previewFont.boundingRectForFont.height)
        let measuredPreviewHeight = ceil((text as NSString).boundingRect(
            with: NSSize(width: previewWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: previewFont],
            context: nil
        ).height)
        let previewHeight = min(max(lineHeight, measuredPreviewHeight), lineHeight * 4)

        // The result has four rows, three 14-point gaps, and 18-point vertical
        // insets. Keeping this calculation independent of SwiftUI layout avoids
        // resizing the AppKit host in response to its own layout pass.
        let chromeHeight: CGFloat = 146
        return NSSize(width: width, height: chromeHeight + previewHeight)
    }

    private func show() {
        presentationTask?.cancel()
        presentationTask = nil
        positionPanel()
        guard !panel.isVisible else {
            panel.alphaValue = 1
            return
        }

        panel.alphaValue = shouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        guard !shouldReduceMotion else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = presentationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hide(clearPhaseWhenFinished: Bool) {
        presentationTask?.cancel()
        presentationTask = nil

        guard panel.isVisible, !shouldReduceMotion else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            if clearPhaseWhenFinished { model.phase = .idle }
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = presentationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }
        let duration = presentationDuration
        presentationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            if clearPhaseWhenFinished { model.phase = .idle }
            presentationTask = nil
        }
    }

    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var autoDismissalDisabledForUITesting: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing-persistent-pill")
#else
        false
#endif
    }

    private func glassCornerRadius(for phase: AppPhase, size: NSSize) -> CGFloat {
        if case .dictationCopied = phase { return 24 }
        return size.height / 2
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
            .contentShape(pillShape(for: model.phase))
            .onHover { model.onHoverChanged?($0) }
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
            if case .recording = model.phase {
                statusText
                Spacer(minLength: 8)
                symbol
            } else {
                symbol
                statusText
                Spacer(minLength: 8)
                countdown
                actions
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold))
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
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
            AudioLevelWaveform(level: level, color: .red)
                .frame(width: 58, height: 24)
        case .transcribing:
            ProgressView().controlSize(.small)
        case .pasted, .dictationCopied:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .apiKeyInvalid, .apiCreditsExhausted, .pasteFailed, .transcriptionFailed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        default:
            Image(systemName: "waveform")
        }
    }

    private var title: String {
        switch model.phase {
        case .idle: "Ready"
        case .recording(_, let elapsed, _): "Recording · \(elapsed.formattedTimer)"
        case .transcribing(let attempt, let delay):
            if attempt == 1, delay == nil { "Transcribing…" }
            else { "Retrying \(min(attempt + (delay == nil ? 0 : 1), 3))/3…" }
        case .pasted: "Pasted"
        case .dictationCopied: "Copied"
        case .apiKeyInvalid: "ElevenLabs API key is invalid"
        case .apiCreditsExhausted: "ElevenLabs credits exhausted"
        case .pasteFailed: "Couldn't paste automatically"
        case .transcriptionFailed: "Transcription failed"
        case .message(let value): value
        }
    }

    private var subtitle: String? {
        switch model.phase {
        case .transcribing(_, let delay):
            delay.map { "Trying again in \(Int($0)) seconds" }
        case .apiKeyInvalid: "Add or update the key in Settings"
        case .apiCreditsExhausted: "Add credits or wait for your quota to reset"
        case .dictationCopied(_, let message), .pasteFailed(let message), .transcriptionFailed(let message): message
        default: nil
        }
    }

    @ViewBuilder private var actions: some View {
        switch model.phase {
        case .apiKeyInvalid:
            Button("Update Key") { model.onOpenAPIKeySettings?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            dismissButton
        case .apiCreditsExhausted:
            Button("View Usage") { model.onOpenUsageSettings?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            dismissButton
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
            .accessibilityLabel("Dismiss")
    }
}

private func pillShape(for phase: AppPhase) -> AnyShape {
    if case .dictationCopied = phase {
        AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    } else {
        AnyShape(Capsule())
    }
}

struct AudioLevelWaveform: View {
    let level: Float
    var color: Color = .accentColor
    private let sampleCount = 18
    @State private var samples = Array(repeating: 0.0, count: 18)

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let barWidth = max(1, (proxy.size.width - spacing * CGFloat(sampleCount - 1)) / CGFloat(sampleCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(samples.indices, id: \.self) { index in
                    let sample = samples[index]
                    Capsule()
                        .fill(color.opacity(sample == 0 ? 0.35 : 0.95))
                        .frame(width: barWidth, height: max(2, proxy.size.height * sample))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { append(level) }
        .onChange(of: level) { _, newLevel in append(newLevel) }
        .animation(.easeOut(duration: 0.1), value: samples)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(AudioSignal.isDetected(decibels: level) ? "Signal detected" : "No signal")
    }

    private func append(_ decibels: Float) {
        samples.removeFirst()
        samples.append(AudioSignal.normalized(decibels: decibels))
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
