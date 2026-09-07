import SwiftUI

/// A live level, published on its own rather than from whatever produces it.
/// `ObservableObject` publishes per object, so a level on a wide-reaching object
/// re-renders every view observing it ten times a second, for a number only the
/// meter draws. Keep it here, where only the views that asked for it are hit.
@MainActor
final class AudioLevelSource: ObservableObject {
    @Published private(set) var level: Float = -160

    func update(_ level: Float) { self.level = level }
    func reset() { level = -160 }
}

/// A meter driven by an `AudioLevelSource`. Observing happens here, in a leaf,
/// so the step or pane around it is not rebuilt at the level's cadence.
struct AudioLevelMeter: View {
    @ObservedObject var source: AudioLevelSource
    let presentation: AudioLevelWaveform.Presentation

    var body: some View {
        AudioLevelWaveform(level: source.level, presentation: presentation)
    }
}

/// A live microphone level, drawn as a scrolling history of bars.
///
/// The pill and the microphone test both draw it, so it takes a `Presentation`
/// rather than raw numbers. Sharing the view alone is not enough to stop the two
/// drifting: left to choose its own frame, colour and backing, a call site can
/// stretch the bars until a quiet signal looks like no signal at all.
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

        /// The meter's width, or for `.pill` the widest it can be — see
        /// `fillsAvailableWidth`. Height is exact in every case.
        var size: CGSize {
            switch self {
            case .pill: CGSize(width: 136, height: 24)
            case .inputTest: CGSize(width: 116, height: 24)
            case .onboarding: CGSize(width: 400, height: 72)
            }
        }

        /// Whether the meter takes whatever width it is handed rather than its
        /// own. The pill's does: the room its Cancel and Confirm controls are not
        /// using belongs to the meter, so the pill keeps one width whether they
        /// are showing or not, and the space between the timer and the meter
        /// stays a gap rather than becoming a hole. `size.width` is then the
        /// widest it can be — the held pill with no pointer on it — which is what
        /// `sampleCount` buffers for.
        var fillsAvailableWidth: Bool {
            switch self {
            case .pill: true
            case .inputTest, .onboarding: false
            }
        }

        /// The plate the bars sit on, where there is one. The pill draws over
        /// its own material and wants none. Kept here with size and colour
        /// because it is the same recipe — leaving it at the call sites is how
        /// the two meters drifted before this type existed.
        var plate: (insets: EdgeInsets, cornerRadius: CGFloat)? {
            switch self {
            case .pill: nil
            case .inputTest: (EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10), 8)
            case .onboarding: (EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), 10)
            }
        }

        /// Held near the pill's 18:1 bar, so a bar stays a bar at any width. Wide
        /// bars read as blocks, and a block does not read as a waveform.
        var sampleCount: Int {
            let size = size
            let spacing = AudioLevelWaveform.spacing
            let targetBarWidth = size.height / 18
            return max(8, Int(((size.width + spacing) / (targetBarWidth + spacing)).rounded()))
        }
    }

    /// Every meter is red, because every meter shows the same thing: a live
    /// microphone. One that reads differently in setup than it does mid-dictation
    /// teaches two things for one signal — so this is not a per-presentation
    /// choice.
    private static let barColor = Color.red

    let level: Float
    let presentation: Presentation
    @State private var samples: [Double]

    private static let spacing: CGFloat = 2

    /// How many bars a meter of this size holds, never more than the buffer has.
    /// Same 18:1 pitch `Presentation.sampleCount` buffers against, so a bar is
    /// the same bar at every width the pill hands it.
    private static func barCount(fitting size: CGSize, within available: Int) -> Int {
        let targetBarWidth = size.height / 18
        let fitting = Int(((size.width + spacing) / (targetBarWidth + spacing)).rounded())
        return max(8, min(available, fitting))
    }

    init(level: Float, presentation: Presentation) {
        self.level = level
        self.presentation = presentation
        _samples = State(initialValue: Array(repeating: 0, count: presentation.sampleCount))
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing = Self.spacing
            // Only the most recent samples that fit. The buffer is one fixed
            // length whatever the meter's width, so a width change draws fewer
            // bars rather than resizing an array ten times a second — and a
            // narrower meter shows recent history rather than a squeezed copy of
            // the same span.
            let visible = samples.suffix(Self.barCount(fitting: proxy.size, within: samples.count))
            let count = CGFloat(visible.count)
            let barWidth = max(1, (proxy.size.width - spacing * (count - 1)) / count)
            // Proportional rather than a fixed 2pt, so a bar at rest is a dot at
            // any size. A fixed floor turns into a dash once the bars are wide,
            // and a dash is exactly what a quiet-but-real signal also draws.
            let floor = max(1, min(barWidth, proxy.size.height * 0.05))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, sample in
                    Capsule()
                        .fill(Self.barColor.opacity(sample == 0 ? 0.35 : 0.95))
                        .frame(width: barWidth, height: max(floor, proxy.size.height * sample))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            // Measured on a SwiftUI harness: the pill's row costs 160 points
            // before the meter, so `PillController.oneLinerWidth` at 210 leaves
            // exactly 50 in the tightest state — locked hands-free with the
            // pointer on it, both Cancel and Confirm showing.
            //
            // Keep this equal to that leftover. It is a tripwire rather than a
            // taste: the meter is the row's flexible child, so a smaller minimum
            // lets a squeezed row quietly draw a stub meter, while one set at the
            // true worst case makes the row overflow the glass instead. Bars need
            // only ~25 points to draw — 8 of them at a 3.33-point pitch — so
            // nothing here is protecting the drawing.
            //
            // Do not: lower `oneLinerWidth` without lowering this to match. At
            // 200 against this same 50 the recording row overflowed its glass by
            // 10 points, hidden inside the 8-point margin around the capsule.
            minWidth: presentation.fillsAvailableWidth ? 50 : presentation.size.width,
            maxWidth: presentation.fillsAvailableWidth ? .infinity : presentation.size.width,
            minHeight: presentation.size.height,
            maxHeight: presentation.size.height
        )
        .modifier(PlateBackground(plate: presentation.plate))
        .onAppear { append(level) }
        .onChange(of: level) { _, newLevel in append(newLevel) }
        // No implicit animation over `samples`. Interpolating every bar between
        // ticks costs more than everything else this view does — about twelve
        // points of CPU on an M4 — to glide a meter that already refreshes ten
        // times a second. Level meters step; the pill's did too, and nobody was
        // reading the movement.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue(AudioSignal.isDetected(decibels: level) ? "Signal detected" : "No signal")
    }

    private func append(_ decibels: Float) {
        samples.removeFirst()
        samples.append(AudioSignal.normalized(decibels: decibels))
    }
}

private struct PlateBackground: ViewModifier {
    let plate: (insets: EdgeInsets, cornerRadius: CGFloat)?

    func body(content: Content) -> some View {
        if let plate {
            content
                .padding(plate.insets)
                .background(
                    .quaternary,
                    in: RoundedRectangle(cornerRadius: plate.cornerRadius, style: .continuous)
                )
        } else {
            content
        }
    }
}
