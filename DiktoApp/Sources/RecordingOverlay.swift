import AppKit
import SwiftUI

/// A floating overlay that shows recording status and partial transcription.
final class RecordingOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<RecordingOverlayView>?
    private var isHiding = false

    func show(text: String, isProcessing: Bool) {
        let view = RecordingOverlayView(text: text, isProcessing: isProcessing)

        // Cancel any in-progress hide animation
        isHiding = false

        if let hostingView {
            hostingView.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            self.hostingView = hosting
        }

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: Theme.Layout.overlayWidth, height: Theme.Layout.overlayHeight),
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            panel.alphaValue = 0

            // Position at top center of screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - Theme.Layout.overlayWidth / 2
                let y = screenFrame.maxY - 72
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }

            self.panel = panel
        }

        panel?.contentView = hostingView
        panel?.orderFront(nil)

        // Animate in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        isHiding = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self = self, self.isHiding else { return }
            self.panel?.orderOut(nil)
            self.panel = nil
            self.hostingView = nil
            self.isHiding = false
        }
    }
}

struct RecordingOverlayView: View {
    let text: String
    let isProcessing: Bool
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Pulsing record indicator
            Circle()
                .fill(isProcessing ? Theme.Colors.statusProcessing : Theme.Colors.statusRecording)
                .frame(width: Theme.Layout.recordingDotSize, height: Theme.Layout.recordingDotSize)
                .shadow(color: isProcessing ? Theme.Colors.processingGlow : Theme.Colors.recordingGlow, radius: isPulsing ? 8 : 4)
                .scaleEffect(isPulsing ? 1.15 : 1.0)
                .animation(Theme.Animation.pulse, value: isPulsing)
                .onAppear { isPulsing = true }
                .accessibilityLabel(isProcessing ? "Processing indicator" : "Recording indicator")

            VStack(alignment: .leading, spacing: 2) {
                Text(isProcessing ? "Processing..." : "Listening...")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                Text(text.isEmpty ? "Speak now..." : text)
                    .font(Theme.Typography.callout)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .accessibilityValue(text.isEmpty ? "Waiting for speech" : text)
            }
            .accessibilityAddTraits(.updatesFrequently)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(width: Theme.Layout.overlayWidth, height: Theme.Layout.overlayHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .stroke(Theme.Colors.overlayBorder, lineWidth: 0.5)
        )
    }
}
