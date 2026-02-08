import AppKit
import Carbon
import Foundation
import SwiftUI

extension Notification.Name {
    static let sottoHotKeyPressed = Notification.Name("sottoHotKeyPressed")
}

/// Callback that bridges UniFFI transcription events to AppState.
final class AppCallback: TranscriptionCallback {
    nonisolated(unsafe) private weak var appState: AppState?

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
        NSLog("[Sotto] onStateChange called: \(state)")
        DispatchQueue.main.async { [weak self] in
            NSLog("[Sotto] onStateChange main queue: self=\(self != nil), appState=\(self?.appState != nil)")
            guard let appState = self?.appState else {
                NSLog("[Sotto] WARNING: appState is nil, cannot handle state change!")
                return
            }
            switch state {
            case .idle:
                appState.isRecording = false
                appState.isProcessing = false
            case .listening:
                appState.isRecording = true
                appState.isProcessing = false
                appState.overlayController.show(text: "Speak now...", isProcessing: false)
            case .processing:
                appState.isProcessing = true
                appState.overlayController.show(text: appState.partialText, isProcessing: true)
            case let .done(text):
                NSLog("[Sotto] Done received, hiding overlay. text='\(text.prefix(60))'")
                appState.isRecording = false
                appState.isProcessing = false
                appState.overlayController.hide()
                NSLog("[Sotto] Overlay hidden")
                appState.handleTranscriptionDone(text)
            case let .error(message):
                appState.isRecording = false
                appState.isProcessing = false
                appState.overlayController.hide()
                appState.lastError = message
            }
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
    @Published var modelLoaded = false
    let overlayController = RecordingOverlayController()
    private var engine: SottoEngine?
    private var sessionHandle: SessionHandle?
    private var activeCallback: AppCallback?
    private var hotKeyRef: EventHotKeyRef?

    init() {
        loadEngine()
        setupGlobalShortcut()
    }

    private func setupGlobalShortcut() {
        // Use Carbon RegisterEventHotKey — works globally without Accessibility permissions
        let hotKeyID = EventHotKeyID(signature: OSType(0x534F5454), id: 1) // "SOTT"
        var ref: EventHotKeyRef?
        // kVK_ANSI_R = 0x0F, optionKey = 0x0800
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("[Sotto] Failed to register global hotkey: \(status)")
        }

        // Install Carbon event handler for the hot key
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            // Dispatch to main queue to call toggleRecording
            DispatchQueue.main.async {
                // Access the shared AppState via NSApp delegate pattern
                // Since we can't capture self in a C function pointer, use NotificationCenter
                NotificationCenter.default.post(name: .sottoHotKeyPressed, object: nil)
            }
            return noErr
        }, 1, &eventType, nil, nil)

        // Listen for the notification
        NotificationCenter.default.addObserver(
            forName: .sottoHotKeyPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.toggleRecording()
            }
        }
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }

    private func loadEngine() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            NSLog("[Sotto] Creating SottoEngine...")
            let engine = SottoEngine()
            NSLog("[Sotto] Loading model...")
            do {
                try engine.loadModel()
                NSLog("[Sotto] Model loaded successfully")
                DispatchQueue.main.async {
                    self?.engine = engine
                    self?.modelLoaded = true
                    self?.refreshModels()
                    self?.refreshConfig()
                }
            } catch {
                NSLog("[Sotto] Model load failed: \(error)")
                DispatchQueue.main.async {
                    self?.engine = engine
                    self?.modelLoaded = false
                    self?.lastError = "Model not loaded: \(error.localizedDescription)"
                    self?.refreshModels()
                    self?.refreshConfig()
                }
            }
        }
    }

    func refreshModels() {
        guard let engine else { return }
        models = engine.listModels()
    }

    func refreshConfig() {
        guard let engine else { return }
        config = engine.getConfig()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard let engine, modelLoaded else {
            lastError = "Model not loaded. Run: sotto --setup"
            return
        }

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

        let callback = AppCallback(appState: self)
        activeCallback = callback
        do {
            sessionHandle = try engine.startListening(listenConfig: listenConfig, callback: callback)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopRecording() {
        sessionHandle?.stop()
        sessionHandle = nil
        activeCallback = nil
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
            NSLog("[Sotto] Copied to clipboard: \(cleaned.prefix(50))...")
        }

        // Auto-paste (Cmd+V) — just attempt it; needs Accessibility permission
        // Transcript stays on clipboard after paste (no save/restore race)
        if wantPaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.simulatePaste()
            }
        }
    }

    private func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) // 'v'
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func switchModel(name: String) {
        guard let engine else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try engine.switchModel(modelName: name)
                DispatchQueue.main.async {
                    self?.modelLoaded = true
                    self?.refreshModels()
                    self?.refreshConfig()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    func updateConfig(_ newConfig: SottoConfig) {
        guard let engine else { return }
        do {
            try engine.updateConfig(config: newConfig)
            refreshConfig()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
