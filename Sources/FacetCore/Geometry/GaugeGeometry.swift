import Foundation

/// How a gauge's stroke ends are drawn. Carried on `GaugeArc` rather than
/// baked into the path because a cap is a stroke property in every backend
/// Facet renders through — SwiftUI's `StrokeStyle`, SVG's `stroke-linecap` —
/// and turning it into outline geometry here would throw that away.
public enum GaugeCap: String, Codable, Sendable {
    case butt
    case round
}

/// Which way the gauge fills from its start angle.
public enum GaugeDirection: String, Codable, Sendable {
    case clockwise
    case counterClockwise
}

/// One resolved gauge: the full sweep and the filled portion of it, as two
/// paths a renderer strokes with the same width and cap.
///
/// Two paths rather than one path plus a trim fraction, because the segmented
/// family has no single continuous parameter to trim — and because a resolved
/// document should carry geometry a dumb renderer can draw without re-deriving
/// anything.
///
/// `progress` is the empty string when there is nothing to draw (value 0). A
/// zero-length subpath would have been the alternative, but SVG and SwiftUI
/// disagree about whether a round cap on one paints a dot, and a gauge that
/// looks different on two surfaces is worse than one that draws nothing.
public struct GaugeArc: Sendable, Hashable {
    /// The whole sweep, drawn in the track colour.
    public let track: String
    /// The reached portion, drawn in the tint. Empty when value is 0.
    public let progress: String
    /// Line cap for both paths.
    public let cap: GaugeCap

    public init(track: String, progress: String, cap: GaugeCap) {
        self.track = track
        self.progress = progress
        self.cap = cap
    }
}

/// Progress-gauge outlines in the same normalized 0...1 space as `LayerFrame`
/// and `PathCommand`: partial arcs, a chosen start angle, either direction,
/// and the segmented "activity ticks" look.
///
/// Angle convention: **degrees, 0° at 12 o'clock, positive turning clockwise
/// on screen** — the same sense as `ShapeGenerator.polygon(rotation:)`, and the
/// sense a person means when they say a dial starts at "the bottom" (180°).
/// `y` grows downward, so a point at angle θ is `(0.5 + r·sin θ, 0.5 − r·cos θ)`.
///
/// Conventions shared with `ShapeGenerator`:
/// - Inputs are clamped *here*, not in an initializer, because `Codable`
///   bypasses initializers and a hand-edited document asking for `sweep: 900`
///   still has to render.
/// - Non-finite inputs fall back to the documented default rather than
///   poisoning the document with `NaN`.
/// - Arcs are cubic Béziers split at the quadrant boundaries, so no piece
///   spans more than 90°.
/// - Pure functions, no RNG: identical inputs give byte-identical strings on
///   every platform.
///
/// One convention is deliberately *not* shared. `ShapeGenerator` normalizes
/// every outline to fill the unit square exactly; a gauge must not. A gauge is
/// concentric with its layer — a 270° arc normalized to its own bounding box
/// would slide off-centre and stop lining up with the value label sitting at
/// the layer's middle, and the same gauge at two different sweeps would sit in
/// two different places. So every arc here is centred on (0.5, 0.5) with one
/// radius, and the emitted box is whatever that circle occupies.
///
/// That also fixes what a renderer owes a non-square layer. These coordinates
/// describe a *square*: stretched to a 2:1 frame a ring becomes an ellipse.
/// A gauge layer should be drawn into the square on its smaller side, centred —
/// which is the same rule that makes `lineWidth` (a fraction of that smaller
/// side) mean one thing on both axes.
public enum GaugeGeometry {

    // MARK: - Ring

    /// A circular gauge: an arc of `sweep` degrees starting at `startAngle`,
    /// with the first `value` of it filled.
    ///
    /// - Parameters:
    ///   - value: 0...1, clamped. Non-finite falls back to 0 (nothing filled).
    ///   - startAngle: degrees, 0 = 12 o'clock, positive clockwise. Wrapped
    ///     rather than clamped — every angle is meaningful, but handing a huge
    ///     one to `sin` invites platform-specific argument reduction, and
    ///     determinism across the editor, the extension, and Linux CI is the
    ///     whole point of generating geometry instead of storing it.
    ///   - sweep: how much of the circle the gauge spans, clamped 1...360.
    ///     360 is a full ring, 270 the classic activity arc, 180 a half-dial.
    ///     Non-finite falls back to 360. Zero is excluded because a gauge with
    ///     no extent cannot show a value.
    ///   - direction: which way the fill runs from `startAngle`.
    ///   - cap: line cap the renderer should use.
    ///   - lineWidth: stroke width as a fraction of the layer's smaller side,
    ///     clamped 0...0.5. The arc radius insets by half of it, so the stroke
    ///     lands inside the layer instead of being clipped at its edge; at 0.5
    ///     the stroke reaches the centre and the ring is a disc, which is as
    ///     thick as a gauge can get. Non-finite falls back to 0.1.
    public static func ring(
        value: Double,
        startAngle: Double,
        sweep: Double,
        direction: GaugeDirection,
        cap: GaugeCap,
        lineWidth: Double
    ) -> GaugeArc {
        let fraction = clamp(value, 0, 1, fallback: 0)
        let extent = clamp(sweep, 1, 360, fallback: 360)
        let start = wrapped(startAngle)
        let radius = radius(for: lineWidth)
        let sign = direction == .clockwise ? 1.0 : -1.0

        let track = subpath(radius: radius, from: start, span: sign * extent)
        // The filled arc starts where the track does, so at value 1 the two
        // strings are identical — the renderer can compare them if it wants to
        // skip drawing the track underneath.
        let progress = subpath(radius: radius, from: start, span: sign * extent * fraction)
        return GaugeArc(
            track: PathData.string(from: track),
            progress: PathData.string(from: progress),
            cap: cap
        )
    }

    // MARK: - Bar

    /// The linear equivalent: a horizontal line across the middle of the layer,
    /// filled left to right. Same `GaugeArc` shape as the rings so a renderer
    /// has one thing to draw rather than a branch per gauge style.
    ///
    /// This is the one gauge a renderer may reasonably stretch to a wide frame
    /// rather than confining to the smaller side's square — a progress bar
    /// should span the layer. The end inset is half a line width measured in
    /// the square, so under that stretch it is never smaller than the cap
    /// actually needs: the bar can fall a little short of the ends, never over
    /// them.
    ///
    /// - Parameters:
    ///   - value: 0...1, clamped. Non-finite falls back to 0.
    ///   - cap: line cap. `round` is why the bar insets from both ends —
    ///     without the inset a round cap would bulge past the layer edge.
    ///   - lineWidth: bar thickness as a fraction of the layer's smaller side,
    ///     clamped 0...0.5 (the same range as the rings, so switching styles
    ///     never changes what a stored width means). Non-finite falls back
    ///     to 0.1.
    public static func bar(value: Double, cap: GaugeCap, lineWidth: Double) -> GaugeArc {
        let fraction = clamp(value, 0, 1, fallback: 0)
        let stroke = clamp(lineWidth, 0, 0.5, fallback: 0.1)
        let inset = stroke / 2
        let left = inset
        let right = 1 - inset
        let width = right - left

        var track: [PathCommand] = []
        if width > epsilon {
            track = [.move(x: left, y: 0.5), .line(x: right, y: 0.5)]
        }
        var progress: [PathCommand] = []
        if width > epsilon, fraction > 0 {
            progress = [.move(x: left, y: 0.5), .line(x: left + width * fraction, y: 0.5)]
        }
        return GaugeArc(
            track: PathData.string(from: track),
            progress: PathData.string(from: progress),
            cap: cap
        )
    }

    // MARK: - Segmented

    /// A ring broken into discrete ticks — activity dots, battery cells.
    ///
    /// A tick is lit as soon as the value reaches *into* it, so the gauge reads
    /// as "3 of 8" rather than as a smoothly growing arc with notches cut out
    /// of it. That is the whole point of the family: the segments are the unit.
    ///
    /// - Parameters:
    ///   - value: 0...1, clamped. Non-finite falls back to 0.
    ///   - segments: number of ticks, clamped 2...60. One tick is not a gauge;
    ///     past 60 the gaps are thinner than a widget pixel and it is a ring
    ///     with a moiré pattern.
    ///   - startAngle: degrees, 0 = 12 o'clock, positive clockwise, wrapped.
    ///   - sweep: total extent, clamped 1...360, non-finite falls back to 360.
    ///   - direction: which way the ticks run from `startAngle`.
    ///   - gapDegrees: gap between neighbouring ticks, clamped to 0...90% of
    ///     the space available for gaps, so a tick can never be starved to
    ///     nothing. Non-finite falls back to 0 (abutting ticks, which still
    ///     light up discretely). A full 360 ring has one gap per tick, because
    ///     the last tick wraps around to meet the first; a partial arc has one
    ///     fewer, so its first and last ticks land exactly on the requested
    ///     sweep's ends and line up with the plain `ring` at the same sweep.
    ///   - lineWidth: as `ring`. With `round` caps and a short tick this is
    ///     also what makes the ticks read as dots rather than dashes.
    ///   - cap: line cap for each tick. Defaults to `butt` — the battery-cell
    ///     look. `round` with a short tick is the activity-dots look, and it
    ///     shortens each tick's *path* by half a line width at both ends so
    ///     that the cap paints back out to the tick's real extent. Without
    ///     that, a round cap eats a gap narrower than the stroke and an
    ///     8-tick ring at `gapDegrees: 6` comes out as a solid ring with the
    ///     gap slider apparently doing nothing. The shortening never inverts
    ///     a tick: below the point where the two caps meet, a tick is a dot of
    ///     the stroke's own diameter, which is as small as a round cap can
    ///     draw anything.
    public static func segmented(
        value: Double,
        segments: Int,
        startAngle: Double,
        sweep: Double,
        direction: GaugeDirection,
        gapDegrees: Double,
        lineWidth: Double,
        cap: GaugeCap = .butt
    ) -> GaugeArc {
        let fraction = clamp(value, 0, 1, fallback: 0)
        let count = clamp(segments, 2, 60)
        let extent = clamp(sweep, 1, 360, fallback: 360)
        let start = wrapped(startAngle)
        let radius = radius(for: lineWidth)
        let sign = direction == .clockwise ? 1.0 : -1.0

        let gapCount = isFullTurn(extent) ? count : count - 1
        let maximumGap = 0.9 * extent / Double(max(gapCount, 1))
        let gap = clamp(gapDegrees, 0, maximumGap, fallback: 0)
        let tick = (extent - gap * Double(gapCount)) / Double(count)
        let pitch = tick + gap

        // Ceiling, not rounding: any part of a tick reached lights the whole
        // tick, and an exact boundary (value 0.5 over 4 ticks) lights exactly
        // half. The epsilon keeps 1.0 × count off the wrong side of `ceil`
        // when the multiplication lands a bit high.
        let lit = fraction <= 0
            ? 0
            : min(count, max(0, Int((fraction * Double(count) - 1e-9).rounded(.up))))

        // What a round cap paints past each end of the tick, as an angle. The
        // drawn arc gives that back so the painted tick is `tick` degrees wide
        // and the gaps the user asked for survive; the floor keeps a very short
        // tick a drawable dot rather than an inverted arc.
        let overhang = cap == .round ? degrees(arcLength: lineWidthUsed(lineWidth) / 2, radius: radius) : 0
        let drawn = max(tick - 2 * overhang, minimumTickDegrees(radius: radius))
        let lead = (tick - drawn) / 2

        var track: [PathCommand] = []
        var progress: [PathCommand] = []
        for index in 0..<count {
            let from = start + sign * (pitch * Double(index) + lead)
            let piece = subpath(radius: radius, from: from, span: sign * drawn)
            track.append(contentsOf: piece)
            if index < lit { progress.append(contentsOf: piece) }
        }
        return GaugeArc(
            track: PathData.string(from: track),
            progress: PathData.string(from: progress),
            cap: cap
        )
    }

    // MARK: - Arcs

    /// One subpath for the arc of `span` degrees starting at `from`, centred on
    /// the layer. Empty when there is nothing to draw, which is what makes
    /// `progress` come back as "" at value 0.
    private static func subpath(radius: Double, from: Double, span: Double) -> [PathCommand] {
        guard radius > epsilon, abs(span) > epsilon else { return [] }
        let cuts = quadrantCuts(from: from, span: span)
        let origin = point(radius: radius, degrees: cuts[0])
        var commands: [PathCommand] = [.move(x: origin.x, y: origin.y)]
        for index in 0..<(cuts.count - 1) {
            commands.append(cubic(radius: radius, from: cuts[index], to: cuts[index + 1]))
        }
        // A whole turn closes: `Z` joins the ends into one continuous stroke
        // instead of butting two caps against each other at the seam.
        if isFullTurn(abs(span)) { commands.append(.close) }
        return commands
    }

    /// The angles the arc is split at: its ends, plus every quadrant boundary
    /// between them.
    ///
    /// Splitting on quadrants rather than just "every 90°" is what keeps the
    /// gauge inside its layer. A cubic's control points sit outside the arc it
    /// approximates, but for a piece that stays within one quadrant they never
    /// leave the circle's own bounding box — the extreme of each piece is an
    /// anchor, exactly as `ShapeGenerator` splits its fillets at their apex.
    /// Split anywhere else and a 90° piece straddling 45° pushes a control
    /// point ~5% past the radius, which at `lineWidth` 0 is past the layer edge.
    private static func quadrantCuts(from: Double, span: Double) -> [Double] {
        let end = from + span
        var cuts: [Double] = [from]
        if span > 0 {
            var step = (from / 90).rounded(.down) + 1
            while step * 90 < end - epsilon {
                cuts.append(step * 90)
                step += 1
            }
        } else {
            var step = (from / 90).rounded(.up) - 1
            while step * 90 > end + epsilon {
                cuts.append(step * 90)
                step -= 1
            }
        }
        cuts.append(end)
        return cuts
    }

    /// One cubic for the circular arc from `from` to `to` degrees. Exact at
    /// both ends; over the ≤90° pieces used here it sits within ~0.02% of the
    /// true circle, finer than a widget's pixel grid at any rendition.
    private static func cubic(radius: Double, from: Double, to: Double) -> PathCommand {
        let handle = 4.0 / 3.0 * radius * tan(radians(to - from) / 4)
        let start = point(radius: radius, degrees: from)
        let finish = point(radius: radius, degrees: to)
        let control1 = start + tangent(degrees: from) * handle
        let control2 = finish - tangent(degrees: to) * handle
        return .cubic(
            c1x: control1.sanitized.x, c1y: control1.sanitized.y,
            c2x: control2.sanitized.x, c2y: control2.sanitized.y,
            x: finish.sanitized.x, y: finish.sanitized.y
        )
    }

    /// 0° at 12 o'clock, positive clockwise, `y` down.
    private static func point(radius: Double, degrees: Double) -> Point {
        let t = radians(degrees)
        return Point(0.5 + radius * sin(t), 0.5 - radius * cos(t))
    }

    /// Unit tangent in the direction of increasing degrees.
    private static func tangent(degrees: Double) -> Point {
        let t = radians(degrees)
        return Point(cos(t), sin(t))
    }

    /// Half the stroke, inset from the layer edge — otherwise the outer half of
    /// the stroke hangs over the edge and the widget's own mask clips it.
    private static func radius(for lineWidth: Double) -> Double {
        0.5 - lineWidthUsed(lineWidth) / 2
    }

    /// The one clamp for stroke width, shared by every family so that a stored
    /// width means the same thing whichever gauge style a layer switches to.
    private static func lineWidthUsed(_ lineWidth: Double) -> Double {
        clamp(lineWidth, 0, 0.5, fallback: 0.1)
    }

    private static func degrees(arcLength: Double, radius: Double) -> Double {
        radius > epsilon ? arcLength / radius * 180 / .pi : 0
    }

    /// Short enough to read as a point, long enough that its two ends survive
    /// the path serializer's rounding — a subpath whose ends collapse onto each
    /// other is the one thing SVG and SwiftUI disagree about drawing.
    private static func minimumTickDegrees(radius: Double) -> Double {
        degrees(arcLength: 0.002, radius: radius)
    }

    private static func isFullTurn(_ degrees: Double) -> Bool {
        degrees >= 360 - epsilon
    }

    // MARK: - Geometry

    private static let epsilon = 1e-9

    private struct Point {
        var x: Double
        var y: Double

        init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
        }

        /// Last line of defence: clamping the inputs should make this
        /// unreachable, but one `NaN` in one control point would otherwise
        /// travel into the document as a coordinate no renderer can draw.
        var sanitized: Point { Point(x.isFinite ? x : 0.5, y.isFinite ? y : 0.5) }

        static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y) }
        static func - (a: Point, b: Point) -> Point { Point(a.x - b.x, a.y - b.y) }
        static func * (a: Point, s: Double) -> Point { Point(a.x * s, a.y * s) }
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees.isFinite ? degrees * .pi / 180 : 0
    }

    /// Wrapped, not clamped — see `ring(startAngle:)`.
    private static func wrapped(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        return degrees.truncatingRemainder(dividingBy: 360)
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
}
