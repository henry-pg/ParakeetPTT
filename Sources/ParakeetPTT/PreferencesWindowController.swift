import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    init(appState: AppState, onAutoPasteChanged: @escaping (Bool) -> Void, onOpenPrivacy: @escaping () -> Void) {
        let view = PreferencesView(
            appState: appState,
            onAutoPasteChanged: onAutoPasteChanged,
            onOpenPrivacy: onOpenPrivacy
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Parakeet PTT"
        window.setContentSize(NSSize(width: 420, height: 280))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PreferencesView: View {
    @ObservedObject var appState: AppState
    var onAutoPasteChanged: (Bool) -> Void
    var onOpenPrivacy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Parakeet PTT")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(appState.status)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Hotkey")
                    Spacer()
                    Text("Option-/")
                        .foregroundStyle(.secondary)
                }
                Toggle("Paste transcript automatically", isOn: $appState.autoPaste)
                    .onChange(of: appState.autoPaste) { _, value in
                        onAutoPasteChanged(value)
                    }
            }

            Divider()

            Text(appState.lastTranscript.isEmpty ? "No transcript yet." : appState.lastTranscript)
                .font(.body)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let lastError = appState.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            HStack {
                Button("Open Accessibility Settings", action: onOpenPrivacy)
                Spacer()
            }
        }
        .padding(22)
        .frame(minWidth: 420, minHeight: 280)
    }
}
