import Foundation
@testable import AgentWatchLib

@MainActor
func runHexLayoutTests() {
    suite("HexLayout Tests")

    test("Zero hexagons returns placeholder") {
        let (centers, radius) = HexLayout.positions(count: 0, in: 22)
        try expectEqual(centers.count, 1)
        try expectEqual(radius, 11.0)
        try expectEqual(centers[0].x, 11.0)
        try expectEqual(centers[0].y, 11.0)
    }

    test("Single hexagon centered") {
        let (centers, _) = HexLayout.positions(count: 1, in: 22)
        try expectEqual(centers.count, 1)
        try expectEqual(centers[0].x, 11.0)
        try expectEqual(centers[0].y, 11.0)
    }

    test("Two hexagons are distinct") {
        let (centers, _) = HexLayout.positions(count: 2, in: 22)
        try expectEqual(centers.count, 2)
        let different = centers[0].x != centers[1].x || centers[0].y != centers[1].y
        try expect(different, "two hexagons should be at different positions")
    }

    test("All positions unique for N=1..12") {
        for n in 1...12 {
            let (centers, _) = HexLayout.positions(count: n, in: 22)
            try expectEqual(centers.count, n, "count mismatch for n=\(n)")

            var seen = Set<String>()
            for c in centers {
                let key = "\(Int(round(c.x * 100))),\(Int(round(c.y * 100)))"
                try expect(!seen.contains(key), "duplicate position for n=\(n)")
                seen.insert(key)
            }
        }
    }

    test("Positions within bounds for N=1..12") {
        let size = 22.0
        for n in 1...12 {
            let (centers, radius) = HexLayout.positions(count: n, in: size)
            for c in centers {
                try expect(c.x - radius >= -1.0, "x too small for n=\(n)")
                try expect(c.x + radius <= size + 1.0, "x too large for n=\(n)")
                try expect(c.y - radius >= -1.0, "y too small for n=\(n)")
                try expect(c.y + radius <= size + 1.0, "y too large for n=\(n)")
            }
        }
    }

    test("Rings needed calculation") {
        try expectEqual(HexLayout.ringsNeeded(for: 0), 0)
        try expectEqual(HexLayout.ringsNeeded(for: 1), 0)
        try expectEqual(HexLayout.ringsNeeded(for: 2), 1)
        try expectEqual(HexLayout.ringsNeeded(for: 7), 1)
        try expectEqual(HexLayout.ringsNeeded(for: 8), 2)
        try expectEqual(HexLayout.ringsNeeded(for: 19), 2)
    }

    test("Hex vertices produces 6 points") {
        let center = HexPosition(x: 10, y: 10)
        let vertices = HexLayout.hexVertices(center: center, radius: 5)
        try expectEqual(vertices.count, 6)
    }

    test("Hex vertices at correct distance") {
        let center = HexPosition(x: 10, y: 10)
        let vertices = HexLayout.hexVertices(center: center, radius: 5)
        for v in vertices {
            let dist = sqrt(pow(v.x - center.x, 2) + pow(v.y - center.y, 2))
            try expect(abs(dist - 5.0) < 0.001, "vertex distance \(dist) != 5.0")
        }
    }

    test("Flat-top orientation (first vertex at 0 degrees)") {
        let center = HexPosition(x: 0, y: 0)
        let vertices = HexLayout.hexVertices(center: center, radius: 10)
        try expect(abs(vertices[0].x - 10.0) < 0.001, "x should be 10")
        try expect(abs(vertices[0].y - 0.0) < 0.001, "y should be 0")
    }
}
