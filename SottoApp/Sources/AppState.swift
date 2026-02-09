import AppKit
import AVFoundation
import Carbon
import Foundation
import SwiftUI

extension Notification.Name {
    static let sottoHotKeyPressed = Notification.Name("sottoHotKeyPressed")
    static let sottoHotKeyReleased = Notification.Name("sottoHotKeyReleased")
}

// MARK: - Carbon HotKey Helpers

struct CarbonHotKey {
    let keyCode: UInt32
    let modifiers: UInt32
}

/// Map a key name (lowercase) to its Carbon virtual key code.
func nameToKeyCode(_ name: String) -> UInt16? {
    let map: [String: UInt16] = [
        // Letters
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
        "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
        "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
        "y": 0x10, "t": 0x11, "u": 0x20, "i": 0x22, "p": 0x23,
        "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "o": 0x1F,
        // Numbers
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        // Special keys
        "space": 0x31, "return": 0x24, "tab": 0x30, "escape": 0x35,
        "delete": 0x33, "forwarddelete": 0x75,
        "leftarrow": 0x7B, "rightarrow": 0x7C,
        "downarrow": 0x7D, "uparrow": 0x7E,
        "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
        // Punctuation
        "-": 0x1B, "=": 0x18, "[": 0x21, "]": 0x1E,
        "\\": 0x2A, ";": 0x29, "'": 0x27, ",": 0x2B,
        ".": 0x2F, "/": 0x2C, "`": 0x32,
        // Function keys
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    ]
    return map[name]
}

/// Parse a shortcut string like "option+r" into Carbon keyCode + modifiers.
func parseCarbonHotKey(from shortcut: String) -> CarbonHotKey? {
    let parts = shortcut.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }

    var modifiers: UInt32 = 0
    var keyName: String?

    for part in parts {
        switch part {
        case "option": modifiers |= UInt32(optionKey)
        case "command": modifiers |= UInt32(cmdKey)
        case "control": modifiers |= UInt32(controlKey)
        case "shift": modifiers |= UInt32(shiftKey)
        default: keyName = part
        }
    }

    guard let key = keyName, let keyCode = nameToKeyCode(key) else { return nil }
    guard modifiers != 0 else { return nil }

    return CarbonHotKey(keyCode: UInt32(keyCode), modifiers: modifiers)
}

// MARK: - Accessibility Probe

/// Probe whether Accessibility permission is *actually* working right now.
///
/// `AXIsProcessTrusted()` caches its result for the process lifetime, so if the
/// user *removes* the app from the Accessibility list (vs toggling it off), the
/// cache returns stale `true`. We use the cached value as a fast first check
/// (it's always correct when it says `false`), then verify with a real AX call
/// only when the cache claims `true`.
func probeAccessibilityPermission() -> Bool {
    // Fast path: AXIsProcessTrusted() is reliable when it returns false.
    guard AXIsProcessTrusted() else { return false }

    // Cache says true — verify with a real AX call to catch stale entries.
    // When the TCC entry is *removed*, the cache is stale and the AX call
    // returns .apiDisabled or .cannotComplete.
    let systemWide = AXUIElementCreateSystemWide()
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(
        systemWide,
        kAXFocusedApplicationAttribute as CFString,
        &value
    )
    if result == .apiDisabled || result == .cannotComplete {
        return false
    }
    // .success, .noValue (no focused app), etc. — AX is working.
    return true
}

/// Callback that bridges UniFFI transcription events to AppState.
final class AppCallback: TranscriptionCallback, @unchecked Sendable {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func onPartial(text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.appState?.partialText = text
            self?.appState?.updateOverlay()
        }
    }

    func onFinalSegment(text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.appState?.partialText = text
            self?.appState?.updateOverlay()
        }
    }

    func onSilence() {}

    func onError(error: String) {
        DispatchQueue.main.async { [weak self] in
            self?.appState?.lastError = error
        }
    }

    func onStateChange(state: RecordingState) {
        DispatchQueue.main.async { [weak self] in
            guard let appState = self?.appState else { return }
            switch state {
            case .listening:
                appState.isRecording = true
                appState.isProcessing = false
                appState.overlayController.show(text: "Speak now...", isProcessing: false)
            case .processing:
                appState.isProcessing = true
                appState.overlayController.show(text: appState.partialText, isProcessing: true)
            case let .done(text):
                appState.isRecording = false
                appState.isProcessing = false
                appState.modelInMemory = true
                appState.overlayController.hide()
                appState.handleTranscriptionDone(text)
                appState.scheduleIdleUnload()
            case let .error(message):
                appState.isRecording = false
                appState.isProcessing = false
                appState.overlayController.hide()
                appState.lastError = message
                if appState.modelInMemory { appState.scheduleIdleUnload() }
            }
        }
    }
}

/// Callback that bridges UniFFI download progress events to AppState.
final class DownloadCallback: DownloadProgressCallback, @unchecked Sendable {
    private weak var appState: AppState?
    private let modelName: String

    init(appState: AppState, modelName: String) {
        self.appState = appState
        self.modelName = modelName
    }

    func onProgress(bytesDownloaded: UInt64, totalBytes: UInt64) {
        let progress = totalBytes > 0 ? Double(bytesDownloaded) / Double(totalBytes) : 0.0
        DispatchQueue.main.async { [weak self] in
            guard let name = self?.modelName else { return }
            self?.appState?.downloadProgress[name] = progress
        }
    }

    func onComplete(modelName: String) {
        DispatchQueue.main.async { [weak self] in
            self?.appState?.downloadProgress.removeValue(forKey: modelName)
            self?.appState?.refreshModels()
            self?.appState?.refreshModelAvailability()
        }
    }

    func onError(error: String) {
        DispatchQueue.main.async { [weak self] in
            guard let name = self?.modelName else { return }
            self?.appState?.downloadProgress.removeValue(forKey: name)
            self?.appState?.lastError = "Download failed: \(error)"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var partialText = ""
    @Published var finalText = ""
    @Published var lastError: String?
    @Published var models: [ModelInfoRecord] = []
    @Published var config: SottoConfig?
    @Published var modelAvailable = false
    @Published var modelInMemory = false
    @Published var downloadProgress: [String: Double] = [:]
    @Published var availableLanguages: [LanguageInfo] = []
    @Published var accessibilityGranted = false
    @Published var selectedSettingsTab: SettingsTab = .general
    let overlayController = RecordingOverlayController()
    private var engine: SottoEngine?
    private var sessionHandle: SessionHandle?
    private var activeCallback: AppCallback?
    private var hotKeyRef: EventHotKeyRef?
    private var pressedHandlerRef: EventHandlerRef?
    private var releasedHandlerRef: EventHandlerRef?
    private var startingRecording = false
    private var holdStartTime: Date?
    private var currentShortcut: String?
    private var currentMode: ActivationMode = .hold
    private var idleUnloadTimer: Timer?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private static let idleUnloadInterval: TimeInterval = 300  // 5 minutes

    init() {
        loadEngine()
        setupGlobalShortcut()
        accessibilityGranted = probeAccessibilityPermission()
        setupMemoryPressureMonitor()
    }

    private func setupGlobalShortcut() {
        let shortcut = config?.globalShortcut ?? "option+r"
        let mode = config?.activationMode ?? .hold
        registerHotKey(shortcut: shortcut, mode: mode)

        // Listen for pressed notification
        NotificationCenter.default.addObserver(
            forName: .sottoHotKeyPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleHotKeyPressed()
            }
        }

        // Listen for released notification
        NotificationCenter.default.addObserver(
            forName: .sottoHotKeyReleased,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleHotKeyReleased()
            }
        }
    }

    private func registerHotKey(shortcut: String, mode: ActivationMode) {
        unregisterHotKey()

        guard let hotKey = parseCarbonHotKey(from: shortcut) else {
            NSLog("[Sotto] Failed to parse shortcut: \(shortcut)")
            return
        }

        currentShortcut = shortcut
        currentMode = mode

        let hotKeyID = EventHotKeyID(signature: OSType(0x534F5454), id: 1) // "SOTT"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("[Sotto] Failed to register global hotkey: \(status)")
            return
        }

        // Install pressed handler (always)
        var pressedEventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var pressedRef: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sottoHotKeyPressed, object: nil)
            }
            return noErr
        }, 1, &pressedEventType, nil, &pressedRef)
        pressedHandlerRef = pressedRef

        // Install released handler (only for hold mode)
        if mode == .hold {
            var releasedEventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            var releasedRef: EventHandlerRef?
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .sottoHotKeyReleased, object: nil)
                }
                return noErr
            }, 1, &releasedEventType, nil, &releasedRef)
            releasedHandlerRef = releasedRef
        }

        NSLog("[Sotto] Registered hotkey: \(shortcut) mode: \(mode == .hold ? "hold" : "toggle")")
    }

    private func unregisterHotKey() {
        if let ref = pressedHandlerRef {
            RemoveEventHandler(ref)
            pressedHandlerRef = nil
        }
        if let ref = releasedHandlerRef {
            RemoveEventHandler(ref)
            releasedHandlerRef = nil
        }
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func handleHotKeyPressed() {
        switch currentMode {
        case .toggle:
            toggleRecording()
        case .hold:
            if !isRecording {
                holdStartTime = Date()
                startRecording()
            } else {
                // Already recording from a quick tap — toggle stop
                stopRecording()
                holdStartTime = nil
            }
        }
    }

    private func handleHotKeyReleased() {
        guard currentMode == .hold else { return }
        guard isRecording else { return }

        if let start = holdStartTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0.2 {
                // Held long enough — stop recording
                stopRecording()
            }
            // else: quick tap (<200ms), keep recording — next press will toggle-stop
        }
        holdStartTime = nil
    }

    deinit {
        idleUnloadTimer?.invalidate()
        memoryPressureSource?.cancel()
        NotificationCenter.default.removeObserver(self)
        // Inline cleanup since deinit can't call @MainActor methods
        if let ref = pressedHandlerRef {
            RemoveEventHandler(ref)
        }
        if let ref = releasedHandlerRef {
            RemoveEventHandler(ref)
        }
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }

    private func loadEngine() {
        NSLog("[Sotto] Creating SottoEngine...")
        let engine = SottoEngine()
        self.engine = engine
        self.modelAvailable = engine.isModelAvailable()
        self.modelInMemory = engine.isModelLoaded()
        refreshModels()
        refreshConfig()
        refreshLanguages()
        NSLog("[Sotto] Engine ready. Model available on disk: \(modelAvailable)")
    }

    func refreshModels() {
        guard let engine else { return }
        models = engine.listModels()
    }

    func refreshModelAvailability() {
        guard let engine else { return }
        modelAvailable = engine.isModelAvailable()
        modelInMemory = engine.isModelLoaded()
    }

    func refreshConfig() {
        guard let engine else { return }
        config = engine.getConfig()
    }

    func refreshLanguages() {
        guard let engine else { return }
        availableLanguages = engine.availableLanguages()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !startingRecording else { return }
        guard let engine else {
            lastError = "Engine not initialized"
            return
        }
        guard modelAvailable else {
            lastError = "No model downloaded. Open Settings to download one."
            return
        }
        startingRecording = true

        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let axOK = probeAccessibilityPermission()
        accessibilityGranted = axOK

        if micOK && axOK {
            proceedWithRecording(engine: engine)
        } else {
            selectedSettingsTab = .permissions
            SettingsWindowController.shared.show(appState: self)
            startingRecording = false
        }
    }

    private func proceedWithRecording(engine: SottoEngine) {
        cancelIdleUnload()
        let cfg = engine.getConfig()
        let listenConfig = ListenConfig(
            language: cfg.language,
            maxDuration: cfg.maxDuration,
            silenceDurationMs: cfg.silenceDurationMs,
            speechThreshold: cfg.speechThreshold
        )

        partialText = ""
        finalText = ""
        lastError = nil
        isRecording = true  // Set immediately to prevent double-start during lazy load

        let callback = AppCallback(appState: self)
        activeCallback = callback
        do {
            sessionHandle = try engine.startListening(listenConfig: listenConfig, callback: callback)
        } catch {
            isRecording = false
            lastError = error.localizedDescription
        }
        startingRecording = false
    }

    func stopRecording() {
        sessionHandle?.stop()
        sessionHandle = nil
        // activeCallback is NOT nilled here — it must stay alive
        // so the Rust thread's .done/.error callbacks can reach AppState.
        // It gets replaced naturally on the next proceedWithRecording() call.
    }

    func updateOverlay() {
        if isRecording {
            overlayController.show(text: partialText, isProcessing: isProcessing)
        }
    }

    func handleTranscriptionDone(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        finalText = cleaned
        partialText = ""

        // Auto-copy / auto-paste
        let cfg = config ?? engine?.getConfig()
        let wantCopy = cfg?.autoCopy ?? true
        let wantPaste = cfg?.autoPaste ?? true

        if wantCopy || wantPaste {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cleaned, forType: .string)
            NSLog("[Sotto] Copied to clipboard")
        }

        if wantPaste {
            let axOK = probeAccessibilityPermission()
            accessibilityGranted = axOK
            if axOK {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.simulatePaste()
                }
            } else {
                lastError = "Accessibility permission lost — text copied to clipboard. Re-grant in Settings."
                selectedSettingsTab = .permissions
                SettingsWindowController.shared.show(appState: self)
            }
        }
    }

    private func simulatePaste() {
        guard probeAccessibilityPermission() else {
            accessibilityGranted = false
            if lastError == nil {
                lastError = "Accessibility permission lost — text copied to clipboard. Re-grant in Settings."
            }
            selectedSettingsTab = .permissions
            SettingsWindowController.shared.show(appState: self)
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) // 'v'
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func switchModel(name: String) {
        cancelIdleUnload()
        guard let engine else { return }
        do {
            try engine.switchModel(modelName: name)
            modelAvailable = engine.isModelAvailable()
            modelInMemory = engine.isModelLoaded()
            refreshModels()
            refreshConfig()
            refreshLanguages()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func downloadModel(name: String) {
        guard let engine else { return }
        let callback = DownloadCallback(appState: self, modelName: name)
        downloadProgress[name] = 0.0
        do {
            try engine.downloadModel(modelName: name, callback: callback)
        } catch {
            downloadProgress.removeValue(forKey: name)
            lastError = "Download failed: \(error.localizedDescription)"
        }
    }

    func updateConfig(_ newConfig: SottoConfig) {
        guard let engine else { return }

        // Detect if hotkey settings changed
        let shortcutChanged = newConfig.globalShortcut != config?.globalShortcut
        let modeChanged = newConfig.activationMode != config?.activationMode

        do {
            try engine.updateConfig(config: newConfig)
            refreshConfig()
        } catch {
            lastError = error.localizedDescription
            return
        }

        // Re-register hotkey if settings changed
        if shortcutChanged || modeChanged, let cfg = config {
            let shortcut = cfg.globalShortcut ?? "option+r"
            registerHotKey(shortcut: shortcut, mode: cfg.activationMode)
        }
    }

    // MARK: - Idle Model Unloading

    func scheduleIdleUnload() {
        idleUnloadTimer?.invalidate()
        idleUnloadTimer = Timer.scheduledTimer(
            withTimeInterval: Self.idleUnloadInterval, repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.performIdleUnload() }
            }
        }
    }

    private func cancelIdleUnload() {
        idleUnloadTimer?.invalidate()
        idleUnloadTimer = nil
    }

    private func performIdleUnload() {
        guard let engine, !isRecording, !isProcessing, engine.isModelLoaded() else { return }
        engine.unloadModel()
        modelInMemory = false
        NSLog("[Sotto] Model unloaded after idle timeout")
    }

    // MARK: - Memory Pressure

    private func setupMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handleMemoryPressure() }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressure() {
        guard let engine, !isRecording, !isProcessing, engine.isModelLoaded() else { return }
        engine.unloadModel()
        modelInMemory = false
        cancelIdleUnload()
        NSLog("[Sotto] Model unloaded due to system memory pressure")
    }
}
