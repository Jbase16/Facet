import XCTest
@testable import FacetCore

final class SceneTests: XCTestCase {

    // MARK: - Fixtures

    // Fixed UUIDs so a failure message names the placement that broke rather
    // than a fresh random one.
    private static let sceneID = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000001")!
    private static let documentA = UUID(uuidString: "0A1B2C3D-0000-4000-8000-0000000000A0")!
    private static let documentB = UUID(uuidString: "0A1B2C3D-0000-4000-8000-0000000000B0")!
    private static let placementIDs = [
        UUID(uuidString: "0A1B2C3D-0000-4000-8000-0000000000F1")!,
        UUID(uuidString: "0A1B2C3D-0000-4000-8000-0000000000F2")!,
        UUID(uuidString: "0A1B2C3D-0000-4000-8000-0000000000F3")!,
        UUID(uuidString: "0A1B2C3D-0000-4000-8000-0000000000F4")!,
    ]

    /// A scene that exercises every serialized field: backdrop, a mixed set of
    /// placements laid out legally on the 4x6 grid, and a non-empty palette.
    private func sampleScene() -> FacetScene {
        FacetScene(
            id: Self.sceneID,
            name: "Dusk",
            backdrop: "img_dusk_ridge",
            placements: [
                ScenePlacement(id: Self.placementIDs[0], documentID: Self.documentA,
                               rendition: .systemSmall, column: 0, row: 0),
                ScenePlacement(id: Self.placementIDs[1], documentID: Self.documentB,
                               rendition: .systemSmall, column: 2, row: 0),
                ScenePlacement(id: Self.placementIDs[2], documentID: Self.documentA,
                               rendition: .systemMedium, column: 0, row: 2),
                ScenePlacement(id: Self.placementIDs[3], documentID: Self.documentB,
                               rendition: .accessoryCircular, column: 0, row: 4),
            ],
            palette: ThemeTokens(
                colors: [
                    "accent": ColorToken(light: ColorValue(hex: "#FF9F0A")!, dark: ColorValue(hex: "#FFB340")!),
                    "background": ColorToken(light: .white, dark: .black),
                ],
                fonts: ["display": FontToken(size: 34, weight: .semibold, design: .rounded)],
                spacing: ["gutter": 12]
            )
        )
    }

    // MARK: - Round trip

    func testRoundTripPreservesEverything() throws {
        let scene = sampleScene()
        let decoded = try SceneFile.decode(try SceneFile.encode(scene))
        XCTAssertEqual(decoded, scene)
        XCTAssertEqual(decoded.schemaVersion, FacetScene.currentSchemaVersion)
        XCTAssertEqual(decoded.backdrop, "img_dusk_ridge")
        XCTAssertEqual(decoded.placements.count, 4)
        XCTAssertEqual(decoded.palette, scene.palette)
    }

    func testPlacementsKeepStableIDsAndOrderThroughARoundTrip() throws {
        let scene = sampleScene()
        let decoded = try SceneFile.decode(try SceneFile.encode(scene))
        // Ids are the handle the editor uses to select and drag a placement;
        // if they churned on save the selection would jump on every reopen.
        XCTAssertEqual(decoded.placements.map(\.id), Self.placementIDs)
        XCTAssertEqual(decoded.placements.map(\.documentID), scene.placements.map(\.documentID))
        XCTAssertEqual(decoded.placements.map(\.rendition), scene.placements.map(\.rendition))
        XCTAssertEqual(decoded.placements.map(\.column), scene.placements.map(\.column))
        XCTAssertEqual(decoded.placements.map(\.row), scene.placements.map(\.row))
        XCTAssertEqual(decoded.id, Self.sceneID, "the scene's own id survives too")

        // Two hops, in case the first decode normalizes something away.
        let twice = try SceneFile.decode(try SceneFile.encode(decoded))
        XCTAssertEqual(twice, scene)
    }

    func testEncodedFormIsStableAndReadable() throws {
        let scene = sampleScene()
        let data = try SceneFile.encode(scene)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"), json)
        XCTAssertTrue(json.contains("\"backdrop\" : \"img_dusk_ridge\""), json)
        XCTAssertTrue(json.contains("\"rendition\" : \"systemSmall\""), json)
        XCTAssertTrue(json.contains("#FF9F0A"), "palette colors serialize as hex")

        // Sorted keys: encoding twice is byte-identical, so a scene diffs cleanly.
        XCTAssertEqual(try SceneFile.encode(scene), data)
        XCTAssertEqual(try SceneFile.encode(scene), try SceneFile.encode(scene))
        // And re-encoding what we decoded reproduces the same bytes.
        XCTAssertEqual(try SceneFile.encode(try SceneFile.decode(data)), data)
    }

    func testEmptySceneRoundTrips() throws {
        let scene = FacetScene(name: "Blank")
        let decoded = try SceneFile.decode(try SceneFile.encode(scene))
        XCTAssertEqual(decoded, scene)
        XCTAssertTrue(decoded.placements.isEmpty)
        XCTAssertEqual(decoded.palette, .empty)
        XCTAssertNil(decoded.backdrop)
    }

    // MARK: - Forward / back compatibility

    func testSceneWithoutOptionalKeysStillDecodes() throws {
        // The oldest possible scene file: nothing but the two required fields.
        // schemaVersion, backdrop, placements and palette are optional-with-default.
        let json = """
        {"id": "0A1B2C3D-0000-4000-8000-000000000001", "name": "Minimal"}
        """
        let scene = try SceneFile.decode(Data(json.utf8))
        XCTAssertEqual(scene.id, Self.sceneID)
        XCTAssertEqual(scene.name, "Minimal")
        XCTAssertEqual(scene.schemaVersion, 1, "a missing schemaVersion reads as v1")
        XCTAssertNil(scene.backdrop)
        XCTAssertEqual(scene.placements, [])
        XCTAssertEqual(scene.palette, .empty)
    }

    func testEachOptionalKeyCanBeMissingIndependently() throws {
        let full: [String: String] = [
            "schemaVersion": "1",
            "backdrop": "\"img_x\"",
            "placements": "[]",
            "palette": "{\"colors\": {}, \"fonts\": {}, \"spacing\": {}}",
        ]
        for omitted in full.keys {
            var fields = [
                "\"id\": \"0A1B2C3D-0000-4000-8000-000000000001\"",
                "\"name\": \"Partial\"",
            ]
            for (key, value) in full where key != omitted {
                fields.append("\"\(key)\": \(value)")
            }
            let json = "{" + fields.joined(separator: ", ") + "}"
            XCTAssertNoThrow(
                try SceneFile.decode(Data(json.utf8)),
                "omitting \(omitted) must still decode: \(json)"
            )
        }
    }

    func testUnknownKeysAreIgnored() throws {
        // A scene written by a newer build carries keys this build has never
        // heard of; they must be skipped, not rejected.
        let json = """
        {"id": "0A1B2C3D-0000-4000-8000-000000000001", "name": "Future",
         "placements": [], "blurRadius": 12, "widgetStack": {"mode": "smart"}}
        """
        let scene = try SceneFile.decode(Data(json.utf8))
        XCTAssertEqual(scene.name, "Future")
    }

    func testAbsentBackdropStaysAbsentInTheFile() throws {
        var scene = sampleScene()
        scene.backdrop = nil
        let json = String(data: try SceneFile.encode(scene), encoding: .utf8)!
        XCTAssertFalse(json.contains("backdrop"), "an absent backdrop writes no key: \(json)")
        XCTAssertNil(try SceneFile.decode(Data(json.utf8)).backdrop)
    }

    func testFutureSchemaVersionRejected() throws {
        var scene = sampleScene()
        scene.schemaVersion = FacetScene.currentSchemaVersion + 1
        XCTAssertThrowsError(try SceneFile.decode(try SceneFile.encode(scene))) { error in
            XCTAssertEqual(
                error as? DocumentError,
                .unsupportedSchemaVersion(FacetScene.currentSchemaVersion + 1)
            )
        }

        scene.schemaVersion = 999
        XCTAssertThrowsError(try SceneFile.decode(try SceneFile.encode(scene))) { error in
            XCTAssertEqual(error as? DocumentError, .unsupportedSchemaVersion(999))
        }

        // The current version and anything below it are accepted.
        scene.schemaVersion = FacetScene.currentSchemaVersion
        XCTAssertNoThrow(try SceneFile.decode(try SceneFile.encode(scene)))
        scene.schemaVersion = 0
        XCTAssertNoThrow(try SceneFile.decode(try SceneFile.encode(scene)))
    }

    func testMissingRequiredFieldsFail() {
        let noID = #"{"name": "Nameless"}"#
        let noName = #"{"id": "0A1B2C3D-0000-4000-8000-000000000001"}"#
        XCTAssertThrowsError(try SceneFile.decode(Data(noID.utf8)))
        XCTAssertThrowsError(try SceneFile.decode(Data(noName.utf8)))
    }

    /// Documents current strictness: unlike `FacetScene`, `ScenePlacement` uses
    /// the synthesized decoder, so every one of its keys is required. Any field
    /// added to `ScenePlacement` later must be optional-with-default or existing
    /// `.facetscene` files stop loading.
    func testPlacementDecodingFillsInMissingFields() throws {
        let complete = """
        {"id": "0A1B2C3D-0000-4000-8000-0000000000F1",
         "documentID": "0A1B2C3D-0000-4000-8000-0000000000A0",
         "rendition": "systemMedium", "column": 2, "row": 4}
        """
        let full = try JSONDecoder().decode(ScenePlacement.self, from: Data(complete.utf8))
        XCTAssertEqual(full.documentID, Self.documentA)
        XCTAssertEqual(full.rendition, .systemMedium)
        XCTAssertEqual(full.column, 2)
        XCTAssertEqual(full.row, 4)

        // Every field but the document defaults, so a scene written before a
        // field existed still opens instead of failing the whole file.
        let sparse = """
        {"documentID": "0A1B2C3D-0000-4000-8000-0000000000A0"}
        """
        let filled = try JSONDecoder().decode(ScenePlacement.self, from: Data(sparse.utf8))
        XCTAssertEqual(filled.documentID, Self.documentA)
        XCTAssertEqual(filled.rendition, .systemSmall)
        XCTAssertEqual(filled.column, 0)
        XCTAssertEqual(filled.row, 0)
    }

    func testPlacementWithoutADocumentIsRejected() {
        // The one field with no sensible default: a placement that names no
        // design has nothing to draw, so it is a corrupt record, not an old one.
        let orphan = """
        {"rendition": "systemSmall", "column": 0, "row": 0}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(ScenePlacement.self, from: Data(orphan.utf8)))
    }

    func testDecodedPlacementsGetDistinctIDsWhenTheFileOmitsThem() throws {
        // A defaulted id must not collide, or two placements become the same
        // drag target the moment the scene is edited.
        let json = """
        [{"documentID": "0A1B2C3D-0000-4000-8000-0000000000A0"},
         {"documentID": "0A1B2C3D-0000-4000-8000-0000000000A0"}]
        """
        let placements = try JSONDecoder().decode([ScenePlacement].self, from: Data(json.utf8))
        XCTAssertEqual(placements.count, 2)
        XCTAssertNotEqual(placements[0].id, placements[1].id)
    }

    // MARK: - Span

    func testSpanPerRendition() {
        XCTAssertEqual(Self.span(of: .systemSmall).columns, 2)
        XCTAssertEqual(Self.span(of: .systemSmall).rows, 2)
        XCTAssertEqual(Self.span(of: .systemMedium).columns, 4)
        XCTAssertEqual(Self.span(of: .systemMedium).rows, 2)
        XCTAssertEqual(Self.span(of: .systemLarge).columns, 4)
        XCTAssertEqual(Self.span(of: .systemLarge).rows, 4)
    }

    func testAccessoryRenditionsFallBackToASmallSpan() {
        for rendition in [RenditionKind.accessoryCircular, .accessoryRectangular, .accessoryInline] {
            let span = Self.span(of: rendition)
            XCTAssertEqual(span.columns, 2, "\(rendition)")
            XCTAssertEqual(span.rows, 2, "\(rendition)")
        }
    }

    func testSpanIgnoresPosition() {
        for rendition in RenditionKind.allCases {
            let atOrigin = ScenePlacement(documentID: Self.documentA, rendition: rendition)
            let moved = ScenePlacement(documentID: Self.documentA, rendition: rendition, column: 3, row: 5)
            XCTAssertEqual(atOrigin.span.columns, moved.span.columns, "\(rendition)")
            XCTAssertEqual(atOrigin.span.rows, moved.span.rows, "\(rendition)")
        }
    }

    func testEverySpanIsPositive() {
        // A zero or negative span would make `overlaps` silently return false
        // for everything, which is exactly the stacking bug it exists to stop.
        for rendition in RenditionKind.allCases {
            let span = Self.span(of: rendition)
            XCTAssertGreaterThan(span.columns, 0, "\(rendition)")
            XCTAssertGreaterThan(span.rows, 0, "\(rendition)")
        }
    }

    // MARK: - Overlap, against a brute-force oracle

    /// `overlaps` is an interval-arithmetic shortcut. The ground truth is the
    /// set of icon cells a placement covers, so this builds those sets directly
    /// and checks the shortcut against set intersection for every rendition
    /// pairing at every position in and just outside the grid.
    func testOverlapsAgreesWithCellSetIntersectionEverywhere() {
        var probes: [(placement: ScenePlacement, cells: Set<Cell>)] = []
        for rendition in RenditionKind.allCases {
            for column in -2...5 {
                for row in -2...7 {
                    let placement = ScenePlacement(
                        documentID: Self.documentA, rendition: rendition, column: column, row: row
                    )
                    probes.append((placement, Self.cells(of: placement)))
                }
            }
        }
        XCTAssertEqual(probes.count, RenditionKind.allCases.count * 8 * 10)

        var comparisons = 0
        var disagreements = 0
        var trueCases = 0
        for a in probes {
            for b in probes {
                comparisons += 1
                let expected = !a.cells.isDisjoint(with: b.cells)
                if expected { trueCases += 1 }
                if a.placement.overlaps(b.placement) != expected {
                    disagreements += 1
                    if disagreements == 1 {
                        XCTFail("""
                        overlaps disagreed with the cell oracle.
                        a: \(a.placement.rendition) at (\(a.placement.column),\(a.placement.row)) \
                        span \(a.placement.span)
                        b: \(b.placement.rendition) at (\(b.placement.column),\(b.placement.row)) \
                        span \(b.placement.span)
                        overlaps said \(a.placement.overlaps(b.placement)), cells say \(expected)
                        """)
                    }
                }
            }
        }
        XCTAssertEqual(disagreements, 0, "\(disagreements) of \(comparisons) pairs disagreed")
        // Guard the oracle itself: a sweep that never sees an overlap, or sees
        // nothing but overlaps, would pass vacuously.
        XCTAssertGreaterThan(trueCases, 0)
        XCTAssertLessThan(trueCases, comparisons)
    }

    func testOverlapsIsSymmetricAndReflexive() {
        for rendition in RenditionKind.allCases {
            for other in RenditionKind.allCases {
                for column in -1...4 {
                    for row in -1...6 {
                        let a = ScenePlacement(documentID: Self.documentA, rendition: rendition)
                        let b = ScenePlacement(
                            documentID: Self.documentB, rendition: other, column: column, row: row
                        )
                        if a.overlaps(b) != b.overlaps(a) {
                            return XCTFail("asymmetric: \(rendition)@(0,0) vs \(other)@(\(column),\(row))")
                        }
                        if !a.overlaps(a) || !b.overlaps(b) {
                            return XCTFail("a placement must overlap itself")
                        }
                    }
                }
            }
        }
    }

    func testTouchingEdgesDoNotCountAsOverlap() {
        let small = ScenePlacement(documentID: Self.documentA, rendition: .systemSmall, column: 0, row: 0)

        // Side by side, sharing a column boundary.
        let right = ScenePlacement(documentID: Self.documentB, rendition: .systemSmall, column: 2, row: 0)
        XCTAssertFalse(small.overlaps(right))
        XCTAssertFalse(right.overlaps(small))

        // Stacked, sharing a row boundary.
        let below = ScenePlacement(documentID: Self.documentB, rendition: .systemSmall, column: 0, row: 2)
        XCTAssertFalse(small.overlaps(below))

        // Corner to corner.
        let diagonal = ScenePlacement(documentID: Self.documentB, rendition: .systemSmall, column: 2, row: 2)
        XCTAssertFalse(small.overlaps(diagonal))

        // One cell in from each of those is a real collision.
        for shifted in [
            ScenePlacement(documentID: Self.documentB, rendition: .systemSmall, column: 1, row: 0),
            ScenePlacement(documentID: Self.documentB, rendition: .systemSmall, column: 0, row: 1),
            ScenePlacement(documentID: Self.documentB, rendition: .systemSmall, column: 1, row: 1),
        ] {
            XCTAssertTrue(small.overlaps(shifted), "(\(shifted.column),\(shifted.row)) should collide")
        }

        // A medium spans the full width, so a small anywhere on its two rows hits it.
        let medium = ScenePlacement(documentID: Self.documentA, rendition: .systemMedium, column: 0, row: 2)
        XCTAssertFalse(medium.overlaps(small), "rows 0-1 sit above rows 2-3")
        for column in 0...2 {
            let onTheSameRows = ScenePlacement(
                documentID: Self.documentB, rendition: .systemSmall, column: column, row: 2
            )
            XCTAssertTrue(medium.overlaps(onTheSameRows), "column \(column)")
        }

        // A large covers rows 2-5; a small at rows 0-1 clears it, one at row 5 does not.
        let large = ScenePlacement(documentID: Self.documentA, rendition: .systemLarge, column: 0, row: 2)
        XCTAssertFalse(large.overlaps(small))
        XCTAssertTrue(large.overlaps(
            ScenePlacement(documentID: Self.documentB, rendition: .systemSmall, column: 2, row: 4)
        ))
    }

    // MARK: - freeSlot

    func testEmptySceneOffersTheOriginToEveryRendition() {
        let scene = FacetScene(name: "Empty")
        for rendition in RenditionKind.allCases {
            let slot = scene.freeSlot(for: rendition)
            XCTAssertNotNil(slot, "\(rendition) should fit on an empty screen")
            XCTAssertEqual(slot?.column, 0, "\(rendition)")
            XCTAssertEqual(slot?.row, 0, "\(rendition)")
        }
    }

    func testFreeSlotSkipsPastWhatIsAlreadyThere() {
        var scene = FacetScene(name: "Partly full")
        scene.placements = [
            ScenePlacement(documentID: Self.documentA, rendition: .systemSmall, column: 0, row: 0),
        ]
        // Next small goes beside it; a medium needs the whole width so it drops
        // a band; a large clears the occupied rows by starting at row 2.
        XCTAssertEqual(scene.freeSlot(for: .systemSmall)?.column, 2)
        XCTAssertEqual(scene.freeSlot(for: .systemSmall)?.row, 0)
        XCTAssertEqual(scene.freeSlot(for: .systemMedium)?.column, 0)
        XCTAssertEqual(scene.freeSlot(for: .systemMedium)?.row, 2)
        XCTAssertEqual(scene.freeSlot(for: .systemLarge)?.column, 0)
        XCTAssertEqual(scene.freeSlot(for: .systemLarge)?.row, 2)
    }

    func testFreeSlotNeverCollidesWithAnyExistingPlacement() {
        // Every subset of a set of legal placements, checked against every
        // rendition — the returned slot must be clear of all of them.
        let candidates = [
            ScenePlacement(documentID: Self.documentA, rendition: .systemSmall, column: 0, row: 0),
            ScenePlacement(documentID: Self.documentA, rendition: .systemSmall, column: 2, row: 0),
            ScenePlacement(documentID: Self.documentA, rendition: .systemMedium, column: 0, row: 2),
            ScenePlacement(documentID: Self.documentA, rendition: .systemSmall, column: 0, row: 4),
            ScenePlacement(documentID: Self.documentA, rendition: .accessoryCircular, column: 2, row: 4),
        ]
        for mask in 0..<(1 << candidates.count) {
            var scene = FacetScene(name: "Subset \(mask)")
            scene.placements = candidates.enumerated()
                .filter { mask & (1 << $0.offset) != 0 }
                .map(\.element)
            for rendition in RenditionKind.allCases {
                guard let slot = scene.freeSlot(for: rendition) else { continue }
                let placed = ScenePlacement(
                    documentID: Self.documentB, rendition: rendition,
                    column: slot.column, row: slot.row
                )
                assertFitsGrid(placed, context: "mask \(mask)")
                let cells = Self.cells(of: placed)
                for existing in scene.placements {
                    XCTAssertFalse(
                        existing.overlaps(placed),
                        "mask \(mask): \(rendition) at (\(slot.column),\(slot.row)) hits "
                            + "\(existing.rendition) at (\(existing.column),\(existing.row))"
                    )
                    XCTAssertTrue(
                        cells.isDisjoint(with: Self.cells(of: existing)),
                        "mask \(mask): cell oracle also says they collide"
                    )
                }
            }
        }
    }

    func testFreeSlotAlwaysFitsInsideTheGrid() {
        // Walk the screen filling it with each rendition in turn; every slot
        // handed out along the way must sit wholly inside 4x6.
        for rendition in RenditionKind.allCases {
            var scene = FacetScene(name: "Grid \(rendition)")
            for step in 0..<50 {
                guard let slot = scene.freeSlot(for: rendition) else { break }
                let placed = ScenePlacement(
                    documentID: Self.documentA, rendition: rendition,
                    column: slot.column, row: slot.row
                )
                assertFitsGrid(placed, context: "\(rendition) step \(step)")
                scene.placements.append(placed)
            }
        }
    }

    func testFillingViaFreeSlotNeverStacksTwoWidgets() {
        for rendition in RenditionKind.allCases {
            var scene = FacetScene(name: "Fill \(rendition)")
            var placed = 0
            while let slot = scene.freeSlot(for: rendition) {
                let placement = ScenePlacement(
                    documentID: Self.documentA, rendition: rendition,
                    column: slot.column, row: slot.row
                )
                assertFitsGrid(placement, context: "\(rendition) #\(placed)")
                scene.placements.append(placement)
                placed += 1
                // Pairwise, at every step — not just at the end.
                assertPairwiseDisjoint(scene, context: "\(rendition) after \(placed)")
                if placed > 50 {
                    return XCTFail("freeSlot kept handing out slots for \(rendition)")
                }
            }
            XCTAssertGreaterThan(placed, 0, "\(rendition) never got a single slot")
            XCTAssertNil(scene.freeSlot(for: rendition), "the loop should end on a full screen")
        }
    }

    func testMixedFillNeverStacksTwoWidgets() {
        // The interesting case: sizes interleaved, so the packer has to reason
        // about bands it partly filled with something else.
        let order: [RenditionKind] = [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular]
        var scene = FacetScene(name: "Mixed")
        var cursor = 0
        var iterations = 0
        while iterations < 100 {
            iterations += 1
            var placedAny = false
            for offset in 0..<order.count {
                let rendition = order[(cursor + offset) % order.count]
                guard let slot = scene.freeSlot(for: rendition) else { continue }
                let placement = ScenePlacement(
                    documentID: Self.documentA, rendition: rendition,
                    column: slot.column, row: slot.row
                )
                assertFitsGrid(placement, context: "mixed step \(iterations)")
                scene.placements.append(placement)
                assertPairwiseDisjoint(scene, context: "mixed step \(iterations)")
                cursor += offset + 1
                placedAny = true
                break
            }
            if !placedAny { break }
        }
        XCTAssertLessThan(iterations, 100, "the mixed fill should terminate")
        XCTAssertGreaterThan(scene.placements.count, 1)
        for rendition in RenditionKind.allCases {
            XCTAssertNil(scene.freeSlot(for: rendition), "\(rendition) still fits after the fill ended")
        }
        assertPairwiseDisjoint(scene, context: "mixed final")
    }

    func testFreeSlotReturnsNilOnAFullScreen() {
        // Six smalls cover all 24 cells of the 4x6 grid, so nothing fits after.
        var scene = FacetScene(name: "Full")
        for row in stride(from: 0, to: 6, by: 2) {
            for column in stride(from: 0, to: 4, by: 2) {
                scene.placements.append(ScenePlacement(
                    documentID: Self.documentA, rendition: .systemSmall, column: column, row: row
                ))
            }
        }
        XCTAssertEqual(scene.placements.count, 6)
        XCTAssertEqual(Self.occupiedCells(of: scene).count, 24, "the grid really is covered")
        for rendition in RenditionKind.allCases {
            let slot = scene.freeSlot(for: rendition)
            XCTAssertNil(
                slot, "\(rendition) got (\(slot?.column ?? -1),\(slot?.row ?? -1)) on a full screen"
            )
        }

        // Removing one small reopens exactly that hole for a small, and nothing
        // bigger than a small can use it.
        scene.placements.removeLast()
        XCTAssertEqual(scene.freeSlot(for: .systemSmall)?.column, 2)
        XCTAssertEqual(scene.freeSlot(for: .systemSmall)?.row, 4)
        XCTAssertNil(scene.freeSlot(for: .systemMedium))
        XCTAssertNil(scene.freeSlot(for: .systemLarge))
    }

    func testGridCapacityPerRendition() {
        // How many of one size the default grid holds, filled greedily by
        // freeSlot. A large is 4 rows tall and rows snap in twos, so a second
        // one would always straddle the first.
        XCTAssertEqual(capacity(of: .systemSmall), 6)
        XCTAssertEqual(capacity(of: .systemMedium), 3)
        XCTAssertEqual(capacity(of: .systemLarge), 1)
        XCTAssertEqual(capacity(of: .accessoryCircular), 6)
        XCTAssertEqual(capacity(of: .accessoryRectangular), 6)
        XCTAssertEqual(capacity(of: .accessoryInline), 6)
    }

    func testFreeSlotHonoursACustomGrid() {
        let scene = FacetScene(name: "Custom")
        // Too short for a large, so only smaller renditions get a slot.
        XCTAssertNil(scene.freeSlot(for: .systemLarge, columns: 4, rows: 2))
        XCTAssertNotNil(scene.freeSlot(for: .systemSmall, columns: 4, rows: 2))
        // Too narrow for a medium.
        XCTAssertNil(scene.freeSlot(for: .systemMedium, columns: 2, rows: 6))
        XCTAssertNotNil(scene.freeSlot(for: .systemSmall, columns: 2, rows: 6))
        // Grids too small for anything return nil rather than trapping.
        XCTAssertNil(scene.freeSlot(for: .systemSmall, columns: 4, rows: 0))
        XCTAssertNil(scene.freeSlot(for: .systemSmall, columns: 4, rows: 1))
        XCTAssertNil(scene.freeSlot(for: .systemSmall, columns: 1, rows: 1))
        XCTAssertNil(scene.freeSlot(for: .systemSmall, columns: 1, rows: 6))
    }

    /// BUG (not fixed here — Scene.swift is out of scope for this test pass).
    ///
    /// `freeSlot(for:columns:rows:)` traps on a zero-width grid instead of
    /// returning nil:
    ///
    ///     FacetScene(name: "x").freeSlot(for: .systemSmall, columns: 0, rows: 6)
    ///     // Swift/Stride.swift: Fatal error: Stride size must not be zero
    ///
    /// `columnStep` is `span.columns >= columns ? columns : 2`, so `columns == 0`
    /// makes the step 0 and `stride(from:through:by: 0)` preconditions out. The
    /// row loop only guards `rows`, so `rows >= span.rows` is enough to reach it.
    /// Reproduces for every rendition. A related, milder case: negative `columns`
    /// makes the step negative and `freeSlot` walks into negative column indices,
    /// handing back a slot outside the grid.
    ///
    /// The default 4x6 grid and every plausible real grid are unaffected, so this
    /// is an input-validation gap rather than a packing error. Enabling the body
    /// below crashes the whole test process, hence the skip.
    func testFreeSlotReturnsNilOnADegenerateGrid() {
        // "No room" is the honest answer for a grid with no cells. This used to
        // trap: the column step computed to zero and `stride` hit a precondition.
        let scene = FacetScene(name: "Degenerate")
        XCTAssertNil(scene.freeSlot(for: .systemSmall, columns: 0, rows: 6))
        XCTAssertNil(scene.freeSlot(for: .systemSmall, columns: 4, rows: 0))
        XCTAssertNil(scene.freeSlot(for: .systemSmall, columns: -3, rows: 6))
        XCTAssertNil(scene.freeSlot(for: .systemLarge, columns: -1, rows: -1))
    }

    // MARK: - Helpers

    private struct Cell: Hashable {
        let column: Int
        let row: Int
    }

    private static func span(of rendition: RenditionKind) -> (columns: Int, rows: Int) {
        ScenePlacement(documentID: documentA, rendition: rendition).span
    }

    /// The ground truth `overlaps` is a shortcut for: every icon cell covered.
    private static func cells(of placement: ScenePlacement) -> Set<Cell> {
        let span = placement.span
        var result: Set<Cell> = []
        for column in placement.column..<(placement.column + span.columns) {
            for row in placement.row..<(placement.row + span.rows) {
                result.insert(Cell(column: column, row: row))
            }
        }
        return result
    }

    private static func occupiedCells(of scene: FacetScene) -> Set<Cell> {
        scene.placements.reduce(into: Set<Cell>()) { $0.formUnion(cells(of: $1)) }
    }

    private func capacity(of rendition: RenditionKind) -> Int {
        var scene = FacetScene(name: "Capacity")
        var count = 0
        while let slot = scene.freeSlot(for: rendition), count <= 50 {
            scene.placements.append(ScenePlacement(
                documentID: Self.documentA, rendition: rendition,
                column: slot.column, row: slot.row
            ))
            count += 1
        }
        return count
    }

    private func assertFitsGrid(
        _ placement: ScenePlacement,
        columns: Int = 4,
        rows: Int = 6,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let span = placement.span
        let label = "\(context) \(placement.rendition) at (\(placement.column),\(placement.row)) span \(span)"
        XCTAssertGreaterThanOrEqual(placement.column, 0, label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(placement.row, 0, label, file: file, line: line)
        XCTAssertLessThanOrEqual(placement.column + span.columns, columns, label, file: file, line: line)
        XCTAssertLessThanOrEqual(placement.row + span.rows, rows, label, file: file, line: line)
    }

    private func assertPairwiseDisjoint(
        _ scene: FacetScene,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let placements = scene.placements
        var covered = 0
        for i in placements.indices {
            covered += Self.cells(of: placements[i]).count
            for j in placements.indices where j > i {
                let a = placements[i], b = placements[j]
                let collides = !Self.cells(of: a).isDisjoint(with: Self.cells(of: b))
                XCTAssertFalse(
                    collides,
                    "\(context): \(a.rendition)@(\(a.column),\(a.row)) overlaps "
                        + "\(b.rendition)@(\(b.column),\(b.row))",
                    file: file, line: line
                )
                XCTAssertEqual(
                    a.overlaps(b), collides,
                    "\(context): overlaps disagrees with the cell oracle",
                    file: file, line: line
                )
            }
        }
        // The same fact stated a second way: disjoint blocks tile without loss.
        XCTAssertEqual(
            Self.occupiedCells(of: scene).count, covered,
            "\(context): covered cells collapsed, so two placements share ground",
            file: file, line: line
        )
    }
}
