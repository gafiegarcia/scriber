import AppKit
import SwiftUI

// MARK: - Shared page chrome

/// The shape every setup step takes: a title, a sentence, and the controls that
/// step owns — ranged left in a column that is centred in the page.
///
/// Keep the text ranged left: a centred sentence that wraps leaves a ragged last
/// line, fixable only by rewording each string until it happens to fit, which
/// holds for one window and one font. Centring the column is what keeps a short
/// step out of the top corner of a half-empty page.
struct OnboardingPage<Content: View>: View {
    let title: String
    let subtitle: LocalizedStringKey?
    /// A second sentence, set as its own line rather than left to wrap. Used
    /// where the two halves are alternatives and reading them as one paragraph
    /// is what makes them hard to tell apart.
    var subtitleDetail: LocalizedStringKey? = nil
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            // Title, sentence and controls travel as one block, centred in the
            // page. Pinning the title holds it still between steps but strands
            // every short step's content against the bottom of a half-empty page.
            // Only the column is centred; its contents stay ranged left.
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.title.bold())
                        // Announced as a heading rather than as another line of
                        // text, so VoiceOver can move between steps by heading
                        // instead of reading each page from the top.
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle { prose(subtitle) }
                    if let subtitleDetail { prose(subtitleDetail) }
                }
                content
            }
            // Set here rather than on each block of prose. It descends to
            // every `Text` below, so a step cannot forget it — which is how the
            // numbered lists ended up tighter than the sentence above them while
            // both claimed the same design.
            .lineSpacing(OnboardingType.lineSpacing)
            .frame(width: OnboardingLayout.contentWidth, alignment: .leading)
            .padding(.horizontal, OnboardingLayout.pageMargin)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, minHeight: OnboardingLayout.pageHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func prose(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(OnboardingType.subtitle)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One ladder for the whole flow, a step above what Settings uses, because setup
/// is read once and often on a display the reader is not sitting close to. Three
/// sizes and two colours: primary for anything acted on, secondary for support.
enum OnboardingType {
    /// The step's own sentence, under the title.
    static let subtitle = Font.title3
    /// Instructions and labels the reader acts on.
    static let body = Font.body
    /// Supporting notes beside or below what they describe.
    static let caption = Font.callout
    /// Every size here is set tighter than it reads well at by default.
    static let lineSpacing: CGFloat = 3
}

/// A numbered instruction. One recipe, so the two places that walk a reader
/// through ElevenLabs' own interface cannot number their steps differently.
struct OnboardingNumberedStep: View {
    let number: Int
    let text: LocalizedStringKey

    init(_ number: Int, _ text: LocalizedStringKey) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .font(OnboardingType.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(OnboardingType.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The plate a step's controls sit on. One recipe, so no step invents its own.
struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay { shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: OnboardingLayout.cardCornerRadius, style: .continuous)
    }
}

// MARK: - 1 · Welcome

struct WelcomeStep: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Welcome to Scriber")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Press a key, talk, and your words appear wherever your cursor is.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Your audio goes only to ElevenLabs, and your history stays on this Mac.")
                    .font(OnboardingType.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .lineSpacing(OnboardingType.lineSpacing)
            .frame(maxWidth: OnboardingLayout.contentWidth)
            .padding(.horizontal, 32)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity, minHeight: OnboardingLayout.pageHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - 2 · ElevenLabs key

struct APIKeyStep: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Binding var apiKey: String
    @Binding var keyFeedback: KeySaveFeedback?
    @Binding var isChecking: Bool

    var body: some View {
        OnboardingPage(
            title: "Connect ElevenLabs",
            subtitle: "ElevenLabs is the service that turns your recordings into text. It is currently the only one Scriber uses, and it has a generous free tier."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Above the card rather than inside it. These are the things to
                // go and do before the field below can be filled in, and reading
                // them off the same plate the field sits on made them look like
                // part of it.
                VStack(alignment: .leading, spacing: 10) {
                    OnboardingNumberedStep(1, "[Create a free ElevenLabs account](https://elevenlabs.io/app/sign-up) if you do not have one.")
                    // ElevenLabs' own labels, capitalised as their dashboard
                    // capitalises them, so the words on this step are the words
                    // to look for on the page it sends people to.
                    OnboardingNumberedStep(2, "[Create an API key](https://elevenlabs.io/app/developers/api-keys). If you turn **Restrict Key** on (recommended), enable **Speech to Text** under Endpoints, and **User** under Administration if you want Scriber to show your remaining credits.")
                    OnboardingNumberedStep(3, "Paste the key below.")
                }
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            SecureField(
                                "",
                                text: $apiKey,
                                // Styled rather than passed as a plain string: the
                                // default placeholder sits at nearly label weight,
                                // which reads as a value already entered.
                                prompt: Text("Paste your key").foregroundStyle(.tertiary)
                            )
                            .textFieldStyle(.roundedBorder)
                            .disabled(isChecking)
                            .onSubmit(submit)
                            .accessibilityLabel("ElevenLabs API key")
                            .accessibilityIdentifier("onboarding-api-key-field")
                            // Trailing, where every other primary action in
                            // setup is, rather than under the field on the left.
                            Button(action: submit) {
                                HStack(spacing: 6) {
                                    // Beside the title, not instead of it: a
                                    // button that renames itself mid-check
                                    // resizes, and the field beside it takes
                                    // the change.
                                    if isChecking { ProgressView().controlSize(.small) }
                                    Text("Save API Key")
                                }
                            }
                            .disabled(!canSubmit)
                        }
                        // Given its row up front. Letting it appear on the
                        // first save would move the card, and the page centred
                        // under the title moves with it.
                        status.frame(minHeight: 15, alignment: .leading)
                    }
                }
                Text("Your key is kept in this Mac's login Keychain. ElevenLabs shows it once, so save a copy in your password manager before you leave the page.")
                    .font(OnboardingType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Every arrival, forward or back, rather than once when setup opens.
        // Nothing tells Scriber that the key was deleted from the Keychain or
        // revoked on ElevenLabs' side, so the badge is only as true as its last
        // look — and this step is where it is claimed.
        .onAppear { runtime.coordinator.validateStoredAPIKey() }
    }

    @ViewBuilder private var status: some View {
        if runtime.coordinator.isCheckingStoredAPIKey {
            Label {
                Text("Checking your saved key…")
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(OnboardingType.caption)
            .foregroundStyle(.secondary)
        } else if let keyFeedback {
            Label(keyFeedback.message, systemImage: keyFeedback.systemImage)
                .font(OnboardingType.caption)
                .foregroundStyle(keyFeedback.color)
                .lineLimit(2)
        } else if apiKey.isEmpty, runtime.preferences.apiKeyConfigured {
            switch runtime.preferences.apiKeyValidity {
            case .valid:
                Label("Verified", systemImage: "checkmark.shield.fill")
                    .font(OnboardingType.caption)
                    .foregroundStyle(.green)
            case .invalid:
                Label("Invalid", systemImage: "exclamationmark.triangle.fill")
                    .font(OnboardingType.caption)
                    .foregroundStyle(.red)
            case .unchecked:
                Label("Stored in Login Keychain", systemImage: "shield")
                    .font(OnboardingType.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canSubmit: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isChecking
    }

    private func submit() {
        guard canSubmit else { return }
        Task {
            isChecking = true
            defer { isChecking = false }
            do {
                try await runtime.coordinator.validateAndSaveAPIKey(apiKey)
                keyFeedback = .saved
                apiKey = ""
            } catch {
                keyFeedback = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - 3 · ElevenLabs data use

/// Everything Scriber has to say about ElevenLabs' training default, in one
/// place. Setup shows it as a step; Settings opens it in a window of its own,
/// for anyone who set Scriber up before that step existed or pressed past it.
///
/// One view rather than two that look alike. The wording is the whole point of
/// this screen, and two copies of it would drift the first time either is
/// edited, with nothing failing to compile to say so.
struct DataUseGuidance: View {
    static let title = "One setting worth changing"
    static let subtitle: LocalizedStringKey = "Every ElevenLabs workspace has **Improve the models for everyone** switched on by default, which lets your recordings train their models."
    /// Shared with Settings' ElevenLabs tab, which offers the same policy as a
    /// button. One address, so the two cannot come to point at different pages.
    static let privacyPolicyURL = URL(string: "https://elevenlabs.io/privacy-policy")!

    @Binding var showsGuide: Bool
    /// Setup's copy is reached from its own step, so it needs no name; the
    /// window's is reached from Settings and shares a screen with other help.
    var guideIdentifier: String

    var body: some View {
        content
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
                Image(.elevenLabsDataUseSetting)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: OnboardingLayout.contentWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .accessibilityLabel("ElevenLabs' Improve the models for everyone setting, a switch above a link to their privacy policy")
                Button("Show me where to turn it off") { showsGuide = true }
                    .buttonStyle(.link)
                    .accessibilityIdentifier(guideIdentifier)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Switching it off changes what you send from then on. ElevenLabs keeps what it already generated about your voice for up to three years after your last use, or longer where the law requires.")
                        .font(OnboardingType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Read their privacy policy", destination: Self.privacyPolicyURL)
                        .font(OnboardingType.caption)
                        .accessibilityIdentifier("data-use-privacy-policy")
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DataUseStep: View {
    @Binding var showsGuide: Bool

    var body: some View {
        OnboardingPage(title: DataUseGuidance.title, subtitle: DataUseGuidance.subtitle) {
            DataUseGuidance(showsGuide: $showsGuide, guideIdentifier: "onboarding-data-use-guide")
        }
    }
}

/// The same guidance as setup's step, in a window Settings can open. Setup's
/// container is a step in a flow with a gate in front of it; this one is a page
/// with a way out. Both sit on `OnboardingPage`, so they cannot drift apart in
/// margins, column width, or type.
struct DataUseWindowView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showsGuide = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingPage(title: DataUseGuidance.title, subtitle: DataUseGuidance.subtitle) {
                DataUseGuidance(showsGuide: $showsGuide, guideIdentifier: "data-use-window-guide")
            }
            Divider()
            HStack {
                Spacer()
                Button("Close") { dismissWindow(id: AppWindowIdentity.dataUseSceneID) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("data-use-close")
            }
            .padding(.horizontal, OnboardingLayout.pageMargin)
            .frame(height: OnboardingLayout.footerHeight)
        }
        .frame(
            minWidth: OnboardingLayout.windowWidth,
            maxWidth: OnboardingLayout.windowWidth,
            minHeight: OnboardingLayout.minimumWindowHeight,
            idealHeight: OnboardingLayout.windowHeight,
            maxHeight: .infinity
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showsGuide) {
            DataUseGuideSheet { showsGuide = false }
        }
    }
}

/// **The one hand-built control in Scriber.** Its two bars reimplement what a
/// window toolbar does for nothing: appear only while content passes under them.
/// A sheet has no toolbar to ask for that, and the alternative is a third window
/// carrying a real one. If this ever needs more than it has — a second image, a
/// title that changes — make it a window and delete `ScrollEdges` and `surface`;
/// do not grow the hand-built version. Everything it approximates, AppKit does
/// better, and it stays only because the thing it lives in cannot have the real
/// one.
///
/// The route through ElevenLabs' own interface, as a sheet rather than a
/// hand-drawn scrim: a sheet already dims what is behind it, keeps its buttons
/// in normal control colours against the window rather than against a dark
/// wash, answers Escape, and cannot cover the footer it is presented from.
///
/// The steps are numbered to match the marks drawn on the screenshot, so the
/// dashboard is a lead-in line rather than a step of its own — a reader looking
/// between the two must not find text step 2 against a picture marked 1.
struct DataUseGuideSheet: View {
    let dismiss: () -> Void

    /// Which edges currently have content passing under them. Settings' toolbar
    /// shows its surface only while something is beneath it, and a bar that is
    /// always drawn reads as a panel bolted on rather than as the content's own
    /// edge — which is also what left a permanent wash on the screenshot at the
    /// end of the scroll, where there is nothing left to pass under anything.
    private struct ScrollEdges: Equatable {
        var underTop = false
        var underBottom = false
    }

    @State private var edges = ScrollEdges()

    /// The two glass strips. Content is inset by these so the first line and the
    /// last can each be scrolled clear of the bar they pass under, rather than
    /// coming to rest half-covered by it.
    private static let headerBarHeight: CGFloat = 40
    private static let footerBarHeight: CGFloat = 48
    /// Added to each bar's height. Clearing the glass by a hair leaves the first
    /// line and the last looking tucked under it; this is the gap that reads as
    /// the content having room rather than as it having just escaped.
    private static let barClearance: CGFloat = 22

    /// The screenshot is 862×1120 pixels. Both dimensions of its frame are stated
    /// because `.frame(maxHeight:)` alone leaves the frame as wide as the column,
    /// and the rounded border then draws around the empty space beside the
    /// picture rather than clipping the picture's own corners.
    private static let menuImageHeight: CGFloat = 420
    private static let menuImageWidth: CGFloat = (menuImageHeight * 862 / 1120).rounded()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Open your ElevenLabs dashboard at [elevenlabs.io/app](https://elevenlabs.io/app), in the workspace your key came from. Then:")
                    .font(OnboardingType.body)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingNumberedStep(1, "Click your profile icon, top right.")
                    OnboardingNumberedStep(2, "Hover over **Terms and privacy**.")
                    OnboardingNumberedStep(3, "Click **Data use**.")
                    // The switch is only half of it. The modal keeps its own
                    // confirm button, so someone who flips it and closes the
                    // window has changed nothing.
                    OnboardingNumberedStep(4, "Switch **Improve the models for everyone** off, then click **Update your choice**.")
                }
                Image(.elevenLabsDataUseMenu)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.menuImageWidth, height: Self.menuImageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .accessibilityLabel("The ElevenLabs profile menu. One, the profile button at the top right. Two, Terms and privacy near the bottom of the menu. Three, Data use in the submenu that opens beside it.")
                    // Centred against the column while the prose stays ranged
                    // left. Safe to place the picture with a frame now that it
                    // carries its own size: this is where it sits, not how big
                    // it is.
                    .frame(maxWidth: .infinity)
            }
            .lineSpacing(OnboardingType.lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, Self.headerBarHeight + Self.barClearance)
            .padding(.bottom, Self.footerBarHeight + Self.barClearance)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
            ScrollEdges(
                underTop: geometry.contentOffset.y > 1,
                underBottom: geometry.contentOffset.y + geometry.containerSize.height
                    < geometry.contentSize.height - 1
            )
        } action: { _, updated in
            withAnimation(.easeInOut(duration: 0.15)) { edges = updated }
        }
        // The scroll view takes the sheet's whole width rather than sitting
        // inside its padding, so the scroll indicator rides the sheet's own edge
        // instead of floating in from it. The inset moved to the content above.
        .frame(width: 520)
        .frame(maxHeight: Self.maximumScrollHeight)
        .overlay(alignment: .top) { headerBar }
        .overlay(alignment: .bottom) { footerBar }
    }

    private var headerBar: some View {
        Text("Where to find it")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: Self.headerBarHeight)
            .background { surface(visible: edges.underTop) }
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Button("Done", action: dismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .frame(height: Self.footerBarHeight)
        .background { surface(visible: edges.underBottom) }
    }

    /// The glass itself, faded rather than switched, so a bar arriving as the
    /// content reaches it does not blink into place.
    private func surface(visible: Bool) -> some View {
        Color.clear
            .glassEffect(.regular, in: .rect)
            .opacity(visible ? 1 : 0)
    }

    /// The sheet has to fit the window it is presented from, and that window is
    /// never taller than the screen — which is as much as a sheet can find out
    /// about its host.
    private static var maximumScrollHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? OnboardingLayout.windowHeight
        return max(220, min(520, visible - 200))
    }
}

// MARK: - 4 · Permissions

/// Both grants on one step. They were separate while each needed a page of its
/// own to explain itself; the microphone's test is what makes this one tall, and
/// Accessibility beside it costs a row. Asking for two related things once beats
/// two pages that each look like the same page.
struct PermissionsStep: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Binding var signalObserved: Bool
    let skipTest: () -> Void

    var body: some View {
        OnboardingPage(
            title: "Let Scriber hear you and type for you",
            subtitle: "Scriber listens only while you are dictating, and types only where your cursor already is."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingCard {
                    if runtime.coordinator.microphoneGranted {
                        granted
                    } else {
                        HStack {
                            PermissionLabel(title: "Microphone", systemImage: "mic", allowed: false)
                            Spacer()
                            MicrophonePermissionButton()
                        }
                    }
                }
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            PermissionLabel(
                                title: "Accessibility",
                                systemImage: "keyboard",
                                allowed: runtime.coordinator.accessibilityGranted
                            )
                            Spacer()
                            AccessibilityPermissionButton()
                        }
                        Text("Lets Scriber notice your shortcut in any app, and put your words where your cursor is.")
                            .font(OnboardingType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        // The coordinator decides this from the samples themselves and flips it
        // once, so the step never watches a value that changes ten times a second.
        .onChange(of: runtime.coordinator.microphoneSignalDetected) { _, detected in
            if detected { signalObserved = true }
        }
    }

    private var granted: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                MicrophonePicker()
                Text("Your Mac's built-in microphone and wired microphones work best. Bluetooth microphones are less reliable.")
                    .font(OnboardingType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                AudioLevelMeter(
                    source: runtime.coordinator.microphoneLevel,
                    presentation: .onboarding
                )
                .accessibilityIdentifier("onboarding-level-meter")
                Label(
                    signalObserved ? "Scriber can hear you" : "Speak to test your microphone",
                    systemImage: signalObserved ? "checkmark.circle.fill" : "waveform"
                )
                .font(OnboardingType.body)
                .foregroundStyle(signalObserved ? Color.green : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let microphoneTestError = runtime.coordinator.microphoneTestError {
                Label(microphoneTestError, systemImage: "exclamationmark.triangle.fill")
                    .font(OnboardingType.caption)
                    .foregroundStyle(.red)
            }
            Divider()
            help
        }
    }

    /// Present from the first second rather than appearing after a wait. Someone
    /// with no working input knows immediately, and nothing Scriber can read
    /// tells the two apart: a virtual device is listed exactly like a real one.
    /// Anyone whose microphone works speaks, sees green, and never reads this.
    private var help: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not hearing anything?")
                .font(OnboardingType.body.weight(.medium))
            Text("Input volume is a macOS setting — around halfway works for most microphones.")
                .font(OnboardingType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Open Sound Settings") { runtime.coordinator.openSystemSoundSettings() }
                Button("Continue without testing", action: skipTest)
                    .buttonStyle(.link)
                    .accessibilityIdentifier("onboarding-skip-microphone-test")
            }
        }
    }
}

// MARK: - 6 · Keyboard shortcut

struct ShortcutStep: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Binding var activeRecorderID: String?
    @Binding var isConfirmed: Bool

    var body: some View {
        OnboardingPage(
            title: "Your keyboard shortcut",
            subtitle: "Pick the key you will press to dictate, then press it once so Scriber knows it can see it."
        ) {
            // The choice is shown rather than hidden behind a disclosure. It was
            // folded away to save height the step no longer needs, and it cost
            // twice for that: opening it resized the step, and the people who
            // most need it are the ones on a keyboard with no `fn`, who have no
            // reason to expect a second control exists.
            OnboardingCard {
                VStack(alignment: .leading, spacing: 14) {
                    ShortcutKeyCapTester(
                        target: runtime.preferences.dictationShortcut,
                        isPaused: activeRecorderID != nil,
                        isConfirmed: $isConfirmed
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    Divider()
                    ShortcutPicker(
                        chord: $runtime.preferences.dictationShortcut,
                        customChord: $runtime.preferences.customShortcut,
                        activeRecorderID: $activeRecorderID,
                        isEditable: !runtime.coordinator.phase.isBusy,
                        refusalResetToken: 0
                    )
                    .accessibilityIdentifier("onboarding-shortcut-alternatives")
                }
            }
        }
    }
}

// MARK: - 6 · Try it

struct TryItStep: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        // The two ways to use the shortcut are taught here rather than on the
        // step that chose it: this is the first moment either one can be tried,
        // and a rule read one step before it can be used is a rule read twice.
        OnboardingPage(
            title: "Try it!",
            subtitle: "**Tap it** to start dictating hands-free, and tap it again when you are done.",
            subtitleDetail: "**Or hold it**, talk, and let go to finish."
        ) {
            // A field with a real prompt rather than a `TextEditor` under a label
            // positioned to look like one, which can only be aligned by matching an
            // inset the text view never publishes. `reservesSpace` keeps the box the
            // same height empty or full, so nothing moves as the transcript lands.
            TextField(
                "",
                text: $text,
                prompt: Text("Tap \(shortcut) to dictate. Tap \(shortcut) again to stop."),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(OnboardingType.body)
            .lineLimit(8, reservesSpace: true)
            .focused($isFocused)
            .accessibilityLabel("Dictate here")
            .accessibilityIdentifier("onboarding-try-it-field")
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: shape)
            .overlay { shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }
        }
        .onAppear { isFocused = true }
    }

    private var shortcut: String { runtime.preferences.dictationShortcut.displayName }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }
}

// MARK: - 7 · Done

/// Also where the two standing preferences are offered. Muting had a step of
/// its own while it sat before Try it; moved behind it, a whole page for one
/// switch is a page asking someone who has just watched their words land to
/// stop and read again. Both settings belong to how Scriber behaves from here
/// on, which is what this step is about.
struct DoneStep: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Binding var launchAtLogin: Bool
    let error: String?

    var body: some View {
        OnboardingPage(
            title: "You're set! ✓",
            subtitle: "Tap **\(runtime.preferences.dictationShortcut.displayName)** in any app to dictate. Scriber lives in your menu bar, and Settings has the rest — including a way to run this setup again."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 10) {
                        MuteOtherAudioToggle(
                            isOn: $runtime.preferences.muteOtherAudioWhileDictating,
                            requestAccess: { runtime.coordinator.requestOtherAudioAccess() }
                        ) { isOn in
                            Toggle("Mute other audio while dictating", isOn: isOn)
                                .accessibilityIdentifier("onboarding-mute-other-audio")
                        }
                        Text("Silences other apps, calls, and notification sounds for as long as you are talking. macOS asks for System Audio Recording access; muting works whether you allow it or not, because Scriber never reads what other apps play.")
                            .font(OnboardingType.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                OnboardingCard {
                    Toggle("Launch Scriber when I log in", isOn: $launchAtLogin)
                        .accessibilityIdentifier("onboarding-launch-at-login")
                }
                if let error {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(OnboardingType.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        // Naming the list is not enough on its own: it is several
                        // panes deep, and the refusal is only actionable there.
                        Button("Open Login Items…") { runtime.coordinator.openLoginItemsSettings() }
                    }
                    .accessibilityIdentifier("onboarding-launch-at-login-advice")
                }
            }
        }
    }
}
