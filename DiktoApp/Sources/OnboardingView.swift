import AppKit
import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axGranted: Bool = probeAccessibilityPermission()
    @State private var pollTimer: Timer?
    @State private var allGranted = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "ear.and.waveform")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                Text("Welcome to Dikto")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Two permissions needed to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            // Permission cards
            VStack(spacing: 12) {
                // Microphone card
                permissionCard(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Hear your voice and transcribe it into text.",
                    granted: micStatus == .authorized
                ) {
                    micActionButton
                }

                // Accessibility card
                permissionCard(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Register global hotkey and auto-paste transcriptions.",
                    granted: axGranted
                ) {
                    if !axGranted {
                        Button("Grant Accessibility") {
                            resetAndRequestAccessibility()
                        }
                        .controlSize(.small)
                    }
                }
            }

            // Footer
            Text("These permissions stay on your device.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if allGranted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All set! Starting Dikto...")
                        .fontWeight(.medium)
                }
                .transition(.opacity)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
    }

    // MARK: - Permission Card

    @ViewBuilder
    private func permissionCard<ActionContent: View>(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        @ViewBuilder action: () -> ActionContent
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .fontWeight(.medium)
                    statusBadge(granted: granted)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            action()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(granted ? Color.green.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Status Badge

    @ViewBuilder
    private func statusBadge(granted: Bool) -> some View {
        if granted {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                Text("Granted")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.green)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                Text("Not Granted")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.red)
        }
    }

    // MARK: - Mic Action Button

    @ViewBuilder
    private var micActionButton: some View {
        switch micStatus {
        case .notDetermined:
            Button("Allow Microphone") {
                requestMicrophoneAccess()
            }
            .controlSize(.small)
        case .denied, .restricted:
            Button("Open System Settings") {
                openMicSettings()
            }
            .controlSize(.small)
        case .authorized:
            EmptyView()
        @unknown default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async {
                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        }
    }

    private func openMicSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func resetAndRequestAccessibility() {
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.dikto.app"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        proc.arguments = ["reset", "Accessibility", bundleID]
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            NSLog("[Dikto] Failed to reset TCC: \(error)")
        }

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                let ax = probeAccessibilityPermission()
                axGranted = ax
                appState.accessibilityGranted = ax

                if micStatus == .authorized && axGranted && !allGranted {
                    allGranted = true
                    appState.onPermissionsGranted()
                    // Auto-dismiss after showing success state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        OnboardingWindowController.shared.dismiss()
                    }
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
