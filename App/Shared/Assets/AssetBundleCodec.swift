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
enum AssetBundleCodec {
    /// Every asset for `documentID`, or nil when there are none — callers
    /// skip writing an empty sidecar rather than shipping `{}`.
    static func encodeBundle(documentID: UUID) throws -> Data? {
        let store = AssetStore()
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
    static func importBundle(_ data: Data, into documentID: UUID) throws {
        let payload: [String: String]
        do {
            payload = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw AssetBundleError.malformedPayload
        }

        let store = AssetStore()
        for (name, base64) in payload {
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
            try store.write(bytes, named: name, for: documentID)
            // The in-memory cache is keyed by name, and an import can
            // legitimately replace bytes under an existing name.
            FacetImageProviderFactory.invalidate(assetName: name, documentID: documentID)
        }
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
