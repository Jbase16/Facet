import Foundation
import FacetCore

/// A rectangle in points, top-left origin. (Not CGRect: FacetRender's
/// resolution pipeline runs on Linux CI, where CoreGraphics doesn't exist.)
public struct Rect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func insetBy(_ amount: Double) -> Rect {
        Rect(
            x: x + amount,
            y: y + amount,
            width: max(0, width - amount * 2),
            height: max(0, height - amount * 2)
        )
    }
}

public struct ResolvedShadow: Sendable, Equatable {
    public var color: ColorValue
    public var radius: Double
    public var offsetX: Double
    public var offsetY: Double
    /// Cast inside the layer's silhouette rather than behind it.
    public var inset: Bool = false
}

/// A stroke inside the node's rect, following its corner radius.
public struct ResolvedBorder: Sendable, Equatable {
    public var color: ColorValue
    public var width: Double
    public var inset: Double

    public init(color: ColorValue, width: Double, inset: Double = 0) {
        self.color = color
        self.width = width
        self.inset = inset
    }
}

public struct ResolvedGlow: Sendable, Equatable {
    public var color: ColorValue
    public var radius: Double

    public init(color: ColorValue, radius: Double) {
        self.color = color
        self.radius = radius
    }
}

/// Per-layer colour grading, already clamped. Non-optional with identity
/// defaults so renderers can ask `isIdentity` once instead of unwrapping four
/// optionals on every node.
public struct ResolvedColorAdjust: Sendable, Equatable {
    /// Additive, -1...1.
    public var brightness: Double
    /// Multiplier about mid-grey, 0...4.
    public var contrast: Double
    /// 0...4.
    public var saturation: Double
    /// Degrees, 0..<360.
    public var hueRotation: Double

    public init(brightness: Double = 0, contrast: Double = 1, saturation: Double = 1, hueRotation: Double = 0) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hueRotation = hueRotation
    }

    public static let identity = ResolvedColorAdjust()

    public var isIdentity: Bool { self == .identity }
}

/// A gradient stop with its color already resolved for the color scheme.
public struct ResolvedGradientStop: Sendable, Equatable {
    public var position: Double
    public var color: ColorValue

    public init(position: Double, color: ColorValue) {
        self.position = position
        self.color = color
    }
}

/// A paint with all token/scheme resolution done.
public enum ResolvedFill: Sendable, Equatable {
    case solid(ColorValue)
    case linearGradient(stops: [ResolvedGradientStop], angle: Double)
    case radialGradient(stops: [ResolvedGradientStop])

    /// A representative color, used where a gradient can't render
    /// (accessory monochrome conversion, fallbacks).
    public var primaryColor: ColorValue {
        switch self {
        case .solid(let color): return color
        case .linearGradient(let stops, _), .radialGradient(let stops):
            return stops.first?.color ?? .black
        }
    }
}

public struct ResolvedText: Sendable, Equatable {
    public var text: String
    public var font: FontToken
    public var color: ColorValue
    public var alignment: TextAlignment
    public var maxLines: Int?
    public var letterSpacing: Double
}

public struct ResolvedSymbol: Sendable, Equatable {
    public var systemName: String
    public var color: ColorValue
    public var size: Double
    public var weight: FontWeight
}

public struct ResolvedShape: Sendable, Equatable {
    public var kind: ShapeKind
    public var fill: ResolvedFill
    public var strokeColor: ColorValue?
    public var strokeWidth: Double
    /// Outline for `.path` shapes, already parsed (still in normalized
    /// 0...1 space — renderers scale it into the node's rect). Parsing in
    /// the resolver means one implementation, shared diagnostics, and no
    /// re-parsing on every frame.
    public var path: [PathCommand]?

    public init(
        kind: ShapeKind,
        fill: ResolvedFill,
        strokeColor: ColorValue? = nil,
        strokeWidth: Double = 0,
        path: [PathCommand]? = nil
    ) {
        self.kind = kind
        self.fill = fill
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.path = path
    }
}

public struct ResolvedLine: Sendable, Equatable {
    public var color: ColorValue
    public var thickness: Double
    public var dash: [Double]?
}

public struct ResolvedChart: Sendable, Equatable {
    /// Values normalized to 0...1 (min → 0, max → 1). Empty when the data
    /// path was missing; the renderer draws nothing and a diagnostic is set.
    public var normalized: [Double]
    public var style: ChartStyle
    public var color: ColorValue
    public var lineWidth: Double
}

public struct ResolvedImage: Sendable, Equatable {
    public var assetName: String
    public var contentMode: ImageContent.ContentMode
}

public struct ResolvedGauge: Sendable, Equatable {
    /// Clamped to 0...1.
    public var fraction: Double
    public var style: GaugeStyle
    public var tint: ColorValue
    public var track: ColorValue
    public var lineWidth: Double
    /// Arc geometry in normalized 0...1 coordinates, present only when the
    /// design uses partial sweeps, segments, caps or a start angle. When nil
    /// the renderers draw the original full ring / filled bar, so untouched
    /// documents are unaffected.
    public var arc: ResolvedGaugeArc?

    public init(
        fraction: Double,
        style: GaugeStyle,
        tint: ColorValue,
        track: ColorValue,
        lineWidth: Double,
        arc: ResolvedGaugeArc? = nil
    ) {
        self.fraction = fraction
        self.style = style
        self.tint = tint
        self.track = track
        self.lineWidth = lineWidth
        self.arc = arc
    }
}

/// Track and progress outlines for a gauge, already parsed so neither renderer
/// re-parses per frame.
public struct ResolvedGaugeArc: Sendable, Equatable {
    public var track: [PathCommand]
    public var progress: [PathCommand]
    public var roundCap: Bool
    /// Stroke thickness as a fraction of the layer's smaller side.
    public var lineWidth: Double

    public init(track: [PathCommand], progress: [PathCommand], roundCap: Bool, lineWidth: Double) {
        self.track = track
        self.progress = progress
        self.roundCap = roundCap
        self.lineWidth = lineWidth
    }
}

/// A fully resolved, concrete render tree: expressions evaluated, tokens
/// resolved, layout computed. Rendering this requires no document, no data,
/// and no decisions — which is what keeps the widget extension trivial.
/// A mask flattened into absolute canvas coordinates, ready for either
/// backend. The shape's rect is resolved here rather than in the renderers so
/// SwiftUI and SVG cannot disagree about where the window sits.
public struct ResolvedMask: Sendable, Equatable {
    public struct FadeStop: Sendable, Equatable {
        public var position: Double
        public var alpha: Double

        public init(position: Double, alpha: Double) {
            self.position = position
            self.alpha = alpha
        }
    }

    public struct Fade: Sendable, Equatable {
        public var kind: MaskFade.Kind
        public var angle: Double
        public var stops: [FadeStop]

        public init(kind: MaskFade.Kind, angle: Double, stops: [FadeStop]) {
            self.kind = kind
            self.angle = angle
            self.stops = stops
        }
    }

    public var shape: ShapeKind
    /// Parsed once by the resolver, exactly like `ResolvedShape.path`, so a
    /// malformed outline is diagnosed in one place and neither renderer has
    /// to know the path grammar.
    public var path: [PathCommand]?
    public var cornerRadius: Double
    /// Absolute canvas coordinates, already offset by the layer's own rect.
    public var rect: Rect
    public var fade: Fade?
    public var invert: Bool

    public init(
        shape: ShapeKind,
        path: [PathCommand]? = nil,
        cornerRadius: Double = 0,
        rect: Rect,
        fade: Fade? = nil,
        invert: Bool = false
    ) {
        self.shape = shape
        self.path = path
        self.cornerRadius = cornerRadius
        self.rect = rect
        self.fade = fade
        self.invert = invert
    }
}

public struct RenderNode: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case group(background: ResolvedFill?)
        case text(ResolvedText)
        case symbol(ResolvedSymbol)
        case shape(ResolvedShape)
        case image(ResolvedImage)
        case gauge(ResolvedGauge)
        case line(ResolvedLine)
        case chart(ResolvedChart)
    }

    public var layerID: UUID
    public var name: String
    public var rect: Rect
    public var opacity: Double
    public var rotation: Double
    public var cornerRadius: Double
    public var shadows: [ResolvedShadow]

    /// Outer shadows fall behind the layer; inset ones are drawn over it.
    /// Split here so neither renderer has to filter the list twice.
    public var outerShadows: [ResolvedShadow] { shadows.filter { !$0.inset } }
    public var innerShadows: [ResolvedShadow] { shadows.filter(\.inset) }
    public var blendMode: BlendMode
    /// Gaussian blur radius in points, 0...50.
    public var blur: Double
    public var border: ResolvedBorder?
    /// Uniform scale about `rect`'s centre, 0.1...4.
    public var scale: Double
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    public var colorAdjust: ResolvedColorAdjust
    public var glow: ResolvedGlow?
    /// Clips this layer (and its subtree) to a shape and/or alpha ramp.
    public var mask: ResolvedMask?
    /// Resolved tap destination (URL string — plain String so the resolver
    /// stays Linux-portable; renderers that can act on it parse it).
    public var tapURL: String?
    public var kind: Kind
    public var children: [RenderNode]

    public init(
        layerID: UUID,
        name: String,
        rect: Rect,
        opacity: Double = 1,
        rotation: Double = 0,
        cornerRadius: Double = 0,
        shadows: [ResolvedShadow] = [],
        blendMode: BlendMode = .normal,
        blur: Double = 0,
        border: ResolvedBorder? = nil,
        scale: Double = 1,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        colorAdjust: ResolvedColorAdjust = .identity,
        glow: ResolvedGlow? = nil,
        mask: ResolvedMask? = nil,
        tapURL: String? = nil,
        kind: Kind,
        children: [RenderNode] = []
    ) {
        self.layerID = layerID
        self.name = name
        self.rect = rect
        self.opacity = opacity
        self.rotation = rotation
        self.cornerRadius = cornerRadius
        self.shadows = shadows
        self.blendMode = blendMode
        self.blur = blur
        self.border = border
        self.scale = scale
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.colorAdjust = colorAdjust
        self.glow = glow
        self.mask = mask
        self.tapURL = tapURL
        self.kind = kind
        self.children = children
    }
}

/// A non-fatal problem hit during resolution (bad expression, missing data).
/// The layer degrades gracefully; the editor surfaces these inline.
public struct RenderDiagnostic: Sendable, Equatable {
    public var layerID: UUID
    public var layerName: String
    public var message: String
}

public struct ResolvedWidget: Sendable, Equatable {
    public var root: RenderNode
    public var canvas: Rect
    public var diagnostics: [RenderDiagnostic]
}
