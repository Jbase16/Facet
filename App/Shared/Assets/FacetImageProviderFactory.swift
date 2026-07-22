import FacetRender
import Foundation
import SwiftUI
import UIKit

/// Wires `AssetStore` into the renderer's image hook. Every surface that
/// draws a document — editor canvas, gallery tile, widget extension —
/// installs one of these, which is what keeps a user's photo identical
/// across all three.
enum FacetImageProviderFactory {
    /// Providers are memoized per document. `FacetImageProvider` compares by
    /// identity (see the @Entry note in CLAUDE.md), so a fresh instance on
    /// every `body` evaluation would invalidate the environment on every
    /// render — the exact cost the reference wrapper exists to avoid.
    /// Memoizing means callers can call this inline in `body` safely.
    static func make(documentID: UUID) -> FacetImageProvider {
        ProviderRegistry.shared.provider(for: documentID) {
            let store = AssetStore()
            return FacetImageProvider { assetName in
                let key = "\(documentID.uuidString)/\(assetName)"
                guard let image = DecodedImageCache.shared.image(for: key, load: {
                    guard let stored = store.load(assetName, for: documentID) else { return nil }
                    // Decode now rather than at draw time: it makes the
                    // cache's cost accounting real, and a widget timeline
                    // renders the same image ~30 times per reload.
                    return stored.preparingForDisplay() ?? stored
                }) else { return nil }
                return Image(uiImage: image)
            }
        }
    }

    /// Call after replacing or deleting an asset — names are content hashes,
    /// so a stale entry would otherwise survive as long as the process does.
    static func invalidate(assetName: String, documentID: UUID) {
        DecodedImageCache.shared.remove("\(documentID.uuidString)/\(assetName)")
    }

    static func invalidateAll() {
        DecodedImageCache.shared.removeAll()
    }
}

/// NSCache is internally synchronized; the wrappers exist only to make that
/// promise legible to strict concurrency.
private final class ProviderRegistry: @unchecked Sendable {
    static let shared = ProviderRegistry()

    private let lock = NSLock()
    private var providers: [UUID: FacetImageProvider] = [:]

    func provider(for documentID: UUID, make: () -> FacetImageProvider) -> FacetImageProvider {
        lock.lock()
        defer { lock.unlock() }
        if let existing = providers[documentID] { return existing }
        let created = make()
        providers[documentID] = created
        return created
    }
}

private final class DecodedImageCache: @unchecked Sendable {
    static let shared = DecodedImageCache()

    private let cache = NSCache<NSString, UIImage>()

    init() {
        // A decoded 1200×1200 image is ~5.5 MB of RGBA and the widget
        // extension's whole budget is ~30 MB, so the cache is deliberately
        // tiny — it exists to stop re-decoding across a timeline's worth of
        // entries, not to hold a library.
        cache.countLimit = 6
        cache.totalCostLimit = 12 * 1024 * 1024
    }

    func image(for key: String, load: () -> UIImage?) -> UIImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit }
        guard let loaded = load() else { return nil }
        cache.setObject(loaded, forKey: key as NSString, cost: Self.cost(of: loaded))
        return loaded
    }

    func remove(_ key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private static func cost(of image: UIImage) -> Int {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels) * 4
    }
}
