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

    // MARK: - Scallop

    /// A rounded rectangle whose straight edges bulge outward in circular arcs
    /// — the "cloud" family, and the one shape that still frames content
    /// because its corners and its content-bearing middle are unchanged.
    ///
    /// - Parameters:
    ///   - bumpsX: bulges along the top and bottom edges, clamped 0...8.
    ///   - bumpsY: bulges along the left and right edges, clamped 0...8.
    ///   - depth: how far each bulge stands off its edge, clamped 0...0.12, and
    ///     additionally capped at 45% of the chord of the *most crowded* edge —
    ///     so every lobe on the outline rises the same amount. Past half a chord
    ///     an arc turns back on itself and neighbouring bulges cross; just under
    ///     that it still cusps like a cartoon cloud. Consequence worth knowing:
    ///     at seven or eight bulges the cap binds for the whole legal range, and
    ///     the depth control stops moving.
    ///   - cornerRadius: the underlying rectangle's corner radius, 0...0.3.
    ///     Past 0.3 the base shape is nearly a circle and the straight run left
    ///     to carry bulges is short enough that they read as warts stuck on it
    ///     rather than lobes of one outline — worst at one bulge per edge. A
    ///     rounder base is `roundedRect`'s job anyway.
    public static func scallop(
        bumpsX: Int,
        bumpsY: Int,
        depth: Double,
        cornerRadius: Double
    ) -> String {
        let countX = clamp(bumpsX, 0, 8)
        let countY = clamp(bumpsY, 0, 8)
        let requested = clamp(depth, 0, 0.12, fallback: 0)
        let radius = clamp(cornerRadius, 0, 0.3, fallback: 0)

        // Flat on both axes is a rounded rectangle, and routing through the same
        // function guarantees it is byte-identical to one.
        guard countX > 0 || countY > 0, requested > 0 else {
            return roundedRect(
                topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius
            )
        }

        // One rise for every bulge on the outline, set by whichever axis is most
        // crowded. Capping the two axes independently let three lobes across the
        // top sit next to two much taller ones down the side, and the result
        // read as two shapes fighting rather than one.
        let span = 1 - 2 * radius
        let crowding = max(countX, countY)
        let sagitta = min(requested, Self.maxSagitta * span / Double(crowding))
        let sagittaX = countX > 0 ? sagitta : 0
        let sagittaY = countY > 0 ? sagitta : 0

        let k = Self.kappa
        var builder = PathBuilder()
        builder.move(to: Point(radius, 0))
        bulge(&builder, to: Point(1 - radius, 0), outward: Point(0, -1), count: countX, sagitta: sagittaX)
        if radius > 0 {
            builder.cubic(
                Point(1 - radius + k * radius, 0), Point(1, radius - k * radius), to: Point(1, radius)
            )
        }
        bulge(&builder, to: Point(1, 1 - radius), outward: Point(1, 0), count: countY, sagitta: sagittaY)
        if radius > 0 {
            builder.cubic(
                Point(1, 1 - radius + k * radius), Point(1 - radius + k * radius, 1),
                to: Point(1 - radius, 1)
            )
        }
        bulge(&builder, to: Point(radius, 1), outward: Point(0, 1), count: countX, sagitta: sagittaX)
        if radius > 0 {
            builder.cubic(
                Point(radius - k * radius, 1), Point(0, 1 - radius + k * radius),
                to: Point(0, 1 - radius)
            )
        }
        bulge(&builder, to: Point(0, radius), outward: Point(-1, 0), count: countY, sagitta: sagittaY)
        if radius > 0 {
            builder.cubic(Point(0, radius - k * radius), Point(radius - k * radius, 0), to: Point(radius, 0))
        }
        builder.close()
        // The bulges push past the unit square by one sagitta on each side;
        // normalization pulls the whole outline back in.
        return serialize(builder.commands)
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
        ShapePreset(name: "Cloud", pathData: scallop(
            bumpsX: 3, bumpsY: 2, depth: 0.12, cornerRadius: 0.18
        )),
        ShapePreset(name: "Wide Cloud", pathData: scallop(
            bumpsX: 5, bumpsY: 3, depth: 0.12, cornerRadius: 0.12
        )),
        ShapePreset(name: "Ticket", pathData: scallop(
            bumpsX: 0, bumpsY: 5, depth: 0.06, cornerRadius: 0.06
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

    /// Replaces the straight run to `end` with `count` outward circular
    /// bulges of height `sagitta`. Each bulge is two cubics meeting at its apex.
    private static func bulge(
        _ builder: inout PathBuilder,
        to end: Point,
        outward: Point,
        count: Int,
        sagitta: Double
    ) {
        let start = builder.currentPoint
        let span = end - start
        guard count > 0, sagitta > Self.epsilon, span.length > Self.epsilon else {
            builder.line(to: end)
            return
        }

        let chord = span / Double(count)
        let chordLength = chord.length
        let direction = chord / chordLength
        // Circle through both chord ends with the requested rise at the middle.
        let radius = (chordLength * chordLength / 4 + sagitta * sagitta) / (2 * sagitta)
        let half = atan2(chordLength / 2, radius - sagitta)

        for index in 0..<count {
            let middle = start + chord * (Double(index) + 0.5)
            let center = middle - outward * (radius - sagitta)
            arc(&builder, center: center, radius: radius, axis: outward, cross: direction, from: -half, to: 0)
            arc(&builder, center: center, radius: radius, axis: outward, cross: direction, from: 0, to: half)
        }
    }

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
    /// Fraction of a chord a bulge may rise. At 0.5 the arc is a semicircle and
    /// adjacent bulges meet in a spike; this leaves a shoulder.
    private static let maxSagitta = 0.45
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
