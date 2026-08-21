import AppKit
import SwiftUI

// MARK: - Shared page chrome

/// The shape every setup step takes: a title, a sentence, and the controls that
/// step owns — ranged left in a column that is centred in the page.
///
/// Ranged left rather than centred text: a centred sentence that wraps leaves a
/// ragged last line, and the only fix available is rewording each string until
/// it happens to fit, which holds for one window and one font. The column being
/// centred is what keeps a short step from sitting in the top corner of a
/// half-empty page.
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
            // page. Pinning the title held it still between steps, but it bought
            // that by stranding every short step's content against the bottom of
            // a half-empty page — and the two were never really separable
            // anyway, since a title with nothing under it is not a step.
            // Horizontal alignment stays ranged left inside the column; only the
            // column is centred.
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
            .frame(width: OnboardingLayout.contentWidth, alignment: .leading)
            .padding(.horizontal, OnboardingLayout.pageMargin)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, minHeight: OnboardingLayout.pageHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func prose(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
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
            subtitle: "ElevenLabs is the service that turns your recordings into text. It is the only one Scriber uses, and its free tier covers daily dictation."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Above the card rather than inside it. These are the things to
                // go and do before the field below can be filled in, and reading
                // them off the same plate the field sits on made them look like
                // part of it.
                VStack(alignment: .leading, spacing: 10) {
                    numbered(1, "[Create a free ElevenLabs account](https://elevenlabs.io/app/sign-up) if you do not have one.")
                    numbered(2, "[Add an API key](https://elevenlabs.io/app/developers/api-keys) with **Speech to Text** access.")
                    numbered(3, "Give it **User** access too, if you want Scriber to show how much ElevenLabs credit you have left.")
                    numbered(4, "Paste the key below.")
                }
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            SecureField(
                                "",
                                text: $apiKey,
                                // `xi-api-key` is the header ElevenLabs wants
                                // the key in, not the shape of the key, and it
                                // read here as an example to copy. Styled rather
                                // than passed as a plain string: the default
                                // placeholder sits at nearly label weight, which
                                // reads as a value already entered.
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
                                if isChecking {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Checking…")
                                    }
                                } else {
                                    Text("Save Key")
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
                    .font(.caption)
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

    private func numbered(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var status: some View {
        if runtime.coordinator.isCheckingStoredAPIKey {
            Label {
                Text("Checking your saved key…")
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let keyFeedback {
            Label(keyFeedback.message, systemImage: keyFeedback.systemImage)
                .font(.caption)
                .foregroundStyle(keyFeedback.color)
                .lineLimit(2)
        } else if apiKey.isEmpty, runtime.preferences.apiKeyConfigured {
            switch runtime.preferences.apiKeyValidity {
            case .valid:
                Label("Verified", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .invalid:
                Label("Invalid", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            case .unchecked:
                Label("Stored in Login Keychain", systemImage: "shield")
                    .font(.caption)
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

struct DataUseStep: View {
    @Binding var showsGuide: Bool

    var body: some View {
        OnboardingPage(
            title: "One setting worth changing",
            subtitle: "New ElevenLabs accounts have **Improve the models for everyone** switched on, which lets your recordings train their models."
        ) {
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Turn it off under **profile → Terms and privacy → Data use**, in the workspace your key came from.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Show me where to find it") { showsGuide = true }
                        .buttonStyle(.link)
                        .accessibilityIdentifier("onboarding-data-use-guide")
                }
                // The whole call to action sits inside the link, so a wrap
                // splits one phrase rather than stranding "policy." on a line
                // of its own.
                Text("Switching it off changes what you send from then on. ElevenLabs keeps what it already generated about your voice for up to three years after your last use, or longer where the law requires. [Read their privacy policy](https://elevenlabs.io/privacy-policy).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The route through ElevenLabs' own interface, as a sheet rather than a
/// hand-drawn scrim: a sheet already dims what is behind it, keeps its buttons
/// in normal control colours against the window rather than against a dark
/// wash, answers Escape, and cannot cover the footer it is presented from.
struct DataUseGuideSheet: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Where to find it")
                .font(.headline)
            Image(.elevenLabsDataUseMenu)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 500)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .accessibilityLabel("The ElevenLabs profile menu. One, the profile button at the top right. Two, Terms and privacy near the bottom of the menu. Three, Data use in the submenu that opens beside it.")
            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onChange(of: runtime.coordinator.microphoneTestLevel) { _, level in
            if AudioSignal.isDetected(decibels: level) { signalObserved = true }
        }
    }

    private var granted: some View {
        VStack(alignment: .leading, spacing: 14) {
            MicrophonePicker()
            VStack(alignment: .leading, spacing: 10) {
                AudioLevelWaveform(
                    level: runtime.coordinator.microphoneTestLevel,
                    presentation: .onboarding
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("onboarding-level-meter")
                Label(
                    signalObserved ? "Scriber can hear you" : "Speak to test your microphone",
                    systemImage: signalObserved ? "checkmark.circle.fill" : "waveform"
                )
                .font(.callout)
                .foregroundStyle(signalObserved ? Color.green : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let microphoneTestError = runtime.coordinator.microphoneTestError {
                Label(microphoneTestError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
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
                .font(.callout.weight(.medium))
            Text("Input volume is a macOS setting — around halfway works for most microphones.")
                .font(.caption)
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
            subtitle: "**Tap it** to start dictating hands-free, tap it again when you are done.",
            subtitleDetail: "**Or hold it**, talk, and let go to finish."
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
                        isCaptureAllowed: true,
                        refusalResetToken: 0
                    )
                    .accessibilityIdentifier("onboarding-shortcut-alternatives")
                }
            }
        }
    }
}

// MARK: - 7 · Mute other audio

struct MuteAudioStep: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        OnboardingPage(
            title: "Mute other audio while you dictate",
            subtitle: "Silences other apps, calls, and notification sounds for as long as you are talking."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 10) {
                        MuteOtherAudioToggle(
                            isOn: $runtime.preferences.muteOtherAudioWhileRecording,
                            requestAccess: { runtime.coordinator.requestOtherAudioAccess() }
                        ) { isOn in
                            Toggle("Mute other audio while recording", isOn: isOn)
                                .accessibilityIdentifier("onboarding-mute-other-audio")
                        }
                        Text("macOS asks for System Audio Recording access. Muting works whether you allow it or not, because Scriber never reads what other apps play.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Using Bluetooth headphones or a speaker? Audio can come back in call quality for a second or two before it returns to normal — which is why the built-in or a wired microphone is the one to pick.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 8 · Try it

struct TryItStep: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        OnboardingPage(
            title: "Try it!",
            subtitle: "Everything is set up. Dictate into the box and watch it land."
        ) {
            // A field with a real prompt rather than a `TextEditor` under a
            // label positioned to look like one. The hand-placed version could
            // only ever be aligned by matching whatever inset the text view
            // happened to use, which is not published and is not promised to
            // stay put. `reservesSpace` keeps the box the same height empty or
            // full, so nothing moves as the transcript lands.
            TextField(
                "",
                text: $text,
                prompt: Text("Tap \(shortcut) to dictate. Tap \(shortcut) again to stop."),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(9, reservesSpace: true)
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

// MARK: - 9 · Done

struct DoneStep: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Binding var launchAtLogin: Bool
    let error: String?

    var body: some View {
        OnboardingPage(
            title: "You're set! ✓",
            subtitle: "Tap **\(runtime.preferences.dictationShortcut.displayName)** in any app to dictate. Scriber lives in your menu bar, and Settings has the rest."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingCard {
                    Toggle("Launch Scriber when I log in", isOn: $launchAtLogin)
                        .accessibilityIdentifier("onboarding-launch-at-login")
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
