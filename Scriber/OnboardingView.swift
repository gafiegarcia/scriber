import AppKit
import SwiftUI

enum OnboardingLayout {
    /// The window is fixed at this size and the scene derives its frame from it,
    /// so every step is laid out against a page that never changes shape. Sitting
    /// between Settings (660×560) and the main window (900×640) keeps setup
    /// recognisably part of the same app.
    static let windowWidth: CGFloat = 760
    static let windowHeight: CGFloat = 620
    /// Text and cards are held to this, so a line of prose never runs the full
    /// width of the window and stops being readable.
    static let contentWidth: CGFloat = 520
    static let footerHeight: CGFloat = 64
    /// What is left for a step once the footer and its rule are taken out. A
    /// step fills it and centres itself in it, so a short step sits in the
    /// middle of the window rather than clinging to the top of it.
    static let pageHeight: CGFloat = windowHeight - footerHeight - 1
    static let cardCornerRadius: CGFloat = 12
    static let heroSize: CGFloat = 68
}

enum OnboardingStep: Int, CaseIterable, Comparable {
    case welcome
    case apiKey
    case dataUse
    case microphone
    case accessibility
    case shortcut
    case muteAudio
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

    var body: some View {
        VStack(spacing: 0) {
            page
            Divider()
            footer
        }
        .frame(width: OnboardingLayout.windowWidth, height: OnboardingLayout.windowHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if showsDataUseGuide {
                DataUseGuideOverlay { showsDataUseGuide = false }
            }
        }
        .onAppear(perform: prepare)
        .onDisappear {
            runtime.coordinator.stopMicrophoneTest()
            applyLaunchAtLoginOnce()
        }
        .onChange(of: runtime.coordinator.microphoneGranted) { _, allowed in
            if allowed {
                runtime.coordinator.startMicrophoneTest()
            } else {
                runtime.coordinator.stopMicrophoneTest()
            }
        }
        .onChange(of: runtime.preferences.audioInputSelection) { _, _ in
            microphoneSignalObserved = false
            if runtime.coordinator.microphoneGranted { runtime.coordinator.startMicrophoneTest() }
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
        case .microphone:
            MicrophoneStep(signalObserved: $microphoneSignalObserved) {
                microphoneTestSkipped = true
                goForward()
            }
        case .accessibility:
            AccessibilityStep()
        case .shortcut:
            ShortcutStep(
                activeRecorderID: $activeShortcutRecorderID,
                isConfirmed: $shortcutConfirmed
            )
        case .muteAudio:
            MuteAudioStep()
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
                } else if step != .done {
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
                && runtime.preferences.apiKeyConfigured
                && runtime.preferences.apiKeyValidity == .valid
        case .microphone:
            runtime.coordinator.microphoneGranted && (microphoneSignalObserved || microphoneTestSkipped)
        case .accessibility:
            runtime.coordinator.accessibilityGranted
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
        guard !reduceMotion else {
            step = next
            return
        }
        withAnimation(.easeInOut(duration: 0.22)) { step = next }
    }

    // MARK: - Lifecycle

    private func prepare() {
        guard !runtime.preferences.onboardingComplete else {
            dismissWindow(id: "onboarding")
            return
        }
        apiKey = ""
        // On for a first run, which is the recommendation. A Redo Setup starts
        // from what macOS has, so the step cannot offer to turn on something that
        // is already on — or quietly re-enable what the user has since turned off.
        launchAtLogin = LaunchAtLoginService.state.isOn || !runtime.coordinator.isRedoingSetup
        runtime.coordinator.refreshPermissions(source: .onboarding)
        if runtime.coordinator.microphoneGranted { runtime.coordinator.startMicrophoneTest() }
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
        } catch {
            self.error = "Scriber could not be set to launch at login: \(error.localizedDescription)"
        }
    }

    private func setUpLater() {
        completeSetup()
        close()
    }

    private func finish() {
        applyLaunchAtLoginOnce()
        close()
    }

    private func close() {
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
