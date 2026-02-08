import SwiftUI

struct SettingsOpenerView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                Task { @MainActor in
                    NSApp.setActivationPolicy(.regular)
                    try? await Task.sleep(for: .milliseconds(100))
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                    try? await Task.sleep(for: .milliseconds(200))
                    for window in NSApp.windows where window.isVisible && window.canBecomeKey {
                        if window.identifier?.rawValue.contains("settings") == true
                            || window.title.localizedCaseInsensitiveContains("settings") {
                            window.makeKeyAndOrderFront(nil)
                            window.orderFrontRegardless()
                            break
                        }
                    }
                    NSApp.setActivationPolicy(.accessory)
                }
            }
    }
}

@main
struct SottoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("", id: "hidden") {
            SettingsOpenerView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "ear.and.waveform")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
