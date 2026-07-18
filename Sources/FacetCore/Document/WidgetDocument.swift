import Foundation

/// The portable `.facet` document: a layer tree, its design tokens, the data
/// sources it depends on, and per-rendition overrides.
public struct WidgetDocument: Codable, Identifiable, Sendable, Hashable {
    /// Bump when the serialized format changes; see `DocumentMigrator`.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var tokens: ThemeTokens
    public var root: Layer
    /// Identifiers of the data sources this document reads (e.g. "time", "battery").
    public var sources: [String]
    public var overrides: [RenditionKind: [LayerPatch]]

    public init(
        id: UUID = UUID(),
        name: String,
        tokens: ThemeTokens = .empty,
        root: Layer,
        sources: [String] = [],
        overrides: [RenditionKind: [LayerPatch]] = [:]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.tokens = tokens
        self.root = root
        self.sources = sources
        self.overrides = overrides
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, tokens, root, sources, overrides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tokens = try container.decodeIfPresent(ThemeTokens.self, forKey: .tokens) ?? .empty
        root = try container.decode(Layer.self, forKey: .root)
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
        let rawOverrides = try container.decodeIfPresent([String: [LayerPatch]].self, forKey: .overrides) ?? [:]
        var mapped: [RenditionKind: [LayerPatch]] = [:]
        for (key, patches) in rawOverrides {
            guard let kind = RenditionKind(rawValue: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .overrides,
                    in: container,
                    debugDescription: "Unknown rendition kind: \(key)"
                )
            }
            mapped[kind] = patches
        }
        overrides = mapped
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(root, forKey: .root)
        try container.encode(sources, forKey: .sources)
        let rawOverrides = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawOverrides, forKey: .overrides)
    }

    /// Patches applicable to `layerID` for the given rendition.
    public func patch(for layerID: UUID, in rendition: RenditionKind) -> LayerPatch? {
        overrides[rendition]?.first(where: { $0.layerID == layerID })
    }
}

public enum DocumentError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

/// Serialization entry points for the `.facet` format. JSON, stable key
/// order, so documents diff cleanly under version control and in the gallery.
public enum FacetFile {
    public static func encode(_ document: WidgetDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> WidgetDocument {
        let decoder = JSONDecoder()
        let document = try decoder.decode(WidgetDocument.self, from: data)
        guard document.schemaVersion <= WidgetDocument.currentSchemaVersion else {
            throw DocumentError.unsupportedSchemaVersion(document.schemaVersion)
        }
        // Future schema bumps migrate here before returning.
        return document
    }
}
