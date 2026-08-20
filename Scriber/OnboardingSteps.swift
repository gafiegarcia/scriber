import AppKit
import SwiftUI

// MARK: - Shared page chrome

/// The shape every setup step takes: a symbol, a title, a sentence, and one
/// card. Steps differ in what is in the card and nothing else, which is what
/// makes nine separate decisions read as one flow.
struct OnboardingPage<Content: View>: View {
    let symbol: String
    var tint: Color = .accentColor
    let title: String
    let subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                OnboardingHero(symbol: symbol, tint: tint)
                    .padding(.bottom, 4)
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
                    .padding(.top, 6)
            }
            .frame(maxWidth: OnboardingLayout.contentWidth)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, minHeight: OnboardingLayout.pageHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct OnboardingHero: View {
    let symbol: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(tint.opacity(0.12))
            .frame(width: OnboardingLayout.heroSize, height: OnboardingLayout.heroSize)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
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
                Text("Press a key, talk, and your words appear wherever you were typing.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Setup takes about two minutes. Your audio goes only to ElevenLabs, and your dictation history stays on this Mac.")
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
            symbol: "key.fill",
            title: "Connect ElevenLabs",
            subtitle: "Scriber sends your recordings to ElevenLabs, which turns them into text. It is the only service Scriber uses, and the free tier covers daily dictation."
        ) {
            OnboardingCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No key yet? [Create a free ElevenLabs account](https://elevenlabs.io/app/sign-up), then [add an API key](https://elevenlabs.io/app/developers/api-keys) with Speech to Text access.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SecureField(
                        runtime.preferences.apiKeyConfigured
                            ? "Enter a new API key to replace the stored key"
                            : "xi-api-key",
                        text: $apiKey
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(isChecking)
                    .onSubmit(submit)
                    .accessibilityIdentifier("onboarding-api-key-field")
                    HStack(spacing: 12) {
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
                        status
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        // Again on the step itself, not only when setup opens: the badge and the
        // gate below it both speak for a Keychain item this is the last chance
        // to confirm is still there.
        .onAppear { runtime.coordinator.reconcileStoredAPIKey() }
    }

    @ViewBuilder private var status: some View {
        if let keyFeedback {
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
            symbol: "hand.raised.fill",
            title: "One setting worth changing",
            subtitle: "New ElevenLabs accounts have **Improve models for everyone** switched on, which lets your recordings train their models."
        ) {
            VStack(spacing: 14) {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 12) {
                        stepLine(1, "Click your profile picture, top right")
                        stepLine(2, "Hover **Terms and privacy**")
                        stepLine(3, "Click **Data use**, then turn the switch off")
                        // The screenshots live behind this rather than on the
                        // step. Shown inline they have to shrink until their own
                        // text is unreadable, at which point they are decoration
                        // on a step whose whole job is three sentences.
                        Button("Show me where to find it") { showsGuide = true }
                            .buttonStyle(.link)
                            .padding(.top, 2)
                            .accessibilityIdentifier("onboarding-data-use-guide")
                    }
                }
                Text("It is set per workspace, so change it in the one your key came from. Switching it off only affects what you send afterwards — it does not remove what has already gone. ElevenLabs says it keeps data it generates about your voice for up to three years after your last use, except where the law requires longer; [their privacy policy](https://elevenlabs.io/privacy-policy) has the detail.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stepLine(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The two screenshots, over the whole window because neither can be read any
/// smaller. Escape, Done, or a click outside puts them away.
struct DataUseGuideOverlay: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.6))
                .onTapGesture(perform: dismiss)
            VStack(spacing: 12) {
                ScrollView {
                    VStack(spacing: 20) {
                        shot(
                            .elevenLabsDataUseMenu,
                            caption: "Where to find it",
                            description: "The ElevenLabs profile menu, with Terms and privacy expanded to show Data use"
                        )
                        shot(
                            .elevenLabsDataUseSetting,
                            caption: "What you'll see",
                            description: "The Improve models for everyone setting, with a switch and a link to the privacy policy"
                        )
                    }
                    .padding(.vertical, 4)
                }
                Button("Done", action: dismiss)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            // The scrim covers the footer too, so this keeps the overlay's own
            // controls out of the band where the step's buttons sit.
            .padding(.bottom, OnboardingLayout.footerHeight)
            .frame(maxWidth: 560)
        }
        .transition(.opacity)
        .onExitCommand(perform: dismiss)
    }

    private func shot(_ resource: ImageResource, caption: String, description: String) -> some View {
        VStack(spacing: 6) {
            Text(caption)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            Image(resource)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(description)
        }
    }
}

// MARK: - 4 · Microphone

struct MicrophoneStep: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Binding var signalObserved: Bool
    let skipTest: () -> Void

    var body: some View {
        OnboardingPage(
            symbol: "mic.fill",
            title: "Let Scriber hear you",
            subtitle: runtime.coordinator.microphoneGranted
                ? "Say something. The meter has to move before setup can go on — that is the only way to know your microphone works."
                : "Scriber listens only while you are dictating."
        ) {
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
        }
        .onChange(of: runtime.coordinator.microphoneTestLevel) { _, level in
            if AudioSignal.isDetected(decibels: level) { signalObserved = true }
        }
    }

    private var granted: some View {
        VStack(alignment: .leading, spacing: 16) {
            MicrophonePicker()
            VStack(spacing: 10) {
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
            .frame(maxWidth: .infinity)
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

// MARK: - 5 · Accessibility

struct AccessibilityStep: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        OnboardingPage(
            symbol: "keyboard",
            title: "Let Scriber type for you",
            subtitle: "Accessibility lets Scriber notice your shortcut in any app, and put your words where your cursor is."
        ) {
            OnboardingCard {
                HStack {
                    PermissionLabel(
                        title: "Accessibility",
                        systemImage: "keyboard",
                        allowed: runtime.coordinator.accessibilityGranted
                    )
                    Spacer()
                    AccessibilityPermissionButton()
                }
            }
        }
    }
}

// MARK: - 6 · Keyboard shortcut

struct ShortcutStep: View {
    @EnvironmentObject private var runtime: AppRuntime
    @Binding var activeRecorderID: String?
    @Binding var isConfirmed: Bool
    @State private var showsAlternatives = false

    var body: some View {
        OnboardingPage(
            symbol: "command",
            title: "Pick your key",
            subtitle: "**Tap it** and Scriber keeps recording with your hands free — tap again when you are done. **Or hold it**, talk, and let go to finish."
        ) {
            VStack(spacing: 14) {
                OnboardingCard {
                    ShortcutKeyCapTester(
                        target: runtime.preferences.dictationShortcut,
                        isPaused: activeRecorderID != nil,
                        isConfirmed: $isConfirmed
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                DisclosureGroup("Use a different key", isExpanded: $showsAlternatives) {
                    ShortcutPicker(
                        chord: $runtime.preferences.dictationShortcut,
                        customChord: $runtime.preferences.customShortcut,
                        activeRecorderID: $activeRecorderID,
                        isCaptureAllowed: true,
                        refusalResetToken: 0
                    )
                    .padding(.top, 10)
                }
                .font(.callout)
                .accessibilityIdentifier("onboarding-shortcut-alternatives")
            }
        }
    }
}

// MARK: - 7 · Mute other audio

struct MuteAudioStep: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        OnboardingPage(
            symbol: "speaker.slash.fill",
            title: "Mute other audio while you dictate",
            subtitle: "Silences other apps, calls, and notification sounds for as long as you are talking."
        ) {
            VStack(spacing: 14) {
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
                Text("Using Bluetooth headphones or a speaker? Audio can come back in call quality for a second or two before it returns to normal. Choosing your Mac's built-in microphone on the previous step avoids it.")
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
            symbol: "text.cursor",
            title: "Try it",
            subtitle: "Everything is set up. Dictate into the box below and see it land."
        ) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(height: 150)
                    .background(Color(nsColor: .textBackgroundColor), in: shape)
                    .overlay { shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }
                    .focused($isFocused)
                    .accessibilityIdentifier("onboarding-try-it-field")
                if text.isEmpty {
                    Text("Tap \(shortcut) to dictate. Tap \(shortcut) again to stop.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
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
            symbol: "checkmark.circle.fill",
            tint: .green,
            title: "You're set",
            subtitle: "Tap **\(runtime.preferences.dictationShortcut.displayName)** in any app to dictate. Scriber lives in your menu bar, and Settings has everything else — including a way to redo this setup."
        ) {
            VStack(spacing: 12) {
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
