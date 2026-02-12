import ServiceManagement
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case models
    case permissions
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedSettingsTab) {
                Label("General", systemImage: "gear")
                    .tag(SettingsTab.general)
                Label("Models", systemImage: "cpu")
                    .tag(SettingsTab.models)
                Label("Permissions", systemImage: "lock.shield")
                    .tag(SettingsTab.permissions)
            }
            .navigationSplitViewColumnWidth(Theme.Layout.sidebarWidth)
        } detail: {
            switch appState.selectedSettingsTab {
            case .general:
                GeneralSettingsView().environmentObject(appState)
            case .models:
                ModelsSettingsView().environmentObject(appState)
            case .permissions:
                PermissionsSettingsView().environmentObject(appState)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: Theme.Layout.settingsWidth, height: Theme.Layout.settingsHeight)
    }
}

// MARK: - Key Code Mapping

/// Map a Carbon keyCode to a human-readable name.
private func keyCodeToName(_ keyCode: UInt16) -> String? {
    KeyCodes.codeToDisplay[keyCode]
}

/// Build both storage format ("option+r") and display format ("Option+R") from key event data.
private func buildShortcutString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> (value: String, display: String)? {
    guard let keyName = keyCodeToName(keyCode) else { return nil }

    var modParts: [(value: String, display: String)] = []
    if modifiers.contains(.control) { modParts.append(("control", "Control")) }
    if modifiers.contains(.option) { modParts.append(("option", "Option")) }
    if modifiers.contains(.shift) { modParts.append(("shift", "Shift")) }
    if modifiers.contains(.command) { modParts.append(("command", "Command")) }

    guard !modParts.isEmpty else { return nil }

    let value = (modParts.map(\.value) + [keyName.lowercased()]).joined(separator: "+")
    let display = (modParts.map(\.display) + [keyName]).joined(separator: "+")
    return (value: value, display: display)
}

/// Format a stored shortcut string for display: "option+r" → "Option+R"
func formatShortcutForDisplay(_ shortcut: String) -> String {
    let displayMap = [
        "option": "Option", "command": "Command",
        "control": "Control", "shift": "Shift",
    ]
    return shortcut
        .split(separator: "+")
        .map { part in
            let s = String(part)
            return displayMap[s] ?? s.capitalized
        }
        .joined(separator: "+")
}

/// Check for known system shortcut conflicts.
private func checkSystemConflict(_ shortcut: String) -> String? {
    let conflicts: [String: String] = [
        "command+q": "Quit application",
        "command+w": "Close window",
        "command+h": "Hide application",
        "command+m": "Minimize window",
        "command+tab": "App switcher",
        "command+space": "Spotlight",
        "command+shift+3": "Screenshot (full)",
        "command+shift+4": "Screenshot (selection)",
        "command+shift+5": "Screenshot options",
    ]
    if let conflict = conflicts[shortcut.lowercased()] {
        return "Conflicts with system shortcut: \(conflict)"
    }
    return nil
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

    // Shortcut recorder state
    @State private var isRecordingShortcut = false
    @State private var shortcutDisplay = "Option+R"
    @State private var shortcutValue = "option+r"
    @State private var activationMode: ActivationMode = .hold
    @State private var shortcutError: String?
    @State private var keyMonitor: Any?

    var body: some View {
        Form {
            Section {
                Toggle("Launch Dikto at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { guard loaded else { return }; setLaunchAtLogin(launchAtLogin) }
                    .help("Automatically start Dikto when you log in")
            }

            Section("Shortcut") {
                    HStack {
                        Text("Hotkey")
                        Spacer()
                        Button(action: {
                            if isRecordingShortcut {
                                cancelRecording()
                            } else {
                                startRecordingShortcut()
                            }
                        }) {
                            HStack(spacing: Theme.Spacing.xs) {
                                if isRecordingShortcut {
                                    Image(systemName: "record.circle")
                                        .foregroundStyle(Theme.Colors.statusRecording)
                                    Text("Press shortcut...")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(shortcutDisplay)
                                        .fontWeight(.medium)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.md)
                                    .fill(isRecordingShortcut ? Theme.Colors.statusRecording.opacity(0.1) : Color.secondary.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isRecording)

                        if shortcutValue != "option+r" {
                            Button("Reset") {
                                shortcutValue = "option+r"
                                shortcutDisplay = "Option+R"
                                shortcutError = nil
                                saveSettings()
                            }
                            .controlSize(.small)
                        }
                    }

                    if let error = shortcutError {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.statusWarning)
                    }

                    Picker("Activation mode", selection: $activationMode) {
                        Text("Push to Talk (Hold)").tag(ActivationMode.hold)
                        Text("Toggle (Press)").tag(ActivationMode.toggle)
                    }
                    .onChange(of: activationMode) {
                        guard loaded else { return }
                        saveSettings()
                    }

                    Text(activationMode == .hold
                        ? "Hold the hotkey to record, release to stop."
                        : "Press the hotkey to start recording, press again to stop.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.tertiary)
                }

                Section("Behavior") {
                    Toggle("Copy result to clipboard", isOn: $autoCopy)
                        .onChange(of: autoCopy) { guard loaded else { return }; saveSettings() }
                        .disabled(autoPaste)
                        .help("Copy transcribed text to the clipboard")
                    Toggle("Auto-paste into active app", isOn: $autoPaste)
                        .onChange(of: autoPaste) {
                            guard loaded else { return }
                            if autoPaste { autoCopy = true }
                            saveSettings()
                        }
                        .help("Automatically paste transcribed text into the focused app")
                    Text("Requires Accessibility permission in System Settings")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.tertiary)
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

                if activationMode == .toggle {
                    Section("Recording") {
                        LabeledContent("Max duration") {
                            HStack(spacing: Theme.Spacing.sm) {
                                Slider(value: $maxDuration, in: 5...120, step: 5)
                                    .onChange(of: maxDuration) { guard loaded else { return }; saveSettings() }
                                    .frame(maxWidth: 160)
                                Text("\(Int(maxDuration))s")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        .help("Maximum recording duration before auto-stop")

                        LabeledContent("Silence timeout") {
                            HStack(spacing: Theme.Spacing.sm) {
                                Slider(value: $silenceDuration, in: 500...5000, step: 250)
                                    .onChange(of: silenceDuration) { guard loaded else { return }; saveSettings() }
                                    .frame(maxWidth: 160)
                                Text(formatMs(Int(silenceDuration)))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        .help("Stop recording after this duration of silence")
                    }
                }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
        .onReceive(appState.$config) { _ in if !loaded { loadSettings() } }
        .onReceive(appState.$availableLanguages) { _ in
            if loaded, let cfg = appState.config {
                selectedLanguage = cfg.language
            }
        }
        .onDisappear { cancelRecording() }
    }

    // MARK: - Shortcut Recording

    private func startRecordingShortcut() {
        isRecordingShortcut = true
        shortcutError = nil
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels
            if event.keyCode == 0x35 {
                self.cancelRecording()
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let result = buildShortcutString(keyCode: event.keyCode, modifiers: mods) else {
                self.shortcutError = "Invalid key combination. Use modifier + key."
                return nil
            }

            // Check system conflicts
            if let conflict = checkSystemConflict(result.value) {
                self.shortcutError = conflict
                self.cancelRecording()
                return nil
            }

            self.shortcutValue = result.value
            self.shortcutDisplay = result.display
            self.shortcutError = nil
            self.cancelRecording()
            self.saveSettings()
            return nil
        }
    }

    private func cancelRecording() {
        isRecordingShortcut = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Helpers

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
        if let shortcut = cfg.globalShortcut {
            shortcutValue = shortcut
            shortcutDisplay = formatShortcutForDisplay(shortcut)
        }
        activationMode = cfg.activationMode
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
            NSLog("[Dikto] Launch at login error: \(error)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func saveSettings() {
        guard let cfg = appState.config else { return }
        let newConfig = DiktoConfig(
            modelName: cfg.modelName,
            language: selectedLanguage,
            maxDuration: UInt32(maxDuration),
            silenceDurationMs: UInt32(silenceDuration),
            speechThreshold: cfg.speechThreshold,
            globalShortcut: shortcutValue,
            autoPaste: autoPaste,
            autoCopy: autoCopy,
            activationMode: activationMode
        )
        appState.updateConfig(newConfig)
    }
}

struct ModelsSettingsView: View {
    @EnvironmentObject var appState: AppState

    private var noModelReady: Bool {
        !appState.models.contains(where: { $0.isDownloaded })
    }

    var body: some View {
        Form {
            if noModelReady {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.statusWarning)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No model installed")
                                .fontWeight(.medium)
                                .font(Theme.Typography.callout)
                            Text("Download a model below to start using Dikto. Parakeet TDT 0.6B v2 is recommended for best accuracy.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Available Models") {
                ForEach(appState.models, id: \.name) { model in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(model.name)
                                    .fontWeight(isActive(model) ? .semibold : .regular)
                                if isActive(model) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.Colors.statusActive)
                                        .font(Theme.Typography.caption)
                                }
                            }
                            Text(model.description)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(formatSize(model.sizeMb))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.tertiary)

                        if let progress = appState.downloadProgress[model.name] {
                            VStack(spacing: 2) {
                                ProgressView(value: progress)
                                    .frame(width: 60)
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .transition(.opacity)
                        } else if model.isDownloaded {
                            if !isActive(model) {
                                Button("Use") {
                                    appState.switchModel(name: model.name)
                                }
                                .controlSize(.small)
                                .help("Switch to this model")
                            } else {
                                Text("Active")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button("Download") {
                                appState.downloadModel(name: model.name)
                            }
                            .controlSize(.small)
                            .disabled(!appState.downloadProgress.isEmpty)
                            .help("Download this model to your device")
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xxs)
                }
            }

            Section {
                HStack {
                    Text("Or via terminal:")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                    Text("dikto --setup --model <name>")
                        .font(Theme.Typography.mono)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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
