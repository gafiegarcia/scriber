@preconcurrency import AppKit
import Combine
import SwiftUI
#if SWIFT_PACKAGE
import ScriberDictateCore
#endif

@MainActor
final class PillModel: ObservableObject {
    @Published var phase: AppPhase = .idle
    var onCopy: (() -> Void)?
    var onOpen: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?
}

private extension AppPhase {
    var isNoEditableTargetPasteFailure: Bool {
        if case .pasteFailed(let message) = self, message == PasteResult.noEditableTargetMessage { return true }
        return false
    }
}

@MainActor
final class PillController {
    let model = PillModel()
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?
    private var preferredScreen: NSScreen?
    private var currentPanelSize = NSSize(width: 300, height: 62)

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 62),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: PillView(model: model))
    }

    func update(_ phase: AppPhase) {
        hideTask?.cancel()
        let desiredSize = panelSize(for: phase)
        if desiredSize != currentPanelSize {
            panel.setContentSize(desiredSize)
            currentPanelSize = desiredSize
        }
        model.phase = phase
        switch phase {
        case .idle:
            panel.orderOut(nil)
        case .pasted, .message:
            show()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.panel.orderOut(nil)
            }
        default:
            show()
        }
    }

    func setPreferredScreen(_ screen: NSScreen?) {
        preferredScreen = screen
    }

    private func panelSize(for phase: AppPhase) -> NSSize {
        switch phase {
        case .pasteFailed where phase.isNoEditableTargetPasteFailure:
            NSSize(width: 360, height: 62)
        case .pasteFailed, .transcriptionFailed:
            NSSize(width: 430, height: 72)
        default:
            NSSize(width: 300, height: 62)
        }
    }

    private func show() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = preferredScreen ?? NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.midX - panel.frame.width / 2
        let y = frame.minY + 18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct PillView: View {
    @ObservedObject var model: PillModel

    var body: some View {
        HStack(spacing: 12) {
            symbol
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder private var symbol: some View {
        switch model.phase {
        case .recording(_, _, let level):
            Circle().fill(.red).frame(width: 12, height: 12).scaleEffect(1 + CGFloat(max(0, level + 60)) / 160)
        case .transcribing:
            ProgressView().controlSize(.small)
        case .pasted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .pasteFailed where model.phase.isNoEditableTargetPasteFailure:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .pasteFailed, .transcriptionFailed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        default:
            Image(systemName: "waveform")
        }
    }

    private var title: String {
        switch model.phase {
        case .idle: "Ready"
        case .recording(let mode, let elapsed, _): mode == .held ? "Recording · \(elapsed.formattedTimer)" : "Hands-free · \(elapsed.formattedTimer)"
        case .transcribing(let attempt, let delay):
            if attempt == 1, delay == nil { "Transcribing…" }
            else { "Retrying \(min(attempt + (delay == nil ? 0 : 1), 3))/3…" }
        case .pasted: "Pasted"
        case .pasteFailed where model.phase.isNoEditableTargetPasteFailure: "Dictation copied"
        case .pasteFailed: "Couldn't paste automatically"
        case .transcriptionFailed: "Transcription failed"
        case .message(let value): value
        }
    }

    private var subtitle: String? {
        switch model.phase {
        case .transcribing(_, let delay):
            delay.map { "Trying again in \(Int($0)) seconds" }
        case .pasteFailed(let message), .transcriptionFailed(let message): message
        default: nil
        }
    }

    @ViewBuilder private var actions: some View {
        switch model.phase {
        case .pasteFailed where model.phase.isNoEditableTargetPasteFailure:
            Button("Open") { model.onOpen?() }.controlSize(.small)
            Button { model.onDismiss?() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        case .pasteFailed:
            Button("Copy") { model.onCopy?() }.buttonStyle(.borderedProminent).controlSize(.small)
            Button("Open") { model.onOpen?() }.controlSize(.small)
            Button { model.onDismiss?() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        case .transcriptionFailed:
            Button("Retry") { model.onRetry?() }.buttonStyle(.borderedProminent).controlSize(.small)
            Button("Open") { model.onOpen?() }.controlSize(.small)
            Button { model.onDismiss?() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        default:
            EmptyView()
        }
    }
}

private extension TimeInterval {
    var formattedTimer: String {
        let seconds = Int(self)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
