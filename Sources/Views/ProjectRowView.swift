import SwiftUI

/// A single row in the config window project list.
public struct ProjectRowView: View {
    let project: ProjectState
    let index: Int
    let onToggle: () -> Void
    let onColorChange: (Color) -> Void

    @State private var pickerColor: Color

    public init(project: ProjectState, index: Int, onToggle: @escaping () -> Void, onColorChange: @escaping (Color) -> Void) {
        self.project = project
        self.index = index
        self.onToggle = onToggle
        self.onColorChange = onColorChange
        self._pickerColor = State(initialValue: project.resolvedColor)
    }

    public var body: some View {
        HStack {
            Text("\(index + 1)")
                .frame(width: 20, alignment: .trailing)
                .foregroundStyle(.secondary)

            Text(project.name)
                .frame(minWidth: 120, alignment: .leading)
                .fontWeight(.medium)

            Text(project.displayStatus)
                .frame(minWidth: 80, alignment: .leading)
                .foregroundStyle(statusColor)

            if project.hasStale {
                Text("stale")
                    .font(.caption)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.yellow.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30)
                .onChange(of: pickerColor) { _, newColor in
                    onColorChange(newColor)
                }

            Toggle("", isOn: Binding(
                get: { project.settings.enabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
        .opacity(project.settings.enabled ? 1.0 : 0.5)
    }

    private var statusColor: Color {
        if project.hasStale { return .yellow }
        if project.isIdle { return .green }
        return .secondary
    }
}
