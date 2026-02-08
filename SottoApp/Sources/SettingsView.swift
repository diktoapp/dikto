import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ModelsSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var autoCopy = true
    @State private var autoPaste = true
    @State private var maxDuration: Double = 30
    @State private var silenceDuration: Double = 1500
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Sotto at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
            }

            Section("Clipboard") {
                Toggle("Auto-copy transcription to clipboard", isOn: $autoCopy)
                    .onChange(of: autoCopy) { saveSettings() }
                Toggle("Auto-paste after recording", isOn: $autoPaste)
                    .onChange(of: autoPaste) { saveSettings() }

            }

            Section("Recording") {
                HStack {
                    Text("Max duration:")
                    Slider(value: $maxDuration, in: 5...120, step: 5) {
                        Text("Max duration")
                    }
                    .onChange(of: maxDuration) { saveSettings() }
                    Text("\(Int(maxDuration))s")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                HStack {
                    Text("Silence timeout:")
                    Slider(value: $silenceDuration, in: 500...5000, step: 250) {
                        Text("Silence timeout")
                    }
                    .onChange(of: silenceDuration) { saveSettings() }
                    Text("\(Int(silenceDuration))ms")
                        .monospacedDigit()
                        .frame(width: 60)
                }
            }
        }
        .padding()
        .onAppear { loadSettings() }
    }

    private func loadSettings() {
        guard let cfg = appState.config else { return }
        autoCopy = cfg.autoCopy
        autoPaste = cfg.autoPaste
        maxDuration = Double(cfg.maxDuration)
        silenceDuration = Double(cfg.silenceDurationMs)
        loadLaunchAtLogin()
    }

    private func loadLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[Sotto] Launch at login error: \(error)")
            // Revert toggle on failure
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func saveSettings() {
        guard let cfg = appState.config else { return }
        let newConfig = SottoConfig(
            modelName: cfg.modelName,
            language: cfg.language,
            maxDuration: UInt32(maxDuration),
            silenceDurationMs: UInt32(silenceDuration),
            speechThreshold: cfg.speechThreshold,
            globalShortcut: cfg.globalShortcut,
            autoPaste: autoPaste,
            autoCopy: autoCopy
        )
        appState.updateConfig(newConfig)
    }
}

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Models")
                .font(.headline)

            List(appState.models, id: \.name) { model in
                HStack {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(model.name)
                                .fontWeight(model.name == appState.config?.modelName ? .bold : .regular)
                            if model.name == appState.config?.modelName {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        Text(model.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(model.sizeMb) MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if model.isDownloaded {
                        if model.name != appState.config?.modelName {
                            Button("Use") {
                                appState.switchModel(name: model.name)
                            }
                            .controlSize(.small)
                        }
                    } else {
                        Text("Not downloaded")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 2)
            }

            Text("Download models via terminal: sotto --setup")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { appState.refreshModels() }
    }
}
