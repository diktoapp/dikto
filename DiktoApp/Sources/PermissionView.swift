import AppKit
import AVFoundation
import SwiftUI

struct PermissionsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axGranted: Bool = probeAccessibilityPermission()
    @State private var axTimer: Timer?

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: Theme.IconSize.lg)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("Microphone")
                                .fontWeight(.medium)
                            StatusBadge(granted: micStatus == .authorized)
                        }
                        Text("Dikto needs microphone access to hear your voice and transcribe it into text.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    micActionButton
                }
                .padding(.vertical, Theme.Spacing.xxs)
                .help("Required for voice transcription")
            }

            Section {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "accessibility")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: Theme.IconSize.lg)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("Accessibility")
                                .fontWeight(.medium)
                            StatusBadge(granted: axGranted)
                        }
                        Text("Dikto needs Accessibility permission to automatically paste transcribed text into your active app.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                        if !axGranted {
                            Text("If permission appears enabled but isn't working, click the button to reset and re-grant.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if !axGranted {
                        Button("Grant Accessibility") {
                            resetAndRequestAccessibility()
                        }
                        .controlSize(.small)
                        .help("Clears any stale permission entry and re-prompts")
                    }
                }
                .padding(.vertical, Theme.Spacing.xxs)
                .help("Required for auto-paste into other applications")
            }
        }
        .formStyle(.grouped)
        .animation(Theme.Animation.standard, value: micStatus == .authorized)
        .animation(Theme.Animation.standard, value: axGranted)
        .onAppear {
            refreshMicStatus()
            refreshAxStatus()
            startPollingAccessibility()
        }
        .onDisappear {
            stopPollingAccessibility()
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

    private func resetAndRequestAccessibility() {
        // Clear any stale TCC entry (e.g. after ad-hoc re-sign changed the CDHash)
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

        // Show the system accessibility prompt
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private func refreshMicStatus() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private func refreshAxStatus() {
        let granted = probeAccessibilityPermission()
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
