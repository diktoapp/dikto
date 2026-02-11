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
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isHovered ? Theme.Colors.menuHover : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(Theme.Animation.quick, value: isHovered)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header + info section (grouped, no dividers between)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack {
                    Text("Dikto")
                        .font(Theme.Typography.sectionTitle)
                    Spacer()
                    if appState.isRecording {
                        Text("Recording...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else if appState.isProcessing {
                        Text("Processing...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)

            Divider()

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(shortcutHint)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text("Model: \(modelLabel)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)

            // Last transcript (only when present)
            if !appState.finalText.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                    Text("Last Transcript")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                    Text(appState.finalText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
            }

            // Error
            if let error = appState.lastError {
                Divider()
                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
            }

            Divider()

            Button {
                dismissMenuBarExtra()
                SettingsWindowController.shared.show(appState: appState)
            } label: {
                Text("Settings")
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
        .font(.body)
        .padding(Theme.Spacing.xs)
        .frame(width: Theme.Layout.menuBarWidth)
        .onAppear {
            appState.accessibilityGranted = probeAccessibilityPermission()
        }
    }

    // MARK: - Helpers

    private var modelLabel: String {
        if appState.modelAvailable {
            return appState.config?.modelName ?? "None"
        } else {
            return "None"
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
}
