import SwiftUI
import AppKit

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
                let path = hexPath(center: centers[0], radius: radius)
                context.stroke(path, with: .color(placeholderGrey), lineWidth: 1.5)
            } else {
                for (i, project) in projects.enumerated() where i < centers.count {
                    let path = hexPath(center: centers[i], radius: radius)
                    let color = project.resolvedColor

                    if project.hasStale {
                        // Stale: dimmed outline
                        context.stroke(path, with: .color(color.opacity(0.4)), lineWidth: 1.0)
                    } else if project.isIdle {
                        // Ready: filled
                        context.fill(path, with: .color(color))
                    } else {
                        // Running: colored outline only
                        context.stroke(path, with: .color(color), lineWidth: 1.0)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }

    /// Renders the hex cluster into an NSImage using ImageRenderer.
    @MainActor
    public static func renderMenuBarImage(projects: [ProjectState], size: CGFloat = 22) -> NSImage {
        let view = HexClusterView(projects: projects, size: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        if let cgImage = renderer.cgImage {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
            nsImage.isTemplate = false
            return nsImage
        }

        // Fallback: empty image
        return NSImage(size: NSSize(width: size, height: size))
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
