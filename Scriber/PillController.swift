@preconcurrency import AppKit
import Combine
import SwiftUI
import os
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

/// How long Cancel and Confirm take to arrive, and with them the status text and
/// the meter sliding inward to make room. SwiftUI owns all of it: the capsule
/// around them does not move, so there is nothing for this to keep in step with.
///
/// Do not: give the capsule an animated width again and expect this to match it.
/// Measured on the locked-recording widening back when it had one — the window
/// covered 77% of its 80-point growth in a single frame and finished in 67ms,
/// while the status text was still travelling 33ms after it had stopped. Both
/// asked for this duration and neither delivered it, and the text swung 15.5
/// points left to settle 3 points from where it began. Handing SwiftUI the
/// capsule's width so they could share a clock was built and reverted:
/// `NSGlassEffectView` re-renders its blur synchronously on every frame written
/// to it, which drops the pill to roughly 5fps.
private let pillResizeDuration: TimeInterval = 0.15

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
    var onRecover: (() -> Void)?
    /// Drives the offline pill's Retry, which cannot work without a route.
    @Published var hasNetworkRoute = true
    var onCancelRecording: (() -> Void)?
    var onConfirmRecording: (() -> Void)?
    var onDismiss: (() -> Void)?
}

/// The pointer region that decides hover, and the one thing in the pill whose
/// frame does not follow the capsule.
///
/// Platform: AppKit rebuilds a view's tracking areas when its geometry changes
/// and re-evaluates them against a pointer that has not moved, which can deliver
/// an exit. While the capsule's own width answered to hover, that exit shrank
/// the capsule, which changed the geometry, which delivered another — 28 resizes
/// in 1.43 seconds, measured, with the pointer motionless and never less than a
/// point and a half inside the drawn capsule. This frame is set to the widest
/// the phase can reach and then left alone, so the loop has nothing to feed on.
///
/// Known and unfixed: an `NSTrackingArea` is a rectangle and the capsule is not,
/// so a sliver at each rounded end reads as hovered while the pointer is
/// visibly outside the drawn shape — up to the 26-point corner radius at the
/// very top and bottom rows, and nothing at all across the middle. Clicks there
/// still reach the application underneath, because those are routed by the
/// rendered pixels rather than by this. Closing it means dropping tracking areas
/// for hand-rolled mouse tracking and a capsule hit test, which is a great deal
/// of machinery for a sliver nobody has complained about.
@MainActor
private final class PillHoverRegion: NSView {
    var onHoverChanged: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // `activeAlways`: the pill floats over other people's apps, so hover has
        // to work while Scriber is not the active application.
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }

    /// Never takes a click. Tracking areas are independent of hit testing, so
    /// this reports the pointer without standing between it and the capsule's
    /// own controls, or the application underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}

/// Platform: a borderless panel with a clear background already lets a click on
/// a fully transparent pixel through to the application underneath — the window
/// server routes by what was rendered, not by the window's frame. The panel is
/// far wider than the capsule now, so that margin is points rather than a
/// hairline; this hit test states the rule in Scriber's own code rather than
/// leaving a 90-point band of someone else's window depending on it.
@MainActor
private final class PillRootView: NSView {
    var capsuleFrame: () -> NSRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `hitTest` is handed a point in the superview's coordinates; every
        // frame this compares it against is in this view's own.
        let local = superview.map { convert(point, from: $0) } ?? point
        guard capsuleFrame().contains(local) else { return nil }
        return super.hitTest(point)
    }
}

@MainActor
final class PillController {
    let model = PillModel()
    private let panel: NSPanel
    private let glassView: NSGlassEffectView
    private var autoDismissTask: Task<Void, Never>?
    private var preferredScreen: NSScreen?
    private var currentPanelSize = PillController.capsulePanelSize
    private var dismissalCountdown: DismissalCountdown?
    private let minimumHoverExitDismissalDelay: TimeInterval = 1.25
    private let hoverRegion = PillHoverRegion()

    /// Every capsule phase shares this one panel, so the window neither resizes
    /// nor recentres while a recording is on screen and the capsule moves inside
    /// it instead. Measured: the widest capsule is the 460-point no-signal
    /// notice and the tallest is the 60-point two-line ones, plus `glassMargin`
    /// on all four sides. `panelSize(for:pillSize:)` grows it rather than let a
    /// widened capsule overflow, so this staying in step is not load-bearing.
    ///
    /// The message boxes keep their own sizes and still resize the window. That
    /// crossing changes the corner radius along with the frame, so it is never
    /// animated and has nothing to gain from a shared panel.
    private static let capsulePanelSize = NSSize(width: 476, height: 76)

    /// Every one-liner is this wide, whatever it says and whichever controls it
    /// carries. Nothing in the family resizes, so nothing inside one is ever
    /// moved by the capsule and by SwiftUI at once: the status text moves inward
    /// to make room for Cancel and Confirm while the meter gives up the width
    /// they take, and that is the only movement there is.
    ///
    /// A floor rather than a fixed size: a one-liner is never narrower than this
    /// and grows only if its text needs more. Recording, transcribing, "Copied"
    /// and "Canceled" all sit exactly on it, which is what keeps the recording
    /// pill from changing width when its controls arrive — without them it wants
    /// 146, and 146 is under the floor.
    ///
    /// Measured on a SwiftUI harness — an `NSHostingView` of each row, read for
    /// its `fittingSize` — because every attempt to add this row up by hand has
    /// come out wrong. Two rows set the floor:
    ///
    /// - `.recording` locked with the pointer on it, so both controls show,
    ///   fits in **160 points plus whatever the meter takes**. The meter is the
    ///   row's flexible child, so this width decides its size: 204 leaves it the
    ///   44 that `AudioLevelWaveform`'s pill minimum is set to.
    /// - `.transcribing`, which shows Cancel unconditionally, fits at **201**
    ///   with "Transcribing…" in it. Every "Retrying n/3…" is a point narrower.
    ///
    /// Do not: derive either number by adding up insets, gaps and control sizes.
    /// That arithmetic has been done three times and given 150, then 138, then
    /// 150 again for a row the harness measures at 160 — the negative padding
    /// that pulls the controls onto the capsule's curve does not come off the
    /// row's width the way it reads as though it should. Measure the row.
    ///
    /// Do not: trust a remembered figure for the meter's width with both
    /// controls showing. It has been recorded here as 82 and as 72, and at the
    /// 222 this used to be it was 62. The 136 recorded for the no-controls case
    /// is right, and is the one number here that has always reproduced.
    private static let oneLinerWidth: CGFloat = 204

    /// A message pill's width less its text: insets, the leading glyph, the
    /// dismissal countdown, and the gaps between them. Too small shows as a
    /// cramped message rather than a wrong one, since the text is measured
    /// against what is left.
    private static let messageChromeWidth: CGFloat = 110

    private static let log = Logger(subsystem: "com.gafiegarcia.scriber", category: "dictation")
    private let glassMargin: CGFloat = 8

    private(set) var isPresented = false

    init() {
        let initialPillSize = NSSize(width: 280, height: 52)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: PillController.capsulePanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        glassView = NSGlassEffectView(frame: NSRect(
            x: (PillController.capsulePanelSize.width - initialPillSize.width) / 2,
            y: 8,
            width: initialPillSize.width,
            height: initialPillSize.height
        ))
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
        let rootView = PillRootView(frame: NSRect(origin: .zero, size: PillController.capsulePanelSize))
        let hostingView = NSHostingView(rootView: PillView(model: model))
        hostingView.frame = glassView.bounds
        hostingView.autoresizingMask = [.width, .height]
        // Do not: give the glass an autoresizing mask. The panel is wider than
        // the capsule now, so a mask would stretch the glass to fill it; every
        // capsule frame here is set deliberately.
        glassView.style = .regular
        glassView.cornerRadius = glassView.bounds.height / 2
        // `tintColor` is unused: it never composited anything visible against a
        // SwiftUI-hosted `contentView` on this OS build, at any alpha up to 0.9.
        // `PillView` paints its own tint layer into that hosted content instead.
        // macOS 26 renders the same glass without the interactive response.
        // SwiftUI's `.interactive()` is not a substitute, for the reason above.
        if #available(macOS 27.0, *) {
            glassView.effectIsInteractive = true
        }
        glassView.contentView = hostingView
        rootView.addSubview(glassView)
        rootView.addSubview(hoverRegion)
        rootView.capsuleFrame = { [weak glassView] in glassView?.frame ?? .zero }
        panel.contentView = rootView
        hoverRegion.frame = glassView.frame
        hoverRegion.onHoverChanged = { [weak self] isHovering in self?.setHovering(isHovering) }
    }

    /// `autoDismiss` is disabled when the caller owns the pill's lifetime, so a
    /// controller countdown and a caller countdown of the same length cannot race
    /// and produce a hide immediately followed by a show.
    func update(_ phase: AppPhase, autoDismiss: Bool = true) {
        clearAutoDismissal()
        guard phase != .idle else {
            // Do not: dismiss twice for one dictation. A dictation reaches idle
            // once when the transcript arrives and again when delivery confirms,
            // a few hundred milliseconds later. The second has a pill already
            // gone to take down, and running it again clears the phase out from
            // under whatever the first dismissal handed on to.
            guard isPresented else { return }
            resetHovering()
            hide(clearPhaseWhenFinished: true)
            return
        }

        // Mount the new phase's content *before* the layout below, never after.
        //
        // `applyLayout` ends in a forced layout pass. Run while the hosted view
        // still holds the outgoing phase, that pass sizes the glass against
        // content about to be replaced, and the taller content wins: crossing
        // from the recovery panel to `.transcribing` asked for a 296x68 panel and
        // settled at 296x80, a capsule's radius on a box twelve points too tall.
        // Recording never showed it because its own content is the short one.
        model.phase = phase
        applyLayout(for: phase)
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
        // Every transition, with where the pointer was and what the capsule held
        // at the time. An exit reported while `inside` is true is the
        // tracking-area loop `PillHoverRegion` defends against, and no reading of
        // the accessibility tree can show it.
        let pointer = NSEvent.mouseLocation
        let capsule = panel.convertToScreen(glassView.frame)
        Self.log.notice("pill hover=\(hovering, privacy: .public) pointer=\(Int(pointer.x), privacy: .public),\(Int(pointer.y), privacy: .public) capsule=\(Int(capsule.minX), privacy: .public)-\(Int(capsule.maxX), privacy: .public) inside=\(capsule.contains(pointer), privacy: .public)")
        // Only the model changes. Hovering no longer touches the pill's geometry
        // at all: Cancel arrives inside a capsule that holds its width, which is
        // what stopped the region under the pointer moving because of the pointer.
        model.isHovering = hovering
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
        // same dwell. Either is news the user did not ask for and has to read, and
        // 1.5 seconds was long enough to see something flash and not long enough
        // to read it.
        case .dictationCopied, .dictationBlockedBySecureField:
            5
        // A History retry reaching the clipboard is the result that was asked for,
        // so this one is a receipt rather than news. It is read at a glance, and
        // holding it as long as an apology makes a deliberate action feel slow.
        case .transcriptCopied:
            1.5
        case .cancelledTranscript, .noInternetConnection, .noSpeechDetected, .retryFoundNoWords:
            5
        case .credentialsUnusable, .transcriptionFailed, .noAudioSignal:
            6
        // Longer than the recovery panel it shares a shape with, because of when
        // it arrives: the device dies mid-sentence, so this appears while the
        // shortcut is still held and the user is still talking. Five seconds is
        // gone before they have finished the sentence and looked up.
        case .inputDisconnected:
            8
        // As long as the longest, because it is the only notice carrying a
        // message nobody wrote for this pill — the system's own account of a
        // failure, up to four lines of it, with no row in History to read it
        // from afterwards. A notice that has grown to be read needs time to be.
        case .dictationFailed:
            8
        default:
            nil
        }
    }

    private func pillSize(for phase: AppPhase) -> NSSize {
        switch phase {
        case .dictationCopied(let text, _), .dictationBlockedBySecureField(let text, _):
            copiedResultSize(for: text)
        case .dictationFailed(let message):
            dictationFailureSize(for: message)
        case .cancelledTranscript, .noInternetConnection:
            NSSize(width: 430, height: 104)
        // Measured: its body is 486 points against the 394 the panel leaves, so
        // it is the one recovery offer whose caption wraps. 16 points taller than
        // the others, for the second line.
        case .inputDisconnected:
            NSSize(width: 430, height: 120)
        // One width for both, because they are the same notice in two subjects
        // and appear in the same place — at different widths the second reads as
        // the pill having moved rather than as a different notice, which is the
        // reasoning the copied-result box and the failure box already share.
        //
        // Measured: the widest of the four rows is "ElevenLabs credits exhausted"
        // beside View Credits at 421x44, and the narrowest is "Permissions
        // required" beside Review at 338. 430 clears the widest with a real gap
        // rather than pinning the spacer at its floor. Their captions never fitted
        // any of it — "Enable Accessibility so Scriber can detect global shortcuts
        // and insert text." wanted 390 points against the 245 left beside Review,
        // and lost 144 of them to the ellipsis.
        //
        // Do not: count either row's chrome without the countdown ring. Both
        // phases dwell, so both draw one, and leaving out its 16 points and the
        // 10 beside them is what produced a 320 that still truncated.
        case .permissionsRequired, .credentialsUnusable:
            NSSize(width: 430, height: 52)
        // The most crowded pill Scriber draws: glyph, title, caption, countdown,
        // Retry, See History and a dismiss. Its caption is the one Scriber does
        // not write — a failed request supplies it — so this takes the widest
        // pill there is rather than a width fitted to today's messages.
        //
        // Measured: 460 is the ceiling, not a preference. `panelSize` holds the
        // capsule panel at 476 and the glass sits `glassMargin` inside each edge,
        // so 460 is the widest pill that leaves the window alone; past it the
        // panel grows and a capsule phase resizes the window, which
        // `PRODUCT_SPEC.md` forbids. At 440 the row truncated captions Scriber
        // writes itself — "ElevenLabs rate limit exceeded" wants 448.
        case .transcriptionFailed:
            NSSize(width: 460, height: 60)
        case .noSpeechDetected, .noAudioSignal:
            NSSize(width: 460, height: 60)
        // Measured: "No words detected" is 120 points, and this is the only
        // one-liner carrying both a countdown and a dismiss control — 148 points
        // of chrome against the 110 the message pills need.
        case .retryFoundNoWords:
            NSSize(width: 270, height: 52)
        case .message(let text):
            NSSize(width: messageWidth(for: text), height: 52)
        default:
            NSSize(width: Self.oneLinerWidth, height: 52)
        }
    }

    /// A message is whatever the caller passed, and two of them are long enough
    /// to have been truncated by the fixed width this replaces — the unavailable
    /// microphone names a device, so its length is not even known here.
    private func messageWidth(for text: String) -> CGFloat {
        let measured = ceil((text as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        ).width)
        return min(max(Self.oneLinerWidth, Self.messageChromeWidth + measured), 460)
    }

    private func panelSize(for phase: AppPhase, pillSize: NSSize) -> NSSize {
        let fitted = NSSize(
            width: pillSize.width + glassMargin * 2,
            height: pillSize.height + glassMargin * 2
        )
        guard phase.pillShapeStyle == .capsule else { return fitted }
        return NSSize(
            width: max(Self.capsulePanelSize.width, fitted.width),
            height: max(Self.capsulePanelSize.height, fitted.height)
        )
    }

    /// The capsule is centred across the panel and sits `glassMargin` up from its
    /// bottom edge, so the 52-point one-liners and the 60-point two-liners rest
    /// on the same line above the screen's edge rather than being centred against
    /// each other.
    private func glassFrame(pillSize: NSSize, panelSize: NSSize) -> NSRect {
        NSRect(
            x: ((panelSize.width - pillSize.width) / 2).rounded(),
            y: glassMargin,
            width: pillSize.width,
            height: pillSize.height
        )
    }

    private func applyLayout(for phase: AppPhase) {
        let desiredPillSize = pillSize(for: phase)
        let desiredPanelSize = panelSize(for: phase, pillSize: desiredPillSize)
        let desiredGlassFrame = glassFrame(pillSize: desiredPillSize, panelSize: desiredPanelSize)
        let desiredCornerRadius = CGFloat(phase.pillCornerRadius(height: Double(desiredPillSize.height)))

        // Captured before anything below mutates them, so the settled line at the
        // end can report on the same resize this one describes.
        let didResizePanel = desiredPanelSize != currentPanelSize
        let wasVisible = panel.isVisible

        // Recording republishes its phase ten times a second to move the waveform
        // and tick the timer, so most calls here change no geometry at all.
        // Writing the destination anyway costs two forced layout passes per tick.
        if !didResizePanel,
           glassView.cornerRadius == desiredCornerRadius,
           glassView.frame == desiredGlassFrame {
            return
        }

        if didResizePanel {
            // The panel only changes size crossing between the shared capsule
            // panel and a message box, and that crossing is never animated: the
            // corner radius changes with the frame and the two have to land
            // together. Every one of them is logged with what was asked for and
            // what the panel and glass actually held a moment before — a shape
            // rendering outside its glass for one pass cannot be read from the
            // accessibility tree, and reading the source has twice pointed at the
            // wrong cause.
            Self.log.notice("pill panel resize to=\(phase.logLabel, privacy: .public) panel=\(Int(self.currentPanelSize.width), privacy: .public)x\(Int(self.currentPanelSize.height), privacy: .public)->\(Int(desiredPanelSize.width), privacy: .public)x\(Int(desiredPanelSize.height), privacy: .public) glass=\(Int(self.glassView.frame.width), privacy: .public)x\(Int(self.glassView.frame.height), privacy: .public) radius=\(Int(self.glassView.cornerRadius), privacy: .public)->\(Int(desiredCornerRadius), privacy: .public)")
            let desiredPanelFrame = NSRect(
                x: panel.frame.midX - desiredPanelSize.width / 2,
                y: panel.frame.minY,
                width: desiredPanelSize.width,
                height: desiredPanelSize.height
            )
            applyingGeometryInstantly {
                if panel.isVisible {
                    panel.setFrame(desiredPanelFrame, display: true)
                } else {
                    panel.setContentSize(desiredPanelSize)
                }
                glassView.frame = desiredGlassFrame
            }
            currentPanelSize = desiredPanelSize
        } else {
            applyingGeometryInstantly { glassView.frame = desiredGlassFrame }
        }

        // The region that decides hover is the capsule, exactly. Every one-liner
        // is one width, so this never moves while a recording is on screen.
        hoverRegion.frame = desiredGlassFrame

        // Apply the destination glass geometry directly on every phase change.
        // Relying on layout alone can leave NSGlassEffectView rendering the
        // fixed copied-result radius after its host shrinks back to a capsule.
        applyingGeometryInstantly {
            panel.contentView?.layoutSubtreeIfNeeded()
            glassView.layoutSubtreeIfNeeded()
            glassView.cornerRadius = desiredCornerRadius
        }

        if didResizePanel {
            // Where the pill actually ended up, against what it asked for. The
            // line before this one records only what it held going in, which
            // cannot tell a frame that was never set from one that was set and
            // then put back — the difference this pair was added to catch.
            //
            // `hosted` is the field that matters: it is the height of the
            // SwiftUI content inside the glass, and a `hosted` that disagrees
            // with the glass is this bug returning. On an animated resize the
            // frame is still travelling when this runs, so `final` reporting the
            // outgoing size there is expected and not a fault.
            Self.log.notice(
                "pill settled to=\(phase.logLabel, privacy: .public) wasVisible=\(wasVisible, privacy: .public) asked=\(Int(desiredPanelSize.width), privacy: .public)x\(Int(desiredPanelSize.height), privacy: .public) final=\(Int(self.panel.frame.width), privacy: .public)x\(Int(self.panel.frame.height), privacy: .public) glass=\(Int(self.glassView.frame.width), privacy: .public)x\(Int(self.glassView.frame.height), privacy: .public) hosted=\(Int(self.glassView.contentView?.frame.height ?? -1), privacy: .public) radius=\(Int(self.glassView.cornerRadius), privacy: .public)"
            )
        }
    }

    /// Applies geometry with layer actions off, so nothing here can be caught
    /// interpolating a frame or a corner radius that was meant to land at once.
    ///
    /// This is not what fixed the crooked capsule — that was the ordering in
    /// `update` — and it has never been measured to change anything on its own.
    /// It is kept because the rule it enforces is the one `PRODUCT_SPEC` states:
    /// a crossing between the message box and the capsule is never animated.
    private func applyingGeometryInstantly(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    private func copiedResultSize(for text: String) -> NSSize {
        // The two boxes Scriber draws share one width. They appear in the same
        // place minutes apart, and at different widths the second reads as the
        // window having moved rather than as a different notice.
        let width: CGFloat = 430
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

        // The result has four rows, three 10-point gaps, 14-point vertical
        // insets, and the 4 points the transcript takes above itself to separate
        // it from the caption that belongs to the title. Keeping this calculation
        // independent of SwiftUI layout avoids resizing the AppKit host in
        // response to its own layout pass.
        let chromeHeight: CGFloat = 120
        return NSSize(width: width, height: chromeHeight + previewHeight)
    }

    /// The same measured-height treatment `copiedResultSize` gives a transcript,
    /// for the one notice whose text nobody wrote to fit: the system's own
    /// account of a failed recording, with no History row to read it from later.
    ///
    /// Measured: at this width the message column is 394 points, which holds the
    /// worst real string in two lines — a Cocoa permission failure with its
    /// recovery suggestion appended runs about 760 points. Four lines is the cap
    /// rather than the expectation: the width is set by how a short message looks,
    /// since nearly every one of these is a single line.
    private func dictationFailureSize(for message: String) -> NSSize {
        let width: CGFloat = 430
        let messageFont = NSFont.systemFont(ofSize: 11)
        let messageWidth = width - 36 // Matches dictationFailure's horizontal padding.
        let lineHeight = ceil(messageFont.boundingRectForFont.height)
        let measured = ceil((message as NSString).boundingRect(
            with: NSSize(width: messageWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: messageFont],
            context: nil
        ).height)

        // Two rows, one 10-point gap, and 11-point vertical insets. No button
        // row: this pill offers no recovery, which is what it exists to say.
        let chromeHeight: CGFloat = 54
        return NSSize(width: width, height: chromeHeight + min(max(lineHeight, measured), lineHeight * 4))
    }

    /// Every pill is put on screen at once. Scriber animates nothing here, and
    /// what fading remains is AppKit's own for a utility-window panel, which is
    /// left to AppKit deliberately: the rule being kept is that Scriber never
    /// delays the user, not that no pixel ever fades.
    private func show() {
        isPresented = true
        positionPanel()
        guard !panel.isVisible else {
            panel.alphaValue = 1
            return
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// The pill always leaves at once. Dismissal is the moment the user turns
    /// back to their own work, so nothing here is worth waiting behind.
    private func hide(clearPhaseWhenFinished: Bool) {
        isPresented = false
        panel.orderOut(nil)
        panel.alphaValue = 1
        if clearPhaseWhenFinished { model.phase = .idle }
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
    @Environment(\.colorScheme) private var colorScheme

    /// `NSGlassEffectView.tintColor` never composited anything visible against
    /// this view's hosted content, at any alpha up to 0.9. This layer paints the
    /// tint directly instead, weaker than the toast stack's 0.18 since a toast is
    /// glass over Scriber's own window while this pill floats over whatever the
    /// user is working in.
    ///
    /// Light glass washes an accent out, so it takes roughly twice the alpha to
    /// separate green from amber there. This tracks the system appearance, which
    /// is not the same as what the pill happens to be floating over: a light-mode
    /// pill sitting on dark content gets the heavier tint anyway, and no API
    /// reports the backdrop's luminance.
    private static let darkTintAlpha: CGFloat = 0.07
    private static let lightTintAlpha: CGFloat = 0.15
    /// Faint over a light background is the accepted cost: raising this to satisfy
    /// light overwhelms the rim on dark before it helps.
    private static let specularAlpha: CGFloat = 0.18

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { tintLayer.clipShape(pillShape(for: model.phase)) }
            .overlay { specularHighlight }
            // The frame above is a maximum, not a size: content taller than the
            // pill still expands past it, and the background and rim are drawn to
            // that larger frame rather than to the glass behind it. Shrinking into
            // a smaller phase gave the content one layout pass to decide the
            // height, which drew the shape below the panel's bottom edge.
            .clipShape(pillShape(for: model.phase))
            // Do not: hang a tap gesture on this. The pill's surface triggers
            // nothing — see the rule in `PRODUCT_SPEC.md`. The shape stays because
            // it is what keeps the pill's own controls and its selectable text
            // hit-testing against the capsule rather than its bounding rectangle.
            .contentShape(pillShape(for: model.phase))
    }

    private var tintAlpha: CGFloat {
        colorScheme == .dark ? Self.darkTintAlpha : Self.lightTintAlpha
    }

    @ViewBuilder private var tintLayer: some View {
        if let accent = model.phase.pillTone.accent {
            accent.opacity(tintAlpha)
        }
    }

    /// Neither `NSGlassEffectView` nor SwiftUI's `Glass` exposes a specular rim to
    /// switch on, so the pill paints its own, following Apple's glass: the top and
    /// bottom edges carry the light and the sides stay clear. The half-point
    /// padding keeps the centred stroke inside the glass edge, which would
    /// otherwise clip its outer half away.
    private var specularHighlight: some View {
        pillShape(for: model.phase)
            .stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(Self.specularAlpha), location: 0),
                        .init(color: .white.opacity(0), location: 0.35),
                        .init(color: .white.opacity(0), location: 0.65),
                        .init(color: .white.opacity(Self.specularAlpha), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .padding(0.5)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .dictationCopied(let text, let message):
            copiedResult(text: text, message: message, symbol: "checkmark.circle.fill")
        case .dictationBlockedBySecureField(let text, let message):
            // Same heading as an ordinary copied result, because the same thing
            // happened: the transcript is on the clipboard. The lock, the amber
            // tint and the caption carry what is different. The title row is the
            // narrowest in the panel — it shares with the icon, countdown and
            // dismiss button, leaving about 293 points against the caption's 394 —
            // so detail belongs in the caption, where there is room for it.
            copiedResult(text: text, message: message, symbol: "lock.fill")
        case .cancelledTranscript:
            cancellationRecovery
        case .noInternetConnection:
            noInternetRecovery
        case .inputDisconnected:
            inputDisconnectionRecovery
        case .dictationFailed(let message):
            dictationFailure(message: message)
        default:
            compactStatus
        }
    }

    /// No Retry, no See History: nothing was kept, so there is no row to open and
    /// nothing to transcribe again. The message gets the whole width instead —
    /// it is the only account of this failure the user will ever see, and it is
    /// selectable because copying it into a bug report is what it is for.
    private func dictationFailure(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(toneAccent)
                Text("Dictation failed")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 6)
                countdown
                dismissButton
            }

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var compactStatus: some View {
        HStack(spacing: 10) {
            // A dictation in flight lays out from its Cancel control and puts its
            // indicator on the trailing edge, so the status text starts at the
            // same point whether the dictation is still recording or already
            // transcribing, and Cancel does not move as one becomes the other.
            if model.phase.isBusy {
                if model.phase.showsCancelControl(isHovering: model.isHovering) {
                    recordingControl(
                        systemImage: "xmark",
                        label: "Cancel dictation",
                        edge: .leading,
                        action: { model.onCancelRecording?() }
                    )
                }
                // Measured: "10:00" is 38.1 points and every shorter time is
                // 29.8, so a 40-point slot holds them all. Without it the pill's
                // floor is set by the widest time and every shorter one leaves
                // the difference sitting in the row.
                statusText.frame(width: isRecording ? 40 : nil, alignment: .leading)
                if isRecording {
                    // No Spacer: the meter takes the room the controls are not
                    // using, so the pill keeps one width either way and the space
                    // beside the timer stays a gap rather than becoming a hole.
                    symbol
                } else {
                    Spacer(minLength: 6)
                    symbol
                }
                if model.phase.showsConfirmRecordingControl {
                    recordingControl(
                        systemImage: "checkmark",
                        label: "Finish recording",
                        edge: .trailing,
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
            reduceMotion ? nil : .easeInOut(duration: pillResizeDuration),
            value: model.phase.showsCancelControl(isHovering: model.isHovering)
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: pillResizeDuration),
            value: model.phase.showsConfirmRecordingControl
        )
    }

    /// The outward pull is deliberate. The capsule's rounded end is a circle of
    /// the pill's half-height — 26 points — so a 28-point control shares its
    /// centre only when its outer edge sits 12 points from the pill's, and the
    /// row's own inset is 18. The 6 points come off the outer side alone: the
    /// gap between a control and the element beside it stays at the row's
    /// spacing, which is what keeps the status text where it was.
    private func recordingControl(
        systemImage: String,
        label: String,
        edge: HorizontalEdge,
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
        .padding(edge == .leading ? .leading : .trailing, -6)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityDetail ?? "")
    }

    private var isRecording: Bool {
        if case .recording = model.phase { return true }
        return false
    }

    /// The recording pill shows a timer and nothing else, so VoiceOver is told
    /// what the pill is rather than being handed four digits.
    private var accessibilityTitle: String {
        if case .recording = model.phase { return "Recording" }
        return title
    }

    /// Read when the element is focused rather than announced as it changes, so
    /// a timer that ticks every second never talks over anything.
    private var accessibilityDetail: String? {
        guard case .recording(_, let elapsed, _) = model.phase else { return subtitle }
        return elapsed.formattedTimer
    }

    private var cancellationRecovery: some View {
        recoveryOffer(
            title: "Recover canceled dictation?",
            body: "Recover pastes it wherever your cursor is now.",
            actionTitle: "Recover",
            isActionEnabled: true,
            action: { model.onRecover?() }
        )
    }

    /// The same offer the cancelled dictation makes, for a recording that never
    /// went out. Retry is dead until this Mac has a route again: pressing a
    /// button that cannot possibly work is a worse answer than one that says so.
    private var noInternetRecovery: some View {
        recoveryOffer(
            title: "No internet connection",
            body: "Your recording is saved. Retry once you are back online.",
            actionTitle: "Retry",
            isActionEnabled: model.hasNetworkRoute,
            action: { model.onRetry?() }
        )
    }

    /// The device went away mid-dictation. Recover, not a name of its own: the
    /// button does what the cancelled dictation's does, and one action under two
    /// names is the inconsistency, not the shared word.
    private var inputDisconnectionRecovery: some View {
        recoveryOffer(
            title: "Microphone disconnected",
            body: "Everything recorded up to that point is saved. Recover pastes it wherever your cursor is now.",
            actionTitle: "Recover",
            isActionEnabled: true,
            symbol: "exclamationmark.triangle.fill",
            action: { model.onRecover?() }
        )
    }

    /// - Parameter symbol: drawn ahead of the title, in the phase's own tone.
    ///   Only the tinted offer carries one; the neutral two would be marking a
    ///   recording that is waiting intact as something to worry about.
    private func recoveryOffer(
        title: String,
        body: String,
        actionTitle: String,
        isActionEnabled: Bool,
        symbol: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(toneAccent)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                countdown
                dismissButton
            }

            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Spacer()
                Button(actionTitle, action: action)
                    .disabled(!isActionEnabled)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("See History") { model.onOpen?() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private func copiedResult(text: String, message: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
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
                // The caption above belongs to the title and the transcript does
                // not, so the transcript takes more air than the row gap gives.
                // Counted in `copiedResultSize`'s chrome — change both together.
                .padding(.top, 4)
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
            AudioLevelWaveform(level: level, presentation: .pill)
        case .transcribing:
            ProgressView().controlSize(.small)
        case .dictationCopied, .transcriptCopied:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(toneAccent)
        case .dictationBlockedBySecureField:
            Image(systemName: "lock.fill").foregroundStyle(toneAccent)
        case .noSpeechDetected, .retryFoundNoWords, .noAudioSignal:
            Image(systemName: "mic.slash.fill").foregroundStyle(toneAccent)
        case .permissionsRequired, .credentialsUnusable, .transcriptionFailed:
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
        // The timer alone. A red level meter running beside a stopwatch inside
        // the dictation app's own pill does not need to be told it is recording,
        // and the word cost 73 points of a pill that floats over the user's work.
        // `PillView`'s accessibility label carries it for VoiceOver.
        case .recording(_, let elapsed, _): elapsed.formattedTimer
        case .transcribing(let attempt, let delay):
            if attempt == 1, delay == nil { "Transcribing…" }
            else { "Retrying \(min(attempt + (delay == nil ? 0 : 1), 3))/3…" }
        // Only `.transcriptCopied` reaches this: `.dictationCopied` always renders
        // expanded and titles itself there. The two say different things on
        // purpose — a History retry reaching the clipboard is the intended result,
        // so this one must not read like the apology the expanded pill is making.
        case .dictationCopied, .transcriptCopied: "Copied"
        case .dictationBlockedBySecureField: "Copied"
        case .cancelledTranscript: "You can recover your canceled dictation"
        case .noInternetConnection: "No internet connection"
        // Never drawn from here either — `.inputDisconnected` renders as the
        // recovery panel, which titles itself.
        case .inputDisconnected: "Microphone disconnected"
        case .permissionsRequired: "Permissions required"
        case .credentialsUnusable(let readiness): readiness.title
        case .transcriptionFailed: "Transcription failed"
        // Never drawn from here — `.dictationFailed` renders expanded and titles
        // itself there — but the switch is exhaustive so that a phase added later
        // cannot slip past it.
        case .dictationFailed: "Dictation failed"
        case .noSpeechDetected, .retryFoundNoWords: "No words detected"
        case .noAudioSignal: "No sound from the microphone"
        case .message(let value): value
        }
    }

    /// Neither the permission nor the credential pill carries one. Their captions
    /// said what their titles and buttons already do — Review opens Settings on
    /// the tab naming the missing permission, and "ElevenLabs API key is missing"
    /// leaves nothing for a second line to add — and both were too long to fit
    /// beside that button anyway. The window's own banner still carries the full
    /// message, which is where it is read.
    private var subtitle: String? {
        switch model.phase {
        case .cancelledTranscript: "Recover pastes it wherever your cursor is now"
        case .dictationCopied(_, let message), .dictationBlockedBySecureField(_, let message),
             .transcriptionFailed(let message): message
        // Keep these short: the compact pill gives its subtitle one line and
        // truncates, and these phases also carry a countdown, an action, and a
        // dismiss control on the same row. The cause goes here; the fix is the
        // button. Keep the two distinct — sound arriving with no words in it is a
        // different problem from no sound arriving.
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
                Button("View Credits") { model.onOpenUsageSettings?() }
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
        // No recovery to offer — the input it would send you to is not what was
        // wrong — but still a way out that is not a keystroke.
        case .retryFoundNoWords:
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
