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
        TabView(selection: $appState.selectedSettingsTab) {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            ModelsSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
                .tag(SettingsTab.models)

            PermissionsSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
                .tag(SettingsTab.permissions)
        }
        .frame(width: 420, height: 480)
    }
}

// MARK: - Key Code Mapping

/// Map a Carbon keyCode to a human-readable name.
private func keyCodeToName(_ keyCode: UInt16) -> String? {
    let map: [UInt16: String] = [
        // Letters
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x1F: "O", 0x20: "U", 0x22: "I",
        0x23: "P", 0x25: "L", 0x26: "J", 0x28: "K", 0x2D: "N",
        0x2E: "M",
        // Numbers
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6",
        0x17: "5", 0x19: "9", 0x1A: "7", 0x1C: "8", 0x1D: "0",
        // Special keys
        0x31: "Space", 0x24: "Return", 0x30: "Tab", 0x35: "Escape",
        0x33: "Delete", 0x75: "Forward Delete",
        0x7B: "Left Arrow", 0x7C: "Right Arrow",
        0x7D: "Down Arrow", 0x7E: "Up Arrow",
        0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down",
        // Punctuation
        0x1B: "-", 0x18: "=", 0x21: "[", 0x1E: "]",
        0x2A: "\\", 0x29: ";", 0x27: "'", 0x2B: ",",
        0x2F: ".", 0x2C: "/", 0x32: "`",
        // Function keys
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
    return map[keyCode]
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
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Launch Sotto at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { guard loaded else { return }; setLaunchAtLogin(launchAtLogin) }
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
                            HStack(spacing: 6) {
                                if isRecordingShortcut {
                                    Image(systemName: "record.circle")
                                        .foregroundStyle(.red)
                                    Text("Press shortcut...")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(shortcutDisplay)
                                        .fontWeight(.medium)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isRecordingShortcut ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
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
                            .font(.caption)
                            .foregroundStyle(.orange)
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
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
                    Text("Requires Accessibility permission in System Settings")
                        .font(.caption2)
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
