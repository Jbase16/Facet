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
    /// Cast *inside* the layer's silhouette rather than behind it.
    ///
    /// The direction of the illusion turns entirely on this flag: the same
    /// pair of shadows reads as raised when outside and pressed-in when
    /// inside. Everything in the neumorphic family — emboss, deboss,
    /// letterpress, inset — is that one inversion.
    public var inset: Bool

    public init(
        color: ColorRef,
        radius: Double,
        offsetX: Double = 0,
        offsetY: Double = 0,
        inset: Bool = false
    ) {
        self.color = color
        self.radius = radius
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.inset = inset
    }

    private enum CodingKeys: String, CodingKey {
        case color, radius, offsetX, offsetY, inset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decode(ColorRef.self, forKey: .color)
        radius = try container.decode(Double.self, forKey: .radius)
        offsetX = try container.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try container.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
        inset = try container.decodeIfPresent(Bool.self, forKey: .inset) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(radius, forKey: .radius)
        try container.encode(offsetX, forKey: .offsetX)
        try container.encode(offsetY, forKey: .offsetY)
        if inset { try container.encode(inset, forKey: .inset) }
    }
}

/// Ready-made shadow pairs for the neumorphic family.
///
/// The effect depends on a light source: one shadow on the lit side, one
/// opposite. Getting the pairing right by hand is fiddly enough that people
/// conclude the feature is broken, so the presets exist to hand you a correct
/// starting point. They write ordinary shadow values — nothing about them is
/// special-cased in the renderers.
///
/// All of them assume the layer is the *same colour as what's behind it*.
/// That is the load-bearing rule: a differently-coloured layer reads as a card
/// sitting on a surface, not as the surface itself deformed.
public enum ShadowPreset: String, CaseIterable, Sendable {
    /// Extruded — pushed up out of the surface.
    case raised
    /// Debossed — a coin pressed into clay and lifted away.
    case pressed
    /// Both at once: a rim of light above, shade below, on a shallow relief.
    case embossed

    public var displayName: String {
        switch self {
        case .raised: return "Raised"
        case .pressed: return "Pressed"
        case .embossed: return "Embossed"
        }
    }

    /// `light`/`dark` are usually a tint and a shade of the surface colour
    /// rather than white and black — pure black reads as dirt on the material.
    public func shadows(
        light: ColorRef = .literal(ColorValue(hex: "#FFFFFFB3")!),
        dark: ColorRef = .literal(ColorValue(hex: "#00000059")!),
        distance: Double = 6,
        softness: Double = 10
    ) -> [ShadowStyle] {
        switch self {
        case .raised:
            return [
                ShadowStyle(color: light, radius: softness, offsetX: -distance, offsetY: -distance),
                ShadowStyle(color: dark, radius: softness, offsetX: distance, offsetY: distance),
            ]
        case .pressed:
            // The same pair, inside and with the light source swapped: the
            // near wall of a dent is the one facing away from the light.
            return [
                ShadowStyle(color: dark, radius: softness, offsetX: distance, offsetY: distance, inset: true),
                ShadowStyle(color: light, radius: softness, offsetX: -distance, offsetY: -distance, inset: true),
            ]
        case .embossed:
            // Shallower and tighter than `raised`: a relief in the surface
            // rather than an object standing on it.
            return [
                ShadowStyle(color: light, radius: softness / 2, offsetX: -distance / 2, offsetY: -distance / 2, inset: true),
                ShadowStyle(color: dark, radius: softness / 2, offsetX: distance / 2, offsetY: distance / 2, inset: true),
                ShadowStyle(color: dark, radius: softness, offsetX: distance / 2, offsetY: distance / 2),
            ]
        }
    }
}

/// How a layer composites into what is already drawn beneath it. Blending is
/// the difference between a design that looks composed and one that looks
/// pasted — a `multiply` shadow or a `screen` highlight picks up the colours
/// underneath instead of covering them.
public enum BlendMode: String, Codable, Sendable {
    case normal
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case softLight
    case hardLight
    case difference
    case exclusion
    case hue
    case saturation
    case color
    case luminosity
    case plusLighter
}

/// A stroke drawn inside a layer's bounds, following its corner radius.
/// Deliberately part of `LayerStyle` and not `ShapeContent`: text, symbols,
/// images and gauges all want outlines too, and only shapes could have them.
public struct BorderStyle: Codable, Hashable, Sendable {
    public var color: ColorRef
    /// Stroke thickness in points, drawn inward from the edge.
    public var width: Double
    /// Points to pull the stroke in from the layer's bounds.
    public var inset: Double

    public init(color: ColorRef, width: Double, inset: Double = 0) {
        self.color = color
        self.width = width
        self.inset = inset
    }

    private enum CodingKeys: String, CodingKey {
        case color, width, inset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decode(ColorRef.self, forKey: .color)
        width = try container.decode(Double.self, forKey: .width)
        inset = try container.decodeIfPresent(Double.self, forKey: .inset) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(width, forKey: .width)
        if inset != 0 { try container.encode(inset, forKey: .inset) }
    }
}

/// A coloured halo: mechanically a shadow with no offset, but kept separate
/// because "neon rim" is a different design decision from "cast shadow" and a
/// layer routinely wants both at once.
public struct GlowStyle: Codable, Hashable, Sendable {
    public var color: ColorRef
    /// Spread in points.
    public var radius: Double

    public init(color: ColorRef, radius: Double) {
        self.color = color
        self.radius = radius
    }
}

/// Visual attributes shared by every layer kind.
///
/// Everything past `shadow` is optional: absent means "no effect", and absent
/// stays absent through a round trip, so adding effects doesn't grow every
/// existing document by a screenful of defaults. Ranges are advisory here and
/// enforced by the resolver — a document is data, not a validated input.
public struct LayerStyle: Codable, Hashable, Sendable {
    public var opacity: Double
    /// Rotation in degrees, clockwise.
    public var rotation: Double
    public var cornerRadius: Double
    /// A list, because the neumorphic family needs two at once — one on the
    /// lit side, one opposite. Documents written when this was a single
    /// optional decode into a one-element list.
    public var shadows: [ShadowStyle]

    /// The first shadow, for the many call sites that only ever meant one.
    public var shadow: ShadowStyle? {
        get { shadows.first }
        set { shadows = newValue.map { [$0] } ?? [] }
    }

    public var blendMode: BlendMode?
    /// Gaussian blur radius in points, 0...50.
    public var blur: Double?
    public var border: BorderStyle?
    /// Uniform scale about the layer's centre, 0.1...4. Distinct from resizing
    /// the frame: layout is unchanged, which is what makes overshoot and pop
    /// effects possible without disturbing neighbours.
    public var scale: Double?
    public var flipHorizontal: Bool?
    public var flipVertical: Bool?
    /// Additive brightness, -1...1.
    public var brightness: Double?
    /// Contrast multiplier about mid-grey, 0...4.
    public var contrast: Double?
    /// 0 is greyscale, 1 unchanged, up to 4.
    public var saturation: Double?
    /// Hue shift in degrees, wrapped. Colour adjustment is what lets one
    /// design be re-themed without editing every layer's fill.
    public var hueRotation: Double?
    public var glow: GlowStyle?
    /// Clips the layer to a shape and/or fades it out. nil draws the whole
    /// layer, which is what every document written before masks existed does.
    public var mask: LayerMask?

    public init(
        opacity: Double = 1.0,
        rotation: Double = 0,
        cornerRadius: Double = 0,
        shadows: [ShadowStyle] = [],
        blendMode: BlendMode? = nil,
        blur: Double? = nil,
        border: BorderStyle? = nil,
        scale: Double? = nil,
        flipHorizontal: Bool? = nil,
        flipVertical: Bool? = nil,
        brightness: Double? = nil,
        contrast: Double? = nil,
        saturation: Double? = nil,
        hueRotation: Double? = nil,
        glow: GlowStyle? = nil,
        mask: LayerMask? = nil
    ) {
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
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hueRotation = hueRotation
        self.glow = glow
        self.mask = mask
    }

    public static let plain = LayerStyle()

    private enum CodingKeys: String, CodingKey {
        case opacity, rotation, cornerRadius, shadow, shadows
        case blendMode, blur, border, scale, flipHorizontal, flipVertical
        case brightness, contrast, saturation, hueRotation, glow, mask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
        // `shadows` is the current form; `shadow` is what documents written
        // before the neumorphic pass carry. Reading both means no migration.
        if let list = try container.decodeIfPresent([ShadowStyle].self, forKey: .shadows) {
            shadows = list
        } else if let single = try container.decodeIfPresent(ShadowStyle.self, forKey: .shadow) {
            shadows = [single]
        } else {
            shadows = []
        }
        blendMode = try container.decodeIfPresent(BlendMode.self, forKey: .blendMode)
        blur = try container.decodeIfPresent(Double.self, forKey: .blur)
        border = try container.decodeIfPresent(BorderStyle.self, forKey: .border)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale)
        flipHorizontal = try container.decodeIfPresent(Bool.self, forKey: .flipHorizontal)
        flipVertical = try container.decodeIfPresent(Bool.self, forKey: .flipVertical)
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness)
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast)
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation)
        hueRotation = try container.decodeIfPresent(Double.self, forKey: .hueRotation)
        glow = try container.decodeIfPresent(GlowStyle.self, forKey: .glow)
        mask = try container.decodeIfPresent(LayerMask.self, forKey: .mask)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        // A lone outer shadow keeps writing the legacy singular key, so the
        // overwhelmingly common case stays byte-identical through a round trip
        // and older builds can still read it.
        if shadows.count == 1, !shadows[0].inset {
            try container.encode(shadows[0], forKey: .shadow)
        } else if !shadows.isEmpty {
            try container.encode(shadows, forKey: .shadows)
        }
        try container.encodeIfPresent(blendMode, forKey: .blendMode)
        try container.encodeIfPresent(blur, forKey: .blur)
        try container.encodeIfPresent(border, forKey: .border)
        try container.encodeIfPresent(scale, forKey: .scale)
        try container.encodeIfPresent(flipHorizontal, forKey: .flipHorizontal)
        try container.encodeIfPresent(flipVertical, forKey: .flipVertical)
        try container.encodeIfPresent(brightness, forKey: .brightness)
        try container.encodeIfPresent(contrast, forKey: .contrast)
        try container.encodeIfPresent(saturation, forKey: .saturation)
        try container.encodeIfPresent(hueRotation, forKey: .hueRotation)
        try container.encodeIfPresent(glow, forKey: .glow)
        try container.encodeIfPresent(mask, forKey: .mask)
    }
}

public enum TextAlignment: String, Codable, Sendable {
    case leading, center, trailing
}

public enum TextCase: String, Codable, Sendable {
    case uppercase, lowercase
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
    /// Tracking in points. Optional so v1 documents decode unchanged.
    public var letterSpacing: Double?
    public var textCase: TextCase?

    public init(
        text: String,
        font: FontRef,
        color: ColorRef,
        alignment: TextAlignment = .center,
        maxLines: Int? = nil,
        letterSpacing: Double? = nil,
        textCase: TextCase? = nil
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.alignment = alignment
        self.maxLines = maxLines
        self.letterSpacing = letterSpacing
        self.textCase = textCase
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
    /// An arbitrary outline from `ShapeContent.pathData` — organic frames,
    /// imported silhouettes, generated blobs.
    case path
}

public struct ShapeContent: Codable, Hashable, Sendable {
    public var kind: ShapeKind
    public var fill: Fill
    public var strokeColor: ColorRef?
    public var strokeWidth: Double
    /// SVG path syntax in normalized 0...1 coordinates, used when
    /// `kind == .path`. Optional so v1/v2 documents decode unchanged.
    public var pathData: String?
    public init(
        kind: ShapeKind,
        fill: Fill,
        strokeColor: ColorRef? = nil,
        strokeWidth: Double = 0,
        pathData: String? = nil
    ) {
        self.kind = kind
        self.fill = fill
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.pathData = pathData
    }

    public init(kind: ShapeKind, fill: ColorRef, strokeColor: ColorRef? = nil, strokeWidth: Double = 0) {
        self.init(kind: kind, fill: .color(fill), strokeColor: strokeColor, strokeWidth: strokeWidth)
    }
}

/// A straight line across the layer's rect, through its center. Rotate the
/// layer for diagonals; use as dividers, tick marks, and decoration.
public struct LineContent: Codable, Hashable, Sendable {
    public var color: ColorRef
    public var thickness: Double
    /// SVG-style dash pattern in points (`[on, off]`); nil for solid.
    public var dash: [Double]?

    public init(color: ColorRef, thickness: Double = 2, dash: [Double]? = nil) {
        self.color = color
        self.thickness = thickness
        self.dash = dash
    }
}

public enum ChartStyle: String, Codable, Sendable {
    case line
    case area
    case bars
}

/// A mini-chart over a list from the data snapshot. `dataPath` addresses a
/// list of numbers (e.g. `weather.hourly`); values are min/max-normalized.
public struct ChartContent: Codable, Hashable, Sendable {
    public var dataPath: String
    public var style: ChartStyle
    public var color: ColorRef
    public var lineWidth: Double

    public init(dataPath: String, style: ChartStyle = .line, color: ColorRef, lineWidth: Double = 2) {
        self.dataPath = dataPath
        self.style = style
        self.color = color
        self.lineWidth = lineWidth
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

    /// Where the arc begins, in degrees, 0 = 12 o'clock and positive clockwise.
    public var startAngle: Double?
    /// How much of the circle the gauge spans: 360 is a full ring, 270 the
    /// classic activity arc, 180 a half-dial.
    public var sweep: Double?
    public var direction: GaugeDirection?
    public var cap: GaugeCap?
    /// Breaks the arc into discrete ticks — the activity-dots look. nil is a
    /// continuous arc.
    public var segments: Int?
    public var gapDegrees: Double?

    public init(
        value: String,
        style: GaugeStyle = .ring,
        tint: ColorRef,
        track: ColorRef,
        lineWidth: Double = 6,
        startAngle: Double? = nil,
        sweep: Double? = nil,
        direction: GaugeDirection? = nil,
        cap: GaugeCap? = nil,
        segments: Int? = nil,
        gapDegrees: Double? = nil
    ) {
        self.value = value
        self.style = style
        self.tint = tint
        self.track = track
        self.lineWidth = lineWidth
        self.startAngle = startAngle
        self.sweep = sweep
        self.direction = direction
        self.cap = cap
        self.segments = segments
        self.gapDegrees = gapDegrees
    }

    /// True once the design asks for anything the legacy full-ring drawing
    /// can't express. Kept explicit so an untouched gauge keeps rendering
    /// through exactly the code path it always did.
    public var usesArcGeometry: Bool {
        startAngle != nil || sweep != nil || direction != nil || cap != nil
            || segments != nil || gapDegrees != nil
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

/// Cross-axis placement for stacked children (e.g. top/center/bottom within
/// a horizontal stack). Optional in serialized form; nil means center.
public enum StackAlignment: String, Codable, Sendable {
    case start, center, end
}

public struct ContainerContent: Codable, Sendable, Hashable {
    public var layout: ContainerLayout
    /// Spacing between stacked children, in points.
    public var spacing: Double
    /// Inner padding, in points.
    public var padding: Double
    public var alignment: StackAlignment?
    public var background: Fill?
    public var children: [Layer]

    public init(
        layout: ContainerLayout = .absolute,
        spacing: Double = 0,
        padding: Double = 0,
        alignment: StackAlignment? = nil,
        background: Fill? = nil,
        children: [Layer] = []
    ) {
        self.layout = layout
        self.spacing = spacing
        self.padding = padding
        self.alignment = alignment
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
    case line(LineContent)
    case chart(ChartContent)
    case container(ContainerContent)
}

/// What tapping a layer does. URL templates may contain `{expression}`
/// spans, so a deep link can carry live data:
/// `"shortcuts://run-shortcut?name=Log{round(health.steps)}"`.
public struct TapAction: Codable, Hashable, Sendable {
    public var urlTemplate: String

    public init(urlTemplate: String) {
        self.urlTemplate = urlTemplate
    }
}

public struct Layer: Codable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var frame: LayerFrame
    public var style: LayerStyle
    public var isHidden: Bool
    /// Expression gate: the layer renders only while this evaluates true
    /// (e.g. `battery.level < 0.2`). nil means always visible. Evaluation
    /// errors fail open — a broken condition shouldn't blank a widget.
    public var visibleWhen: String?
    /// Drop this layer when the system asks for a simplified rendering
    /// (WidgetKit's `LevelOfDetail.simplified`, iOS 26+). Decoration and
    /// secondary labels should set this; the one number the widget exists to
    /// show should not. Defaults to false, so a document written before this
    /// existed renders exactly as it always did.
    public var hiddenWhenSimplified: Bool
    public var tapAction: TapAction?
    public var content: LayerContent

    public init(
        id: UUID = UUID(),
        name: String,
        frame: LayerFrame = .full,
        style: LayerStyle = .plain,
        isHidden: Bool = false,
        visibleWhen: String? = nil,
        hiddenWhenSimplified: Bool = false,
        tapAction: TapAction? = nil,
        content: LayerContent
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.style = style
        self.isHidden = isHidden
        self.visibleWhen = visibleWhen
        self.hiddenWhenSimplified = hiddenWhenSimplified
        self.tapAction = tapAction
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
        case id, name, frame, style, isHidden, visibleWhen, hiddenWhenSimplified, tapAction, type
        case text, symbol, shape, image, gauge, line, chart, container
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        frame = try container.decodeIfPresent(LayerFrame.self, forKey: .frame) ?? .full
        style = try container.decodeIfPresent(LayerStyle.self, forKey: .style) ?? .plain
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        visibleWhen = try container.decodeIfPresent(String.self, forKey: .visibleWhen)
        hiddenWhenSimplified = try container.decodeIfPresent(Bool.self, forKey: .hiddenWhenSimplified) ?? false
        tapAction = try container.decodeIfPresent(TapAction.self, forKey: .tapAction)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text": content = .text(try container.decode(TextContent.self, forKey: .text))
        case "symbol": content = .symbol(try container.decode(SymbolContent.self, forKey: .symbol))
        case "shape": content = .shape(try container.decode(ShapeContent.self, forKey: .shape))
        case "image": content = .image(try container.decode(ImageContent.self, forKey: .image))
        case "gauge": content = .gauge(try container.decode(GaugeContent.self, forKey: .gauge))
        case "line": content = .line(try container.decode(LineContent.self, forKey: .line))
        case "chart": content = .chart(try container.decode(ChartContent.self, forKey: .chart))
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
        try container.encodeIfPresent(visibleWhen, forKey: .visibleWhen)
        // Absent stays absent: only write the flag when it is actually set, so
        // documents that never touch it round-trip byte-identical.
        if hiddenWhenSimplified { try container.encode(hiddenWhenSimplified, forKey: .hiddenWhenSimplified) }
        try container.encodeIfPresent(tapAction, forKey: .tapAction)
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
        case .line(let value):
            try container.encode("line", forKey: .type)
            try container.encode(value, forKey: .line)
        case .chart(let value):
            try container.encode("chart", forKey: .type)
            try container.encode(value, forKey: .chart)
        case .container(let value):
            try container.encode("container", forKey: .type)
            try container.encode(value, forKey: .container)
        }
    }
}
