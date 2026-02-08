import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            HStack {
                Circle()
                    .fill(appState.modelLoaded ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()

            // Record button
            Button(action: { appState.toggleRecording() }) {
                HStack {
                    Image(systemName: appState.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(appState.isRecording ? .red : .primary)
                    Text(appState.isRecording ? "Stop Recording" : "Start Recording")
                    Spacer()
                    Text("⌥R")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .keyboardShortcut("r", modifiers: .option)
            .disabled(!appState.modelLoaded)
            .padding(.horizontal, 4)

            // Last transcription
            if !appState.finalText.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Last transcription:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("(copied to clipboard)")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    Text(appState.finalText)
                        .font(.caption)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
            }

            // Transcript history
            if !appState.transcriptHistory.isEmpty {
                Divider()
                Menu {
                    ForEach(appState.transcriptHistory) { entry in
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                        }) {
                            Text(entry.text.prefix(60) + (entry.text.count > 60 ? "..." : ""))
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("History (\(appState.transcriptHistory.count))")
                        Spacer()
                    }
                }
                .padding(.horizontal, 4)
            }

            // Error display
            if let error = appState.lastError {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 12)
            }

            Divider()

            // Model selector
            Menu {
                ForEach(appState.models, id: \.name) { model in
                    Button(action: { appState.switchModel(name: model.name) }) {
                        HStack {
                            if model.name == appState.config?.modelName {
                                Image(systemName: "checkmark")
                            }
                            Text("\(model.name) (\(model.sizeMb)MB)")
                            if !model.isDownloaded {
                                Text("(not downloaded)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!model.isDownloaded)
                }
            } label: {
                HStack {
                    Image(systemName: "cpu")
                    Text("Model: \(appState.config?.modelName ?? "none")")
                    Spacer()
                }
            }
            .padding(.horizontal, 4)

            Divider()

            // Settings
            Button(action: {
                if NSApp.responds(to: Selector(("showSettingsWindow:"))) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
                NSApp.activate(ignoringOtherApps: true)
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings...")
                }
            }
            .padding(.horizontal, 4)

            Divider()

            // Quit
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Text("Quit Sotto")
                    Spacer()
                    Text("⌘Q")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .keyboardShortcut("q", modifiers: .command)
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 4)
        .frame(width: 300)
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
