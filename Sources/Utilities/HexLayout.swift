import Foundation

public struct HexPosition: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Computes hex center positions for N pointy-top hexagons in a honeycomb layout.
public enum HexLayout {
    // Gap between hexagons in points
    private static let gap: Double = 1.0

    // Pointy-top hex geometry for circumradius r:
    //   width  = sqrt(3) * r
    //   height = 2 * r
    // Same-row neighbors: dx = sqrt(3)*r + gap
    // Next-row offset:    dx = sqrt(3)/2*r + gap/2,  dy = 1.5*r + gap

    /// Returns center positions for `count` hexagons laid out in honeycomb pattern,
    /// normalized to fit within a square of `size` x `size` points.
    public static func positions(count: Int, in size: Double) -> (centers: [HexPosition], hexRadius: Double) {
        let cx = size / 2.0
        let cy = size / 2.0

        switch count {
        case 0:
            return ([HexPosition(x: cx, y: cy)], size / 2.0)

        case 1:
            return ([HexPosition(x: cx, y: cy)], size / 2.0)

        case 2:
            // Side by side: total width = 2 * sqrt(3)*r + gap
            // width = sqrt(3)*r per hex, so total = 2*sqrt(3)*r + gap = size
            let r = (size - gap) / (2.0 * sqrt(3.0))
            let dx = sqrt(3.0) * r / 2.0 + gap / 2.0
            return ([
                HexPosition(x: cx - dx, y: cy),
                HexPosition(x: cx + dx, y: cy)
            ], r)

        case 3:
            // Honeycomb triangle: 2 top, 1 bottom nestled between them
            // Pointy-top hex: width = sqrt(3)*r, height = 2*r
            // Width used:  2*sqrt(3)*r + gap  (two side-by-side top hexes)
            // Height used: 3.5*r + gap        (r above top center + 1.5r+gap row spacing + r below bottom center)
            let rw = (size - gap) / (2.0 * sqrt(3.0))
            let rh = (size - gap) / 3.5
            let r = min(rw, rh)
            let colDx = sqrt(3.0) * r / 2.0 + gap / 2.0
            // Center vertically: top row at cy - 0.75r - gap/2, bottom at cy + 0.75r + gap/2
            let yTop = cy - 0.75 * r - gap / 2.0
            let yBot = cy + 0.75 * r + gap / 2.0
            return ([
                HexPosition(x: cx - colDx, y: yTop),
                HexPosition(x: cx + colDx, y: yTop),
                HexPosition(x: cx, y: yBot)
            ], r)

        case 4:
            // 2x2 honeycomb: top row 2, bottom row 2 offset by half
            // Width  = 5*sqrt(3)*r/2 + 3*gap/2   (bottom row extends further)
            // Height = 3.5*r + gap
            let rw = 2.0 * (size - 1.5 * gap) / (5.0 * sqrt(3.0))
            let rh = (size - gap) / 3.5
            let r = min(rw, rh)
            let colSpacing = sqrt(3.0) * r + gap
            let rowOffset = colSpacing / 2.0
            let rowDy = 1.5 * r + gap
            let halfHexW = sqrt(3.0) * r / 2.0

            // Unshifted centers: top row at y=0, bottom row at y=rowDy
            let raw: [(Double, Double)] = [
                (0, 0), (colSpacing, 0),
                (rowOffset, rowDy), (rowOffset + colSpacing, rowDy)
            ]

            // Bounding box including hex extent
            let bboxLeft = -halfHexW
            let bboxRight = rowOffset + colSpacing + halfHexW
            let bboxTop = -r
            let bboxBottom = rowDy + r

            // Center in size x size
            let sx = cx - (bboxLeft + bboxRight) / 2.0
            let sy = cy - (bboxTop + bboxBottom) / 2.0

            return (raw.map { HexPosition(x: $0.0 + sx, y: $0.1 + sy) }, r)

        default:
            // 5+: honeycomb ring layout (1 center + surrounding)
            let rings = ringsNeeded(for: count)
            // For pointy-top, cluster width ~ (2*rings+1) * sqrt(3) * r
            let hexRadius = (size - Double(rings) * gap) / (Double(2 * rings + 1) * sqrt(3.0))
            let rh = (size - Double(rings) * gap) / (Double(2 * rings + 1) * 2.0)
            let r = min(hexRadius, rh)
            let allPositions = honeycombPositions(rings: rings, hexRadius: r, center: HexPosition(x: cx, y: cy))
            return (Array(allPositions.prefix(count)), r)
        }
    }

    /// Number of concentric rings needed to hold `count` hexagons.
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

    /// Generates honeycomb positions for pointy-top hexagons, spiraling outward.
    private static func honeycombPositions(rings: Int, hexRadius r: Double, center: HexPosition) -> [HexPosition] {
        var positions: [HexPosition] = [center]

        // Pointy-top neighbor directions (center-to-center with gap)
        let dx = sqrt(3.0) * r + gap
        let halfDx = dx / 2.0
        let dy = 1.5 * r + gap

        let directions: [(Double, Double)] = [
            (dx, 0),              // 0: right
            (halfDx, dy),         // 1: right-down
            (-halfDx, dy),        // 2: left-down
            (-dx, 0),             // 3: left
            (-halfDx, -dy),       // 4: left-up
            (halfDx, -dy)         // 5: right-up
        ]

        for ring in 1...max(rings, 1) {
            // Start to the right
            var x = center.x + Double(ring) * directions[0].0
            var y = center.y + Double(ring) * directions[0].1

            // Walk 6 edges starting from direction 2 (left-down)
            for edge in 0..<6 {
                let dir = (2 + edge) % 6
                for _ in 0..<ring {
                    positions.append(HexPosition(x: x, y: y))
                    x += directions[dir].0
                    y += directions[dir].1
                }
            }
        }

        return positions
    }

    /// Returns the 6 vertices of a pointy-top hexagon centered at `center` with given `radius`.
    public static func hexVertices(center: HexPosition, radius: Double) -> [HexPosition] {
        (0..<6).map { i in
            let angle = .pi / 6.0 + Double(i) * .pi / 3.0
            return HexPosition(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }
}
