import SwiftUI

/// A single row in the config window project list.
public struct ProjectRowView: View {
    let project: ProjectState
    let index: Int
    let onToggle: () -> Void
    let onColorChange: (Color) -> Void
    let onSwatchTap: () -> Void
    let onRemove: () -> Void
    let onHide: () -> Void
    let onRevealInFinder: () -> Void

    public init(project: ProjectState, index: Int, onToggle: @escaping () -> Void, onColorChange: @escaping (Color) -> Void, onSwatchTap: @escaping () -> Void, onRemove: @escaping () -> Void, onHide: @escaping () -> Void, onRevealInFinder: @escaping () -> Void) {
        self.project = project
        self.index = index
        self.onToggle = onToggle
        self.onColorChange = onColorChange
        self.onSwatchTap = onSwatchTap
        self.onRemove = onRemove
        self.onHide = onHide
        self.onRevealInFinder = onRevealInFinder
    }

    public var body: some View {
        HStack {
            // Numbered color swatch as first column
            Button {
                onSwatchTap()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(project.resolvedColor)
                        .frame(width: 26, height: 18)
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 0.5, x: 0, y: 0.5)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 30)

            Text(project.name)
                .frame(maxWidth: 180, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .fontWeight(.medium)
                .help(project.sessions.first?.cwd ?? project.name)

            Text(project.displayStatus)
                .frame(alignment: .leading)
                .foregroundStyle(statusColor)

            if project.hasStale {
                Text("stale")
                    .font(.caption)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.yellow.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { project.settings.enabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
        .opacity(project.settings.enabled ? 1.0 : 0.5)
        .contextMenu {
            Button("Reveal in Finder") {
                onRevealInFinder()
            }
            Divider()
            Button("Hide Project") {
                onHide()
            }
            Button("Remove from List") {
                onRemove()
            }
        }
    }

    private var statusColor: Color {
        if project.hasStale { return .yellow }
        if project.isIdle { return .green }
        return .secondary
    }
}
