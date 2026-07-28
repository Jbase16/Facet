import Foundation

/// How a corner is taken out of the rectangle it belongs to.
///
/// Every case is described by the same two tangent points and the corner
/// vertex between them, which is why they all fall out of one generator: pick
/// where the corner starts and ends, then choose what to draw across the gap.
public enum CornerStyle: String, Codable, Sendable, Hashable, CaseIterable {
    /// A convex quarter-circle — what a rounded rectangle has always been, and
    /// what every document written before corner profiles existed means.
    case rounded
    /// A straight bevel across the two tangent points.
    case chamfered
    /// A concave quarter-circle centred on the corner itself: the bite a
    /// die-cut sticker leaves. Meets both edges tangentially, so the join is
    /// smooth and the cut reads as a notch rather than a nick.
    case inverted
    /// A concave semicircular scoop over the tangent chord. Deeper than
    /// `inverted` and it meets the edges at 45° instead of tangentially —
    /// those cusps are what make a scalloped edge read as scalloped.
    case scalloped

    public var displayName: String {
        switch self {
        case .rounded: return "Rounded"
        case .chamfered: return "Chamfered"
        case .inverted: return "Inverted"
        case .scalloped: return "Scalloped"
        }
    }

    /// True when the corner eats into the rectangle instead of shaving it.
    public var isConcave: Bool {
        self == .inverted || self == .scalloped
    }

    /// How far along an edge a corner reaches, as a multiple of its radius.
    /// Only the scallop overshoots (its semicircle bulges ~20.7% past the
    /// tangent point); the fitting pass multiplies by this so two scoops
    /// sharing an edge can never eat into each other.
    var reach: Double {
        self == .scalloped ? 1.25 : 1
    }
}

/// Four corner radii in points, named the way the layout world names them.
///
/// Kept separate from `CornerProfile` because `LayerMask` wants the radii
/// without a style of its own — a masked layer's clip follows the layer's
/// corner style unless it is told otherwise.
public struct CornerRadii: Codable, Hashable, Sendable {
    public var topLeading: Double
    public var topTrailing: Double
    public var bottomLeading: Double
    public var bottomTrailing: Double

    public init(
        topLeading: Double = 0,
        topTrailing: Double = 0,
        bottomLeading: Double = 0,
        bottomTrailing: Double = 0
    ) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }

    public init(_ uniform: Double) {
        self.init(
            topLeading: uniform,
            topTrailing: uniform,
            bottomLeading: uniform,
            bottomTrailing: uniform
        )
    }

    public static let none = CornerRadii(0)

    /// The shared radius when all four agree, else nil. This is the test both
    /// renderers use to decide whether their native rounded-rect primitive can
    /// draw the outline.
    public var uniform: Double? {
        topLeading == topTrailing && topLeading == bottomLeading && topLeading == bottomTrailing
            ? topLeading
            : nil
    }

    public var maximum: Double {
        max(max(topLeading, topTrailing), max(bottomLeading, bottomTrailing))
    }

    public var isZero: Bool { uniform == 0 }

    public func map(_ transform: (Double) -> Double) -> CornerRadii {
        CornerRadii(
            topLeading: transform(topLeading),
            topTrailing: transform(topTrailing),
            bottomLeading: transform(bottomLeading),
            bottomTrailing: transform(bottomTrailing)
        )
    }

    /// Negative and non-finite radii collapse to 0 rather than poisoning the
    /// generated path: a corrupt document degrades one corner, not the widget.
    public var sanitized: CornerRadii {
        map { $0.isFinite ? max(0, $0) : 0 }
    }

    /// Pulled in by `amount` points, floored at 0 — an inward offset of a
    /// convex corner shrinks its radius by exactly the offset.
    public func inset(by amount: Double) -> CornerRadii {
        map { max(0, $0 - amount) }
    }

    // A `radius` shorthand for the overwhelmingly common uniform case, with
    // per-corner keys overriding it. Zero corners are omitted entirely, so an
    // unrounded profile writes nothing at all.
    private enum CodingKeys: String, CodingKey {
        case radius, topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = try container.decodeIfPresent(Double.self, forKey: .radius) ?? 0
        topLeading = try container.decodeIfPresent(Double.self, forKey: .topLeading) ?? base
        topTrailing = try container.decodeIfPresent(Double.self, forKey: .topTrailing) ?? base
        bottomLeading = try container.decodeIfPresent(Double.self, forKey: .bottomLeading) ?? base
        bottomTrailing = try container.decodeIfPresent(Double.self, forKey: .bottomTrailing) ?? base
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let uniform {
            if uniform != 0 { try container.encode(uniform, forKey: .radius) }
            return
        }
        if topLeading != 0 { try container.encode(topLeading, forKey: .topLeading) }
        if topTrailing != 0 { try container.encode(topTrailing, forKey: .topTrailing) }
        if bottomLeading != 0 { try container.encode(bottomLeading, forKey: .bottomLeading) }
        if bottomTrailing != 0 { try container.encode(bottomTrailing, forKey: .bottomTrailing) }
    }
}

/// A style plus four radii: everything needed to draw a layer's outline.
///
/// This is the single source of truth for that outline. Both renderers used to
/// rebuild a rounded rectangle at every site that needed one — nine in the
/// SwiftUI backend, five in SVG — and the two bugs that came out of that
/// (`Ellipse` where SVG inscribed a circle, a private copy of the home-grid
/// constants) are the reason it now lives in exactly one place.
///
/// Radii are in *points*, like `LayerStyle.cornerRadius` always was; the
/// outline comes back in normalized 0...1 coordinates, like every other path
/// in this directory, which is why `outline` needs the layer's size: a corner
/// is circular in points and therefore elliptical in a non-square layer's
/// normalized space.
public struct CornerProfile: Codable, Hashable, Sendable {
    public var style: CornerStyle
    public var radii: CornerRadii

    public init(style: CornerStyle = .rounded, radii: CornerRadii = .none) {
        self.style = style
        self.radii = radii
    }

    public init(style: CornerStyle = .rounded, radius: Double) {
        self.init(style: style, radii: CornerRadii(radius))
    }

    /// Square corners: what `LayerStyle.plain` has always meant.
    public static let square = CornerProfile()

    /// The radius a plain `RoundedRectangle` / `rx=` can express, or nil when
    /// the outline has to be generated.
    ///
    /// Zero counts whatever the style says, because a corner with no radius is
    /// a right angle in every style — which keeps a document that never
    /// touched corners on exactly the code path it always used.
    public var simpleRadius: Double? {
        guard let uniform = radii.sanitized.uniform else { return nil }
        return uniform == 0 || style == .rounded ? uniform : nil
    }

    /// True when this profile is the historical `cornerRadius: Double` and
    /// nothing more, so `LayerStyle`/`LayerMask` can keep writing the legacy
    /// key and old documents round-trip byte-identical.
    public var isLegacyForm: Bool {
        style == .rounded && radii.uniform != nil
    }

    /// Pulled in by `amount` points — what a border inset or a `strokeBorder`
    /// half-width does to the outline it traces.
    ///
    /// Convex corners shrink with the offset. Concave ones deliberately do
    /// not: offsetting the boundary of a notch *into* the material grows its
    /// arc rather than shrinking it, and the exact offset curve is no longer a
    /// corner profile at all, so holding the radius is both simpler and closer
    /// than shrinking it would be.
    public func inset(by amount: Double) -> CornerProfile {
        guard !style.isConcave else { return self }
        return CornerProfile(style: style, radii: radii.inset(by: amount))
    }

    /// The outline as normalized 0...1 path commands, ready for
    /// `NormalizedPath` in SwiftUI and `pathDescription` in SVG.
    ///
    /// `width`/`height` are the layer's size in points. Radii are fitted
    /// CSS-style: any edge whose two corners would overrun it scales every
    /// radius down by one shared factor, so no combination of inputs can make
    /// the outline fold through itself.
    public func outline(width: Double, height: Double) -> [PathCommand] {
        let w = width.isFinite && width > 0 ? width : 1
        let h = height.isFinite && height > 0 ? height : 1
        let fitted = fittedRadii(width: w, height: h)

        // Two fractions per corner: a corner is a circle in points, so in the
        // layer's normalized space it is an ellipse with these half-axes.
        let tlx = fitted.topLeading / w, tly = fitted.topLeading / h
        let trx = fitted.topTrailing / w, tryy = fitted.topTrailing / h
        let brx = fitted.bottomTrailing / w, bry = fitted.bottomTrailing / h
        let blx = fitted.bottomLeading / w, bly = fitted.bottomLeading / h

        var builder = OutlineBuilder()
        builder.move(to: PathPoint(x: tlx, y: 0))
        builder.line(to: PathPoint(x: 1 - trx, y: 0))
        corner(&builder,
               entry: PathPoint(x: 1 - trx, y: 0),
               exit: PathPoint(x: 1, y: tryy),
               vertex: PathPoint(x: 1, y: 0))
        builder.line(to: PathPoint(x: 1, y: 1 - bry))
        corner(&builder,
               entry: PathPoint(x: 1, y: 1 - bry),
               exit: PathPoint(x: 1 - brx, y: 1),
               vertex: PathPoint(x: 1, y: 1))
        builder.line(to: PathPoint(x: blx, y: 1))
        corner(&builder,
               entry: PathPoint(x: blx, y: 1),
               exit: PathPoint(x: 0, y: 1 - bly),
               vertex: PathPoint(x: 0, y: 1))
        builder.line(to: PathPoint(x: 0, y: tly))
        corner(&builder,
               entry: PathPoint(x: 0, y: tly),
               exit: PathPoint(x: tlx, y: 0),
               vertex: PathPoint(x: 0, y: 0))
        builder.close()
        return builder.commands
    }

    /// SVG path syntax for the same outline, for anywhere a string is the
    /// natural currency (pasting an outline into `ShapeContent.pathData`).
    public func pathData(width: Double, height: Double) -> String {
        PathData.string(from: outline(width: width, height: height))
    }

    // MARK: - Fitting

    /// CSS's rounded-rectangle overlap rule: find the tightest edge, and if
    /// any edge is overrun scale *every* radius by that one factor, so the
    /// corners stay in proportion instead of one being singled out.
    private func fittedRadii(width: Double, height: Double) -> CornerRadii {
        let radii = self.radii.sanitized
        let reach = style.reach
        func factor(_ available: Double, _ a: Double, _ b: Double) -> Double {
            let needed = (a + b) * reach
            return needed > available ? available / needed : 1
        }
        let scale = min(
            min(factor(width, radii.topLeading, radii.topTrailing),
                factor(height, radii.topTrailing, radii.bottomTrailing)),
            min(factor(width, radii.bottomLeading, radii.bottomTrailing),
                factor(height, radii.topLeading, radii.bottomLeading))
        )
        return scale < 1 ? radii.map { $0 * scale } : radii
    }

    // MARK: - Corners

    /// One corner, walked from `entry` on the incoming edge to `exit` on the
    /// outgoing one, with `vertex` the right angle they would have met at.
    /// Every style is a different answer to "what goes between those points".
    private func corner(
        _ builder: inout OutlineBuilder,
        entry: PathPoint,
        exit: PathPoint,
        vertex: PathPoint
    ) {
        guard !entry.isNearly(exit) else { return }
        switch style {
        case .rounded:
            // Handles pull toward the vertex: the classic quarter-arc Bézier,
            // identical to what `ShapeGenerator.roundedRect` emits.
            builder.cubic(
                entry + (vertex - entry) * Self.kappa,
                exit + (vertex - exit) * Self.kappa,
                to: exit
            )
        case .chamfered:
            builder.line(to: exit)
        case .inverted:
            // The same quarter-arc turned inside out: centred on the vertex,
            // so the handles pull along the *other* edge's direction.
            builder.cubic(
                entry + (exit - vertex) * Self.kappa,
                exit + (entry - vertex) * Self.kappa,
                to: exit
            )
        case .scalloped:
            // A half-turn about the chord's midpoint, split at its apex so the
            // deepest point of the scoop is an anchor rather than something a
            // control point overshoots. `half` and `normal` are perpendicular
            // and equal length once the layer's own aspect is applied, which
            // is what makes this a true semicircle on screen.
            let mid = PathPoint(x: (entry.x + exit.x) / 2, y: (entry.y + exit.y) / 2)
            let half = entry - mid
            let normal = mid - vertex
            let apex = mid + normal
            builder.cubic(entry + normal * Self.kappa, apex + half * Self.kappa, to: apex)
            builder.cubic(apex - half * Self.kappa, exit + normal * Self.kappa, to: exit)
        }
    }

    /// Bézier approximation constant for a quarter turn: 4/3·(√2 − 1).
    private static let kappa = 0.5522847498307933

    // MARK: - Codable

    // `style` rides in the same object as the radii — `{"style":"chamfered",
    // "radius":12}` — and is omitted when it is the historical `.rounded`, so
    // a profile that is only a radius encodes as only a radius.
    private enum CodingKeys: String, CodingKey {
        case style
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(CornerStyle.self, forKey: .style) ?? .rounded
        radii = try CornerRadii(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try radii.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        if style != .rounded { try container.encode(style, forKey: .style) }
    }
}

// MARK: - Path assembly

/// Minimal builder over `PathCommand`, mirroring the one in `ShapeGenerators`:
/// it drops zero-length lines and the redundant closing line, which is what
/// lets a square profile come out as literally four points.
private struct OutlineBuilder {
    private(set) var commands: [PathCommand] = []
    private var current = PathPoint(x: 0, y: 0)
    private var start = PathPoint(x: 0, y: 0)

    mutating func move(to point: PathPoint) {
        commands.append(.move(x: point.x, y: point.y))
        current = point
        start = point
    }

    mutating func line(to point: PathPoint) {
        guard !point.isNearly(current) else { return }
        commands.append(.line(x: point.x, y: point.y))
        current = point
    }

    mutating func cubic(_ control1: PathPoint, _ control2: PathPoint, to point: PathPoint) {
        commands.append(.cubic(
            c1x: control1.x, c1y: control1.y,
            c2x: control2.x, c2y: control2.y,
            x: point.x, y: point.y
        ))
        current = point
    }

    mutating func close() {
        if case .line(let x, let y)? = commands.last,
           PathPoint(x: x, y: y).isNearly(start) {
            commands.removeLast()
        }
        commands.append(.close)
        current = start
    }
}

private extension PathPoint {
    static func + (a: PathPoint, b: PathPoint) -> PathPoint {
        PathPoint(x: a.x + b.x, y: a.y + b.y)
    }

    static func - (a: PathPoint, b: PathPoint) -> PathPoint {
        PathPoint(x: a.x - b.x, y: a.y - b.y)
    }

    static func * (a: PathPoint, scale: Double) -> PathPoint {
        PathPoint(x: a.x * scale, y: a.y * scale)
    }

    func isNearly(_ other: PathPoint) -> Bool {
        abs(x - other.x) < 1e-9 && abs(y - other.y) < 1e-9
    }
}
