import XCTest
@testable import FacetCore

/// The bundle is what makes a scene shareable, and the thing it must never do
/// is land on top of widgets the receiving user already has. Most of what
/// follows is about that: the round trip proves the screen survives, the
/// collision tests prove it survives *without* touching anything else.
final class SceneBundleTests: XCTestCase {

    // MARK: - Fixtures

    private static let sceneID = UUID(uuidString: "5CE9E000-0000-4000-8000-000000000001")!
    private static let documentA = UUID(uuidString: "D0C00000-0000-4000-8000-0000000000A0")!
    private static let documentB = UUID(uuidString: "D0C00000-0000-4000-8000-0000000000B0")!
    private static let placement0 = UUID(uuidString: "51ACE000-0000-4000-8000-0000000000F1")!
    private static let placement1 = UUID(uuidString: "51ACE000-0000-4000-8000-0000000000F2")!
    private static let placement2 = UUID(uuidString: "51ACE000-0000-4000-8000-0000000000F3")!

    /// Two photos and a wallpaper. `shared.jpg` is deliberately used by both
    /// documents — asset names are content hashes, so that is what "the same
    /// photo in two widgets" actually looks like on disk.
    private static let wallpaper = "img_aaaa0000aaaa0000aaaa.jpg"
    private static let shared = "img_bbbb1111bbbb1111bbbb.jpg"
    private static let onlyB = "img_cccc2222cccc2222cccc.png"

    private func document(id: UUID, name: String, text: String) -> WidgetDocument {
        WidgetDocument(
            id: id,
            name: name,
            tokens: ThemeTokens(colors: [
                "primary": ColorToken(light: ColorValue(hex: "#111111")!, dark: ColorValue(hex: "#EEEEEE")!),
            ]),
            root: Layer(
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("primary"),
                    children: [
                        Layer(
                            name: "Photo",
                            frame: LayerFrame(x: 0.5, y: 0.5, width: 1, height: 1),
                            content: .image(ImageContent(assetName: Self.shared))
                        ),
                        Layer(
                            name: "Label",
                            content: .text(TextContent(
                                text: text,
                                font: .token("display"),
                                color: .token("primary")
                            ))
                        ),
                    ]
                ))
            ),
            sources: ["time"]
        )
    }

    private func sampleScene() -> FacetScene {
        FacetScene(
            id: Self.sceneID,
            name: "Dusk",
            backdrop: Self.wallpaper,
            placements: [
                ScenePlacement(id: Self.placement0, documentID: Self.documentA,
                               rendition: .systemSmall, column: 0, row: 0),
                ScenePlacement(id: Self.placement1, documentID: Self.documentB,
                               rendition: .systemMedium, column: 0, row: 2),
                // The same design placed twice — one document, two placements,
                // which is the whole reason a placement stores a reference.
                ScenePlacement(id: Self.placement2, documentID: Self.documentA,
                               rendition: .systemSmall, column: 2, row: 0),
            ],
            palette: ThemeTokens(colors: [
                "accent": ColorToken(light: ColorValue(hex: "#FF9F0A")!, dark: ColorValue(hex: "#FFB340")!),
            ])
        )
    }

    private func sampleBundle() -> SceneBundle {
        SceneBundle(
            scene: sampleScene(),
            documents: [
                document(id: Self.documentA, name: "Clock", text: "9:41"),
                document(id: Self.documentB, name: "Weather", text: "18°"),
            ],
            blobs: [
                Self.wallpaper: "d2FsbHBhcGVy",
                Self.shared: "c2hhcmVk",
                Self.onlyB: "b25seUI=",
            ],
            assets: [
                Self.sceneID: [Self.wallpaper],
                Self.documentA: [Self.shared],
                Self.documentB: [Self.shared, Self.onlyB],
            ]
        )
    }

    /// Ids handed out in a predictable order, so a failure names the identity
    /// that went wrong instead of a fresh random one.
    private final class IDSequence {
        private var next = 0
        var issued: [UUID] = []
        func callAsFunction() -> UUID {
            next += 1
            let id = UUID(uuidString: String(format: "9E000000-0000-4000-8000-%012d", next))!
            issued.append(id)
            return id
        }
    }

    // MARK: - Round trip

    func testBundleRoundTripsLosslessly() throws {
        let bundle = sampleBundle()
        let decoded = try SceneBundleFile.decode(try SceneBundleFile.encode(bundle))
        XCTAssertEqual(decoded, bundle)
        XCTAssertEqual(decoded.schemaVersion, SceneBundle.currentSchemaVersion)
        XCTAssertEqual(decoded.scene, bundle.scene)
        XCTAssertEqual(decoded.documents, bundle.documents)
        XCTAssertEqual(decoded.blobs, bundle.blobs)
        XCTAssertEqual(decoded.assets, bundle.assets)

        // Two hops, in case the first decode normalizes something away.
        XCTAssertEqual(try SceneBundleFile.decode(try SceneBundleFile.encode(decoded)), bundle)
    }

    func testEncodingIsByteStable() throws {
        let bundle = sampleBundle()
        let data = try SceneBundleFile.encode(bundle)
        XCTAssertEqual(try SceneBundleFile.encode(bundle), data)
        XCTAssertEqual(try SceneBundleFile.encode(try SceneBundleFile.decode(data)), data)
    }

    func testEmptySceneBundlesRoundTrip() throws {
        let bundle = SceneBundle(scene: FacetScene(name: "Blank"))
        let decoded = try SceneBundleFile.decode(try SceneBundleFile.encode(bundle))
        XCTAssertEqual(decoded, bundle)
        XCTAssertTrue(decoded.documents.isEmpty)
        XCTAssertTrue(decoded.blobs.isEmpty)
        XCTAssertTrue(decoded.assets.isEmpty)

        // An empty payload writes no keys at all, so a photoless scene bundle
        // stays as small as the scene file it grew out of.
        let json = String(data: try SceneBundleFile.encode(bundle), encoding: .utf8)!
        XCTAssertFalse(json.contains("blobs"), json)
        XCTAssertFalse(json.contains("assets"), json)
    }

    /// The end-to-end claim: export, import, and the screen you get is the
    /// screen you sent — same wallpaper, same widgets, same slots.
    func testExportThenImportReproducesTheSameScreen() throws {
        let original = sampleBundle()
        let decoded = try SceneBundleFile.decode(try SceneBundleFile.encode(original))
        let imported = decoded.imported()

        XCTAssertEqual(imported.scene.name, original.scene.name)
        XCTAssertEqual(imported.scene.backdrop, original.scene.backdrop)
        XCTAssertEqual(imported.scene.palette, original.scene.palette)
        XCTAssertEqual(imported.scene.placements.count, original.scene.placements.count)

        for (new, old) in zip(imported.scene.placements, original.scene.placements) {
            XCTAssertEqual(new.rendition, old.rendition)
            XCTAssertEqual(new.column, old.column)
            XCTAssertEqual(new.row, old.row)
        }

        // Every placement resolves to a document that arrived with the bundle,
        // and to the *same design* the sender had in that slot.
        let byID = Dictionary(uniqueKeysWithValues: imported.documents.map { ($0.id, $0) })
        for (new, old) in zip(imported.scene.placements, original.scene.placements) {
            let landed = try XCTUnwrap(byID[new.documentID], "placement lost its design")
            let sent = try XCTUnwrap(original.documents.first { $0.id == old.documentID })
            assertSameDesign(landed, sent)
        }

        // The two placements that shared a design still share it afterwards —
        // a scene is a composition, and duplicating the widget would change it.
        XCTAssertEqual(imported.scene.placements[0].documentID, imported.scene.placements[2].documentID)
        XCTAssertEqual(imported.documents.count, 2, "one document per design, not per placement")
    }

    func testAssetsFollowTheirOwnersNewIdentity() {
        let bundle = sampleBundle()
        let imported = bundle.imported()

        let newA = try! XCTUnwrap(imported.documentIDs[Self.documentA])
        let newB = try! XCTUnwrap(imported.documentIDs[Self.documentB])

        // The wallpaper is keyed by the *scene's* id, not a document's.
        XCTAssertEqual(imported.assets[imported.scene.id]?[Self.wallpaper], "d2FsbHBhcGVy")
        XCTAssertEqual(imported.assets[newA]?[Self.shared], "c2hhcmVk")
        XCTAssertEqual(imported.assets[newB]?[Self.shared], "c2hhcmVk")
        XCTAssertEqual(imported.assets[newB]?[Self.onlyB], "b25seUI=")

        // Nothing is filed under an identity that no longer exists.
        XCTAssertNil(imported.assets[Self.sceneID])
        XCTAssertNil(imported.assets[Self.documentA])
        XCTAssertNil(imported.assets[Self.documentB])

        // Asset *names* are content hashes and must survive untouched: the
        // layers reference them by name, and re-hashing would orphan every one.
        guard case .container(let canvas) = imported.documents[0].root.content else {
            return XCTFail("the root stopped being a container")
        }
        let photoLayer = canvas.children.first { layer in
            if case .image = layer.content { return true }
            return false
        }
        if case .image(let image)? = photoLayer?.content {
            XCTAssertEqual(image.assetName, Self.shared)
        } else {
            XCTFail("the image layer went missing")
        }
    }

    func testSharedPhotoIsCarriedOnce() throws {
        let bundle = sampleBundle()
        // Two owners want `shared.jpg`; the blob table holds one copy of it.
        XCTAssertEqual(bundle.assets[Self.documentA], [Self.shared])
        XCTAssertTrue(bundle.assets[Self.documentB]?.contains(Self.shared) == true)
        XCTAssertEqual(bundle.blobs.count, 3, "three distinct photos, three blobs")

        let json = String(data: try SceneBundleFile.encode(bundle), encoding: .utf8)!
        let occurrences = json.components(separatedBy: "c2hhcmVk").count - 1
        XCTAssertEqual(occurrences, 1, "the shared photo's bytes appear once in the file")
    }

    // MARK: - Identity, and not clobbering anything

    func testEveryIdentityIsFresh() {
        let ids = IDSequence()
        let bundle = sampleBundle()
        let imported = bundle.imported(newID: ids.callAsFunction)

        XCTAssertNotEqual(imported.scene.id, Self.sceneID)
        XCTAssertEqual(imported.sceneID.old, Self.sceneID)
        XCTAssertEqual(imported.sceneID.new, imported.scene.id)

        for document in imported.documents {
            XCTAssertNotEqual(document.id, Self.documentA)
            XCTAssertNotEqual(document.id, Self.documentB)
        }
        for (new, old) in zip(imported.scene.placements, bundle.scene.placements) {
            XCTAssertNotEqual(new.id, old.id, "placement ids are fresh too")
        }

        // Every id the import produced came out of the generator, and none of
        // them repeats — a duplicate placement id would make two widgets the
        // same drag target the moment the scene is opened.
        let produced = [imported.scene.id]
            + imported.documents.map(\.id)
            + imported.scene.placements.map(\.id)
        XCTAssertEqual(Set(produced).count, produced.count)
        XCTAssertTrue(Set(produced).isSubset(of: Set(ids.issued)))
    }

    /// The case that matters most: a bundle whose widgets carry the *same ids*
    /// as widgets already in the library. Nothing existing may be touched.
    func testImportingOntoExistingIdsOverwritesNothing() throws {
        // The library already holds documents under exactly the bundle's ids —
        // different designs, the user's own work.
        var library: [UUID: WidgetDocument] = [
            Self.documentA: document(id: Self.documentA, name: "My Clock", text: "MINE"),
            Self.documentB: document(id: Self.documentB, name: "My Weather", text: "ALSO MINE"),
        ]
        let before = library
        var scenes: [UUID: FacetScene] = [Self.sceneID: FacetScene(name: "My Scene")]
        scenes[Self.sceneID]?.id = Self.sceneID
        let scenesBefore = scenes

        let imported = try SceneBundleFile.decode(try SceneBundleFile.encode(sampleBundle())).imported()

        // Apply the import the way the app does: save each document, save the
        // scene. If the policy were wrong, these writes would land on the keys
        // above and the assertions after them would fail.
        for document in imported.documents { library[document.id] = document }
        scenes[imported.scene.id] = imported.scene

        for (id, original) in before {
            XCTAssertEqual(library[id], original, "existing widget \(id) was modified by an import")
        }
        for (id, original) in scenesBefore {
            XCTAssertEqual(scenes[id], original, "existing scene \(id) was modified by an import")
        }
        XCTAssertEqual(library.count, 4, "the import added, it did not replace")
        XCTAssertEqual(scenes.count, 2)

        // And the imported scene points at the imported copies, never at the
        // user's same-id originals.
        for placement in imported.scene.placements {
            XCTAssertNotEqual(placement.documentID, Self.documentA)
            XCTAssertNotEqual(placement.documentID, Self.documentB)
            XCTAssertNotNil(imported.documents.first { $0.id == placement.documentID })
        }
    }

    func testImportingTheSameBundleTwiceDoesNotOverwriteTheFirstImport() throws {
        let data = try SceneBundleFile.encode(sampleBundle())
        let first = try SceneBundleFile.decode(data).imported()
        let second = try SceneBundleFile.decode(data).imported()

        XCTAssertNotEqual(first.scene.id, second.scene.id)
        XCTAssertTrue(Set(first.documents.map(\.id)).isDisjoint(with: Set(second.documents.map(\.id))))
        XCTAssertTrue(
            Set(first.scene.placements.map(\.id))
                .isDisjoint(with: Set(second.scene.placements.map(\.id)))
        )
        // Assets too: the second copy's photos must not be written over the
        // first copy's, or editing one would change the other.
        XCTAssertTrue(Set(first.assets.keys).isDisjoint(with: Set(second.assets.keys)))
    }

    func testPlacementWithNoCarriedDocumentDanglesRatherThanRebinding() {
        var bundle = sampleBundle()
        // The sender's scene references a design the bundle failed to carry.
        bundle.documents.removeAll { $0.id == Self.documentB }
        let imported = bundle.imported()

        let orphan = imported.scene.placements[1]
        XCTAssertNotEqual(
            orphan.documentID, Self.documentB,
            "keeping the sender's id could bind this slot to an unrelated local widget"
        )
        XCTAssertNil(imported.documents.first { $0.id == orphan.documentID })
        XCTAssertEqual(imported.scene.placements.count, 3, "the slot is kept, so the gap is visible")

        // The placements that did travel are unaffected.
        XCTAssertNotNil(imported.documents.first { $0.id == imported.scene.placements[0].documentID })
    }

    func testDuplicateDocumentIdsInAMalformedBundleStillGetDistinctIdentities() {
        var bundle = sampleBundle()
        bundle.documents.append(document(id: Self.documentA, name: "Impostor", text: "?"))
        let imported = bundle.imported()

        XCTAssertEqual(imported.documents.count, 3)
        XCTAssertEqual(Set(imported.documents.map(\.id)).count, 3, "neither copy overwrites the other")
        // Placements resolve to the first of the two, deterministically.
        let first = imported.documents[0]
        XCTAssertEqual(imported.scene.placements[0].documentID, first.id)
        XCTAssertEqual(first.name, "Clock")
    }

    func testAssetsForAnUnknownOwnerAreDropped() {
        var bundle = sampleBundle()
        let stranger = UUID()
        bundle.assets[stranger] = [Self.onlyB]
        let imported = bundle.imported()

        XCTAssertNil(imported.assets[stranger])
        XCTAssertEqual(
            imported.assets.count, 3,
            "the scene and the two documents own everything that lands on disk"
        )
    }

    // MARK: - Payloads

    func testPayloadDropsNamesWithNoBytes() {
        var bundle = sampleBundle()
        bundle.assets[Self.documentA] = [Self.shared, "img_missing0000missing.jpg"]
        XCTAssertEqual(bundle.payload(for: Self.documentA), [Self.shared: "c2hhcmVk"])
        XCTAssertEqual(bundle.payload(for: UUID()), [:])

        // And the missing name does not reach the store as an empty write.
        let imported = bundle.imported()
        let newA = imported.documentIDs[Self.documentA]!
        XCTAssertEqual(imported.assets[newA]?.count, 1)
    }

    func testPayloadByteCountMeasuresWhatTravels() {
        let bundle = sampleBundle()
        let expected = ["d2FsbHBhcGVy", "c2hhcmVk", "b25seUI="].reduce(0) { $0 + $1.count }
        XCTAssertEqual(bundle.payloadByteCount, expected)
        XCTAssertEqual(SceneBundle(scene: FacetScene(name: "x")).payloadByteCount, 0)
    }

    func testReferencedDocumentIDsDedupeInPlacementOrder() {
        XCTAssertEqual(sampleScene().referencedDocumentIDs, [Self.documentA, Self.documentB])
        XCTAssertEqual(FacetScene(name: "Empty").referencedDocumentIDs, [])
    }

    // MARK: - Format compatibility

    func testABareSceneFileStillImports() throws {
        // The pre-bundle `.facetscene`: no documents, no bytes. It has to open
        // — as a screen of empty slots, which is the honest result — rather
        // than be rejected as the wrong kind of file.
        let data = try SceneFile.encode(sampleScene())
        let bundle = try SceneBundleFile.decode(data)
        XCTAssertEqual(bundle.scene.name, "Dusk")
        XCTAssertTrue(bundle.documents.isEmpty)
        XCTAssertTrue(bundle.blobs.isEmpty)

        let imported = bundle.imported()
        XCTAssertEqual(imported.scene.placements.count, 3)
        for placement in imported.scene.placements {
            XCTAssertNotEqual(placement.documentID, Self.documentA)
            XCTAssertNotEqual(placement.documentID, Self.documentB)
        }
    }

    func testBundlesAndBareScenesAreToldApartBothWays() throws {
        // A bundle must not decode as a bare scene (it has no top-level id or
        // name), and a bare scene must not decode as a bundle (no `scene` key).
        let bundleData = try SceneBundleFile.encode(sampleBundle())
        XCTAssertThrowsError(try SceneFile.decode(bundleData))

        let sceneData = try SceneFile.encode(sampleScene())
        XCTAssertThrowsError(try JSONDecoder().decode(SceneBundle.self, from: sceneData))
        XCTAssertNoThrow(try SceneBundleFile.decode(sceneData))
    }

    func testNonSceneDataIsRejected() {
        XCTAssertThrowsError(try SceneBundleFile.decode(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? SceneBundleError, .notASceneFile)
        }
        XCTAssertThrowsError(try SceneBundleFile.decode(Data(#"{"hello": 1}"#.utf8))) { error in
            XCTAssertEqual(error as? SceneBundleError, .notASceneFile)
        }
        // A `.facet` document is not a scene either.
        let document = try! FacetFile.encode(document(id: Self.documentA, name: "Solo", text: "x"))
        XCTAssertThrowsError(try SceneBundleFile.decode(document))
    }

    func testFutureSchemaVersionIsRejected() throws {
        var bundle = sampleBundle()
        bundle.schemaVersion = SceneBundle.currentSchemaVersion + 1
        XCTAssertThrowsError(try SceneBundleFile.decode(try SceneBundleFile.encode(bundle))) { error in
            XCTAssertEqual(
                error as? SceneBundleError,
                .unsupportedSchemaVersion(SceneBundle.currentSchemaVersion + 1)
            )
        }
        bundle.schemaVersion = SceneBundle.currentSchemaVersion
        XCTAssertNoThrow(try SceneBundleFile.decode(try SceneBundleFile.encode(bundle)))
    }

    func testUnknownKeysAreIgnoredAndOptionalOnesMayBeAbsent() throws {
        let json = """
        {"scene": {"id": "5CE9E000-0000-4000-8000-000000000001", "name": "Future"},
         "documents": [], "widgetStack": {"mode": "smart"}}
        """
        let bundle = try SceneBundleFile.decode(Data(json.utf8))
        XCTAssertEqual(bundle.scene.name, "Future")
        XCTAssertEqual(bundle.schemaVersion, 1, "a missing schemaVersion reads as v1")
        XCTAssertTrue(bundle.blobs.isEmpty)
        XCTAssertTrue(bundle.assets.isEmpty)
    }

    func testAssetOwnerThatIsNotAUUIDIsRejected() {
        // Owner keys index directories in the shared container. A key that is
        // not a UUID has no business reaching the store.
        let json = """
        {"scene": {"id": "5CE9E000-0000-4000-8000-000000000001", "name": "Hostile"},
         "documents": [], "assets": {"../../../etc": ["img_x.jpg"]}}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(SceneBundle.self, from: Data(json.utf8)))
        // And it does not quietly fall through to the bare-scene path either.
        XCTAssertThrowsError(try SceneBundleFile.decode(Data(json.utf8)))
    }

    // MARK: - Helpers

    private func assertSameDesign(
        _ actual: WidgetDocument,
        _ expected: WidgetDocument,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var normalized = actual
        normalized.id = expected.id
        XCTAssertEqual(normalized, expected, "the design changed in transit", file: file, line: line)
    }
}
