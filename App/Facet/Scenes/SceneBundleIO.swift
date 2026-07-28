import Foundation
import FacetCore

/// Sharing a scene, both directions.
///
/// `SceneBundle` (FacetCore) is the format and owns the id-remapping rules;
/// `AssetBundleCodec` owns reading and validating image bytes. This is only the
/// wiring between them and the shared container: which owners to gather from on
/// the way out, and what to hand the stores on the way in.
enum SceneBundleIO {

    // MARK: - Export

    /// A bundle carrying `scene`, every design its placements reference, and
    /// the photos both depend on.
    ///
    /// Placements whose design is no longer in the library are kept rather than
    /// dropped: the sender sees "Missing widget" in that slot too, and silently
    /// rearranging someone's screen on export would be a stranger result than
    /// reproducing the hole.
    static func bundle(for scene: FacetScene, library: [WidgetDocument]) -> SceneBundle {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let documents = scene.referencedDocumentIDs.compactMap { byID[$0] }

        var owners: [(id: UUID, names: [String]?)] = documents.map { ($0.id, nil) }
        // The scene's own directory is *not* curated — changing wallpaper saves
        // a new asset and never deletes the old one — so ask for the one it is
        // actually wearing instead of everything it has ever worn.
        if let backdrop = scene.backdrop {
            owners.append((scene.id, [backdrop]))
        }

        let gathered = AssetBundleCodec.gather(owners)
        return SceneBundle(
            scene: scene,
            documents: documents,
            blobs: gathered.blobs,
            assets: gathered.assets
        )
    }

    static func encode(_ scene: FacetScene, library: [WidgetDocument]) throws -> Data {
        try SceneBundleFile.encode(bundle(for: scene, library: library))
    }

    /// The bundle written to a shareable temp file, for `ShareLink`.
    static func exportURL(for scene: FacetScene, library: [WidgetDocument]) -> URL? {
        let slug = scene.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(slug).\(SceneBundleFile.fileExtension)")
        guard let data = try? encode(scene, library: library),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    // MARK: - Import

    /// Decodes a bundle, rewrites every identity in it, and files the photos
    /// under the identities it produced.
    ///
    /// Nothing already in the container can be reached from here: `imported()`
    /// hands back ids that are fresh by construction, so every write below
    /// creates rather than replaces. The caller saves the returned models.
    static func install(_ data: Data) throws -> (scene: FacetScene, documents: [WidgetDocument]) {
        let imported = try SceneBundleFile.decode(data).imported()
        do {
            try AssetBundleCodec.install(imported.assets)
        } catch {
            // A rejected entry leaves the earlier ones on disk under owner ids
            // nothing will ever reference again. Sweep them, or every damaged
            // file that gets opened costs the user a few megabytes forever.
            let store = AssetStore()
            for owner in imported.assets.keys { try? store.deleteAll(for: owner) }
            throw error
        }
        return (imported.scene, imported.documents)
    }
}
