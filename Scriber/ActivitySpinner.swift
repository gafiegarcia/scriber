import SwiftUI

/// Scriber's spinner, wherever one appears. It takes its size from the
/// surrounding font, so a call site sizes it with `.font` rather than
/// `.controlSize`.
///
/// Do not: use `ProgressView` for a spinner. It is an `NSProgressIndicator`,
/// which redrew with dark spokes for about 70 ms whenever the pill's panel was
/// ordered in or took a click, while the SwiftUI row around it held still. A
/// symbol is drawn by SwiftUI like everything beside it.
struct ActivitySpinner: View {
    var body: some View {
        Image(systemName: "progress.indicator")
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeat(.continuous))
            .foregroundStyle(.secondary)
            .accessibilityLabel("In progress")
    }
}
