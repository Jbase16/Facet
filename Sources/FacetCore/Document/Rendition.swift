import Foundation

/// The widget surfaces a document can target. One document, many renditions.
public enum RenditionKind: String, Codable, CaseIterable, Sendable {
    case systemSmall
    case systemMedium
    case systemLarge
    /// iPad only, landscape-proportioned. `WidgetFamily.systemExtraLarge`.
    case systemExtraLarge
    /// iPad only, portrait-proportioned. `WidgetFamily.systemExtraLargePortrait`,
    /// added in the iOS 27 SDK.
    case systemExtraLargePortrait
    case accessoryCircular
    case accessoryRectangular
    case accessoryInline

    /// Canonical design-time size in points, used by the editor preview and
    /// the SVG debug renderer. On device, WidgetKit supplies the real size.
    ///
    /// The system sizes are the 390×844 iPhone class. The two extra-large
    /// sizes are derived from it rather than measured: an extra-large widget
    /// is two larges side by side, so 338 × 2 plus the 39pt gutter, and the
    /// portrait variant is that transposed. Since these are design-time only,
    /// an aspect ratio that matches the device is what actually matters —
    /// but they are worth confirming on an iPad before anyone treats the
    /// absolute numbers as authoritative.
    public var designSize: (width: Double, height: Double) {
        switch self {
        case .systemSmall: return (158, 158)
        case .systemMedium: return (338, 158)
        case .systemLarge: return (338, 354)
        case .systemExtraLarge: return (715, 354)
        case .systemExtraLargePortrait: return (354, 715)
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

    /// iPad-only families. The editor still offers them — you design on a
    /// phone and place on a tablet — but the scene composer, which models an
    /// iPhone home screen, does not.
    public var isExtraLarge: Bool {
        switch self {
        case .systemExtraLarge, .systemExtraLargePortrait: return true
        default: return false
        }
    }

    /// One name per rendition, shared by every surface that shows one. The
    /// editor, the scene composer and the size picker each used to spell
    /// these out separately, which is how "Large" and "Lock ▭" drifted apart.
    public var displayName: String {
        switch self {
        case .systemSmall: return "Small"
        case .systemMedium: return "Medium"
        case .systemLarge: return "Large"
        case .systemExtraLarge: return "iPad Wide"
        case .systemExtraLargePortrait: return "iPad Tall"
        case .accessoryCircular: return "Lock Circle"
        case .accessoryRectangular: return "Lock Rectangle"
        case .accessoryInline: return "Lock Inline"
        }
    }

    /// The three sizes you switch between constantly while designing. Kept
    /// separate from `allCases` so the editor can give them a fast control
    /// and push the rest behind a menu.
    public static let homeScreenSizes: [RenditionKind] = [.systemSmall, .systemMedium, .systemLarge]

    /// Everything else a document can target: Lock Screen accessories and the
    /// iPad-only extra-large families.
    public static let secondarySurfaces: [RenditionKind] = [
        .accessoryCircular, .accessoryRectangular, .accessoryInline,
        .systemExtraLarge, .systemExtraLargePortrait,
    ]
}

/// How much the system wants drawn. Mirrors WidgetKit's `LevelOfDetail`
/// (iOS 26+), kept as its own type so FacetCore stays free of WidgetKit —
/// the package builds on Linux, where that framework does not exist.
///
/// The system asks for `.simplified` when a widget is shown small or at a
/// distance. Layers opt in to disappearing there; nothing is dropped by
/// default, because only the author knows which layers are decoration.
public enum DetailLevel: String, Codable, CaseIterable, Sendable {
    case full
    case simplified
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
