import SwiftUI

/// Manages a standalone Settings window that opens on the current Space
/// without switching desktops. Uses NSWindow directly instead of SwiftUI's
/// Settings scene to avoid the activation policy change that causes Space switching.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
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
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 480)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.title = "Dikto Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        // This is the key: moveToActiveSpace prevents Space switching
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.hostingView = hosting
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.window = nil
            self.hostingView = nil
        }
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    func show(appState: AppState) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView()
            .environmentObject(appState)
        let hosting = NSHostingView(rootView: AnyView(onboardingView))
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 360)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.title = "Welcome to Dikto"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        self.hostingView = hosting
    }

    func dismiss() {
        window?.close()
        window = nil
        hostingView = nil
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.window = nil
            self.hostingView = nil
        }
    }
}

@main
struct DiktoApp: App {
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
