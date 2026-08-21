import AppKit
import SwiftUI

enum OnboardingLayout {
    /// The window is fixed at this size and the scene derives its frame from it,
    /// so every step is laid out against a page that never changes shape. Sitting
    /// between Settings (660×560) and the main window (900×640) keeps setup
    /// recognisably part of the same app.
    static let windowWidth: CGFloat = 660
    static let windowHeight: CGFloat = 700
    static let pageMargin: CGFloat = 40
    /// The single column everything on a step is set in — cards, images, and
    /// prose alike. Two widths is what made captions stop short of the card
    /// above them, with nothing to say why one edge sat inside the other.
    static let contentWidth: CGFloat = windowWidth - pageMargin * 2
    static let footerHeight: CGFloat = 64
    /// What is left for a step once the footer and its rule are taken out. A
    /// step fills it and hangs from the top of it, so its title lands in the
    /// same place on every step rather than moving with the content below it.
    static let pageHeight: CGFloat = windowHeight - footerHeight - 1
    static let cardCornerRadius: CGFloat = 12
}

enum OnboardingStep: Int, CaseIterable, Comparable {
    case welcome
    case apiKey
    case dataUse
    case permissions
    case shortcut
    case tryIt
    case done

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct OnboardingView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var runtime: AppRuntime

    @State private var step: OnboardingStep = .welcome
    /// Which way the last move went, so a step entering from a Back press slides
    /// in from the side it left towards.
    @State private var isAdvancing = true

    // Step-owned state that has to survive the step being scrolled off screen and
    // back, which rules out `@State` inside the step views themselves.
    @State private var apiKey = ""
    @State private var keyFeedback: KeySaveFeedback?
    @State private var isCheckingAPIKey = false
    @State private var activeShortcutRecorderID: String?
    @State private var shortcutConfirmed = false
    @State private var microphoneSignalObserved = false
    @State private var microphoneTestSkipped = false
    @State private var showsDataUseGuide = false
    @State private var tryItText = ""
    @State private var error: String?
    /// Held here rather than in `Preferences`, because nothing is registered
    /// until setup ends: the checkbox is an intention until then, and afterwards
    /// the only honest answer is what macOS reports.
    @State private var launchAtLogin = true
    @State private var didCompleteSetup = false
    @State private var didApplyLaunchAtLogin = false
    @State private var centreShortcutMonitor: Any?
    /// `resumedStep` has to read the credential before the check it kicks off can
    /// answer, so the restore is checked once more when it does.
    @State private var didClampAfterValidation = false

    var body: some View {
        VStack(spacing: 0) {
            page
            Divider()
            footer
        }
        .frame(width: OnboardingLayout.windowWidth, height: OnboardingLayout.windowHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showsDataUseGuide) {
            DataUseGuideSheet { showsDataUseGuide = false }
        }
        .onAppear {
            prepare()
            watchForCentreShortcut()
        }
        .onDisappear {
            runtime.coordinator.stopMicrophoneTest()
            if let centreShortcutMonitor { NSEvent.removeMonitor(centreShortcutMonitor) }
            centreShortcutMonitor = nil
            applyLaunchAtLoginOnce()
        }
        .onChange(of: runtime.coordinator.isCheckingStoredAPIKey) { _, checking in
            guard !checking, !didClampAfterValidation else { return }
            didClampAfterValidation = true
            clampToFirstUnmetStep()
        }
        .onChange(of: step) { _, _ in syncMicrophoneTest() }
        .onChange(of: runtime.coordinator.microphoneGranted) { _, _ in syncMicrophoneTest() }
        .onChange(of: runtime.preferences.audioInputSelection) { _, _ in
            microphoneSignalObserved = false
            syncMicrophoneTest()
        }
        .onChange(of: apiKey) { _, newValue in
            if !newValue.isEmpty { keyFeedback = nil }
        }
    }

    // MARK: - Page

    private var page: some View {
        ZStack {
            currentStep
                .id(step)
                .transition(transition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder private var currentStep: some View {
        switch step {
        case .welcome:
            WelcomeStep()
        case .apiKey:
            APIKeyStep(
                apiKey: $apiKey,
                keyFeedback: $keyFeedback,
                isChecking: $isCheckingAPIKey
            )
        case .dataUse:
            DataUseStep(showsGuide: $showsDataUseGuide)
        case .permissions:
            PermissionsStep(signalObserved: $microphoneSignalObserved) {
                // Only the test is skipped. Accessibility shares this step and
                // is not something this button offers to pass, so the move still
                // goes through the gate.
                microphoneTestSkipped = true
                if canAdvance { goForward() }
            }
        case .shortcut:
            ShortcutStep(
                activeRecorderID: $activeShortcutRecorderID,
                isConfirmed: $shortcutConfirmed
            )
        case .tryIt:
            TryItStep(text: $tryItText)
        case .done:
            DoneStep(launchAtLogin: $launchAtLogin, error: error)
        }
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let entering: Edge = isAdvancing ? .trailing : .leading
        let leaving: Edge = isAdvancing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: entering).combined(with: .opacity),
            removal: .move(edge: leaving).combined(with: .opacity)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        ZStack {
            StepIndicator(step: step)
            HStack(spacing: 12) {
                if step == .welcome {
                    // Nothing else on the welcome step takes focus, so without
                    // this the ring lands here and a quiet secondary control
                    // reads as the one being offered.
                    Button("Set Up Later", action: setUpLater)
                        .buttonStyle(.link)
                        .focusEffectDisabled()
                        .accessibilityIdentifier("onboarding-skip")
                } else {
                    Button("Back", action: goBack)
                        .accessibilityIdentifier("onboarding-back")
                }
                Spacer(minLength: 0)
                Button(primaryTitle, action: goForward)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdvance)
                    .accessibilityIdentifier("onboarding-continue")
            }
        }
        .padding(.horizontal, 24)
        .frame(height: OnboardingLayout.footerHeight)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .tryIt: tryItText.isEmpty ? "Skip" : "Continue"
        case .done: "Done"
        default: "Continue"
        }
    }

    /// Each gate is the thing the step exists to establish, and nothing else.
    private var canAdvance: Bool {
        guard !AppLaunchConfiguration.unlocksOnboardingSteps else { return true }
        return switch step {
        case .apiKey:
            !isCheckingAPIKey
                && !runtime.coordinator.isCheckingStoredAPIKey
                && runtime.preferences.apiKeyConfigured
                && runtime.preferences.apiKeyValidity == .valid
        case .permissions:
            runtime.coordinator.microphoneGranted
                && (microphoneSignalObserved || microphoneTestSkipped)
                && runtime.coordinator.accessibilityGranted
        case .shortcut:
            shortcutConfirmed
        default:
            true
        }
    }

    // MARK: - Navigation

    private func goForward() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        // Setup is over once every decision has been made, and Try it is the
        // first step that needs the real thing running: the shortcut tap refuses
        // to start until setup is complete, so it cannot be demonstrated before
        // this point.
        if next == .tryIt { completeSetup() }
        move(to: next, advancing: true)
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        move(to: previous, advancing: false)
    }

    private func move(to next: OnboardingStep, advancing: Bool) {
        isAdvancing = advancing
        // Written on every move, so a relaunch mid-setup — which granting the
        // microphone invites — knows where it was.
        runtime.preferences.onboardingStep = next.rawValue
        guard !reduceMotion else {
            step = next
            return
        }
        withAnimation(.easeInOut(duration: 0.22)) { step = next }
    }

    // MARK: - Lifecycle

    /// Runs on every appearance, and an appearance is not always a first one:
    /// SwiftUI keeps a `Window` scene's `@State` alive after the window closes,
    /// so a second run of setup starts out holding the first run's answers —
    /// including the step it ended on and the flag saying setup is already
    /// finished. Everything the flow accumulates is cleared here rather than
    /// trusted to be fresh.
    private func prepare() {
        guard !runtime.preferences.onboardingComplete else {
            dismissWindow(id: "onboarding")
            return
        }
        apiKey = ""
        keyFeedback = nil
        isCheckingAPIKey = false
        activeShortcutRecorderID = nil
        shortcutConfirmed = false
        microphoneSignalObserved = false
        microphoneTestSkipped = false
        showsDataUseGuide = false
        tryItText = ""
        error = nil
        didCompleteSetup = false
        didApplyLaunchAtLogin = false
        didClampAfterValidation = false
        // On for a first run, which is the recommendation. A Redo Setup starts
        // from what macOS has, so the step cannot offer to turn on something that
        // is already on — or quietly re-enable what the user has since turned off.
        launchAtLogin = LaunchAtLoginService.state.isOn || !runtime.coordinator.isRedoingSetup
        runtime.coordinator.refreshPermissions(source: .onboarding)
        runtime.coordinator.validateStoredAPIKey()
        step = resumedStep
        syncMicrophoneTest()
    }

    /// Where setup left off, clamped to the first step whose gate is not yet
    /// met. Granting the microphone makes macOS offer to relaunch Scriber, and
    /// coming back to the welcome step after that reads as having lost the
    /// grant. Resuming past an unmet requirement would be the opposite mistake —
    /// a step whose Continue cannot be pressed, above a Back nobody is expecting
    /// to need — so the two are resolved together.
    private var resumedStep: OnboardingStep {
        let stored = OnboardingStep(rawValue: runtime.preferences.onboardingStep) ?? .welcome
        let firstUnmet = OnboardingStep.allCases.first { !isSatisfied($0) } ?? stored
        return min(stored, firstUnmet)
    }

    /// Pulls the flow back if the restore landed past a step that has since
    /// turned out to be unmet. `prepare` can only clamp against what the
    /// credential preferences say at that instant, and the check it starts on the
    /// same line is what decides whether they were telling the truth — so a key
    /// deleted from the Keychain reads as valid for exactly as long as that check
    /// takes. Runs once per appearance: after this, an unmet step is something
    /// the user has caused and not something to be moved away from mid-read.
    private func clampToFirstUnmetStep() {
        guard let firstUnmet = OnboardingStep.allCases.first(where: { !isSatisfied($0) }),
              step > firstUnmet
        else { return }
        move(to: firstUnmet, advancing: false)
    }

    /// Whether a step's gate is already met by what the app can see right now.
    /// Only the steps that ask something of the system can answer: the rest are
    /// decisions, and a decision cannot be recovered from state.
    private func isSatisfied(_ candidate: OnboardingStep) -> Bool {
        switch candidate {
        case .apiKey:
            runtime.preferences.apiKeyConfigured && runtime.preferences.apiKeyValidity == .valid
        case .permissions:
            runtime.coordinator.microphoneGranted && runtime.coordinator.accessibilityGranted
        default:
            true
        }
    }

    /// The microphone is held open only by the step that draws a meter from it.
    /// Left running for the whole of setup it lights the menu bar's recording
    /// indicator on every page, which says Scriber is listening when it has no
    /// reason to be. Try it does not need this: a real dictation opens the input
    /// itself and closes it again.
    private func syncMicrophoneTest() {
        if step == .permissions, runtime.coordinator.microphoneGranted {
            runtime.coordinator.startMicrophoneTest()
        } else {
            runtime.coordinator.stopMicrophoneTest()
        }
    }

    /// Stops Control-C standing in for Enter, and hands the key to the menu
    /// instead — which is where it was always meant to go.
    ///
    /// AppKit resolves Control-C to `NSEnterCharacter` (0x03), the character the
    /// Enter key sends, so the default button answers to it and answers first.
    /// The Window menu's Center never sees ⌃🌐C, though clicking that same item
    /// works. The two keys are only separable before that resolution, where
    /// Enter reports 0x03 with no modifier and Control-C reports "c" with
    /// Control held — which is what this reads.
    ///
    /// Offering the event to the main menu rather than centring the window here
    /// is what makes the shortcut behave exactly like the menu item: same
    /// animation, same resting place. `NSWindow.center` is not that command —
    /// it places a window higher than centre by design, and moves it in one
    /// jump. Anything the menu declines is swallowed, because Control-C is not
    /// a command in this window either way.
    private func watchForCentreShortcut() {
        guard centreShortcutMonitor == nil else { return }
        centreShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.control),
                  !event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "c",
                  let window = event.window,
                  window.title == AppWindowIdentity.onboardingTitle
            else { return event }
            NSApp.mainMenu?.performKeyEquivalent(with: event)
            return nil
        }
    }

    /// Marks setup finished and brings the app's services up. Idempotent: Back
    /// out of Try it and forward into it again, and this runs once.
    private func completeSetup() {
        guard !didCompleteSetup else { return }
        didCompleteSetup = true
        runtime.preferences.onboardingComplete = true
        runtime.coordinator.startServices()
    }

    /// Applied once, on Done or on the window going away — whichever comes
    /// first, so closing setup at Try it still honours the default rather than
    /// silently dropping it.
    private func applyLaunchAtLoginOnce() {
        guard !didApplyLaunchAtLogin else { return }
        didApplyLaunchAtLogin = true
        guard launchAtLogin != LaunchAtLoginService.state.isOn else { return }
        do {
            try runtime.coordinator.setLaunchAtLogin(launchAtLogin)
            // A refusal does not throw. macOS keeps the entry switched off under
            // Background App Activity and reports the old state straight back,
            // which is the same shape Settings detects.
            if launchAtLogin, !runtime.coordinator.launchAtLoginState.isOn {
                error = runtime.coordinator.launchAtLoginState.recoveryAdvice
                    ?? "macOS would not add Scriber to your login items."
            }
        } catch {
            self.error = "Scriber could not be set to launch at login: \(error.localizedDescription)"
        }
    }

    private func setUpLater() {
        completeSetup()
        close()
    }

    private func finish() {
        // Reaching the last step is its own proof that setup is done. Leaving
        // that to the Try it transition alone made Done a button that closed the
        // window and finished nothing whenever that transition had been taken on
        // a previous run of the flow.
        completeSetup()
        // Whether the refusal is already on screen. Setup closes over it the
        // second time Done is pressed rather than trapping someone on a step
        // whose only control refuses to finish.
        let alreadyReported = didApplyLaunchAtLogin
        applyLaunchAtLoginOnce()
        guard error == nil || alreadyReported else { return }
        close()
    }

    private func close() {
        // Both routes here have just finished setup, and a finished setup has no
        // step left to resume. Closing the window with ⌘W deliberately does not
        // come through here: that one is meant to be resumable.
        runtime.preferences.onboardingStep = 0
        runtime.coordinator.stopMicrophoneTest()
        dismissWindow(id: "onboarding")
        Task { @MainActor in
            // Let the setup window finish closing before restoring the
            // already-created main window to its default Dictation destination.
            await Task.yield()
            runtime.coordinator.openMainWindow()
        }
    }
}

/// Page dots. Non-interactive, and announced as one control rather than nine, so
/// VoiceOver reads a position instead of a row of unlabelled circles.
private struct StepIndicator: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { candidate in
                Circle()
                    .fill(candidate == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }
}
