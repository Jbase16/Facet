import Foundation

/// Where a widget sits on the home screen, in icon-grid coordinates.
/// `column`/`row` are the top-left cell of the block the widget occupies —
/// the same grid iOS itself snaps widgets to.
public struct ScenePlacement: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// The design shown here. A reference, not a copy: editing the widget
    /// updates every scene that places it.
    public var documentID: UUID
    public var rendition: RenditionKind
    public var column: Int
    public var row: Int

    public init(
        id: UUID = UUID(),
        documentID: UUID,
        rendition: RenditionKind = .systemSmall,
        column: Int = 0,
        row: Int = 0
    ) {
        self.id = id
        self.documentID = documentID
        self.rendition = rendition
        self.column = column
        self.row = row
    }

    /// How many icon cells this placement covers, which is what makes overlap
    /// checkable without consulting the renderer.
    public var span: (columns: Int, rows: Int) {
        switch rendition {
        case .systemSmall: return (2, 2)
        case .systemMedium: return (4, 2)
        case .systemLarge: return (4, 4)
        default: return (2, 2)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, documentID, rendition, column, row
    }

    /// Decoded field-by-field with defaults rather than by the synthesized
    /// initializer, so a `.facetscene` written by an older build still opens
    /// after this struct gains a field. `documentID` is the exception: a
    /// placement that names no design cannot be drawn, so it stays required.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        documentID = try container.decode(UUID.self, forKey: .documentID)
        rendition = try container.decodeIfPresent(RenditionKind.self, forKey: .rendition) ?? .systemSmall
        column = try container.decodeIfPresent(Int.self, forKey: .column) ?? 0
        row = try container.decodeIfPresent(Int.self, forKey: .row) ?? 0
    }

    public func overlaps(_ other: ScenePlacement) -> Bool {
        let a = span, b = other.span
        let columnsOverlap = column < other.column + b.columns && other.column < self.column + a.columns
        let rowsOverlap = row < other.row + b.rows && other.row < self.row + a.rows
        return columnsOverlap && rowsOverlap
    }
}

/// A whole home screen: the wallpaper, the widgets placed on it, and the
/// palette they share.
///
/// This is the unit Facet is actually about. A widget designed alone can only
/// hope to suit the screen it lands on; a Scene is composed against its own
/// backdrop, so the wallpaper, the widgets and their colours are one decision
/// rather than several unrelated ones. It is also what people trade — nobody
/// shares a lone widget, they share a home screen.
public struct FacetScene: Codable, Identifiable, Hashable, Sendable {
    /// Bump when the serialized form changes; additive fields decode without
    /// migration, exactly as `WidgetDocument` does.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    /// Wallpaper asset name, stored in the scene's own asset bundle.
    public var backdrop: String?
    public var placements: [ScenePlacement]
    /// Colours every widget in the scene can resolve against. Empty means each
    /// document keeps its own palette untouched.
    public var palette: ThemeTokens

    public init(
        id: UUID = UUID(),
        name: String,
        backdrop: String? = nil,
        placements: [ScenePlacement] = [],
        palette: ThemeTokens = .empty
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.backdrop = backdrop
        self.placements = placements
        self.palette = palette
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, backdrop, placements, palette
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        backdrop = try container.decodeIfPresent(String.self, forKey: .backdrop)
        placements = try container.decodeIfPresent([ScenePlacement].self, forKey: .placements) ?? []
        palette = try container.decodeIfPresent(ThemeTokens.self, forKey: .palette) ?? .empty
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(backdrop, forKey: .backdrop)
        try container.encode(placements, forKey: .placements)
        try container.encode(palette, forKey: .palette)
    }

    /// The first free slot that fits `rendition`, or nil when the screen is
    /// full — so adding a widget never silently stacks it on another.
    public func freeSlot(for rendition: RenditionKind, columns: Int = 4, rows: Int = 6) -> (column: Int, row: Int)? {
        // A non-positive grid has no slots by definition. Without this the
        // column step below computes to zero and `stride` traps — a crash
        // where "no room" is the honest answer.
        guard columns > 0, rows > 0 else { return nil }
        let probe = ScenePlacement(documentID: UUID(), rendition: rendition)
        let span = probe.span
        // Widgets snap to two-row bands, and anything wider than half the grid
        // starts at the left margin — the same rule iOS applies.
        let columnStep = max(1, span.columns >= columns ? columns : 2)
        for row in stride(from: 0, through: rows - span.rows, by: 2) {
            for column in stride(from: 0, through: columns - span.columns, by: columnStep) {
                var candidate = probe
                candidate.column = column
                candidate.row = row
                if !placements.contains(where: { $0.overlaps(candidate) }) {
                    return (column, row)
                }
            }
        }
        return nil
    }
}

/// Serialization for the portable `.facetscene` format — the same plain,
/// diffable JSON the widget format uses, so a scene is shareable as one file.
public enum SceneFile {
    public static func encode(_ scene: FacetScene) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(scene)
    }

    public static func decode(_ data: Data) throws -> FacetScene {
        let scene = try JSONDecoder().decode(FacetScene.self, from: data)
        guard scene.schemaVersion <= FacetScene.currentSchemaVersion else {
            throw DocumentError.unsupportedSchemaVersion(scene.schemaVersion)
        }
        return scene
    }
}
