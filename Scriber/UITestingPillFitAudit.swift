#if DEBUG
import AppKit
import os
#if SWIFT_PACKAGE
import ScriberCore
#endif

/// Raises every pill Scriber can show, one after another, and logs whether its
/// content fits the glass it was given. `./scripts/smoke.sh` launches it with
/// `--ui-testing-pill-fit` and fails on any `pill fit` line reading `overflows`.
///
/// Each sample is the widest content its phase realistically carries, except
/// where the text is not Scriber's: `.transcriptionFailed` shows whatever the
/// failed request said, and `PRODUCT_SPEC.md` lets that truncate, so it is
/// sampled with the shortest message it takes. A caption that cannot fit even
/// that fails; a long one is expected to be cut off.
@MainActor
enum PillFitAudit {
    private static let log = Logger(subsystem: "com.gafiegarcia.scriber", category: "dictation")

    static func run(on pill: PillController) {
        var overflowing = 0
        for phase in samples {
            let fit = pill.measureFit(of: phase)
            if fit.overflows { overflowing += 1 }
            log.notice("pill fit \(fit.overflows ? "overflows" : "fits", privacy: .public) phase=\(phase.logLabel, privacy: .public) glass=\(Int(fit.glass.width), privacy: .public)x\(Int(fit.glass.height), privacy: .public) content=\(fit.content.width, format: .fixed(precision: 1), privacy: .public)x\(fit.content.height, format: .fixed(precision: 1), privacy: .public) sample=\(String(describing: phase), privacy: .public)")
        }
        pill.dismiss()
        log.notice("pill fit done checked=\(samples.count, privacy: .public) overflowing=\(overflowing, privacy: .public)")
    }

    /// Every phase that raises a pill. A phase added to `AppPhase` stops
    /// `requireSample(for:)` compiling until it is placed there, which is the
    /// reminder to add it here as well.
    static let samples: [AppPhase] = [
        .recording(mode: .locked, elapsed: RecordingLimit.maximumDuration - 1, level: 0.5),
        .recording(mode: .held, elapsed: RecordingLimit.maximumDuration - 1, level: 0.5),
        .transcribing(attempt: 1, retryDelay: nil),
        .transcribing(attempt: 2, retryDelay: 3),
        .canceledTranscript,
        .noInternetConnection,
        .inputDisconnected,
        .dictationCopied(text: "Meet me at noon.", message: "No text box was focused to paste into"),
        .dictationCopied(
            text: String(repeating: "A transcript long enough to reach the four-line cap. ", count: 8),
            message: "The focused app changed before Scriber could paste."
        ),
        .dictationBlockedBySecureField(
            text: "Meet me at noon.",
            message: "Secure field detected, not pasted. Paste with ⌘V if you wish."
        ),
        .permissionsRequired([.microphone, .accessibility]),
        .credentialsUnusable(.missingAPIKey),
        .credentialsUnusable(.invalidAPIKey),
        .credentialsUnusable(.creditsExhausted),
        .transcriptionFailed("Connection timed out"),
        .dictationFailed("Dictation history could not be opened. Quit and reopen Scriber."),
        .dictationFailed(String(repeating: "The operation could not be completed because the device is busy. ", count: 6)),
        .noSpeechDetected,
        .retryFoundNoWords,
        .inputVolumeZero,
        .noAudioSignal,
        .transcriptCopied,
        .message("Canceled"),
        .message("This dictation is no longer retryable"),
        .message("Microphone “MacBook Air Microphone” is unavailable"),
    ]

    /// Names every `AppPhase` so that a new one fails to compile here. `.idle`
    /// is the one without a sample, because `update` raises no pill for it.
    private static func requireSample(for phase: AppPhase) {
        switch phase {
        case .idle, .recording, .transcribing, .canceledTranscript, .noInternetConnection, .inputDisconnected,
             .dictationCopied, .permissionsRequired, .credentialsUnusable, .transcriptionFailed,
             .dictationFailed, .noSpeechDetected, .retryFoundNoWords, .inputVolumeZero, .noAudioSignal,
             .transcriptCopied, .dictationBlockedBySecureField, .message:
            break
        }
    }
}
#endif
