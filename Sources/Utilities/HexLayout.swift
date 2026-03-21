import Foundation

public struct HexPosition: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Computes hex center positions for N hexagons in a honeycomb layout.
public enum HexLayout {
    /// Returns center positions for `count` hexagons laid out in honeycomb pattern,
    /// normalized to fit within a square of `size` x `size` points.
    public static func positions(count: Int, in size: Double) -> (centers: [HexPosition], hexRadius: Double) {
        guard count > 0 else {
            // Placeholder: single hex outline at center
            let r = size / 2.0
            return ([HexPosition(x: size / 2, y: size / 2)], r)
        }

        let rings = ringsNeeded(for: count)
        let hexRadius: Double
        if rings == 0 {
            hexRadius = size / 2.0
        } else {
            // Hex radius so that the full cluster fits in `size`
            // For flat-top hexagons: width = 2*r, height = sqrt(3)*r
            // Cluster spans (2*rings + 1) hex widths horizontally
            hexRadius = size / (Double(2 * rings + 1) * 2.0)
        }

        let allPositions = honeycombPositions(rings: rings, hexRadius: hexRadius, center: HexPosition(x: size / 2, y: size / 2))

        // Take only the first `count` positions
        let selected = Array(allPositions.prefix(count))
        return (selected, hexRadius)
    }

    /// Number of concentric rings needed to hold `count` hexagons.
    /// Ring 0 = 1 hex, ring 1 = 1 + 6 = 7, ring 2 = 7 + 12 = 19, etc.
    public static func ringsNeeded(for count: Int) -> Int {
        if count <= 1 { return 0 }
        var total = 1
        var ring = 1
        while total < count {
            total += 6 * ring
            ring += 1
        }
        return ring - 1
    }

    /// Generates honeycomb positions starting from center, spiraling outward.
    private static func honeycombPositions(rings: Int, hexRadius r: Double, center: HexPosition) -> [HexPosition] {
        var positions: [HexPosition] = [center]

        // Flat-top hex: horizontal spacing = 1.5 * width = 3r, vertical spacing = sqrt(3) * r
        let w = r * 2.0        // hex width (flat-top)
        let h = r * sqrt(3.0)  // hex height

        // Axial directions for hex grid (flat-top): 6 directions
        // Each direction as (dx, dy) in pixel space
        let directions: [(Double, Double)] = [
            (w * 0.75, h * 0.5),    // right-down
            (0, h),                  // down
            (-w * 0.75, h * 0.5),   // left-down
            (-w * 0.75, -h * 0.5),  // left-up
            (0, -h),                // up
            (w * 0.75, -h * 0.5)    // right-up
        ]

        for ring in 1...max(rings, 1) {
            // Start position: go `ring` steps in direction 4 (up) from center
            var x = center.x + Double(ring) * directions[4].0
            var y = center.y + Double(ring) * directions[4].1

            for dir in 0..<6 {
                for _ in 0..<ring {
                    positions.append(HexPosition(x: x, y: y))
                    x += directions[dir].0
                    y += directions[dir].1
                }
            }
        }

        return positions
    }

    /// Returns the 6 vertices of a flat-top hexagon centered at `center` with given `radius`.
    public static func hexVertices(center: HexPosition, radius: Double) -> [HexPosition] {
        (0..<6).map { i in
            let angle = Double(i) * .pi / 3.0
            return HexPosition(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }
}
