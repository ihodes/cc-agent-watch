import Foundation
@preconcurrency import HotKey
import Carbon

/// Manages the global keyboard shortcut for opening the config window.
@MainActor
public final class HotkeyManager {
    private var hotKey: HotKey?
    private let onActivate: @MainActor () -> Void

    public init(onActivate: @escaping @MainActor () -> Void) {
        self.onActivate = onActivate
        setupHotkey()
    }

    private func setupHotkey() {
        // Cmd+Shift+Option+Ctrl+' (quote key)
        hotKey = HotKey(
            key: .quote,
            modifiers: [.command, .shift, .option, .control]
        )
        hotKey?.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.onActivate()
            }
        }
    }
}
