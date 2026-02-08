import AppKit
import SwiftUI

/// A floating overlay that shows recording status and partial transcription.
final class RecordingOverlayController {
    private var panel: NSPanel?

    func show(text: String, isProcessing: Bool) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 60),
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

            // Position at top center of screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - 210
                let y = screenFrame.maxY - 80
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }

            self.panel = panel
        }

        let view = RecordingOverlayView(text: text, isProcessing: isProcessing)
        panel?.contentView = NSHostingView(rootView: view)
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct RecordingOverlayView: View {
    let text: String
    let isProcessing: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing record indicator
            Circle()
                .fill(isProcessing ? Color.orange : Color.red)
                .frame(width: 12, height: 12)
                .shadow(color: isProcessing ? .orange : .red, radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(isProcessing ? "Processing..." : "Listening...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text.isEmpty ? "Speak now..." : text)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 420, height: 60)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}
