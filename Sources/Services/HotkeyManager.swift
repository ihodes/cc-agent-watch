import Foundation
import AppKit
@preconcurrency import HotKey
import Carbon

/// Persisted hotkey configuration.
public struct HotkeyConfig: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt // NSEvent.ModifierFlags.rawValue

    public static let defaultConfig = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_Quote),
        modifiers: NSEvent.ModifierFlags([.command, .shift, .option, .control]).rawValue
    )

    public static func load() -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: "hotkeyConfig"),
              let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data)
        else { return .defaultConfig }
        return config
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "hotkeyConfig")
        }
    }

    public var displayString: String {
        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: modifiers)
        if mods.contains(.control) { parts.append("^") }
        if mods.contains(.option) { parts.append("\u{2325}") }
        if mods.contains(.shift) { parts.append("\u{21E7}") }
        if mods.contains(.command) { parts.append("\u{2318}") }
        parts.append(keyName)
        return parts.joined()
    }

    private var keyName: String {
        // Map common key codes to names
        switch Int(keyCode) {
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Grave: return "`"
        case kVK_Space: return "Space"
        default: return "Key(\(keyCode))"
        }
    }
}

/// Manages the global keyboard shortcut for opening the config window.
@MainActor
public final class HotkeyManager {
    private var hotKey: HotKey?
    private let onActivate: @MainActor () -> Void

    public private(set) var config: HotkeyConfig

    public init(onActivate: @escaping @MainActor () -> Void) {
        self.onActivate = onActivate
        self.config = HotkeyConfig.load()
        applyConfig()
    }

    public func updateHotkey(_ newConfig: HotkeyConfig) {
        config = newConfig
        config.save()
        applyConfig()
    }

    private func applyConfig() {
        hotKey = nil
        guard let key = Key(carbonKeyCode: config.keyCode) else { return }
        var mods: NSEvent.ModifierFlags = []
        let raw = NSEvent.ModifierFlags(rawValue: config.modifiers)
        if raw.contains(.command) { mods.insert(.command) }
        if raw.contains(.shift) { mods.insert(.shift) }
        if raw.contains(.option) { mods.insert(.option) }
        if raw.contains(.control) { mods.insert(.control) }

        hotKey = HotKey(key: key, modifiers: mods)
        hotKey?.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.onActivate()
            }
        }
    }
}
