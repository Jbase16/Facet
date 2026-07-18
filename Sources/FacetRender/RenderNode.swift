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

public struct ResolvedText: Sendable, Equatable {
    public var text: String
    public var font: FontToken
    public var color: ColorValue
    public var alignment: TextAlignment
    public var maxLines: Int?
}

public struct ResolvedSymbol: Sendable, Equatable {
    public var systemName: String
    public var color: ColorValue
    public var size: Double
    public var weight: FontWeight
}

public struct ResolvedShape: Sendable, Equatable {
    public var kind: ShapeKind
    public var fill: ColorValue
    public var strokeColor: ColorValue?
    public var strokeWidth: Double
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
        case group(background: ColorValue?)
        case text(ResolvedText)
        case symbol(ResolvedSymbol)
        case shape(ResolvedShape)
        case image(ResolvedImage)
        case gauge(ResolvedGauge)
    }

    public var layerID: UUID
    public var name: String
    public var rect: Rect
    public var opacity: Double
    public var rotation: Double
    public var cornerRadius: Double
    public var shadow: ResolvedShadow?
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
