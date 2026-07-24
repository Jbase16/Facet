import Foundation

/// A named starting point for the shape picker: the outline already resolved
/// to `ShapeContent.pathData`, so choosing one is a plain assignment.
public struct ShapePreset: Sendable, Hashable {
    public let name: String
    public let pathData: String

    public init(name: String, pathData: String) {
        self.name = name
        self.pathData = pathData
    }
}

/// Parametric outlines for `ShapeKind.path` layers, in the same normalized
/// 0...1 space as `LayerFrame` and `PathCommand`.
///
/// Widget shapes are *rect-derived*, not circle-derived. A frame has to fill
/// the layer it lives in, hold a clock or a weather block without eating the
/// content, and look the same tomorrow — so every family here fills the unit
/// square exactly, is a pure function of its parameters, and never touches a
/// random number generator. (`BlobPath` is the one deliberately organic
/// family; it stays, but it is not the model for these.)
///
/// Conventions shared by every generator:
/// - Inputs are clamped *here*, not in an initializer, because `Codable`
///   bypasses initializers and a hand-edited document asking for `sides: 99`
///   still has to render.
/// - Non-finite inputs fall back to the family's default rather than poisoning
///   the whole document with `NaN`.
/// - Every path ends with a bounding-box normalization pass over the emitted
///   coordinates — control points included — so the outline fills the unit
///   square and no coordinate ever leaves 0...1. Arcs are split at their apex
///   precisely so that the apex is an *anchor*: a curve's extreme then lands on
///   the box edge instead of a control point overshooting past it.
/// - `y` grows downward, matching SVG and SwiftUI, so `topLeft` is (0, 0).
public enum ShapeGenerator {

    // MARK: - Superellipse

    /// |x|ⁿ + |y|ⁿ = 1 mapped onto the unit square.
    ///
    /// - Parameter roundness: the exponent, clamped 1.5...12. 2 is an ellipse,
    ///   ~4 is the Apple-style squircle, 12 is a box with a soft corner. Below
    ///   1.5 the sides cave into a starfish; above 12 the corner is tighter
    ///   than a widget's own mask and the extra boxiness is invisible.
    public static func superellipse(roundness: Double) -> String {
        let n = clamp(roundness, 1.5, 12, fallback: 4)

        // The 45° point, where the quadrant is split. It is also the tightest
        // constraint on the control points: everything must stay inside the box.
        let m = pow(0.5, 1 / n)
        // Target the curve should pass through at the middle of each half-arc.
        let target = Point(pow(cos(.pi / 8), 2 / n), pow(sin(.pi / 8), 2 / n))

        // A cubic's midpoint is (P0 + 3P1 + 3P2 + P3) / 8 — linear in the two
        // handle lengths — so matching it to `target` solves in closed form.
        // `diagonal` is the handle at (m, m) resolved along one axis; capping it
        // at 1 - m is what keeps P2 from poking past x = 1, and that cap is
        // exactly what makes high exponents read as boxy instead of bulging.
        let diagonal = clamp((8 * target.x - 4 - 4 * m) / 3, 0, 1 - m, fallback: 0)
        let handle = clamp((8 * target.y - 4 * m + 3 * diagonal) / 3, 0, 1, fallback: 0)

        // One quadrant, centered coordinates with half-extent 1: (1,0) → (m,m)
        // → (0,1) as two cubics. Two per quadrant rather than one, because a
        // single cubic per quadrant cannot exceed roundness ≈ 5.2 without its
        // control points leaving the unit square — the slider would go dead
        // over half its range. Eight cubics is still a ~250-byte path.
        let quadrant = [
            Point(1, 0),
            Point(1, handle), Point(m + diagonal, m - diagonal), Point(m, m),
            Point(m - diagonal, m + diagonal), Point(handle, 1), Point(0, 1),
        ]

        // Mirror the quadrant around the four corners of the box. Reversing the
        // mirrored copies (a cubic reversed is the same curve) keeps the walk
        // continuous, so the joins need no special-casing.
        var points: [Point] = [quadrant[0]]
        func sweep(_ transform: (Point) -> Point, reversed: Bool) {
            let mapped = quadrant.map(transform)
            points.append(contentsOf: (reversed ? mapped.reversed() : mapped).dropFirst())
        }
        sweep({ $0 }, reversed: false)
        sweep({ Point(-$0.x, $0.y) }, reversed: true)
        sweep({ Point(-$0.x, -$0.y) }, reversed: false)
        sweep({ Point($0.x, -$0.y) }, reversed: true)

        var builder = PathBuilder()
        builder.move(to: unitSquare(points[0]))
        for index in stride(from: 1, to: points.count, by: 3) {
            builder.cubic(
                unitSquare(points[index]),
                unitSquare(points[index + 1]),
                to: unitSquare(points[index + 2])
            )
        }
        builder.close()
        return serialize(builder.commands)
    }

    // MARK: - Rounded rectangle

    /// A rectangle with independent corner radii.
    ///
    /// Radii are fractions of the unit square's side, clamped 0...0.5 each —
    /// the same units on both axes, so the corners stay circular in the shape's
    /// own space and skew only as far as the layer frame itself is skewed.
    /// Two radii meeting on one edge are then scaled down together, CSS-style,
    /// if they would overrun it.
    public static func roundedRect(
        topLeft: Double,
        topRight: Double,
        bottomRight: Double,
        bottomLeft: Double
    ) -> String {
        var tl = clamp(topLeft, 0, 0.5, fallback: 0)
        var tr = clamp(topRight, 0, 0.5, fallback: 0)
        var br = clamp(bottomRight, 0, 0.5, fallback: 0)
        var bl = clamp(bottomLeft, 0, 0.5, fallback: 0)

        // Per-corner clamping already keeps every edge's pair under 1, but the
        // proportional pass is what a wider range would need and it costs
        // nothing here, so the invariant is enforced rather than assumed.
        var scale = 1.0
        for sum in [tl + tr, tr + br, br + bl, bl + tl] where sum > 1 {
            scale = min(scale, 1 / sum)
        }
        if scale < 1 {
            tl *= scale; tr *= scale; br *= scale; bl *= scale
        }

        // Quarter-circle corners are written with the exact Bézier constant
        // instead of going through `arc`, so an unrounded rectangle comes out
        // as literal 0s and 1s rather than 1e-17 dust.
        let k = Self.kappa
        var builder = PathBuilder()
        builder.move(to: Point(tl, 0))
        builder.line(to: Point(1 - tr, 0))
        if tr > 0 {
            builder.cubic(Point(1 - tr + k * tr, 0), Point(1, tr - k * tr), to: Point(1, tr))
        }
        builder.line(to: Point(1, 1 - br))
        if br > 0 {
            builder.cubic(Point(1, 1 - br + k * br), Point(1 - br + k * br, 1), to: Point(1 - br, 1))
        }
        builder.line(to: Point(bl, 1))
        if bl > 0 {
            builder.cubic(Point(bl - k * bl, 1), Point(0, 1 - bl + k * bl), to: Point(0, 1 - bl))
        }
        builder.line(to: Point(0, tl))
        if tl > 0 {
            builder.cubic(Point(0, tl - k * tl), Point(tl - k * tl, 0), to: Point(tl, 0))
        }
        builder.close()
        return serialize(builder.commands)
    }

    // MARK: - Cloud

    /// A cartoon cloud: a flat bottom with a few big overlapping circular puffs
    /// on top. It is the union of those circles, walked as one outline — the
    /// upper envelope over the puffs, then a straight run back along the base.
    /// The asymmetry (flat bottom, puffy top) is the point: it is what a radial
    /// ring of lobes can never be, because evenly-spaced outward lobes are a
    /// rosette. This is the shape people actually read as "cloud".
    ///
    /// - Parameters:
    ///   - puffs: number of billows across the top, clamped 3...7.
    ///   - puffiness: the base puff radius, clamped 0.05...0.5 — bigger is taller.
    ///   - irregularity: 0 is an even, tidy cloud; toward 1 the puffs vary in
    ///     size and spacing so it reads hand-drawn.
    ///   - seed: picks the variation. Deterministic (SplitMix64) so a document
    ///     renders identically everywhere instead of reshaping each redraw.
    public static func cloud(
        puffs: Int,
        puffiness: Double,
        irregularity: Double,
        seed: UInt64
    ) -> String {
        let n = clamp(puffs, 3, 7)
        let puff = clamp(puffiness, 0.05, 0.5, fallback: 0.25)
        let variation = clamp(irregularity, 0, 1, fallback: 0.3)
        var random = SeededRandom(seed: seed)

        // Every puff's bottom sits the same fraction below a shared baseline, so
        // the puffs rest on one flat ground line. Bigger puffs (the middle ones)
        // then reach higher.
        let sink = 0.42
        let baseline = 0.80

        let middle = Double(n - 1) / 2
        let spacing = 0.72 / Double(max(n - 1, 1))
        var discs: [(center: Point, radius: Double)] = []
        for index in 0..<n {
            let t = n == 1 ? 0.5 : Double(index) / Double(n - 1)
            let fromCentre = middle == 0 ? 0 : abs(Double(index) - middle) / middle
            // Big in the middle, tapering to the ends, jittered by irregularity —
            // but floored so neighbours always overlap and the coverage is
            // gap-free across the width.
            let jittered = puff * (1 - 0.4 * fromCentre) * (1 + random.nextSignedUnit() * 0.28 * variation)
            // Floor and jitter are both in units of the spacing so overlap holds
            // at any puff count: max centre drift (2·0.25·spacing) stays under the
            // combined floor radius (2·0.78·spacing), leaving no coverage gap.
            let radius = max(spacing * 0.78, jittered)
            let x = 0.14 + 0.72 * t + random.nextSignedUnit() * variation * spacing * 0.25
            discs.append((Point(x, baseline - radius * sink), radius))
        }
        discs.sort { $0.center.x < $1.center.x }

        // The outline top is the *upper envelope* of the puffs: at each x, the
        // highest circle covering it. That is a single-valued function of x, so
        // the top can never fold back on itself no matter how the puffs vary —
        // which is exactly the self-intersection the arc-walk couldn't avoid.
        let leftX = discs.map { $0.center.x - $0.radius }.min() ?? 0
        let rightX = discs.map { $0.center.x + $0.radius }.max() ?? 1
        func envelope(_ x: Double) -> Double {
            var top = baseline
            for disc in discs {
                let dx = x - disc.center.x
                if abs(dx) <= disc.radius {
                    top = min(top, disc.center.y - (disc.radius * disc.radius - dx * dx).squareRoot())
                }
            }
            return top
        }

        // Sample the envelope, then round the sampled corners with an open
        // spline: crossings between puffs become soft valleys instead of cusps,
        // which is what a cloud wants anyway.
        let samples = max(28, 6 * n)
        var top: [Point] = []
        for step in 0...samples {
            let x = leftX + (rightX - leftX) * Double(step) / Double(samples)
            top.append(Point(x, envelope(x)))
        }

        var builder = PathBuilder()
        builder.move(to: Point(leftX, baseline))
        builder.line(to: top[0])                       // up the left side
        // A tight tension keeps the spline from overshooting into a tiny loop at
        // the sharp valley between two puffs; dense samples keep it smooth anyway.
        appendOpenSpline(&builder, through: top, tension: 0.7)
        builder.line(to: Point(rightX, baseline))      // down the right side
        builder.close()                                // flat bottom back to start
        return serialize(builder.commands)
    }

    /// Threads an open Catmull-Rom spline through `points`, appending cubics from
    /// the current point. Endpoints are clamped (no wrap), so the two ends stay
    /// put and the sides meet them cleanly.
    private static func appendOpenSpline(
        _ builder: inout PathBuilder,
        through points: [Point],
        tension: Double
    ) {
        guard points.count >= 2 else { return }
        let scale = clamp(tension, 0, 1, fallback: 0.9) / 6
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            builder.cubic(p1 + (p2 - p0) * scale, p2 - (p3 - p1) * scale, to: p2)
        }
    }

    // MARK: - Polygon

    /// A regular polygon stretched to fill the unit square.
    ///
    /// - Parameters:
    ///   - sides: 3...12. Beyond 12 a widget-sized polygon is a circle.
    ///   - cornerRadius: 0...1 as a fraction of the largest fillet that fits —
    ///     at 1 the fillets from neighbouring vertices meet at the edge
    ///     midpoints, which is the roundest a polygon can get without eating
    ///     itself. Expressing it this way means no combination self-intersects.
    ///   - rotation: degrees clockwise on screen. 0 puts a vertex at the top.
    public static func polygon(sides: Int, cornerRadius: Double, rotation: Double) -> String {
        let count = clamp(sides, 3, 12)
        let start = -Double.pi / 2 + radians(rotation)
        let step = 2 * Double.pi / Double(count)
        let vertices = (0..<count).map { index -> Point in
            let angle = start + step * Double(index)
            return Point(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
        }
        return serialize(roundedPolygon(vertices, cornerRadius: cornerRadius))
    }

    // MARK: - Star

    /// A star: `points` outer vertices alternating with `points` inner ones.
    ///
    /// - Parameters:
    ///   - points: 3...12.
    ///   - innerRatio: inner radius as a fraction of the outer, clamped
    ///     0.2...0.9. Below 0.2 the arms are needles that vanish at widget
    ///     scale; above 0.9 it is a polygon with a rippled edge.
    ///   - cornerRadius: 0...1, same fraction-of-the-largest-fillet meaning as
    ///     `polygon`, applied to the inner notches as well as the outer tips.
    ///   - rotation: degrees clockwise on screen. 0 puts a tip at the top.
    public static func star(
        points: Int,
        innerRatio: Double,
        cornerRadius: Double,
        rotation: Double
    ) -> String {
        let tips = clamp(points, 3, 12)
        let ratio = clamp(innerRatio, 0.2, 0.9, fallback: 0.5)
        let start = -Double.pi / 2 + radians(rotation)
        let step = Double.pi / Double(tips)
        let vertices = (0..<(2 * tips)).map { index -> Point in
            let angle = start + step * Double(index)
            let radius = index % 2 == 0 ? 0.5 : 0.5 * ratio
            return Point(0.5 + radius * cos(angle), 0.5 + radius * sin(angle))
        }
        return serialize(roundedPolygon(vertices, cornerRadius: cornerRadius))
    }

    // MARK: - Presets

    /// Starting points for the picker, one or more per family, chosen so that
    /// every one of them still reads as a frame you could drop a clock into.
    public static let presets: [ShapePreset] = [
        ShapePreset(name: "Squircle", pathData: superellipse(roundness: 4)),
        ShapePreset(name: "Boxy", pathData: superellipse(roundness: 9)),
        ShapePreset(name: "Soft Rect", pathData: roundedRect(
            topLeft: 0.18, topRight: 0.18, bottomRight: 0.18, bottomLeft: 0.18
        )),
        ShapePreset(name: "Pill", pathData: roundedRect(
            topLeft: 0.5, topRight: 0.5, bottomRight: 0.5, bottomLeft: 0.5
        )),
        ShapePreset(name: "Leaf", pathData: roundedRect(
            topLeft: 0.5, topRight: 0.06, bottomRight: 0.5, bottomLeft: 0.06
        )),
        ShapePreset(name: "Arch", pathData: roundedRect(
            topLeft: 0.5, topRight: 0.5, bottomRight: 0.08, bottomLeft: 0.08
        )),
        ShapePreset(name: "Cloud", pathData: cloud(
            puffs: 5, puffiness: 0.26, irregularity: 0.3, seed: 7
        )),
        ShapePreset(name: "Puffy", pathData: cloud(
            puffs: 4, puffiness: 0.32, irregularity: 0.4, seed: 12
        )),
        ShapePreset(name: "Thought", pathData: cloud(
            puffs: 6, puffiness: 0.22, irregularity: 0.25, seed: 4
        )),
        ShapePreset(name: "Hexagon", pathData: polygon(
            sides: 6, cornerRadius: 0.22, rotation: 30
        )),
        ShapePreset(name: "Shield", pathData: polygon(
            sides: 5, cornerRadius: 0.3, rotation: 180
        )),
        ShapePreset(name: "Star", pathData: star(
            points: 5, innerRatio: 0.5, cornerRadius: 0.3, rotation: 0
        )),
    ]

    // MARK: - Rounded polygons

    /// Shared by `polygon` and `star`: walk the vertices, replacing each with a
    /// circular fillet tangent to both of its edges. Works unchanged at a
    /// star's reflex notches, because "arc tangent to both edges, centered on
    /// the bisector" describes rounding a notch just as well as a tip.
    private static func roundedPolygon(_ vertices: [Point], cornerRadius: Double) -> [PathCommand] {
        let fraction = clamp(cornerRadius, 0, 1, fallback: 0)
        let count = vertices.count
        var builder = PathBuilder()
        var started = false

        for index in 0..<count {
            let vertex = vertices[index]
            let previous = vertices[(index + count - 1) % count]
            let next = vertices[(index + 1) % count]
            let toPrevious = previous - vertex
            let toNext = next - vertex
            let lengthPrevious = toPrevious.length
            let lengthNext = toNext.length

            // Half the shorter edge is the most a fillet can take without
            // colliding with its neighbour's, which is why no `cornerRadius`
            // in 0...1 can make the outline self-intersect.
            let inset = fraction * min(lengthPrevious, lengthNext) / 2
            guard inset > Self.epsilon, lengthPrevious > Self.epsilon, lengthNext > Self.epsilon else {
                if started { builder.line(to: vertex) } else { builder.move(to: vertex); started = true }
                continue
            }

            let directionPrevious = toPrevious / lengthPrevious
            let directionNext = toNext / lengthNext
            // |dNext + dPrev| = 2cos(ω) and |dNext - dPrev| = 2sin(ω) for the
            // half-angle ω, so the whole fillet falls out of these two vectors
            // without a single inverse trig call.
            let bisector = directionPrevious + directionNext
            let separation = directionNext - directionPrevious
            let cosine = bisector.length / 2
            let sine = separation.length / 2
            guard cosine > Self.epsilon, sine > Self.epsilon else {
                if started { builder.line(to: vertex) } else { builder.move(to: vertex); started = true }
                continue
            }

            let radius = inset * sine / cosine
            let center = vertex + bisector / bisector.length * (inset / cosine)
            // Frame for the arc: `axis` points from the center back at the
            // vertex, `cross` runs from the incoming edge toward the outgoing
            // one, and the arc sweeps -half...+half around `axis`.
            let axis = bisector / bisector.length * -1
            let cross = separation / separation.length
            let half = atan2(cosine, sine)

            let entry = center + axis * (radius * cos(half)) - cross * (radius * sin(half))
            if started { builder.line(to: entry) } else { builder.move(to: entry); started = true }
            // Split at the apex so the fillet's extreme point is an anchor, not
            // something a control point overshoots.
            arc(&builder, center: center, radius: radius, axis: axis, cross: cross, from: -half, to: 0)
            arc(&builder, center: center, radius: radius, axis: axis, cross: cross, from: 0, to: half)
        }

        builder.close()
        return builder.commands
    }

    // MARK: - Arcs

    /// One cubic for the circular arc `P(t) = center + radius·(cos t·axis + sin
    /// t·cross)`, `t` from `from` to `to`. Exact at both ends; the ≤90° spans
    /// used here sit within ~0.02% of the true circle, which is finer than a
    /// widget's pixel grid at any rendition.
    private static func arc(
        _ builder: inout PathBuilder,
        center: Point,
        radius: Double,
        axis: Point,
        cross: Point,
        from: Double,
        to: Double
    ) {
        func point(_ t: Double) -> Point {
            center + axis * (radius * cos(t)) + cross * (radius * sin(t))
        }
        func tangent(_ t: Double) -> Point {
            axis * -sin(t) + cross * cos(t)
        }
        let handle = 4.0 / 3.0 * radius * tan((to - from) / 4)
        builder.cubic(
            point(from) + tangent(from) * handle,
            point(to) - tangent(to) * handle,
            to: point(to)
        )
    }

    // MARK: - Constants

    /// Bézier approximation constant for a quarter circle: 4/3·(√2 − 1).
    private static let kappa = 0.5522847498307933
    private static let epsilon = 1e-9

    // MARK: - Geometry

    private struct Point {
        var x: Double
        var y: Double

        init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
        }

        var length: Double { (x * x + y * y).squareRoot() }
        /// Last line of defence: clamping the inputs should make this
        /// unreachable, but one `NaN` in one control point would otherwise
        /// spread through normalization into every coordinate in the document.
        var sanitized: Point { Point(x.isFinite ? x : 0, y.isFinite ? y : 0) }

        static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y) }
        static func - (a: Point, b: Point) -> Point { Point(a.x - b.x, a.y - b.y) }
        static func * (a: Point, s: Double) -> Point { Point(a.x * s, a.y * s) }
        static func / (a: Point, s: Double) -> Point { Point(a.x / s, a.y / s) }

        func isNearly(_ other: Point) -> Bool {
            abs(x - other.x) < ShapeGenerator.epsilon && abs(y - other.y) < ShapeGenerator.epsilon
        }
    }

    /// Maps centered half-extent-1 coordinates onto the unit square.
    private static func unitSquare(_ point: Point) -> Point {
        Point(0.5 + 0.5 * point.x, 0.5 + 0.5 * point.y)
    }

    /// SplitMix64 — the same deterministic generator `BlobPath` uses, so the
    /// two organic families share one notion of "seeded but stable". Not
    /// cryptographic, which does not matter for choosing lobe sizes.
    private struct SeededRandom {
        private var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// Uniform in -1...1.
        mutating func nextSignedUnit() -> Double {
            Double(next() >> 11) / Double(UInt64(1) << 53) * 2 - 1
        }
    }

    private static func radians(_ degrees: Double) -> Double {
        // Wrapped rather than clamped: any rotation is meaningful, but feeding
        // a huge angle to `cos` invites platform-specific argument reduction,
        // and determinism across the editor, the extension, and Linux CI is the
        // whole point of generating shapes instead of storing them.
        guard degrees.isFinite else { return 0 }
        return degrees.truncatingRemainder(dividingBy: 360) * .pi / 180
    }

    private struct PathBuilder {
        private(set) var commands: [PathCommand] = []
        private(set) var currentPoint = Point(0, 0)
        private var subpathStart = Point(0, 0)

        mutating func move(to point: Point) {
            let point = point.sanitized
            commands.append(.move(x: point.x, y: point.y))
            currentPoint = point
            subpathStart = point
        }

        mutating func line(to point: Point) {
            let point = point.sanitized
            guard !point.isNearly(currentPoint) else { return }
            commands.append(.line(x: point.x, y: point.y))
            currentPoint = point
        }

        mutating func cubic(_ control1: Point, _ control2: Point, to point: Point) {
            let control1 = control1.sanitized
            let control2 = control2.sanitized
            let point = point.sanitized
            commands.append(.cubic(
                c1x: control1.x, c1y: control1.y,
                c2x: control2.x, c2y: control2.y,
                x: point.x, y: point.y
            ))
            currentPoint = point
        }

        /// `Z` already draws the closing line, so a final `L` back to the start
        /// is dropped — that is what lets a radius-0 rounded rect come out as
        /// literally four points.
        mutating func close() {
            if case .line(let x, let y)? = commands.last, Point(x, y).isNearly(subpathStart) {
                commands.removeLast()
            }
            commands.append(.close)
            currentPoint = subpathStart
        }
    }

    // MARK: - Clamping

    private static func clamp(
        _ value: Double,
        _ lower: Double,
        _ upper: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, lower), upper)
    }

    private static func clamp(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    // MARK: - Normalization

    /// Scales the outline so its emitted coordinates span exactly 0...1 on both
    /// axes, then hands off to the one serializer the document format has.
    /// Measuring control points rather than the curve is deliberate: it is the
    /// only cheap way to guarantee nothing in the string leaves the unit square,
    /// and every family above puts its extremes on anchors so the cost is
    /// nothing for rectangles and under a percent for a fully rounded polygon.
    private static func serialize(_ commands: [PathCommand]) -> String {
        var minimum = Point(.infinity, .infinity)
        var maximum = Point(-.infinity, -.infinity)
        func note(_ x: Double, _ y: Double) {
            minimum = Point(min(minimum.x, x), min(minimum.y, y))
            maximum = Point(max(maximum.x, x), max(maximum.y, y))
        }
        for command in commands {
            switch command {
            case .move(let x, let y), .line(let x, let y):
                note(x, y)
            case .quad(let cx, let cy, let x, let y):
                note(cx, cy); note(x, y)
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                note(c1x, c1y); note(c2x, c2y); note(x, y)
            case .close:
                break
            }
        }
        guard minimum.x.isFinite, minimum.y.isFinite else {
            return PathData.string(from: commands, precision: 4)
        }

        // A zero span is unreachable for the shapes above, but dividing by it
        // would turn the whole path into NaN, so it is worth the guard.
        let width = maximum.x - minimum.x
        let height = maximum.y - minimum.y
        let scaleX = width > 0 ? 1 / width : 0
        let scaleY = height > 0 ? 1 / height : 0
        func mapX(_ x: Double) -> Double { (x - minimum.x) * scaleX }
        func mapY(_ y: Double) -> Double { (y - minimum.y) * scaleY }

        let mapped = commands.map { command -> PathCommand in
            switch command {
            case .move(let x, let y):
                return .move(x: mapX(x), y: mapY(y))
            case .line(let x, let y):
                return .line(x: mapX(x), y: mapY(y))
            case .quad(let cx, let cy, let x, let y):
                return .quad(cx: mapX(cx), cy: mapY(cy), x: mapX(x), y: mapY(y))
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                return .cubic(
                    c1x: mapX(c1x), c1y: mapY(c1y),
                    c2x: mapX(c2x), c2y: mapY(c2y),
                    x: mapX(x), y: mapY(y)
                )
            case .close:
                return .close
            }
        }
        return PathData.string(from: mapped, precision: 4)
    }
}
