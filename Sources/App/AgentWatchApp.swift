import SwiftUI
import AgentWatchLib

@main
struct AgentWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let appState = AppState()
    var hotkeyManager: HotkeyManager!
    private var watcher: DirectoryWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            updateIcon()
        }

        hotkeyManager = HotkeyManager { [weak self] in
            self?.togglePopover()
        }

        popover = NSPopover()
        popover.behavior = .transient
        let hostingController = NSHostingController(
            rootView: ConfigWindow(appState: appState, hotkeyManager: hotkeyManager)
        )
        hostingController.view.setFrameSize(hostingController.sizeThatFits(in: NSSize(width: 500, height: 600)))
        popover.contentViewController = hostingController

        appState.loadSessions()
        updateIcon()

        watcher = DirectoryWatcher(directoryPath: appState.monitorDirectory) { [weak self] in
            Task { @MainActor in
                self?.appState.loadSessions()
                self?.updateIcon()
            }
        }

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateIcon()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if appState.isPaused {
            button.image = HexClusterView.renderPausedImage(size: 22)
        } else {
            button.image = HexClusterView.renderMenuBarImage(
                projects: appState.enabledProjects,
                size: 22
            )
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
