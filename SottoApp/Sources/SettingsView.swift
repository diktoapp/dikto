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
        .frame(width: 420, height: 400)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var autoCopy = true
    @State private var autoPaste = true
    @State private var maxDuration: Double = 30
    @State private var silenceDuration: Double = 1500
    @State private var selectedLanguage = "en"
    @State private var launchAtLogin = false
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Launch Sotto at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { guard loaded else { return }; setLaunchAtLogin(launchAtLogin) }
                }

                Section {
                    Toggle("Copy result to clipboard", isOn: $autoCopy)
                        .onChange(of: autoCopy) { guard loaded else { return }; saveSettings() }
                        .disabled(autoPaste)
                    Toggle("Auto-paste into active app", isOn: $autoPaste)
                        .onChange(of: autoPaste) {
                            guard loaded else { return }
                            if autoPaste { autoCopy = true }
                            saveSettings()
                        }
                }

                if appState.availableLanguages.count > 1 {
                    Section {
                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(appState.availableLanguages, id: \.code) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                        .onChange(of: selectedLanguage) {
                            guard loaded else { return }
                            saveSettings()
                        }
                    }
                }

                Section {
                    LabeledContent("Max duration") {
                        HStack(spacing: 8) {
                            Slider(value: $maxDuration, in: 5...120, step: 5)
                                .onChange(of: maxDuration) { guard loaded else { return }; saveSettings() }
                                .frame(maxWidth: 160)
                            Text("\(Int(maxDuration))s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    LabeledContent("Silence timeout") {
                        HStack(spacing: 8) {
                            Slider(value: $silenceDuration, in: 500...5000, step: 250)
                                .onChange(of: silenceDuration) { guard loaded else { return }; saveSettings() }
                                .frame(maxWidth: 160)
                            Text(formatMs(Int(silenceDuration)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { loadSettings() }
        .onReceive(appState.$config) { _ in if !loaded { loadSettings() } }
        .onReceive(appState.$availableLanguages) { _ in
            if loaded, let cfg = appState.config {
                selectedLanguage = cfg.language
            }
        }
    }

    private func formatMs(_ ms: Int) -> String {
        if ms >= 1000 && ms % 1000 == 0 {
            return "\(ms / 1000)s"
        }
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }

    private func loadSettings() {
        guard let cfg = appState.config else { return }
        autoCopy = cfg.autoCopy
        autoPaste = cfg.autoPaste
        maxDuration = Double(cfg.maxDuration)
        silenceDuration = Double(cfg.silenceDurationMs)
        selectedLanguage = cfg.language
        loadLaunchAtLogin()
        loaded = true
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
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func saveSettings() {
        guard let cfg = appState.config else { return }
        let newConfig = SottoConfig(
            modelName: cfg.modelName,
            language: selectedLanguage,
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
        VStack(spacing: 0) {
            List {
                ForEach(appState.models, id: \.name) { model in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(model.name)
                                    .fontWeight(isActive(model) ? .semibold : .regular)
                                if isActive(model) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                                Text(model.backend)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        model.backend == "Parakeet"
                                            ? Color.blue.opacity(0.15)
                                            : Color.purple.opacity(0.15)
                                    )
                                    .foregroundStyle(
                                        model.backend == "Parakeet"
                                            ? Color.blue
                                            : Color.purple
                                    )
                                    .cornerRadius(3)
                            }
                            Text(model.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(formatSize(model.sizeMb))
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if let progress = appState.downloadProgress[model.name] {
                            ProgressView(value: progress)
                                .frame(width: 60)
                        } else if model.isDownloaded {
                            if !isActive(model) {
                                Button("Use") {
                                    appState.switchModel(name: model.name)
                                }
                                .controlSize(.small)
                            } else {
                                Text("Active")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button("Download") {
                                appState.downloadModel(name: model.name)
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack {
                Text("Or via terminal:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("sotto --setup --model <name>")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear { appState.refreshModels() }
    }

    private func isActive(_ model: ModelInfoRecord) -> Bool {
        model.name == appState.config?.modelName
    }

    private func formatSize(_ mb: UInt32) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        }
        return "\(mb) MB"
    }
}
