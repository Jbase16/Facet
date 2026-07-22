import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// User photos backing `ImageContent` layers. Assets live in the App Group
/// container so the widget extension can read the same bytes the editor
/// previewed — the renderer is shared, so the pixels must be too.
///
/// Layout: `<container>/Assets/<documentUUID>/<contenthash>.<jpg|png>`.
/// Names are content hashes, so re-importing the same photo resolves to the
/// existing file instead of a duplicate, and a `.facet` shared between
/// devices keeps its layer references valid.
struct AssetStore: Sendable {
    /// Long-edge cap in pixels. A systemLarge widget is ~1080×1146 device
    /// pixels at 3x, so 1200 covers a full-bleed background with nothing to
    /// spare and nothing wasted. This is a hard requirement, not a nicety:
    /// the widget extension gets ~30 MB total (SPEC §5.1) and a decoded
    /// 48 MP photo is ~190 MB of RGBA — it would be jettisoned before it
    /// ever drew. Downsampling happens once, on import, in the app process
    /// where memory is cheap.
    static let maxPixelSize = 1200

    /// Visually lossless at this size; the difference between 0.85 and 1.0
    /// is ~4x the bytes for pixels nobody can see at widget scale.
    static let jpegQuality = 0.85

    /// Advisory ceiling for the picker's budget readout. Not enforced —
    /// documents get to be as heavy as the user wants, but they should see
    /// the weight before a widget starts getting evicted.
    static let recommendedBudgetBytes = 8 * 1024 * 1024

    var root: URL = AppGroup.containerURL.appendingPathComponent("Assets", isDirectory: true)

    // MARK: - Locations

    func directory(for documentID: UUID) -> URL {
        root.appendingPathComponent(documentID.uuidString, isDirectory: true)
    }

    func url(for assetName: String, in documentID: UUID) -> URL {
        directory(for: documentID).appendingPathComponent(assetName)
    }

    // MARK: - Saving

    /// Downsamples, re-encodes, and stores `data`, returning the asset name
    /// to put in an `ImageContent`. Identical source bytes always yield the
    /// same name, so this doubles as the dedupe path.
    @discardableResult
    func save(_ data: Data, for documentID: UUID) throws -> String {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw AssetStoreError.unreadableImage
        }

        // Alpha survives as PNG; everything else becomes JPEG. HEIC from the
        // photo library re-encodes here too, so the extension never pays a
        // HEIC decode at render time.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let hasAlpha = properties?[kCGImagePropertyHasAlpha] as? Bool ?? false

        // Hash the *source*, not the re-encode: it's stable across OS
        // versions whose ImageIO encoders differ byte-for-byte, and it lets
        // a repeat import skip the work entirely.
        let assetName = Self.assetName(forSource: data, hasAlpha: hasAlpha)
        let destination = url(for: assetName, in: documentID)
        if FileManager.default.fileExists(atPath: destination.path) { return assetName }

        let encoded = try Self.downsample(source, hasAlpha: hasAlpha)
        try write(encoded, named: assetName, for: documentID)
        return assetName
    }

    /// Convenience for images already in memory (camera capture, pasteboard).
    /// Round-tripping through lossless data keeps one downsample path rather
    /// than two that can drift.
    @discardableResult
    func save(_ image: UIImage, for documentID: UUID) throws -> String {
        let hasAlpha = image.cgImage.map(Self.hasAlpha) ?? true
        guard let data = hasAlpha ? image.pngData() : image.jpegData(compressionQuality: 1.0) else {
            throw AssetStoreError.encodingFailed
        }
        return try save(data, for: documentID)
    }

    /// Stores already-encoded bytes under an exact name. The bundle importer
    /// needs this: layers reference assets by name, so re-hashing on import
    /// would orphan every image in the document.
    func write(_ data: Data, named assetName: String, for documentID: UUID) throws {
        guard Self.isValidAssetName(assetName) else {
            throw AssetStoreError.invalidAssetName(assetName)
        }
        let directory = directory(for: documentID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(assetName), options: .atomic)
    }

    // MARK: - Loading

    func load(_ assetName: String, for documentID: UUID) -> UIImage? {
        guard Self.isValidAssetName(assetName) else { return nil }
        return UIImage(contentsOfFile: url(for: assetName, in: documentID).path)
    }

    func data(for assetName: String, in documentID: UUID) -> Data? {
        guard Self.isValidAssetName(assetName) else { return nil }
        return try? Data(contentsOf: url(for: assetName, in: documentID))
    }

    /// A small decode for list rows and grid tiles. Full-size decodes for
    /// 72pt thumbnails are how an asset browser turns into a memory spike.
    func thumbnail(_ assetName: String, for documentID: UUID, maxPixelSize: Int = 320) -> UIImage? {
        guard Self.isValidAssetName(assetName),
              let source = CGImageSourceCreateWithURL(
                url(for: assetName, in: documentID) as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    // MARK: - Inventory

    /// Asset names for a document, alphabetical so list rows don't shuffle.
    func list(for documentID: UUID) -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory(for: documentID),
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .map(\.lastPathComponent)
            .filter(Self.isValidAssetName)
            .sorted()
    }

    func byteCount(of assetName: String, for documentID: UUID) -> Int {
        let values = try? url(for: assetName, in: documentID)
            .resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    func totalBytes(for documentID: UUID) -> Int {
        list(for: documentID).reduce(0) { $0 + byteCount(of: $1, for: documentID) }
    }

    // MARK: - Deleting

    func delete(_ assetName: String, for documentID: UUID) throws {
        guard Self.isValidAssetName(assetName) else {
            throw AssetStoreError.invalidAssetName(assetName)
        }
        let target = url(for: assetName, in: documentID)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// For document deletion — otherwise a removed widget leaves its photos
    /// in the shared container forever.
    func deleteAll(for documentID: UUID) throws {
        let directory = directory(for: documentID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Naming

    /// Asset names are generated, never user-supplied, so an exact-shape
    /// check is both cheap and a complete defence against a hostile `.facet`
    /// trying to write outside the container via `../`.
    static func isValidAssetName(_ name: String) -> Bool {
        guard name.count > 4, name.count <= 80 else { return false }
        guard name.hasSuffix(".jpg") || name.hasSuffix(".png") else { return false }
        let stem = name.dropLast(4)
        guard !stem.isEmpty else { return false }
        return stem.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private static func assetName(forSource data: Data, hasAlpha: Bool) -> String {
        let digest = SHA256.hash(data: data)
        // 80 bits of a SHA-256 is far past collision risk for a handful of
        // photos per document, and keeps the on-disk name readable.
        let hex = digest.prefix(10).map { String(format: "%02x", $0) }.joined()
        return "img_\(hex).\(hasAlpha ? "png" : "jpg")"
    }

    // MARK: - Downsampling

    private static func downsample(_ source: CGImageSource, hasAlpha: Bool) throws -> Data {
        // ThumbnailFromImageAlways forces a real resample even when the file
        // carries an embedded thumbnail (which is usually far too small);
        // WithTransform bakes in EXIF orientation so the widget doesn't have
        // to know about it. ImageIO never upscales, so small photos pass
        // through at their native size.
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary) else {
            throw AssetStoreError.downsampleFailed
        }

        let type = hasAlpha ? UTType.png : UTType.jpeg
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, type.identifier as CFString, 1, nil
        ) else {
            throw AssetStoreError.encodingFailed
        }
        let options: [CFString: Any] = hasAlpha
            ? [:]
            : [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, scaled, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AssetStoreError.encodingFailed
        }
        return buffer as Data
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}

enum AssetStoreError: Error, LocalizedError, Equatable {
    case unreadableImage
    case downsampleFailed
    case encodingFailed
    case invalidAssetName(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "That file isn't an image Facet can read."
        case .downsampleFailed: return "Couldn't resize that image."
        case .encodingFailed: return "Couldn't encode that image."
        case .invalidAssetName(let name): return "Rejected asset name \"\(name)\"."
        }
    }
}
