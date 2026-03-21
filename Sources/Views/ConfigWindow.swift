import SwiftUI

/// The configuration window showing project list and IPC directory settings.
public struct ConfigWindow: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Watch")
                .font(.title2)
                .fontWeight(.bold)

            Divider()

            // IPC Directory section
            HStack {
                Text("IPC Directory:")
                    .foregroundStyle(.secondary)
                Text(appState.monitorDirectory)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            HStack {
                Button("Change...") {
                    chooseDirectory()
                }
                Button("Reveal in Finder") {
                    revealInFinder()
                }
            }

            Divider()

            // Project list header
            HStack {
                Text("#").frame(width: 20, alignment: .trailing)
                Text("Project").frame(minWidth: 120, alignment: .leading)
                Text("Status").frame(minWidth: 80, alignment: .leading)
                Spacer()
                Text("Color").frame(width: 30)
                Text("On/Off").frame(width: 50)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Project list
            ScrollView {
                VStack(spacing: 0) {
                    let sorted = appState.projects.sorted { $0.name < $1.name }
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, project in
                        ProjectRowView(
                            project: project,
                            index: index,
                            onToggle: { appState.toggleProject(named: project.name) },
                            onColorChange: { color in appState.setColor(for: project.name, color: color) }
                        )
                        if index < sorted.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(minHeight: 100, maxHeight: 300)

            Divider()

            // Keyboard shortcut hints
            VStack(alignment: .leading, spacing: 2) {
                Text("Cmd+1..9 — Toggle project on/off")
                Text("Shift+Cmd+1..9 — Open color picker")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
        .onKeyPress(.escape) {
            appState.isConfigWindowVisible = false
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            handleNumberKey(press)
        }
    }

    private func handleNumberKey(_ press: KeyPress) -> KeyPress.Result {
        guard let digit = press.characters.first?.wholeNumberValue, digit >= 1, digit <= 9 else {
            return .ignored
        }
        let sorted = appState.projects.sorted { $0.name < $1.name }
        let index = digit - 1
        guard index < sorted.count else { return .ignored }

        if press.modifiers.contains(.shift) {
            // Color picker handled by the ColorPicker in the row
            return .ignored
        } else {
            appState.toggleProject(named: sorted[index].name)
            return .handled
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose IPC Directory"
        if panel.runModal() == .OK, let url = panel.url {
            appState.monitorDirectory = url.path
        }
    }

    private func revealInFinder() {
        let url = URL(fileURLWithPath: appState.monitorDirectory)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}
