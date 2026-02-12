import AppKit
import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axGranted: Bool = probeAccessibilityPermission()
    @State private var pollTimer: Timer?
    @State private var allGranted = false
    @State private var currentStep = 0 // 0 = permissions, 1 = model download
    @State private var isMovingForward = true
    @State private var hasExistingModels = false
    @State private var downloadingModelName: String?
    @State private var downloadCompleted = false
    @State private var downloadError: String?

    private var totalSteps: Int { hasExistingModels ? 1 : 2 }

    var body: some View {
        VStack(spacing: 0) {
            // ─── HEADER (fixed) ───
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "ear.and.waveform")
                    .font(.system(size: Theme.IconSize.xl))
                    .foregroundStyle(.blue)
                Text(currentStep == 0 ? "Welcome to Dikto" : "Almost there")
                    .font(Theme.Typography.largeTitle)
                Text(currentStep == 0
                    ? "Two permissions needed to get started"
                    : "Pick one to get started. You can switch anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Theme.Spacing.lg)
            .padding(.horizontal, Theme.Spacing.xl)

            // ─── STEP INDICATOR ───
            if totalSteps > 1 {
                Text("Step \(currentStep + 1) of \(totalSteps) · \(currentStep == 0 ? "Permissions" : "Model Setup")")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.sm)
            } else {
                Spacer()
                    .frame(height: Theme.Spacing.sm)
            }

            // ─── CONTENT (flexible, slides) ───
            ZStack {
                if currentStep == 0 {
                    permissionsContent
                        .transition(slideTransition)
                }
                if currentStep == 1 {
                    modelDownloadContent
                        .transition(slideTransition)
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()

            Spacer(minLength: 0)

            // ─── FOOTER (fixed) ───
            Divider()
            footerButtons
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
        }
        .frame(width: Theme.Layout.onboardingWidth, height: Theme.Layout.onboardingHeight)
        .animation(Theme.Animation.standard, value: currentStep)
        .animation(Theme.Animation.spring, value: allGranted)
        .animation(Theme.Animation.spring, value: downloadCompleted)
        .onAppear {
            hasExistingModels = appState.models.contains(where: { $0.isDownloaded })
            startPolling()
        }
        .onDisappear { stopPolling() }
        .onChange(of: appState.downloadProgress) {
            guard let name = downloadingModelName, !downloadCompleted else { return }
            if appState.downloadProgress[name] == nil {
                if appState.models.first(where: { $0.name == name })?.isDownloaded == true {
                    downloadCompleted = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        OnboardingWindowController.shared.animatedDismiss()
                    }
                } else {
                    downloadError = appState.lastError ?? "Download failed"
                    downloadingModelName = nil
                }
            }
        }
    }

    // MARK: - Slide Transition

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Navigation

    private func goForward() {
        guard currentStep < totalSteps - 1 else { return }
        isMovingForward = true
        withAnimation(Theme.Animation.standard) {
            currentStep += 1
        }
    }

    private func goBack() {
        guard currentStep > 0 else { return }
        isMovingForward = false
        withAnimation(Theme.Animation.standard) {
            currentStep -= 1
        }
        // Restart polling when returning to permissions step
        if currentStep == 0 {
            startPolling()
        }
    }

    // MARK: - Footer Buttons

    @ViewBuilder
    private var footerButtons: some View {
        HStack {
            // Left side: Back button (only on step 2)
            if currentStep == 1 && !downloadCompleted {
                Button {
                    goBack()
                } label: {
                    HStack(spacing: Theme.Spacing.xxxs) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .foregroundStyle(.secondary)
                .disabled(downloadingModelName != nil)
            }

            Spacer()

            // Right side: context-dependent
            if currentStep == 0 {
                if allGranted {
                    Button("Continue") {
                        handlePermissionsContinue()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    Button("Skip for now") {
                        handlePermissionsSkip()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .foregroundStyle(.secondary)
                }
            } else if currentStep == 1 {
                if downloadCompleted {
                    Button("Get Started") {
                        OnboardingWindowController.shared.animatedDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    Button("Skip for now") {
                        OnboardingWindowController.shared.animatedDismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Step 1: Permissions Content

    private var permissionsContent: some View {
        Form {
            Section {
                permissionCard(icon: "mic.fill", title: "Microphone",
                    description: "Hear your voice and transcribe it into text.",
                    granted: micStatus == .authorized) { micActionButton }
            }
            Section {
                permissionCard(icon: "accessibility", title: "Accessibility",
                    description: "Auto-paste transcriptions into your active app.",
                    granted: axGranted) {
                    if !axGranted { Button("Grant Accessibility") { resetAndRequestAccessibility() }.controlSize(.regular) }
                }
            } footer: {
                VStack(spacing: Theme.Spacing.sm) {
                    Text("These permissions stay on your device.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.tertiary)
                    if allGranted {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Colors.statusActive)
                            Text(hasExistingModels ? "All set! Starting Dikto..." : "All set! Setting up models...")
                                .fontWeight(.medium)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Step 2: Model Download Content

    private var modelDownloadContent: some View {
        Form {
            if appState.models.isEmpty {
                Section {
                    Text("Could not load models")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Section {
                    ForEach(appState.models, id: \.name) { model in
                        modelRow(model)
                    }
                } footer: {
                    VStack(spacing: Theme.Spacing.sm) {
                        if let error = downloadError {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Colors.statusWarning)
                                Text(error)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.statusError)
                                    .lineLimit(2)
                            }
                        }
                        if downloadCompleted {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.statusActive)
                                Text("All set! Starting Dikto...")
                                    .fontWeight(.medium)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { appState.refreshModels() }
    }

    // MARK: - Permission Continue / Skip

    private func handlePermissionsContinue() {
        stopPolling()
        if hasExistingModels {
            OnboardingWindowController.shared.animatedDismiss()
        } else {
            goForward()
        }
    }

    private func handlePermissionsSkip() {
        appState.needsOnboarding = false
        stopPolling()
        if hasExistingModels {
            OnboardingWindowController.shared.animatedDismiss()
        } else {
            goForward()
        }
    }

    // MARK: - Model Row

    @ViewBuilder
    private func modelRow(_ model: ModelInfoRecord) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(model.name)
                        .fontWeight(.medium)
                    if model.name == "parakeet-tdt-0.6b-v2" {
                        Text("(Best Accuracy)")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(formatSize(model.sizeMb)) · \(model.description)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.xxs)

            Group {
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
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.statusActive)
                } else {
                    Button("Download") {
                        downloadError = nil
                        downloadingModelName = model.name
                        appState.downloadModel(name: model.name)
                    }
                    .controlSize(.regular)
                    .disabled(!appState.downloadProgress.isEmpty)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    // MARK: - Highlight Tag

    private func highlightTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.Typography.monoSmall)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
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
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: Theme.IconSize.lg)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    StatusBadge(granted: granted)
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: Theme.Spacing.xxs)

            action()
                .fixedSize()
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
            .controlSize(.regular)
        case .denied, .restricted:
            Button("Open System Settings") {
                openMicSettings()
            }
            .controlSize(.regular)
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

    // MARK: - Helpers

    private func formatSize(_ mb: UInt32) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        }
        return "\(mb) MB"
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                let ax = probeAccessibilityPermission()
                axGranted = ax
                appState.accessibilityGranted = ax

                if micStatus == .authorized && axGranted && !allGranted {
                    allGranted = true
                    appState.onPermissionsGranted()
                    // Auto-advance after showing success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        guard currentStep == 0 else { return }
                        stopPolling()
                        if hasExistingModels {
                            OnboardingWindowController.shared.animatedDismiss()
                        } else {
                            goForward()
                        }
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
