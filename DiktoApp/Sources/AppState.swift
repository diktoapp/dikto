import AppKit
import AVFoundation
import Carbon
import Foundation
import SwiftUI

extension Notification.Name {
    static let diktoHotKeyPressed = Notification.Name("diktoHotKeyPressed")
    static let diktoHotKeyReleased = Notification.Name("diktoHotKeyReleased")
}

// MARK: - Carbon HotKey Helpers

struct CarbonHotKey {
    let keyCode: UInt32
    let modifiers: UInt32
}

/// Map a key name (lowercase) to its Carbon virtual key code.
func nameToKeyCode(_ name: String) -> UInt16? {
    KeyCodes.nameToCode[name]
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
        DispatchQueue.main.async { [self] in
            guard let appState = self.appState else { return }
            appState.downloadProgress.removeValue(forKey: modelName)
            appState.activeDownloadCallback = nil
            // Auto-switch to the downloaded model if none is currently available
            if !appState.modelAvailable {
                appState.switchModel(name: modelName)
            } else {
                appState.refreshModels()
                appState.refreshModelAvailability()
            }
        }
    }

    func onError(error: String) {
        let name = self.modelName
        DispatchQueue.main.async { [self] in
            guard let appState = self.appState else { return }
            appState.downloadProgress.removeValue(forKey: name)
            appState.activeDownloadCallback = nil
            appState.lastError = "Download failed: \(error)"
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
    @Published var config: DiktoConfig?
    @Published var modelAvailable = false
    @Published var modelInMemory = false
    @Published var downloadProgress: [String: Double] = [:]
    @Published var availableLanguages: [LanguageInfo] = []
    @Published var accessibilityGranted = false
    @Published var needsOnboarding = false
    @Published var selectedSettingsTab: SettingsTab = .general
    let overlayController = RecordingOverlayController()
    private var engine: DiktoEngine?
    private var sessionHandle: SessionHandle?
    private var activeCallback: AppCallback?
    var activeDownloadCallback: DownloadCallback?
    private var hotKeyRef: EventHotKeyRef?
    private var pressedHandlerRef: EventHandlerRef?
    private var releasedHandlerRef: EventHandlerRef?
    private var startingRecording = false

    private var currentShortcut: String?
    private var currentMode: ActivationMode = .hold
    private var idleUnloadTimer: Timer?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private static let idleUnloadInterval: TimeInterval = 300  // 5 minutes

    init() {
        loadEngine()
        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let axOK = probeAccessibilityPermission()
        accessibilityGranted = axOK

        // Always register the global hotkey — Carbon RegisterEventHotKey does
        // NOT require Accessibility permission. Only CGEvent-based paste does.
        setupGlobalShortcut()

        if !micOK || !axOK {
            needsOnboarding = true
            // Defer to after app finishes launching so NSWindow creation works
            DispatchQueue.main.async { [weak self] in
                guard let self, self.needsOnboarding else { return }
                OnboardingWindowController.shared.show(appState: self)
            }
        }
        setupMemoryPressureMonitor()
    }

    func onPermissionsGranted() {
        needsOnboarding = false
        accessibilityGranted = true
    }

    private func setupGlobalShortcut() {
        let shortcut = config?.globalShortcut ?? "option+r"
        let mode = config?.activationMode ?? .hold
        registerHotKey(shortcut: shortcut, mode: mode)

        // Listen for pressed notification
        NotificationCenter.default.addObserver(
            forName: .diktoHotKeyPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleHotKeyPressed()
            }
        }

        // Listen for released notification
        NotificationCenter.default.addObserver(
            forName: .diktoHotKeyReleased,
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
            NSLog("[Dikto] Failed to parse shortcut: \(shortcut)")
            return
        }

        currentShortcut = shortcut
        currentMode = mode

        let hotKeyID = EventHotKeyID(signature: OSType(0x44494B54), id: 1) // "DIKT"
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
            NSLog("[Dikto] Failed to register global hotkey: \(status)")
            return
        }

        // Install pressed handler (always)
        var pressedEventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var pressedRef: EventHandlerRef?
        let pressedStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .diktoHotKeyPressed, object: nil)
            }
            return noErr
        }, 1, &pressedEventType, nil, &pressedRef)

        if pressedStatus != noErr {
            NSLog("[Dikto] Failed to install pressed event handler: \(pressedStatus)")
            // Clean up the registered hotkey since handler failed
            if let ref = hotKeyRef {
                UnregisterEventHotKey(ref)
                hotKeyRef = nil
            }
            return
        }
        pressedHandlerRef = pressedRef

        // Install released handler (only for hold mode)
        if mode == .hold {
            var releasedEventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            var releasedRef: EventHandlerRef?
            let releasedStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .diktoHotKeyReleased, object: nil)
                }
                return noErr
            }, 1, &releasedEventType, nil, &releasedRef)

            if releasedStatus != noErr {
                NSLog("[Dikto] Failed to install released event handler: \(releasedStatus)")
                // Clean up pressed handler and hotkey
                if let ref = pressedHandlerRef {
                    RemoveEventHandler(ref)
                    pressedHandlerRef = nil
                }
                if let ref = hotKeyRef {
                    UnregisterEventHotKey(ref)
                    hotKeyRef = nil
                }
                return
            }
            releasedHandlerRef = releasedRef
        }

        NSLog("[Dikto] Registered hotkey: \(shortcut) mode: \(mode == .hold ? "hold" : "toggle")")
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
                startRecording()
            }
        }
    }

    private func handleHotKeyReleased() {
        guard currentMode == .hold else { return }
        guard isRecording else { return }
        stopRecording()
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
        NSLog("[Dikto] Creating DiktoEngine...")
        let engine = DiktoEngine()
        self.engine = engine
        self.modelAvailable = engine.isModelAvailable()
        self.modelInMemory = engine.isModelLoaded()
        refreshModels()
        refreshConfig()
        refreshLanguages()
        NSLog("[Dikto] Engine ready. Model available on disk: \(modelAvailable)")
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
            selectedSettingsTab = .models
            SettingsWindowController.shared.show(appState: self)
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

    private func proceedWithRecording(engine: DiktoEngine) {
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
            NSLog("[Dikto] Copied to clipboard")
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
            lastError = nil
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
        activeDownloadCallback = callback  // retain until completion
        downloadProgress[name] = 0.0
        do {
            try engine.downloadModel(modelName: name, callback: callback)
        } catch {
            activeDownloadCallback = nil
            downloadProgress.removeValue(forKey: name)
            lastError = "Download failed: \(error.localizedDescription)"
        }
    }

    func updateConfig(_ newConfig: DiktoConfig) {
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
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.performIdleUnload() }
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
        NSLog("[Dikto] Model unloaded after idle timeout")
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
        NSLog("[Dikto] Model unloaded due to system memory pressure")
    }
}
