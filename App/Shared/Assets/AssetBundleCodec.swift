import Foundation
import ImageIO

/// Makes a document's photos travel with it. A `.facet` file references
/// assets by name; without the bytes, a shared document renders grey boxes
/// on the receiving device.
///
/// This is a standalone sidecar on purpose — `FacetFile` stays a clean JSON
/// document, and whoever welds the two together (export as a package, a
/// zip, an appended section) owns that container's versioning. The payload
/// here is exactly `{assetName: base64}`, nothing more.
///
/// `SceneBundle` is the container that welds them together for a whole
/// screen; it reuses the read/validate/write halves below (`gather`,
/// `install`) rather than growing a second encoder, so there is exactly one
/// place that decides what a `.facet` or a `.facetscene` is allowed to drop
/// into the App Group.
enum AssetBundleCodec {
    /// Every asset for `documentID`, or nil when there are none — callers
    /// skip writing an empty sidecar rather than shipping `{}`.
    static func encodeBundle(documentID: UUID, store: AssetStore = AssetStore()) throws -> Data? {
        let names = store.list(for: documentID)
        guard !names.isEmpty else { return nil }

        var payload: [String: String] = [:]
        for name in names {
            guard let data = store.data(for: name, in: documentID) else { continue }
            payload[name] = data.base64EncodedString()
        }
        guard !payload.isEmpty else { return nil }

        let encoder = JSONEncoder()
        // Sorted for stable diffs, matching FacetFile. Not pretty-printed:
        // the values are base64 blobs, so indentation buys nothing and the
        // sidecar is the largest part of a shared document.
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// Writes an incoming bundle into the store under its original names,
    /// because the document's layers already reference them.
    ///
    /// Bundles arrive from outside the device, so every entry is validated:
    /// the name must match the store's generated shape (blocking `../` path
    /// escapes) and the bytes must actually decode as an image. A `.facet`
    /// file is not permitted to drop arbitrary files into the App Group.
    static func importBundle(_ data: Data, into documentID: UUID, store: AssetStore = AssetStore()) throws {
        let payload: [String: String]
        do {
            payload = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw AssetBundleError.malformedPayload
        }
        try install([documentID: payload], store: store)
    }

    // MARK: - Many owners at once

    /// What a set of owners has on disk, as `(deduplicated bytes, names per
    /// owner)` — the shape `SceneBundle` stores.
    ///
    /// `names` nil means "everything this owner has", which is what a document
    /// wants: its images are curated (the picker deletes them), so the
    /// directory *is* the answer and walking the layer tree could only lose a
    /// reference. Pass an explicit list where the directory is not curated —
    /// a scene accumulates every wallpaper it has ever worn.
    ///
    /// Bytes are keyed by name, not by owner: `AssetStore` names assets by
    /// content hash, so the same photo in two widgets has one name and gets
    /// carried once.
    static func gather(
        _ owners: [(id: UUID, names: [String]?)],
        store: AssetStore = AssetStore()
    ) -> (blobs: [String: String], assets: [UUID: [String]]) {
        var blobs: [String: String] = [:]
        var assets: [UUID: [String]] = [:]

        for owner in owners {
            let names = owner.names ?? store.list(for: owner.id)
            var carried: [String] = []
            for name in names {
                if blobs[name] == nil {
                    guard let data = store.data(for: name, in: owner.id) else { continue }
                    blobs[name] = data.base64EncodedString()
                }
                carried.append(name)
            }
            guard !carried.isEmpty else { continue }
            // Sorted so the same scene exports to the same bytes twice running.
            assets[owner.id] = carried.sorted()
        }
        return (blobs, assets)
    }

    /// Writes incoming bytes into the store under their original names, for
    /// any number of owners.
    ///
    /// Names are kept because the layers already reference them — re-hashing on
    /// import would orphan every image in the document. The *owner* ids, on the
    /// other hand, are the caller's to choose, and for an import they are always
    /// fresh (see `SceneBundle.imported`), so this can only ever add files.
    ///
    /// Bundles arrive from outside the device, so every entry is validated: the
    /// name must match the store's generated shape (blocking `../` path escapes)
    /// and the bytes must actually decode as an image. A shared file is not
    /// permitted to drop arbitrary files into the App Group.
    static func install(_ assets: [UUID: [String: String]], store: AssetStore = AssetStore()) throws {
        for (owner, payload) in assets {
            for (name, base64) in payload {
                let bytes = try decoded(name: name, base64: base64)
                try store.write(bytes, named: name, for: owner)
                // The in-memory cache is keyed by name, and an import can
                // legitimately replace bytes under an existing name.
                FacetImageProviderFactory.invalidate(assetName: name, documentID: owner)
            }
        }
    }

    /// Validated bytes for one entry, or a throw naming what was wrong with it.
    private static func decoded(name: String, base64: String) throws -> Data {
        guard AssetStore.isValidAssetName(name) else {
            throw AssetBundleError.invalidAssetName(name)
        }
        guard let bytes = Data(base64Encoded: base64) else {
            throw AssetBundleError.malformedPayload
        }
        guard CGImageSourceCreateWithData(bytes as CFData, nil).map({
            CGImageSourceGetType($0) != nil
        }) == true else {
            throw AssetBundleError.notAnImage(name)
        }
        return bytes
    }
}

enum AssetBundleError: Error, LocalizedError, Equatable {
    case malformedPayload
    case invalidAssetName(String)
    case notAnImage(String)

    var errorDescription: String? {
        switch self {
        case .malformedPayload:
            return "The image bundle is damaged."
        case .invalidAssetName(let name):
            return "The image bundle contains an unsafe name (\"\(name)\")."
        case .notAnImage(let name):
            return "The image bundle entry \"\(name)\" isn't an image."
        }
    }
}
