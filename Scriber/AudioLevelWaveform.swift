import SwiftUI

/// A live microphone level, drawn as a scrolling history of bars.
///
/// Two features depend on this — the pill and the microphone test — so it takes a
/// `Presentation` rather than raw numbers. Sharing the view alone was not enough
/// to stop the two from drifting apart: each call site chose its own frame,
/// colour and backing, and one of them stretched the bars until a quiet signal
/// looked like no signal at all.
struct AudioLevelWaveform: View {
    /// Where this meter is being drawn, which decides everything about how it
    /// looks. Add a case rather than passing numbers; the sizes below are a
    /// single family, and a frame chosen freely leaves that family.
    enum Presentation {
        /// The recording pill. The proportions every other case is derived from.
        case pill
        /// The input test in Settings.
        case inputTest
        /// The microphone step in setup, where the meter is the subject of the
        /// page rather than an ornament on a row.
        case onboarding

        var size: CGSize {
            switch self {
            case .pill: CGSize(width: 58, height: 24)
            case .inputTest: CGSize(width: 116, height: 24)
            case .onboarding: CGSize(width: 400, height: 72)
            }
        }

        /// Every meter is red, because every meter shows the same thing: a live
        /// microphone. One that reads differently here than it does mid-dictation
        /// teaches two things for one signal.
        var color: Color { .red }

        /// Held near the pill's 18:1 bar, so a bar stays a bar at any width. Wide
        /// bars read as blocks, and a block does not read as a waveform.
        var sampleCount: Int {
            let size = size
            let spacing = AudioLevelWaveform.spacing
            let targetBarWidth = size.height / 18
            return max(8, Int(((size.width + spacing) / (targetBarWidth + spacing)).rounded()))
        }
    }

    let level: Float
    let presentation: Presentation
    @State private var samples: [Double]

    private static let spacing: CGFloat = 2

    init(level: Float, presentation: Presentation) {
        self.level = level
        self.presentation = presentation
        _samples = State(initialValue: Array(repeating: 0, count: presentation.sampleCount))
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing = Self.spacing
            let count = CGFloat(samples.count)
            let barWidth = max(1, (proxy.size.width - spacing * (count - 1)) / count)
            // Proportional rather than a fixed 2pt, so a bar at rest is a dot at
            // any size. A fixed floor turns into a dash once the bars are wide,
            // and a dash is exactly what a quiet-but-real signal also draws.
            let floor = max(1, min(barWidth, proxy.size.height * 0.05))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(samples.indices, id: \.self) { index in
                    let sample = samples[index]
                    Capsule()
                        .fill(presentation.color.opacity(sample == 0 ? 0.35 : 0.95))
                        .frame(width: barWidth, height: max(floor, proxy.size.height * sample))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: presentation.size.width, height: presentation.size.height)
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
