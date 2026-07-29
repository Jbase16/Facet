import Foundation

/// A scene and everything it needs to open somewhere else.
///
/// A `.facetscene` on its own is a list of *references*: every placement names
/// a document id, and on another device none of those ids exist, so the scene
/// opens as a screen of empty slots. A bundle closes that gap by carrying the
/// referenced `WidgetDocument`s and the image bytes both they and the scene's
/// wallpaper depend on.
///
/// Asset bytes are base64 in a flat, content-addressed table rather than
/// nested under each owner: `AssetStore` names assets by content hash, so two
/// widgets using the same photo name it identically and the bundle carries it
/// once. `assets` then says only which names each owner needs.
///
/// FacetCore has no image decoder (it builds on Linux), so the bytes are
/// opaque here — validating that a blob really is an image, and writing it to
/// the shared container, belongs to the platform layer.
public struct SceneBundle: Codable, Sendable, Hashable {
    /// Bump when the serialized form changes; additive fields decode without
    /// migration, exactly as `WidgetDocument` and `FacetScene` do.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var scene: FacetScene
    /// Every document the scene's placements reference, in placement order.
    public var documents: [WidgetDocument]
    /// Asset bytes, base64, keyed by asset name.
    public var blobs: [String: String]
    /// Asset names each owner needs: a document's own id for its image layers,
    /// the *scene's* id for the wallpaper — the same keying `AssetStore` uses.
    public var assets: [UUID: [String]]

    public init(
        scene: FacetScene,
        documents: [WidgetDocument] = [],
        blobs: [String: String] = [:],
        assets: [UUID: [String]] = [:]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.scene = scene
        self.documents = documents
        self.blobs = blobs
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, scene, documents, blobs, assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        // `scene` and `documents` stay required: they are what distinguishes a
        // bundle from a bare `.facetscene`, which shares the file extension and
        // is told apart by exactly this.
        scene = try container.decode(FacetScene.self, forKey: .scene)
        documents = try container.decode([WidgetDocument].self, forKey: .documents)
        blobs = try container.decodeIfPresent([String: String].self, forKey: .blobs) ?? [:]
        let raw = try container.decodeIfPresent([String: [String]].self, forKey: .assets) ?? [:]
        var mapped: [UUID: [String]] = [:]
        for (key, names) in raw {
            guard let owner = UUID(uuidString: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .assets,
                    in: container,
                    debugDescription: "Asset owner is not a UUID: \(key)"
                )
            }
            mapped[owner] = names
        }
        assets = mapped
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(scene, forKey: .scene)
        try container.encode(documents, forKey: .documents)
        // Absent rather than empty, so a bundle with no photos in it stays as
        // small and as readable as the scene file it grew out of.
        if !blobs.isEmpty { try container.encode(blobs, forKey: .blobs) }
        if !assets.isEmpty {
            let raw = Dictionary(uniqueKeysWithValues: assets.map { ($0.key.uuidString, $0.value) })
            try container.encode(raw, forKey: .assets)
        }
    }

    /// Base64 bytes for one owner, dropping names the bundle has no blob for —
    /// a missing photo costs one grey box, and refusing the whole scene over it
    /// would be a worse trade.
    public func payload(for owner: UUID) -> [String: String] {
        var result: [String: String] = [:]
        for name in assets[owner] ?? [] {
            if let base64 = blobs[name] { result[name] = base64 }
        }
        return result
    }

    /// Total base64 length of the carried bytes. The transported size, not the
    /// decoded one — base64 is ~4/3 of the bytes on disk.
    public var payloadByteCount: Int {
        blobs.values.reduce(0) { $0 + $1.utf8.count }
    }
}

/// The result of importing a bundle: the same screen, under identities that
/// cannot collide with anything already in the library.
public struct ImportedSceneBundle: Sendable {
    public var scene: FacetScene
    public var documents: [WidgetDocument]
    /// Bytes to file under each *new* owner id, base64 exactly as carried.
    public var assets: [UUID: [String: String]]
    /// Old document id → new one. Not needed to apply the import; it is how a
    /// caller (or a test) can prove nothing was rebound to an existing widget.
    public var documentIDs: [UUID: UUID]
    /// Old scene id → new one, for the same reason.
    public var sceneID: (old: UUID, new: UUID)

    public init(
        scene: FacetScene,
        documents: [WidgetDocument],
        assets: [UUID: [String: String]],
        documentIDs: [UUID: UUID],
        sceneID: (old: UUID, new: UUID)
    ) {
        self.scene = scene
        self.documents = documents
        self.assets = assets
        self.documentIDs = documentIDs
        self.sceneID = sceneID
    }
}

public extension SceneBundle {
    /// The bundle rewritten onto brand-new identities.
    ///
    /// Every document, the scene, and every placement gets a fresh id, always —
    /// not only when the incoming id happens to be taken. Two reasons:
    ///
    /// - The format cannot see the library, and a policy that depends on what
    ///   is already installed is a policy that behaves differently on two
    ///   devices for the same file.
    /// - Even with no collision today, keeping the sender's ids means a *second*
    ///   import of the same bundle overwrites the first one — including any
    ///   edits made to it in between. Reusing an id is only ever safe if the two
    ///   documents are the same design, and a shared file cannot promise that.
    ///
    /// The cost is duplication: importing the same scene twice leaves two copies
    /// of its widgets. That is the direction to err in — the alternative
    /// silently replaces work the user did not agree to give up. It is also
    /// exactly what `.facet` import already does.
    ///
    /// `newID` is injectable so tests can name the identities they expect.
    func imported(newID: () -> UUID = { UUID() }) -> ImportedSceneBundle {
        var documentIDs: [UUID: UUID] = [:]
        var rewritten: [WidgetDocument] = []
        rewritten.reserveCapacity(documents.count)
        for var document in documents {
            let old = document.id
            let fresh = newID()
            // First mapping wins: a malformed bundle can carry the same id
            // twice, and placements must resolve to one of them deterministically
            // rather than to whichever happened to be last. Both copies still get
            // distinct ids, so neither overwrites the other on save.
            if documentIDs[old] == nil { documentIDs[old] = fresh }
            document.id = fresh
            rewritten.append(document)
        }

        var newScene = scene
        let oldSceneID = scene.id
        newScene.id = newID()
        newScene.placements = scene.placements.map { placement in
            var copy = placement
            copy.id = newID()
            // A placement whose design the bundle failed to carry gets an id
            // that matches nothing, rather than keeping the sender's. Keeping it
            // could bind the placement to an unrelated local widget that happens
            // to share the id — a stranger's screen quietly showing your widget.
            // Dangling, it draws as "Missing widget", which is the truth.
            copy.documentID = documentIDs[placement.documentID] ?? newID()
            return copy
        }

        // Documents win over the scene on the (pathological) chance that a
        // document was saved under the scene's own id.
        var owners = [oldSceneID: newScene.id]
        owners.merge(documentIDs) { _, document in document }

        var assets: [UUID: [String: String]] = [:]
        for (owner, _) in self.assets {
            // An owner that is neither the scene nor a carried document owns
            // nothing on this device; writing its bytes would just leak files
            // into the container.
            guard let newOwner = owners[owner] else { continue }
            let payload = payload(for: owner)
            guard !payload.isEmpty else { continue }
            assets[newOwner, default: [:]].merge(payload) { existing, _ in existing }
        }

        return ImportedSceneBundle(
            scene: newScene,
            documents: rewritten,
            assets: assets,
            documentIDs: documentIDs,
            sceneID: (oldSceneID, newScene.id)
        )
    }
}

public extension FacetScene {
    /// Document ids the placements reference, deduplicated, in placement order.
    /// What a bundle has to carry for this scene to mean anything elsewhere.
    var referencedDocumentIDs: [UUID] {
        var seen: Set<UUID> = []
        return placements.compactMap { seen.insert($0.documentID).inserted ? $0.documentID : nil }
    }
}

public enum SceneBundleError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    /// Neither a bundle nor a bare scene.
    case notASceneFile
}

/// Serialization for the shareable `.facetscene` file.
///
/// Same extension as the scene-only file the app writes into its own container,
/// on purpose: to the person sending it this is "the scene", and the two shapes
/// are told apart unambiguously by their top-level keys. `decode` therefore
/// accepts a bare `FacetScene` too — a hand-copied one still opens, just with
/// its widgets missing, which beats refusing the file.
public enum SceneBundleFile {
    public static let fileExtension = "facetscene"

    public static func encode(_ bundle: SceneBundle) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted, but not pretty-printed: the base64 blobs are almost all of
        // the file, so indenting them costs bytes and buys no legibility. The
        // scene-only `.facetscene` in the container stays pretty-printed.
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(bundle)
    }

    public static func decode(_ data: Data) throws -> SceneBundle {
        let decoder = JSONDecoder()
        if let bundle = try? decoder.decode(SceneBundle.self, from: data) {
            guard bundle.schemaVersion <= SceneBundle.currentSchemaVersion else {
                throw SceneBundleError.unsupportedSchemaVersion(bundle.schemaVersion)
            }
            return bundle
        }
        // A pre-bundle scene file: no documents, no assets, every placement
        // dangling. Wrapping it here means one import path, not two.
        guard let scene = try? SceneFile.decode(data) else {
            throw SceneBundleError.notASceneFile
        }
        return SceneBundle(scene: scene)
    }
}
