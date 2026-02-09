import AppKit
import AVFoundation
import SwiftUI

struct PermissionsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axGranted: Bool = AXIsProcessTrusted()
    @State private var axTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    // Microphone row
                    HStack(spacing: 12) {
                        Image(systemName: "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("Microphone")
                                    .fontWeight(.medium)
                                statusBadge(granted: micStatus == .authorized)
                            }
                            Text("Sotto needs microphone access to hear your voice and transcribe it into text.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        micActionButton
                    }
                    .padding(.vertical, 4)

                    // Accessibility row
                    HStack(spacing: 12) {
                        Image(systemName: "accessibility")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("Accessibility")
                                    .fontWeight(.medium)
                                statusBadge(granted: axGranted)
                            }
                            Text("Sotto needs Accessibility permission to automatically paste transcribed text into your active app.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !axGranted {
                            Button("Open System Settings") {
                                openAccessibilitySettings()
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            refreshMicStatus()
            refreshAxStatus()
            startPollingAccessibility()
        }
        .onDisappear {
            stopPollingAccessibility()
        }
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
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                refreshMicStatus()
            }
        }
    }

    private func openMicSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private func refreshMicStatus() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private func refreshAxStatus() {
        let granted = AXIsProcessTrusted()
        axGranted = granted
        appState.accessibilityGranted = granted
    }

    // MARK: - Accessibility Polling

    private func startPollingAccessibility() {
        axTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                refreshAxStatus()
                refreshMicStatus()
            }
        }
    }

    private func stopPollingAccessibility() {
        axTimer?.invalidate()
        axTimer = nil
    }
}
