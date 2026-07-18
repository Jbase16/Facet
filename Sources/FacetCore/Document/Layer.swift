import Foundation

/// A layer's placement within its parent, in normalized coordinates (0...1).
/// `x`/`y` locate the layer's center; `width`/`height` are fractions of the
/// parent's size. Normalized coordinates are what let one design adapt across
/// widget sizes.
public struct LayerFrame: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double = 0.5, y: Double = 0.5, width: Double = 1.0, height: Double = 1.0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = LayerFrame()
}

public struct ShadowStyle: Codable, Hashable, Sendable {
    public var color: ColorRef
    public var radius: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(color: ColorRef, radius: Double, offsetX: Double = 0, offsetY: Double = 0) {
        self.color = color
        self.radius = radius
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

/// Visual attributes shared by every layer kind.
public struct LayerStyle: Codable, Hashable, Sendable {
    public var opacity: Double
    /// Rotation in degrees, clockwise.
    public var rotation: Double
    public var cornerRadius: Double
    public var shadow: ShadowStyle?

    public init(opacity: Double = 1.0, rotation: Double = 0, cornerRadius: Double = 0, shadow: ShadowStyle? = nil) {
        self.opacity = opacity
        self.rotation = rotation
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }

    public static let plain = LayerStyle()
}

public enum TextAlignment: String, Codable, Sendable {
    case leading, center, trailing
}

/// Text content. `text` is a template string: `{...}` spans are expressions
/// evaluated against the data snapshot (e.g. `"{battery.level * 100}%"`).
/// Use `{{` and `}}` for literal braces.
public struct TextContent: Codable, Hashable, Sendable {
    public var text: String
    public var font: FontRef
    public var color: ColorRef
    public var alignment: TextAlignment
    public var maxLines: Int?

    public init(
        text: String,
        font: FontRef,
        color: ColorRef,
        alignment: TextAlignment = .center,
        maxLines: Int? = nil
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.alignment = alignment
        self.maxLines = maxLines
    }
}

/// An SF Symbol.
public struct SymbolContent: Codable, Hashable, Sendable {
    public var systemName: String
    public var color: ColorRef
    /// Point size of the symbol.
    public var size: Double
    public var weight: FontWeight

    public init(systemName: String, color: ColorRef, size: Double, weight: FontWeight = .regular) {
        self.systemName = systemName
        self.color = color
        self.size = size
        self.weight = weight
    }
}

public enum ShapeKind: String, Codable, Sendable {
    case rectangle
    case circle
    case capsule
}

public struct ShapeContent: Codable, Hashable, Sendable {
    public var kind: ShapeKind
    public var fill: ColorRef
    public var strokeColor: ColorRef?
    public var strokeWidth: Double

    public init(kind: ShapeKind, fill: ColorRef, strokeColor: ColorRef? = nil, strokeWidth: Double = 0) {
        self.kind = kind
        self.fill = fill
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }
}

/// An image from the document's asset bundle (referenced by asset name).
public struct ImageContent: Codable, Hashable, Sendable {
    public enum ContentMode: String, Codable, Sendable {
        case fit, fill
    }

    public var assetName: String
    public var contentMode: ContentMode

    public init(assetName: String, contentMode: ContentMode = .fill) {
        self.assetName = assetName
        self.contentMode = contentMode
    }
}

public enum GaugeStyle: String, Codable, Sendable {
    case ring
    case bar
}

/// A progress gauge. `value` is an expression that must evaluate to 0...1.
public struct GaugeContent: Codable, Hashable, Sendable {
    public var value: String
    public var style: GaugeStyle
    public var tint: ColorRef
    public var track: ColorRef
    public var lineWidth: Double

    public init(value: String, style: GaugeStyle = .ring, tint: ColorRef, track: ColorRef, lineWidth: Double = 6) {
        self.value = value
        self.style = style
        self.tint = tint
        self.track = track
        self.lineWidth = lineWidth
    }
}

public enum ContainerLayout: String, Codable, Sendable {
    /// Children are placed by their own normalized frames.
    case absolute
    /// Children are stacked horizontally / vertically with `spacing`,
    /// centered on the cross axis. Child frames supply relative sizes.
    case horizontal
    case vertical
    /// Children are stacked on top of each other, all centered.
    case overlay
}

public struct ContainerContent: Codable, Sendable, Hashable {
    public var layout: ContainerLayout
    /// Spacing between stacked children, in points.
    public var spacing: Double
    /// Inner padding, in points.
    public var padding: Double
    public var background: ColorRef?
    public var children: [Layer]

    public init(
        layout: ContainerLayout = .absolute,
        spacing: Double = 0,
        padding: Double = 0,
        background: ColorRef? = nil,
        children: [Layer] = []
    ) {
        self.layout = layout
        self.spacing = spacing
        self.padding = padding
        self.background = background
        self.children = children
    }
}

/// What a layer draws. Serialized with a `type` discriminator so the on-disk
/// format stays readable and stable.
public enum LayerContent: Sendable, Hashable {
    case text(TextContent)
    case symbol(SymbolContent)
    case shape(ShapeContent)
    case image(ImageContent)
    case gauge(GaugeContent)
    case container(ContainerContent)
}

public struct Layer: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var frame: LayerFrame
    public var style: LayerStyle
    public var isHidden: Bool
    public var content: LayerContent

    public init(
        id: UUID = UUID(),
        name: String,
        frame: LayerFrame = .full,
        style: LayerStyle = .plain,
        isHidden: Bool = false,
        content: LayerContent
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.style = style
        self.isHidden = isHidden
        self.content = content
    }

    /// Depth-first search across the layer tree.
    public func firstLayer(withID id: UUID) -> Layer? {
        if self.id == id { return self }
        if case .container(let container) = content {
            for child in container.children {
                if let found = child.firstLayer(withID: id) { return found }
            }
        }
        return nil
    }

    /// In-place mutation of the first layer matching `id`, anywhere in the
    /// tree. Returns false if no layer matched. This is the editor's write
    /// path: value semantics keep undo/redo as simple as keeping old copies.
    @discardableResult
    public mutating func updateFirstLayer(withID id: UUID, _ mutate: (inout Layer) -> Void) -> Bool {
        if self.id == id {
            mutate(&self)
            return true
        }
        guard case .container(var container) = content else { return false }
        for index in container.children.indices {
            if container.children[index].updateFirstLayer(withID: id, mutate) {
                content = .container(container)
                return true
            }
        }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, frame, style, isHidden, type
        case text, symbol, shape, image, gauge, container
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        frame = try container.decodeIfPresent(LayerFrame.self, forKey: .frame) ?? .full
        style = try container.decodeIfPresent(LayerStyle.self, forKey: .style) ?? .plain
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text": content = .text(try container.decode(TextContent.self, forKey: .text))
        case "symbol": content = .symbol(try container.decode(SymbolContent.self, forKey: .symbol))
        case "shape": content = .shape(try container.decode(ShapeContent.self, forKey: .shape))
        case "image": content = .image(try container.decode(ImageContent.self, forKey: .image))
        case "gauge": content = .gauge(try container.decode(GaugeContent.self, forKey: .gauge))
        case "container": content = .container(try container.decode(ContainerContent.self, forKey: .container))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown layer type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(frame, forKey: .frame)
        try container.encode(style, forKey: .style)
        if isHidden { try container.encode(isHidden, forKey: .isHidden) }
        switch content {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .symbol(let value):
            try container.encode("symbol", forKey: .type)
            try container.encode(value, forKey: .symbol)
        case .shape(let value):
            try container.encode("shape", forKey: .type)
            try container.encode(value, forKey: .shape)
        case .image(let value):
            try container.encode("image", forKey: .type)
            try container.encode(value, forKey: .image)
        case .gauge(let value):
            try container.encode("gauge", forKey: .type)
            try container.encode(value, forKey: .gauge)
        case .container(let value):
            try container.encode("container", forKey: .type)
            try container.encode(value, forKey: .container)
        }
    }
}
