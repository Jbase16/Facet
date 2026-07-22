import Foundation

/// Controls for a procedurally generated organic blob.
///
/// A soft, irregular silhouette is the one frame shape you cannot express as
/// a rectangle, circle, or capsule, and hand-authoring Bézier data on a phone
/// is miserable. So the editor gives users four numbers instead of a curve
/// editor and generates the path from them.
public struct BlobParameters: Codable, Hashable, Sendable {
    /// Anchor points spaced evenly around the circle, 3...12. Fewer reads as
    /// a lumpy triangle, more as noise at widget scale.
    public var points: Int
    /// How far radii may vary, 0...1. 0 is a circle; high values pinch.
    public var irregularity: Double
    /// Cubic handle length as a fraction of the circular-arc ideal, 0...1.
    /// 1 traces a true arc through the anchors; lower values pull the curve
    /// toward the straight polygon, giving a faceted, pebble-like edge.
    public var smoothness: Double
    /// Picks which blob you get. Same seed, same shape, forever.
    public var seed: UInt64

    public init(
        points: Int = 6,
        irregularity: Double = 0.3,
        smoothness: Double = 1.0,
        seed: UInt64 = 0
    ) {
        self.points = points
        self.irregularity = irregularity
        self.smoothness = smoothness
        self.seed = seed
    }

    public static let `default` = BlobParameters()

    // Clamped where the path is generated rather than in `init`, because
    // `Codable` bypasses `init` — a hand-edited document asking for 99 points
    // still has to render something sane instead of trapping.
    var resolvedPoints: Int { min(max(points, 3), 12) }
    var resolvedIrregularity: Double { Self.clamp(irregularity, fallback: 0) }
    var resolvedSmoothness: Double { Self.clamp(smoothness, fallback: 1) }

    private static func clamp(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, 0), 1)
    }
}

/// Generates closed, C1-continuous blob outlines as SVG path data in
/// normalized 0...1 coordinates — the same space `LayerFrame` and
/// `PathCommand` use, so a blob fills whatever layer holds it.
public enum BlobPath {
    /// SVG `d` string for `parameters`: `M`, one `C` per point, then `Z`.
    public static func path(_ parameters: BlobParameters) -> String {
        PathData.string(from: commands(parameters), precision: 4)
    }

    /// The same outline as commands, before serialization. Internal because
    /// the document stores paths as strings; useful for tests and callers
    /// that would only parse the string back again.
    static func commands(_ parameters: BlobParameters) -> [PathCommand] {
        let count = parameters.resolvedPoints
        let irregularity = parameters.resolvedIrregularity
        let smoothness = parameters.resolvedSmoothness
        let step = 2 * Double.pi / Double(count)

        // Anchors on a circle, each pulled inward by its own random amount.
        // Starting at -90° puts the first anchor at the top, which keeps an
        // unperturbed blob left/right symmetric and the path readable.
        var anchors: [Point] = []
        anchors.reserveCapacity(count)
        for index in 0..<count {
            let angle = -Double.pi / 2 + step * Double(index)
            let radius = 0.5 * (1 - irregularity * rand01(seed: parameters.seed, index: index))
            anchors.append(Point(x: cos(angle) * radius, y: sin(angle) * radius))
        }

        // Catmull-Rom → Bézier: the handle at p1 points along (p2 - p0), which
        // is what makes the joins C1-continuous. The classic 1/6 undershoots a
        // circle, so `arc` rescales it such that smoothness == 1 reproduces a
        // true circular arc when the radii are equal.
        let arc = 4 * tan(step / 4) / sin(step)
        let tangent = smoothness * arc / 6

        // Emission order: start point, then (control, control, end) per
        // segment. Kept flat so the normalization pass below can walk every
        // coordinate the path will actually contain.
        var coordinates: [Point] = [anchors[0]]
        coordinates.reserveCapacity(1 + 3 * count)
        for index in 0..<count {
            let previous = anchors[(index + count - 1) % count]
            let start = anchors[index]
            let end = anchors[(index + 1) % count]
            let next = anchors[(index + 2) % count]
            coordinates.append(Point(
                x: start.x + (end.x - previous.x) * tangent,
                y: start.y + (end.y - previous.y) * tangent
            ))
            coordinates.append(Point(
                x: end.x - (next.x - start.x) * tangent,
                y: end.y - (next.y - start.y) * tangent
            ))
            coordinates.append(end)
        }

        normalize(&coordinates)

        var commands: [PathCommand] = [.move(x: coordinates[0].x, y: coordinates[0].y)]
        commands.reserveCapacity(count + 2)
        for index in 0..<count {
            let control1 = coordinates[3 * index + 1]
            let control2 = coordinates[3 * index + 2]
            let end = coordinates[3 * index + 3]
            commands.append(.cubic(
                c1x: control1.x, c1y: control1.y,
                c2x: control2.x, c2y: control2.y,
                x: end.x, y: end.y
            ))
        }
        commands.append(.close)
        return commands
    }

    /// Six shapes worth putting in front of a user, so the feature is usable
    /// before anyone touches a slider.
    public static let presets: [(name: String, parameters: BlobParameters)] = [
        ("Pebble", BlobParameters(points: 6, irregularity: 0.28, smoothness: 1.0, seed: 7)),
        ("Cloud", BlobParameters(points: 9, irregularity: 0.16, smoothness: 1.0, seed: 3)),
        ("Droplet", BlobParameters(points: 5, irregularity: 0.34, smoothness: 1.0, seed: 12)),
        ("Boulder", BlobParameters(points: 7, irregularity: 0.3, smoothness: 0.72, seed: 21)),
        ("Puddle", BlobParameters(points: 8, irregularity: 0.22, smoothness: 1.0, seed: 5)),
        ("Splat", BlobParameters(points: 11, irregularity: 0.42, smoothness: 1.0, seed: 42)),
    ]

    // MARK: - Geometry

    private struct Point {
        var x: Double
        var y: Double
    }

    /// Scales the outline so its bounding box is exactly 0,0...1,1 — whatever
    /// the random radii did, the blob fills its layer frame. Run as a final
    /// pass over control points as well as anchors, which keeps every emitted
    /// coordinate inside the unit square (the curve itself then sits a hair
    /// inside the box, since a Bézier stays within its control hull).
    private static func normalize(_ coordinates: inout [Point]) {
        var minimum = coordinates[0]
        var maximum = coordinates[0]
        for point in coordinates {
            minimum.x = min(minimum.x, point.x)
            minimum.y = min(minimum.y, point.y)
            maximum.x = max(maximum.x, point.x)
            maximum.y = max(maximum.y, point.y)
        }
        // A zero span is unreachable for 3+ distinct anchors, but dividing by
        // it would poison the whole path with NaN, so it is worth the guard.
        let width = maximum.x - minimum.x
        let height = maximum.y - minimum.y
        let scaleX = width > 0 ? 1 / width : 0
        let scaleY = height > 0 ? 1 / height : 0
        for index in coordinates.indices {
            coordinates[index] = Point(
                x: (coordinates[index].x - minimum.x) * scaleX,
                y: (coordinates[index].y - minimum.y) * scaleY
            )
        }
    }

    // MARK: - Deterministic noise

    /// SplitMix64, inlined. Determinism is not a nicety here: a `.facet`
    /// document stores only the parameters, so the same blob has to come back
    /// bit-for-bit in the editor, in the widget extension, and in Linux CI's
    /// SVG snapshots. `Double.random` and any system RNG are disqualified.
    private static func rand01(seed: UInt64, index: Int) -> Double {
        // Hashing seed + (index + 1) * gamma is exactly the (index + 1)-th
        // output of a SplitMix64 stream seeded with `seed`, but as a pure
        // function of the index — so growing `points` leaves earlier radii
        // alone instead of reshuffling the blob under the user's slider.
        let gamma: UInt64 = 0x9E37_79B9_7F4A_7C15
        var z = seed &+ (UInt64(index) &+ 1) &* gamma
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        // Top 53 bits: every result is exactly representable, so the same
        // Double comes out on every platform.
        return Double(z >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
