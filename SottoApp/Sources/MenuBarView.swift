import SwiftUI

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
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
                let truncated = String(appState.finalText.prefix(80))
                Text(truncated)
            }

            if let error = appState.lastError {
                Divider()
                Text("⚠ \(error)")
            }

            Text(appState.config?.modelName ?? "No model")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Button("Settings...") {
                NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
            }

            Divider()

            Button("Quit Sotto") {
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
        if !appState.modelLoaded {
            return "No model loaded"
        }
        return "Ready"
    }
}
