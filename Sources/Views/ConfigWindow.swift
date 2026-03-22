import SwiftUI

/// CC-matching preset colors with labels.
public struct PresetColor: Codable, Sendable, Equatable {
    public let name: String
    public var hex: String
    public let key: Int // 1-8, 0 for system

    public static let defaults: [PresetColor] = [
        PresetColor(name: "red", hex: "#FF3B30", key: 1),
        PresetColor(name: "blue", hex: "#007AFF", key: 2),
        PresetColor(name: "green", hex: "#34D058", key: 3),
        PresetColor(name: "yellow", hex: "#FFD60A", key: 4),
        PresetColor(name: "purple", hex: "#BF5AF2", key: 5),
        PresetColor(name: "orange", hex: "#FF9500", key: 6),
        PresetColor(name: "pink", hex: "#FF2D55", key: 7),
        PresetColor(name: "cyan", hex: "#5AC8FA", key: 8),
    ]

    public static func loadPresets() -> [PresetColor] {
        guard let data = UserDefaults.standard.data(forKey: "presetColors"),
              let presets = try? JSONDecoder().decode([PresetColor].self, from: data),
              presets.count == 8 else {
            return defaults
        }
        return presets
    }

    public static func savePresets(_ presets: [PresetColor]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: "presetColors")
        }
    }
}

// Map keyCode → digit for the number row (US keyboard layout)
private let keyCodeToDigit: [UInt16: Int] = [
    18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0
]

/// The main popover content showing project list.
public struct ConfigWindow: View {
    @Bindable var appState: AppState
    var hotkeyManager: HotkeyManager
    @State private var eventMonitor: Any?
    @State private var colorPickerProjectIndex: Int? = nil
    @State private var presets: [PresetColor] = PresetColor.loadPresets()
    @State private var systemPickerProjectName: String? = nil
    @State private var colorPanelObserver: Any? = nil

    public init(appState: AppState, hotkeyManager: HotkeyManager) {
        self.appState = appState
        self.hotkeyManager = hotkeyManager
    }

    private var sortedProjects: [ProjectState] {
        appState.visibleProjects
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Project list header
            HStack {
                Text("#").frame(width: 30)
                Text("Project").frame(minWidth: 120, alignment: .leading)
                Text("Status").frame(minWidth: 80, alignment: .leading)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Project list
            VStack(spacing: 0) {
                ForEach(Array(sortedProjects.enumerated()), id: \.element.id) { index, project in
                    ProjectRowView(
                        project: project,
                        index: index,
                        onToggle: { appState.toggleProject(named: project.name) },
                        onColorChange: { color in appState.setColor(for: project.name, color: color) },
                        onSwatchTap: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                colorPickerProjectIndex = (colorPickerProjectIndex == index) ? nil : index
                            }
                        },
                        onRemove: { appState.removeProject(named: project.name) },
                        onHide: { appState.hideProject(named: project.name) },
                        onRevealInFinder: {
                            if let cwd = project.sessions.first?.cwd {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
                            }
                        }
                    )
                    .zIndex(colorPickerProjectIndex == index ? 100 : 0)
                    .overlay(alignment: .topLeading) {
                        if colorPickerProjectIndex == index {
                            ColorPaletteDropdown(
                                presets: presets,
                                onSelect: { hex in
                                    appState.setColor(for: project.name, hex: hex)
                                    withAnimation { colorPickerProjectIndex = nil }
                                },
                                onSystemPicker: {
                                    openSystemPicker(for: project)
                                    withAnimation { colorPickerProjectIndex = nil }
                                },
                                onDismiss: {
                                    withAnimation { colorPickerProjectIndex = nil }
                                }
                            )
                            .offset(x: 0, y: 24)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)))
                        }
                    }
                    if index < sortedProjects.count - 1 {
                        Divider()
                    }
                }
            }

            // Bottom bar: gear on the right
            HStack {
                Spacer()
                Button {
                    openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Settings (Cmd+,)")
            }
            .padding(.top, 2)
        }
        .padding(10)
        .onAppear {
            presets = PresetColor.loadPresets()
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if handleKeyEvent(event) {
                    return nil
                }
                return event
            }
            colorPanelObserver = NotificationCenter.default.addObserver(
                forName: NSColorPanel.colorDidChangeNotification,
                object: NSColorPanel.shared,
                queue: .main
            ) { _ in
                guard let name = systemPickerProjectName else { return }
                let hex = Color(nsColor: NSColorPanel.shared.color).toHex() ?? "#34D058"
                appState.setColor(for: name, hex: hex)
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
            if let observer = colorPanelObserver {
                NotificationCenter.default.removeObserver(observer)
                colorPanelObserver = nil
            }
            systemPickerProjectName = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let hasCmd = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)

        // Cmd+, opens settings
        if hasCmd && event.keyCode == 43 { // kVK_ANSI_Comma
            openSettingsWindow()
            return true
        }

        guard let digit = keyCodeToDigit[event.keyCode] else { return false }

        if colorPickerProjectIndex != nil {
            if digit >= 1 && digit <= 8 {
                let preset = presets[digit - 1]
                let projName = sortedProjects[colorPickerProjectIndex!].name
                appState.setColor(for: projName, hex: preset.hex)
                withAnimation { colorPickerProjectIndex = nil }
                return true
            } else if digit == 0 {
                let project = sortedProjects[colorPickerProjectIndex!]
                openSystemPicker(for: project)
                withAnimation { colorPickerProjectIndex = nil }
                return true
            } else if digit == 9 {
                withAnimation { colorPickerProjectIndex = nil }
                return true
            }
        }

        if event.keyCode == 53 && colorPickerProjectIndex != nil {
            withAnimation { colorPickerProjectIndex = nil }
            return true
        }

        guard hasCmd else { return false }
        guard digit >= 1 && digit <= 9 else { return false }

        let index = digit - 1
        guard index < sortedProjects.count else { return false }

        if hasShift {
            withAnimation(.easeInOut(duration: 0.15)) {
                colorPickerProjectIndex = (colorPickerProjectIndex == index) ? nil : index
            }
            return true
        } else {
            appState.toggleProject(named: sortedProjects[index].name)
            return true
        }
    }

    private func openSystemPicker(for project: ProjectState) {
        systemPickerProjectName = project.name
        let panel = NSColorPanel.shared
        panel.color = NSColor(project.resolvedColor)
        panel.orderFront(nil)
    }

    private func openSettingsWindow() {
        let settingsView = SettingsView(appState: appState, hotkeyManager: hotkeyManager)
        let controller = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Agent Watch Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 500, height: 380))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Settings window for IPC directory, swatch customization, hotkey, and shortcuts reference.
struct SettingsView: View {
    @Bindable var appState: AppState
    var hotkeyManager: HotkeyManager
    @State private var presets: [PresetColor] = PresetColor.loadPresets()
    @State private var isRecordingHotkey = false
    @State private var hotkeyDisplay: String = ""
    @State private var hotkeyMonitor: Any? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Global Hotkey
            GroupBox("Global Shortcut") {
                HStack {
                    Text("Toggle panel:")
                    Button {
                        startRecording()
                    } label: {
                        Text(isRecordingHotkey ? "Press shortcut..." : hotkeyDisplay)
                            .frame(minWidth: 120)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isRecordingHotkey ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button("Reset") {
                        hotkeyManager.updateHotkey(.defaultConfig)
                        hotkeyDisplay = hotkeyManager.config.displayString
                    }
                    .controlSize(.small)

                    Spacer()
                }
                .padding(4)
            }

            // IPC Directory
            GroupBox("IPC Directory") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.monitorDirectory)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    HStack {
                        Button("Change...") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Choose IPC Directory"
                            if panel.runModal() == .OK, let url = panel.url {
                                appState.monitorDirectory = url.path
                            }
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(
                                nil,
                                inFileViewerRootedAtPath: appState.monitorDirectory
                            )
                        }
                    }
                }
                .padding(4)
            }

            // Color Swatches
            GroupBox("Color Swatches") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Array(presets.enumerated()), id: \.element.key) { i, preset in
                            VStack(spacing: 2) {
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: preset.hex) ?? .gray },
                                    set: { newColor in
                                        presets[i].hex = newColor.toHex() ?? preset.hex
                                        PresetColor.savePresets(presets)
                                    }
                                ), supportsOpacity: false)
                                .labelsHidden()

                                Text("\(preset.key)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button("Reset to Defaults") {
                        presets = PresetColor.defaults
                        PresetColor.savePresets(presets)
                    }
                    .controlSize(.small)
                }
                .padding(4)
            }

            // Keyboard Shortcuts Reference
            // Hidden Projects
            if !appState.hiddenProjects.isEmpty {
                GroupBox("Hidden Projects") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.hiddenProjects) { project in
                            HStack {
                                Text(project.name)
                                    .lineLimit(1)
                                Spacer()
                                Button("Unhide") {
                                    appState.unhideProject(named: project.name)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(4)
                }
            }

            GroupBox("Keyboard Shortcuts") {
                VStack(alignment: .leading, spacing: 4) {
                    shortcutRow("Cmd + 1..9", "Toggle project on/off")
                    shortcutRow("Shift + Cmd + 1..9", "Color picker for project")
                    shortcutRow("1..8", "Pick preset color (when palette open)")
                    shortcutRow("0", "System color picker (when palette open)")
                    shortcutRow("Cmd + ,", "Open settings")
                    shortcutRow("Esc", "Dismiss palette / close panel")
                    shortcutRow("Right-click row", "Remove / Hide / Reveal")
                }
                .padding(4)
            }
        }
        .padding()
        .onAppear {
            hotkeyDisplay = hotkeyManager.config.displayString
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 180, alignment: .trailing)
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func startRecording() {
        isRecordingHotkey = true
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            // Require at least one modifier
            guard !mods.isEmpty else {
                if event.keyCode == 53 { // Escape cancels
                    stopRecording()
                }
                return nil
            }
            let config = HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: mods.rawValue)
            hotkeyManager.updateHotkey(config)
            hotkeyDisplay = config.displayString
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecordingHotkey = false
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
    }
}

/// Floating dropdown color palette with liquid glass styling.
struct ColorPaletteDropdown: View {
    let presets: [PresetColor]
    let onSelect: (String) -> Void
    let onSystemPicker: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(presets, id: \.key) { preset in
                Button {
                    onSelect(preset.hex)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: preset.hex)!)
                            .frame(width: 20, height: 20)
                        Text("\(preset.key)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 0.5, x: 0, y: 0.5)
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                onSystemPicker()
            } label: {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        )
                    )
                    .frame(width: 20, height: 20)
                    .overlay {
                        Text("0")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 0.5, x: 0, y: 0.5)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
