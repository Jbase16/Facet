import Foundation

/// A soft edge for a mask: an alpha ramp, not a colour ramp.
///
/// Deliberately shaped like `GradientFill` — same angle convention, same
/// normalized stop positions — so the two read the same way in the editor and
/// map onto the same primitives in both renderers. The difference is that a
/// stop carries an alpha rather than a colour, because a mask has no colour.
public struct MaskFade: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case linear
        case radial
    }

    /// 0...1 along the ramp axis paired with the alpha at that point.
    public struct Stop: Codable, Hashable, Sendable {
        public var position: Double
        public var alpha: Double

        public init(position: Double, alpha: Double) {
            self.position = position
            self.alpha = alpha
        }
    }

    public var kind: Kind
    /// Direction in degrees: 0 points right, 90 down. Matches `GradientFill`.
    /// Ignored for radial ramps, which run centre-out.
    public var angle: Double
    public var stops: [Stop]

    public init(kind: Kind = .linear, angle: Double = 90, stops: [Stop]) {
        self.kind = kind
        self.angle = angle
        self.stops = stops
    }

    /// Opaque at the start of the axis, transparent at the end — the plain
    /// "fade out" every design tool offers as its first gradient preset.
    public static func fadeOut(angle: Double = 90) -> MaskFade {
        MaskFade(kind: .linear, angle: angle, stops: [
            Stop(position: 0, alpha: 1),
            Stop(position: 1, alpha: 0),
        ])
    }

    /// A vignette: solid in the middle, gone at the rim.
    public static var vignette: MaskFade {
        MaskFade(kind: .radial, angle: 0, stops: [
            Stop(position: 0, alpha: 1),
            Stop(position: 0.65, alpha: 1),
            Stop(position: 1, alpha: 0),
        ])
    }
}

/// What a layer is clipped to.
///
/// A mask is a shape and, optionally, an alpha ramp multiplied into it — which
/// covers the two things people actually reach for ("clip this photo to a
/// blob", "fade the bottom out") and their combination, without inventing a
/// second geometry language. `shape` reuses `ShapeKind`, so every path shape
/// and everything the generators produce works as a mask the day it is added.
///
/// The mask is *not* a layer. Masking by another layer's alpha — text
/// knockouts, image-luminance masks — is a strictly bigger feature: it needs
/// cycle detection and a second render pass, and it is not what this is.
public struct LayerMask: Codable, Hashable, Sendable {
    public var shape: ShapeKind
    /// SVG path syntax in normalized 0...1 coordinates, used when
    /// `shape == .path`.
    public var pathData: String?
    /// Corner rounding for `.rectangle`, in points. Ignored otherwise.
    /// Documents written when this was a lone `cornerRadius` decode into four
    /// equal radii.
    public var corners: CornerRadii
    /// The corner style the clip is cut with. nil follows the layer's own —
    /// which is what you want almost always: a chamfered layer masked to a
    /// rounded rectangle looks like a mistake, not a choice.
    public var cornerStyle: CornerStyle?

    /// The mask's corner radius, for call sites that only ever meant one
    /// number. Reading a mixed set gives the largest; writing sets all four.
    public var cornerRadius: Double {
        get { corners.maximum }
        set { corners = CornerRadii(newValue) }
    }
    /// Where the shape sits inside the layer, in the same normalized
    /// coordinates as `LayerFrame`. nil fills the layer exactly.
    public var frame: LayerFrame?
    /// Multiplied into the shape's coverage. nil is a hard edge.
    public var fade: MaskFade?
    /// Keep what falls outside the shape instead of inside it — a hole rather
    /// than a window.
    public var invert: Bool

    public init(
        shape: ShapeKind = .rectangle,
        pathData: String? = nil,
        cornerRadius: Double = 0,
        corners: CornerRadii? = nil,
        cornerStyle: CornerStyle? = nil,
        frame: LayerFrame? = nil,
        fade: MaskFade? = nil,
        invert: Bool = false
    ) {
        self.shape = shape
        self.pathData = pathData
        self.corners = corners ?? CornerRadii(cornerRadius)
        self.cornerStyle = cornerStyle
        self.frame = frame
        self.fade = fade
        self.invert = invert
    }

    /// A mask with no shape to speak of and no ramp clips nothing, so the
    /// renderers can skip it entirely rather than paying for a no-op layer.
    public var isNoOp: Bool {
        guard !invert else { return false }
        guard fade == nil, frame == nil else { return false }
        switch shape {
        // Square corners clip nothing whatever style they are cut in, so the
        // style alone never makes a full-bleed rectangle worth compositing.
        case .rectangle: return corners.isZero
        case .path: return pathData?.isEmpty ?? true
        case .circle, .capsule: return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case shape, pathData, cornerRadius, corners, cornerStyle, frame, fade, invert
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shape = try container.decodeIfPresent(ShapeKind.self, forKey: .shape) ?? .rectangle
        pathData = try container.decodeIfPresent(String.self, forKey: .pathData)
        // Same rule as `LayerStyle`: the per-corner form wins, the legacy
        // scalar means four equal radii, and absent means square.
        if let radii = try container.decodeIfPresent(CornerRadii.self, forKey: .corners) {
            corners = radii
        } else {
            corners = CornerRadii(try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0)
        }
        cornerStyle = try container.decodeIfPresent(CornerStyle.self, forKey: .cornerStyle)
        frame = try container.decodeIfPresent(LayerFrame.self, forKey: .frame)
        fade = try container.decodeIfPresent(MaskFade.self, forKey: .fade)
        invert = try container.decodeIfPresent(Bool.self, forKey: .invert) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(shape, forKey: .shape)
        try container.encodeIfPresent(pathData, forKey: .pathData)
        if let uniform = corners.uniform {
            if uniform != 0 { try container.encode(uniform, forKey: .cornerRadius) }
        } else {
            try container.encode(corners, forKey: .corners)
        }
        try container.encodeIfPresent(cornerStyle, forKey: .cornerStyle)
        try container.encodeIfPresent(frame, forKey: .frame)
        try container.encodeIfPresent(fade, forKey: .fade)
        if invert { try container.encode(invert, forKey: .invert) }
    }
}
