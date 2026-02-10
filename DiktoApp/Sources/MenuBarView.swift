import SwiftUI

/// Dismiss the MenuBarExtra popover window.
private func dismissMenuBarExtra() {
    for window in NSApp.windows where window is NSPanel && window.isVisible && window.level.rawValue > NSWindow.Level.normal.rawValue {
        window.close()
        return
    }
}

/// Button style matching macOS system menu rows: rounded-rect highlight on hover.
struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header: bold title + right-aligned status
            HStack {
                Text("Dikto")
                    .fontWeight(.bold)
                Spacer()
                if !statusText.isEmpty {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Text(shortcutHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            Divider()

            // Model info
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.config?.modelName ?? "No model")
                    modelMemoryStatus
                }
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Last transcript (only when present)
            if !appState.finalText.isEmpty {
                Divider()
                Text("Last Transcript")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                let truncated = appState.finalText.count > 80
                    ? String(appState.finalText.prefix(80)) + "..."
                    : appState.finalText
                Text(truncated)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }

            // Error
            if let error = appState.lastError {
                Divider()
                Text("⚠ \(error)")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }

            Divider()

            // Actions
            Button {
                dismissMenuBarExtra()
                SettingsWindowController.shared.show(appState: appState)
            } label: {
                Text("Settings...")
            }
            .buttonStyle(MenuRowButtonStyle())

            Divider()

            Button {
                dismissMenuBarExtra()
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
            }
            .buttonStyle(MenuRowButtonStyle())
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(6)
        .frame(width: 280)
        .onAppear {
            appState.accessibilityGranted = probeAccessibilityPermission()
            if appState.needsOnboarding {
                OnboardingWindowController.shared.show(appState: appState)
            }
        }
    }

    private var shortcutHint: String {
        let shortcut = formatShortcutForDisplay(appState.config?.globalShortcut ?? "option+r")
        let isHold = appState.config?.activationMode == .hold

        if appState.isRecording {
            return isHold ? "Release \(shortcut) to stop" : "\(shortcut) to stop"
        } else {
            return isHold ? "Hold \(shortcut) to record" : "\(shortcut) to record"
        }
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
        return ""
    }

    @ViewBuilder
    private var modelMemoryStatus: some View {
        if appState.modelInMemory {
            Text("Loaded\(modelSizeString)")
                .font(.caption)
                .foregroundStyle(.green)
        } else if appState.modelAvailable {
            Text("Not loaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Not downloaded")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var modelSizeString: String {
        guard let modelName = appState.config?.modelName,
              let model = appState.models.first(where: { $0.name == modelName })
        else { return "" }
        if model.sizeMb >= 1024 {
            return String(format: " (~%.1f GB)", Double(model.sizeMb) / 1024.0)
        }
        return " (~\(model.sizeMb) MB)"
    }
}
