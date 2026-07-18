import Foundation

/// An sRGB color with alpha, serialized as `#RRGGBB` or `#RRGGBBAA`.
public struct ColorValue: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init?(hex: String) {
        var string = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard string.count == 6 || string.count == 8 else { return nil }
        if string.count == 6 { string += "FF" }
        guard let value = UInt64(string, radix: 16) else { return nil }
        red = Double((value >> 24) & 0xFF) / 255.0
        green = Double((value >> 16) & 0xFF) / 255.0
        blue = Double((value >> 8) & 0xFF) / 255.0
        alpha = Double(value & 0xFF) / 255.0
    }

    public var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        let a = Int((alpha * 255).rounded())
        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        guard let color = ColorValue(hex: hex) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid color hex string: \(hex)"
            )
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }

    public static let white = ColorValue(red: 1, green: 1, blue: 1)
    public static let black = ColorValue(red: 0, green: 0, blue: 0)
    public static let clear = ColorValue(red: 0, green: 0, blue: 0, alpha: 0)
}

/// A color token with automatic light/dark resolution.
public struct ColorToken: Codable, Hashable, Sendable {
    public var light: ColorValue
    public var dark: ColorValue

    public init(light: ColorValue, dark: ColorValue? = nil) {
        self.light = light
        self.dark = dark ?? light
    }

    public func resolved(for scheme: ColorScheme) -> ColorValue {
        scheme == .dark ? dark : light
    }
}

public enum ColorScheme: String, Codable, Sendable {
    case light
    case dark
}

public enum FontDesign: String, Codable, Sendable {
    case standard = "default"
    case rounded
    case serif
    case monospaced
}

public enum FontWeight: String, Codable, Sendable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
}

public struct FontToken: Codable, Hashable, Sendable {
    public var size: Double
    public var weight: FontWeight
    public var design: FontDesign
    /// Custom font family name; nil means the system font.
    public var family: String?

    public init(size: Double, weight: FontWeight = .regular, design: FontDesign = .standard, family: String? = nil) {
        self.size = size
        self.weight = weight
        self.design = design
        self.family = family
    }
}

/// The named design tokens for a document. Layers reference these by name so a
/// theme swap restyles the whole widget.
public struct ThemeTokens: Codable, Hashable, Sendable {
    public var colors: [String: ColorToken]
    public var fonts: [String: FontToken]
    public var spacing: [String: Double]

    public init(
        colors: [String: ColorToken] = [:],
        fonts: [String: FontToken] = [:],
        spacing: [String: Double] = [:]
    ) {
        self.colors = colors
        self.fonts = fonts
        self.spacing = spacing
    }

    public static let empty = ThemeTokens()
}

/// A color reference: either a token name or a literal value.
/// Serialized as `"token:accent"` or `"#RRGGBBAA"`.
public enum ColorRef: Codable, Hashable, Sendable {
    case token(String)
    case literal(ColorValue)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw.hasPrefix("token:") {
            self = .token(String(raw.dropFirst("token:".count)))
        } else if let color = ColorValue(hex: raw) {
            self = .literal(color)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid color reference: \(raw)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .token(let name): try container.encode("token:" + name)
        case .literal(let color): try container.encode(color.hexString)
        }
    }
}

// MARK: - Fills

public struct GradientStop: Codable, Hashable, Sendable {
    /// 0...1 along the gradient axis.
    public var position: Double
    public var color: ColorRef

    public init(position: Double, color: ColorRef) {
        self.position = position
        self.color = color
    }
}

public struct GradientFill: Codable, Hashable, Sendable {
    public var stops: [GradientStop]
    /// Direction of the gradient vector in degrees: 0 points right, 90 down.
    /// Ignored for radial gradients (center-out).
    public var angle: Double

    public init(stops: [GradientStop], angle: Double = 90) {
        self.stops = stops
        self.angle = angle
    }
}

/// A paint: solid color or gradient. Solid fills serialize as the same plain
/// string as `ColorRef`, so every schema-v1 document decodes unchanged.
public enum Fill: Codable, Hashable, Sendable {
    case color(ColorRef)
    case linearGradient(GradientFill)
    case radialGradient(GradientFill)

    /// Conveniences mirroring ColorRef so call sites read identically.
    public static func token(_ name: String) -> Fill { .color(.token(name)) }
    public static func literal(_ color: ColorValue) -> Fill { .color(.literal(color)) }

    private enum CodingKeys: String, CodingKey {
        case type, gradient
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let raw = try? container.decode(String.self) {
            if raw.hasPrefix("token:") {
                self = .color(.token(String(raw.dropFirst("token:".count))))
                return
            }
            if let color = ColorValue(hex: raw) {
                self = .color(.literal(color))
                return
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid fill: \(raw)"
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "linearGradient":
            self = .linearGradient(try container.decode(GradientFill.self, forKey: .gradient))
        case "radialGradient":
            self = .radialGradient(try container.decode(GradientFill.self, forKey: .gradient))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown fill type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .color(let ref):
            var container = encoder.singleValueContainer()
            switch ref {
            case .token(let name): try container.encode("token:" + name)
            case .literal(let color): try container.encode(color.hexString)
            }
        case .linearGradient(let gradient):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("linearGradient", forKey: .type)
            try container.encode(gradient, forKey: .gradient)
        case .radialGradient(let gradient):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("radialGradient", forKey: .type)
            try container.encode(gradient, forKey: .gradient)
        }
    }
}

/// A font reference: either a token name or an inline font description.
public enum FontRef: Codable, Hashable, Sendable {
    case token(String)
    case literal(FontToken)

    private enum CodingKeys: String, CodingKey {
        case token, literal
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let name = try? container.decode(String.self) {
            self = .token(name)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try container.decodeIfPresent(String.self, forKey: .token) {
            self = .token(name)
        } else {
            self = .literal(try container.decode(FontToken.self, forKey: .literal))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .token(let name):
            var container = encoder.singleValueContainer()
            try container.encode(name)
        case .literal(let font):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(font, forKey: .literal)
        }
    }
}
