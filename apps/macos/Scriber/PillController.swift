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
    @Published var isHovering = false
    var onOpen: (() -> Void)?
    var onOpenAPIKeySettings: (() -> Void)?
    var onOpenUsageSettings: (() -> Void)?
    var onOpenPermissionSettings: (() -> Void)?
    var onOpenInputSettings: (() -> Void)?
    var onRetry: (() -> Void)?
    var onUndo: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onConfirmRecording: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onDefaultAction: (() -> Void)?
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
    private var currentPanelSize = NSSize(width: 316, height: 78)
    private var dismissalCountdown: DismissalCountdown?
    private var keepsPanelCenterForCurrentUpdate = false
    private var isResizingPanel = false
    private var panelResizeGeneration = 0
    private let minimumHoverExitDismissalDelay: TimeInterval = 1.25
    private let presentationDuration: TimeInterval = 0.18
    private let glassMargin: CGFloat = 8

    private(set) var isPresented = false

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 316, height: 78),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        glassView = NSGlassEffectView(frame: NSRect(x: 8, y: 8, width: 300, height: 62))
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // SwiftUI glass only has this transparent panel's empty content to sample.
        // AppKit glass can instead sample the window beneath this overlay.
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 316, height: 78))
        let hostingView = NSHostingView(rootView: PillView(model: model))
        hostingView.frame = glassView.bounds
        hostingView.autoresizingMask = [.width, .height]
        glassView.autoresizingMask = [.width, .height]
        glassView.style = .regular
        glassView.cornerRadius = glassView.bounds.height / 2
        // `tintColor` is unused: it never composited anything visible against a
        // SwiftUI-hosted `contentView` on this OS build, at any alpha up to 0.9.
        // `PillView` paints its own tint layer into that hosted content instead.
        glassView.effectIsInteractive = true
        glassView.contentView = hostingView
        rootView.addSubview(glassView)
        panel.contentView = rootView
        model.onHoverChanged = { [weak self] isHovering in self?.setHovering(isHovering) }
    }

    /// `autoDismiss` is disabled when the caller owns the pill's lifetime, so a
    /// controller countdown and a caller countdown of the same length cannot race
    /// and produce a hide immediately followed by a show.
    func update(_ phase: AppPhase, autoDismiss: Bool = true) {
        clearAutoDismissal()
        guard phase != .idle else {
            resetHovering()
            hide(clearPhaseWhenFinished: true)
            return
        }

        keepsPanelCenterForCurrentUpdate = false
        applyLayout(for: phase)
        model.phase = phase
        show()
        if autoDismiss,
           !autoDismissalDisabledForUITesting,
           let delay = dismissalDelay(for: phase) {
            startAutoDismissal(after: delay)
        }
    }

    func setPreferredScreen(_ screen: NSScreen?) {
        preferredScreen = screen
    }

    func dismiss() {
        clearAutoDismissal()
        resetHovering()
        hide(clearPhaseWhenFinished: false)
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != model.isHovering else { return }
        model.isHovering = hovering
        if case .recording(.held, _, _) = model.phase {
            applyLayout(for: model.phase, forceAnimated: true)
        }
        guard dismissalCountdown != nil else { return }
        hovering ? pauseAutoDismissal() : resumeAutoDismissal()
    }

    /// A pill that reappears while the pointer happens to sit elsewhere must
    /// never inherit a stale hovering state from before it was last hidden.
    private func resetHovering() {
        model.isHovering = false
    }

    private func startAutoDismissal(after delay: TimeInterval) {
        let countdown = DismissalCountdown(startedAt: .now, remainingAtStart: delay, duration: delay)
        dismissalCountdown = countdown
        model.dismissalCountdown = countdown
        guard !model.isHovering else {
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
        resetHovering()
        hide(clearPhaseWhenFinished: false)
    }

    private func dismissalDelay(for phase: AppPhase) -> TimeInterval? {
        switch phase {
        case .message:
            1.5
        case .permissionsRequired:
            8
        // Both forms of "your text is on the clipboard, not in your app" get the
        // same dwell. The compact one used to inherit `.message`'s 1.5 seconds,
        // which was long enough to see something flash and not long enough to read
        // it.
        case .dictationCopied, .transcriptCopied:
            5
        case .cancelledTranscript, .credentialsUnusable, .transcriptionFailed,
             .noSpeechDetected, .noAudioSignal:
            6
        default:
            nil
        }
    }

    private func pillSize(for phase: AppPhase) -> NSSize {
        switch phase {
        case .recording(let mode, _, _):
            NSSize(width: mode == .locked ? 360 : (model.isHovering ? 320 : 280), height: 52)
        case .dictationCopied(let text, _):
            copiedResultSize(for: text)
        case .cancelledTranscript:
            NSSize(width: 430, height: 104)
        case .permissionsRequired:
            NSSize(width: 450, height: 60)
        case .credentialsUnusable:
            NSSize(width: 430, height: 60)
        case .transcriptionFailed:
            NSSize(width: 390, height: 60)
        case .noSpeechDetected, .noAudioSignal:
            NSSize(width: 460, height: 60)
        default:
            NSSize(width: 280, height: 52)
        }
    }

    private func panelSize(for pillSize: NSSize) -> NSSize {
        NSSize(
            width: pillSize.width + glassMargin * 2,
            height: pillSize.height + glassMargin * 2
        )
    }

    private func applyLayout(for phase: AppPhase, forceAnimated: Bool = false) {
        let desiredPillSize = pillSize(for: phase)
        let desiredPanelSize = panelSize(for: desiredPillSize)
        let desiredGlassFrame = NSRect(
            x: glassMargin,
            y: glassMargin,
            width: desiredPillSize.width,
            height: desiredPillSize.height
        )
        let desiredCornerRadius = CGFloat(phase.pillCornerRadius(height: Double(desiredPillSize.height)))

        // Recording republishes its phase ten times a second to move the waveform and
        // tick the timer, so most calls here change no geometry at all. Writing the
        // destination anyway costs two forced layout passes per tick, and mid-resize it
        // lands the animation's own target straight onto the glass, ending the animation
        // a tenth of a second in: the capsule snaps to full width inside a panel still
        // growing around it, and the panel clips whatever overhangs its right edge.
        if desiredPanelSize == currentPanelSize, glassView.cornerRadius == desiredCornerRadius {
            if isResizingPanel { return }
            if glassView.frame == desiredGlassFrame { return }
        }

        if desiredPanelSize != currentPanelSize {
            if panel.isVisible {
                let desiredPanelFrame = NSRect(
                    x: panel.frame.midX - desiredPanelSize.width / 2,
                    y: panel.frame.minY,
                    width: desiredPanelSize.width,
                    height: desiredPanelSize.height
                )
                let animatesConfirmExpansion = model.phase.showsConfirmRecordingControl == false
                    && phase.showsConfirmRecordingControl

                if !shouldReduceMotion && (forceAnimated || animatesConfirmExpansion) {
                    // Only the update()/show() pairing consumes this note, so only set it
                    // when this call is part of that pairing. A hover-driven resize
                    // (forceAnimated) never calls show(), so leaving it set here would
                    // dangle until some later, unrelated show() call reads it.
                    if !forceAnimated {
                        keepsPanelCenterForCurrentUpdate = true
                    }
                    panelResizeGeneration += 1
                    let generation = panelResizeGeneration
                    isResizingPanel = true
                    // Known and unfixed: AppKit interpolates the panel and SwiftUI
                    // interpolates its contents, so anything whose position both of
                    // them contribute to lands the difference between the two engines
                    // as a small correction at the end. The status text is the visible
                    // one: it owes 38 points right to Cancel's insertion and 20 left
                    // to the panel recentring under it.
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = presentationDuration
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        panel.animator().setFrame(desiredPanelFrame, display: false)
                        glassView.animator().frame = desiredGlassFrame
                    }, completionHandler: { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, generation == self.panelResizeGeneration else { return }
                            self.isResizingPanel = false
                        }
                    })
                } else {
                    // A resize already in flight keeps driving the panel after a plain
                    // setter writes the new geometry, so the superseded animation wins and
                    // the panel settles at the outgoing phase's size. Retargeting the
                    // animator over zero seconds ends it; the direct set that follows
                    // guarantees the frame synchronously, since `show()` reads it back in
                    // the same turn to recentre the panel.
                    if isResizingPanel {
                        panelResizeGeneration += 1
                        isResizingPanel = false
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0
                            panel.animator().setFrame(desiredPanelFrame, display: true)
                            glassView.animator().frame = desiredGlassFrame
                        }
                    }
                    panel.setFrame(desiredPanelFrame, display: true)
                    glassView.frame = desiredGlassFrame
                }
            } else {
                panel.setContentSize(desiredPanelSize)
                glassView.frame = desiredGlassFrame
            }
            currentPanelSize = desiredPanelSize
        } else {
            glassView.frame = desiredGlassFrame
        }

        // Apply the destination glass geometry directly on every phase change.
        // Relying on autoresizing alone can leave NSGlassEffectView rendering the
        // fixed copied-result radius after its host shrinks back to a capsule.
        panel.contentView?.layoutSubtreeIfNeeded()
        glassView.layoutSubtreeIfNeeded()
        glassView.cornerRadius = desiredCornerRadius
    }

    private func copiedResultSize(for text: String) -> NSSize {
        let width: CGFloat = 480
        let previewFont = NSFont.systemFont(ofSize: 14)
        let previewWidth = width - 36 // Matches copiedResult's horizontal padding.
        let lineHeight = ceil(previewFont.boundingRectForFont.height)
        let measuredPreviewHeight = ceil((text as NSString).boundingRect(
            with: NSSize(width: previewWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: previewFont],
            context: nil
        ).height)
        let previewHeight = min(max(lineHeight, measuredPreviewHeight), lineHeight * 4)

        // The result has four rows, three 10-point gaps, and 14-point vertical
        // insets. Keeping this calculation independent of SwiftUI layout avoids
        // resizing the AppKit host in response to its own layout pass.
        let chromeHeight: CGFloat = 116
        return NSSize(width: width, height: chromeHeight + previewHeight)
    }

    private func show() {
        isPresented = true
        presentationTask?.cancel()
        presentationTask = nil
        if !keepsPanelCenterForCurrentUpdate { positionPanel() }
        keepsPanelCenterForCurrentUpdate = false
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
        isPresented = false
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

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = preferredScreen ?? NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.midX - panel.frame.width / 2
        let y = frame.minY + 18 - glassMargin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct PillView: View {
    @ObservedObject var model: PillModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `NSGlassEffectView.tintColor` never composited anything visible against
    /// this view's hosted content, at any alpha up to 0.9. This layer paints the
    /// tint directly instead, weaker than the toast stack's 0.18 since a toast is
    /// glass over Scriber's own window while this pill floats over whatever the
    /// user is working in.
    private static let tintAlpha: CGFloat = 0.07

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { tintLayer.clipShape(pillShape(for: model.phase)) }
            .contentShape(pillShape(for: model.phase))
            .onTapGesture { if hasDefaultAction { model.onDefaultAction?() } }
            // Declarative rather than an `NSCursor` push/pop pair: the phase can
            // change while the pointer is still inside the pill, and a manual
            // stack cannot stay balanced across that.
            .pointerStyle(hasDefaultAction ? .link : nil)
            .onHover { model.onHoverChanged?($0) }
    }

    @ViewBuilder private var tintLayer: some View {
        if let accent = model.phase.pillTone.accent {
            accent.opacity(Self.tintAlpha)
        }
    }

    /// The pill is presented whenever this view is on screen, so the phase alone
    /// decides. Buttons inside still win the hit test; this only covers the body
    /// around them.
    private var hasDefaultAction: Bool {
        model.phase.pillDefaultAction(isPresented: true) != .none
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .dictationCopied(let text, let message):
            copiedResult(text: text, message: message)
        case .cancelledTranscript:
            cancellationRecovery
        default:
            compactStatus
        }
    }

    private var compactStatus: some View {
        HStack(spacing: 10) {
            if case .recording = model.phase {
                if model.phase.showsCancelRecordingControl(isHovering: model.isHovering) {
                    recordingControl(
                        systemImage: "xmark",
                        label: "Cancel recording",
                        action: { model.onCancelRecording?() }
                    )
                }
                statusText
                Spacer(minLength: 6)
                symbol
                if model.phase.showsConfirmRecordingControl {
                    recordingControl(
                        systemImage: "checkmark",
                        label: "Finish recording",
                        action: { model.onConfirmRecording?() }
                    )
                }
            } else {
                symbol
                statusText
                Spacer(minLength: 6)
                countdown
                actions
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: model.phase.showsCancelRecordingControl(isHovering: model.isHovering)
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: model.phase.showsConfirmRecordingControl
        )
    }

    private func recordingControl(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .transition(.scale(scale: 0.72).combined(with: .opacity))
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var cancellationRecovery: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(toneAccent)
                Text("Recover cancelled transcript?")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                countdown
                dismissButton
            }

            Text("The recording is saved and ready to transcribe.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Spacer()
                Button("Undo") { model.onUndo?() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("See History") { model.onOpen?() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private func copiedResult(text: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(toneAccent)
                Text("Copied to clipboard")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 6)
                countdown
                dismissButton
            }

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            HStack {
                Spacer()
                Button("See History") { model.onOpen?() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
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
        case .dictationCopied, .transcriptCopied:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(toneAccent)
        case .noSpeechDetected, .noAudioSignal:
            Image(systemName: "mic.slash.fill").foregroundStyle(toneAccent)
        case .cancelledTranscript, .permissionsRequired, .credentialsUnusable,
             .transcriptionFailed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(toneAccent)
        default:
            Image(systemName: "waveform")
        }
    }

    /// Which glyph appears is still per phase; only its colour comes from the
    /// outcome, so a glyph and the glass behind it can never disagree.
    private var toneAccent: Color { model.phase.pillTone.accent ?? .primary }

    private var title: String {
        switch model.phase {
        case .idle: "Ready"
        case .recording(_, let elapsed, _): "Recording · \(elapsed.formattedTimer)"
        case .transcribing(let attempt, let delay):
            if attempt == 1, delay == nil { "Transcribing…" }
            else { "Retrying \(min(attempt + (delay == nil ? 0 : 1), 3))/3…" }
        // Only `.transcriptCopied` reaches this: `.dictationCopied` always renders
        // expanded and titles itself there. The two say different things on
        // purpose — a History retry reaching the clipboard is the intended result,
        // so this one must not read like the apology the expanded pill is making.
        case .dictationCopied, .transcriptCopied: "Copied"
        case .cancelledTranscript: "You can recover your cancelled transcript"
        case .permissionsRequired: "Permissions required"
        case .credentialsUnusable(let readiness): readiness.title
        case .transcriptionFailed: "Transcription failed"
        case .noSpeechDetected: "No words detected"
        case .noAudioSignal: "No sound from the microphone"
        case .message(let value): value
        }
    }

    private var subtitle: String? {
        switch model.phase {
        case .transcribing(_, let delay):
            delay.map { "Trying again in \(Int($0)) seconds" }
        case .credentialsUnusable(let readiness): readiness.recoveryMessage
        case .cancelledTranscript: "We noticed you cancelled your transcription"
        case .permissionsRequired(let missing):
            PermissionReadiness(missingPermissions: missing).recoveryMessage
        case .dictationCopied(_, let message), .transcriptionFailed(let message): message
        // Kept short deliberately: the compact pill gives its subtitle one line
        // and truncates, and these phases also carry a countdown, an action, and
        // a dismiss control on the same row. The cause goes here; the fix is the
        // button.
        //
        // These two no longer say the same thing. Sound reaching the recorder and
        // no words coming back is a different problem from no sound arriving at
        // all, and the old copy blamed a muted microphone for both — which was
        // actively wrong in the case where audio did arrive.
        case .noSpeechDetected: "No recognisable words in the recording"
        case .noAudioSignal: "Check the selected input and its volume"
        default: nil
        }
    }

    @ViewBuilder private var actions: some View {
        switch model.phase {
        case .permissionsRequired:
            Button("Review") { model.onOpenPermissionSettings?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            dismissButton
        case .credentialsUnusable(let readiness):
            if readiness.resolvesInUsageSettings {
                Button("View Usage") { model.onOpenUsageSettings?() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button("Update Key") { model.onOpenAPIKeySettings?() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            dismissButton
        case .transcriptionFailed:
            Button("Retry") { model.onRetry?() }.buttonStyle(.borderedProminent).controlSize(.small)
            Button("See History") { model.onOpen?() }.controlSize(.small)
            dismissButton
        case .noSpeechDetected, .noAudioSignal:
            Button("Check Input") { model.onOpenInputSettings?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            dismissButton
        default:
            EmptyView()
        }
    }

    private var dismissButton: some View {
        Button { model.onDismiss?() } label: { Image(systemName: "xmark") }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .accessibilityLabel("Dismiss")
    }
}

private func pillShape(for phase: AppPhase) -> AnyShape {
    switch phase.pillShapeStyle {
    case .capsule:
        AnyShape(Capsule())
    case .roundedRectangle:
        AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
