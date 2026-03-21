import SwiftUI

/// Renders a cluster of hexagons for the menubar icon.
public struct HexClusterView: View {
    let projects: [ProjectState]
    let size: CGFloat

    private let placeholderGrey = Color(hex: "#C0C0C0")!
    private let busyGrey = Color(hex: "#C0C0C0")!

    public init(projects: [ProjectState], size: CGFloat) {
        self.projects = projects
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let (centers, radius) = HexLayout.positions(count: max(projects.count, 0), in: Double(s))

            if projects.isEmpty {
                // Placeholder: single grey hex outline
                let center = centers[0]
                let path = hexPath(center: center, radius: radius)
                context.stroke(path, with: .color(placeholderGrey), lineWidth: 1.5)
            } else {
                for (i, project) in projects.enumerated() where i < centers.count {
                    let center = centers[i]
                    let path = hexPath(center: center, radius: radius * 0.9) // slight padding

                    let fillColor: Color
                    if project.hasStale {
                        fillColor = busyGrey.opacity(0.5)
                    } else if project.isIdle {
                        fillColor = project.resolvedColor
                    } else {
                        fillColor = busyGrey
                    }

                    context.fill(path, with: .color(fillColor))
                    context.stroke(path, with: .color(fillColor.opacity(0.8)), lineWidth: 0.5)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func hexPath(center: HexPosition, radius: Double) -> Path {
        let vertices = HexLayout.hexVertices(center: center, radius: radius)
        var path = Path()
        guard let first = vertices.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for v in vertices.dropFirst() {
            path.addLine(to: CGPoint(x: v.x, y: v.y))
        }
        path.closeSubpath()
        return path
    }
}
