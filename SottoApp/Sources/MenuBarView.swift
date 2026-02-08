import SwiftUI

/// Dismiss the MenuBarExtra popover window by sending Escape to it.
private func dismissMenuBarExtra() {
    // Find the MenuBarExtra panel and close it
    for window in NSApp.windows {
        // MenuBarExtra .window style creates an NSPanel subclass
        if window is NSPanel, window.isVisible, window.className.contains("StatusBarWindow")
            || window.className.contains("MenuBarExtraWindow")
            || (window.level.rawValue > NSWindow.Level.normal.rawValue && window.styleMask.contains(.nonactivatingPanel))
        {
            window.close()
            return
        }
    }
    // Fallback: post escape key to dismiss any popover
    let esc = CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: true)
    esc?.post(tap: .cghidEventTap)
    let escUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: false)
    escUp?.post(tap: .cghidEventTap)
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
