import SwiftUI

/// Manages a standalone Settings window that opens on the current Space
/// without switching desktops. Uses NSWindow directly instead of SwiftUI's
/// Settings scene to avoid the activation policy change that causes Space switching.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    func show(appState: AppState) {
        if let existing = window, existing.isVisible {
            existing.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(appState)
        let hosting = NSHostingView(rootView: AnyView(settingsView))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 400)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.title = "Sotto Settings"
        window.isReleasedWhenClosed = false
        // This is the key: moveToActiveSpace prevents Space switching
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.hostingView = hosting
    }
}

@main
struct SottoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "ear.and.waveform")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
