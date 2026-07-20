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
}

/// A fully resolved, concrete render tree: expressions evaluated, tokens
/// resolved, layout computed. Rendering this requires no document, no data,
/// and no decisions — which is what keeps the widget extension trivial.
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
    public var shadow: ResolvedShadow?
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
        shadow: ResolvedShadow? = nil,
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
        self.shadow = shadow
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
