import Foundation

/// The widget surfaces a document can target. One document, many renditions.
public enum RenditionKind: String, Codable, CaseIterable, Sendable {
    case systemSmall
    case systemMedium
    case systemLarge
    case accessoryCircular
    case accessoryRectangular
    case accessoryInline

    /// Canonical design-time size in points, used by the editor preview and
    /// the SVG debug renderer. On device, WidgetKit supplies the real size.
    public var designSize: (width: Double, height: Double) {
        switch self {
        case .systemSmall: return (158, 158)
        case .systemMedium: return (338, 158)
        case .systemLarge: return (338, 354)
        case .accessoryCircular: return (72, 72)
        case .accessoryRectangular: return (160, 72)
        case .accessoryInline: return (160, 26)
        }
    }

    /// Lock Screen accessories render monochrome/vibrant; color is ignored.
    public var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }
}

/// A sparse patch applied to one layer for a specific rendition.
/// Only non-nil fields override the base document.
public struct LayerPatch: Codable, Hashable, Sendable {
    public var layerID: UUID
    public var frame: LayerFrame?
    public var isHidden: Bool?
    public var opacity: Double?
    /// Overrides the point size for text/symbol layers.
    public var fontSize: Double?

    public init(
        layerID: UUID,
        frame: LayerFrame? = nil,
        isHidden: Bool? = nil,
        opacity: Double? = nil,
        fontSize: Double? = nil
    ) {
        self.layerID = layerID
        self.frame = frame
        self.isHidden = isHidden
        self.opacity = opacity
        self.fontSize = fontSize
    }
}
