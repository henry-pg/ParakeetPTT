import AppKit
import SwiftUI

@MainActor
final class RecordingHUDWindowController: NSWindowController {
    private let hudState = RecordingHUDState()

    init() {
        let contentView = RecordingHUDView(state: hudState)
        let hostingController = NSHostingController(rootView: contentView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 78),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(mode: RecordingHUDMode) {
        hudState.mode = mode
        hudState.resetLevels()
        centerAboveScreenBottom()
        window?.orderFrontRegardless()
    }

    func update(mode: RecordingHUDMode) {
        hudState.mode = mode
    }

    func updateAudioLevel(_ level: Double) {
        hudState.pushLevel(level)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func centerAboveScreenBottom() {
        guard let window else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }

        let size = window.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 96
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class RecordingHUDState: ObservableObject {
    @Published var mode: RecordingHUDMode = .recording
    @Published var bars: [WaveformBar] = Array(repeating: .empty, count: 72)

    private let maxLevelCount = 72

    func resetLevels() {
        bars = Array(repeating: .empty, count: maxLevelCount)
    }

    func pushLevel(_ rawLevel: Double) {
        let noiseFloor = 0.006
        let normalized = max(0, min(1, (rawLevel - noiseFloor) / 0.11))
        let scaled = pow(normalized, 0.72)
        let bar = WaveformBar.fromLevel(scaled)
        bars.append(bar)
        if bars.count > maxLevelCount {
            bars.removeFirst(bars.count - maxLevelCount)
        }
    }
}

struct WaveformBar: Equatable {
    let height: CGFloat
    let opacity: Double

    static let empty = WaveformBar(height: 2.5, opacity: 0.24)

    static func fromLevel(_ level: Double) -> WaveformBar {
        let activity = min(1.0, max(0.025, level * 1.32))
        let height = CGFloat(max(2.5, min(42.0, 2.5 + 39.5 * activity)))
        let opacity = max(0.24, min(0.96, 0.24 + activity * 0.72))
        return WaveformBar(height: height, opacity: opacity)
    }
}

enum RecordingHUDMode {
    case recording
    case transcribing
}

struct RecordingHUDView: View {
    @ObservedObject var state: RecordingHUDState

    var body: some View {
        WaveformView(bars: state.bars)
            .frame(width: 318, height: 42)
            .padding(.horizontal, 21)
            .padding(.vertical, 18)
            .frame(width: 360, height: 78)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.055, green: 0.055, blue: 0.055),
                            Color.black
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct WaveformView: View {
    let bars: [WaveformBar]

    private let barCount = 72

    var body: some View {
        HStack(alignment: .center, spacing: 2.1) {
            ForEach(0..<barCount, id: \.self) { index in
                let bar = bars.indices.contains(index) ? bars[index] : .empty
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white.opacity(bar.opacity))
                    .frame(width: 2.2, height: bar.height)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
