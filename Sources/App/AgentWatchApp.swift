import SwiftUI
import AgentWatchLib

@main
struct AgentWatchApp: App {
    @State private var appState = AppState()
    @State private var watcher: DirectoryWatcher?
    @State private var hotkeyManager: HotkeyManager?

    var body: some Scene {
        MenuBarExtra {
            ConfigWindow(appState: appState)
        } label: {
            HexClusterView(projects: appState.enabledProjects, size: 22)
        }
        .menuBarExtraStyle(.window)

        // Info.plist equivalent: LSUIElement = YES (no Dock icon)
        Settings {
            EmptyView()
        }
    }

    init() {
        // Set LSUIElement programmatically
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func startWatching() {
        appState.loadSessions()
        watcher = DirectoryWatcher(directoryPath: appState.monitorDirectory) { [appState] in
            Task { @MainActor in
                appState.loadSessions()
            }
        }
        hotkeyManager = HotkeyManager {
            appState.isConfigWindowVisible.toggle()
        }
    }
}
