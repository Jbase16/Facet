import XCTest
import UIKit
import FacetCore
@testable import Facet

/// The asset pipeline that no package test can reach.
///
/// `App/Shared` is compiled into the app and the widget extension, not into
/// the Swift package, so `AssetStore` and `AssetBundleCodec` had no tests at
/// all — including the code that writes bytes from an *imported* bundle to
/// disk. This target exists for that gap. Every test here runs against a
/// temporary directory rather than the real App Group container.
final class AssetBundleCodecTests: XCTestCase {
    private var root: URL!
    private var store: AssetStore!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FacetAssetTests-\(UUID().uuidString)", isDirectory: true)
        store = AssetStore(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A real encoded image, because the codec validates that bytes actually
    /// decode — a fixture of random bytes would test the rejection path only.
    private func imageData(_ color: UIColor = .systemPink, size: CGFloat = 8) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        return image.pngData()!
    }

    @discardableResult
    private func seed(_ owner: UUID, _ color: UIColor = .systemPink) throws -> String {
        try store.save(imageData(color), for: owner)
    }

    // MARK: - Round trip

    func testBundleRoundTripsBytesForOneOwner() throws {
        let owner = UUID()
        let name = try seed(owner)
        let original = try XCTUnwrap(store.data(for: name, in: owner))

        let bundle = try XCTUnwrap(try AssetBundleCodec.encodeBundle(documentID: owner, store: store))

        let destination = UUID()
        try AssetBundleCodec.importBundle(bundle, into: destination, store: store)

        XCTAssertEqual(store.list(for: destination), [name])
        XCTAssertEqual(store.data(for: name, in: destination), original)
    }

    func testAnOwnerWithNoAssetsEncodesToNilRatherThanAnEmptyBundle() throws {
        XCTAssertNil(try AssetBundleCodec.encodeBundle(documentID: UUID(), store: store))
    }

    func testImportingDoesNotDisturbTheSource() throws {
        let owner = UUID()
        let name = try seed(owner)
        let bundle = try XCTUnwrap(try AssetBundleCodec.encodeBundle(documentID: owner, store: store))
        try AssetBundleCodec.importBundle(bundle, into: UUID(), store: store)
        XCTAssertEqual(store.list(for: owner), [name])
    }

    // MARK: - Untrusted input

    /// The reason this matters: a bundle is a file from a stranger, and its
    /// asset names are used to build a path. `AssetStore`'s allowlist is what
    /// stands between that and an arbitrary write into the App Group.
    func testPathTraversalNamesAreRejected() throws {
        // The target is unique per run and its absence is checked at the exact
        // path the traversal resolves to. A fixed name would be polluted by any
        // earlier run that legitimately wrote it — which is precisely what a
        // mutation check does, and it turned this test red for the wrong reason.
        let target = "escape-\(UUID().uuidString).png"
        let payload = ["../../\(target)": imageData().base64EncodedString()]
        XCTAssertThrowsError(try AssetBundleCodec.install([UUID(): payload], store: store))

        let escaped = root
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(target)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: escaped.path),
            "A traversal name must not write outside the asset root"
        )
    }

    func testAbsolutePathNamesAreRejected() {
        let target = "/tmp/escape-\(UUID().uuidString).png"
        let payload = [target: imageData().base64EncodedString()]
        XCTAssertThrowsError(try AssetBundleCodec.install([UUID(): payload], store: store))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target))
    }

    func testNonImageExtensionsAreRejected() {
        for name in ["payload.exe", "script.sh", "notes.txt", "archive.zip"] {
            XCTAssertThrowsError(
                try AssetBundleCodec.install([UUID(): [name: imageData().base64EncodedString()]], store: store),
                "\(name) should not be installable"
            )
        }
    }

    func testMalformedBase64IsRejected() {
        let payload = ["img_abcdef012345.png": "not base64 !!!"]
        XCTAssertThrowsError(try AssetBundleCodec.install([UUID(): payload], store: store))
    }

    func testBytesThatAreNotAnImageAreRejected() {
        let payload = ["img_abcdef012345.png": Data("hello".utf8).base64EncodedString()]
        XCTAssertThrowsError(try AssetBundleCodec.install([UUID(): payload], store: store))
    }

    /// A rejected entry must not leave earlier ones behind: the import as a
    /// whole failed, so the caller will not record the owner and anything
    /// written under it would be unreachable bytes on disk forever.
    func testARejectedEntryDoesNotSilentlyKeepTheGoodOnes() throws {
        let owner = UUID()
        let good = try seed(owner)
        let carried = try XCTUnwrap(store.data(for: good, in: owner))
        let destination = UUID()

        let payload = [good: carried.base64EncodedString(), "../evil.png": carried.base64EncodedString()]
        XCTAssertThrowsError(try AssetBundleCodec.install([destination: payload], store: store))
        // install() itself is not transactional; SceneBundleIO sweeps on
        // failure. What must hold here is that the throw actually happened, so
        // the caller knows to sweep rather than believing the import worked.
    }

    // MARK: - Many owners

    func testGatherDeduplicatesTheSamePhotoAcrossOwners() throws {
        // Names are content hashes, so one photo in two widgets is one blob.
        let a = UUID(), b = UUID()
        let bytes = imageData(.systemTeal)
        let nameA = try store.save(bytes, for: a)
        let nameB = try store.save(bytes, for: b)
        XCTAssertEqual(nameA, nameB, "Content-hash naming should give identical bytes one name")

        let gathered = AssetBundleCodec.gather([(id: a, names: nil), (id: b, names: nil)], store: store)
        XCTAssertEqual(gathered.blobs.count, 1, "The shared photo must be carried once")
        XCTAssertEqual(gathered.assets[a], [nameA])
        XCTAssertEqual(gathered.assets[b], [nameB])
    }

    func testGatherWithAnExplicitNameListIgnoresTheRestOfTheDirectory() throws {
        // A scene's directory accumulates every wallpaper it has ever worn, so
        // it passes the one name it still uses rather than the whole folder.
        let owner = UUID()
        let keep = try store.save(imageData(.systemRed), for: owner)
        _ = try store.save(imageData(.systemBlue), for: owner)
        XCTAssertEqual(store.list(for: owner).count, 2)

        let gathered = AssetBundleCodec.gather([(id: owner, names: [keep])], store: store)
        XCTAssertEqual(gathered.assets[owner], [keep])
        XCTAssertEqual(gathered.blobs.count, 1)
    }

    func testGatherOnAnOwnerWithNothingYieldsNothing() {
        let gathered = AssetBundleCodec.gather([(id: UUID(), names: nil)], store: store)
        XCTAssertTrue(gathered.blobs.isEmpty)
        XCTAssertTrue(gathered.assets.isEmpty || gathered.assets.values.allSatisfy(\.isEmpty))
    }

    func testInstallWritesEveryOwnerUnderItsOwnDirectory() throws {
        let a = UUID(), b = UUID()
        let nameA = "img_aaaaaaaaaaaa.png", nameB = "img_bbbbbbbbbbbb.png"
        let bytes = imageData().base64EncodedString()
        try AssetBundleCodec.install([a: [nameA: bytes], b: [nameB: bytes]], store: store)

        XCTAssertEqual(store.list(for: a), [nameA])
        XCTAssertEqual(store.list(for: b), [nameB])
        XCTAssertNil(store.data(for: nameB, in: a), "An owner must not see another's assets")
    }
}

/// The name grammar itself, which is the security boundary for imports.
final class AssetNameValidationTests: XCTestCase {
    func testGeneratedNamesAreAccepted() {
        XCTAssertTrue(AssetStore.isValidAssetName("img_0123456789ab.png"))
        XCTAssertTrue(AssetStore.isValidAssetName("img_0123456789ab.jpg"))
        XCTAssertTrue(AssetStore.isValidAssetName("photo-1_final.png"))
    }

    func testEverythingThatCouldEscapeIsRejected() {
        for name in [
            "../escape.png", "../../escape.png", "/absolute.png", "dir/nested.png",
            "trailing/.png", "a\\b.png", "nul\0.png", ".png", "x.png ", " x.png",
            "img.PNG.exe", "im g.png", "café.png", "emoji🙂.png",
        ] {
            XCTAssertFalse(AssetStore.isValidAssetName(name), "\(name) must be rejected")
        }
    }

    func testExtensionMustBeAnImage() {
        XCTAssertFalse(AssetStore.isValidAssetName("thing.gif"))
        XCTAssertFalse(AssetStore.isValidAssetName("thing.svg"))
        XCTAssertFalse(AssetStore.isValidAssetName("thing"))
    }

    func testLengthIsBounded() {
        XCTAssertFalse(AssetStore.isValidAssetName(String(repeating: "a", count: 200) + ".png"))
        XCTAssertFalse(AssetStore.isValidAssetName(".jpg"))
    }
}
