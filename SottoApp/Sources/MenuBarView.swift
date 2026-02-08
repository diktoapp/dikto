import SwiftUI

/// Dismiss the MenuBarExtra popover window.
private func dismissMenuBarExtra() {
    for window in NSApp.windows where window is NSPanel && window.isVisible && window.level.rawValue > NSWindow.Level.normal.rawValue {
        window.close()
        return
    }
}

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
                .font(.body)

            Divider()

            Text(appState.isRecording ? "⌥R to stop" : "⌥R to record")
                .foregroundColor(.secondary)

            if !appState.finalText.isEmpty {
                Divider()
                let truncated = appState.finalText.count > 80
                    ? String(appState.finalText.prefix(80)) + "..."
                    : appState.finalText
                Text(truncated)
            }

            if let error = appState.lastError {
                Divider()
                Text("⚠ \(error)")
            }

            HStack(spacing: 4) {
                Text(appState.config?.modelName ?? "No model")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if appState.modelInMemory {
                    Text("(loaded)")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Divider()

            Button("Settings...") {
                dismissMenuBarExtra()
                SettingsWindowController.shared.show(appState: appState)
            }

            Divider()

            Button("Quit Sotto") {
                dismissMenuBarExtra()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
        .frame(width: 272)
    }

    private var statusText: String {
        if appState.isProcessing {
            return "Processing..."
        }
        if appState.isRecording {
            return "Recording..."
        }
        if !appState.modelAvailable {
            return "No model downloaded"
        }
        return "Ready"
    }
}
