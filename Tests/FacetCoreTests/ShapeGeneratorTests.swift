import XCTest
@testable import FacetCore

final class ShapeGeneratorTests: XCTestCase {
    private let epsilon = 0.0001

    /// One representative spread per family, reused by the invariant tests so
    /// that "parses", "stays in the box", and "fills the box" are all checked
    /// over the same corners of the parameter space.
    private static let spread: [(family: String, path: String)] = {
        var cases: [(String, String)] = []
        for roundness in [1.5, 2, 2.7, 4, 6, 9, 12] {
            cases.append(("superellipse \(roundness)", ShapeGenerator.superellipse(roundness: roundness)))
        }
        for radii in [
            (0.0, 0.0, 0.0, 0.0), (0.5, 0.5, 0.5, 0.5), (0.18, 0.18, 0.18, 0.18),
            (0.5, 0.05, 0.5, 0.05), (0.5, 0.5, 0.0, 0.0), (0.4, 0.0, 0.12, 0.33),
        ] {
            cases.append(("roundedRect \(radii)", ShapeGenerator.roundedRect(
                topLeft: radii.0, topRight: radii.1, bottomRight: radii.2, bottomLeft: radii.3
            )))
        }
        for bumps in [(0, 0), (1, 1), (3, 2), (0, 4), (5, 0), (8, 8)] {
            for depth in [0.0, 0.05, 0.12] {
                for radius in [0.0, 0.15, 0.3] {
                    cases.append((
                        "scallop \(bumps) d\(depth) r\(radius)",
                        ShapeGenerator.scallop(
                            bumpsX: bumps.0, bumpsY: bumps.1, depth: depth, cornerRadius: radius
                        )
                    ))
                }
            }
        }
        for sides in 3...12 {
            for corner in [0.0, 0.4, 1.0] {
                for rotation in [0.0, 17.5, 90, -45] {
                    cases.append((
                        "polygon \(sides) c\(corner) @\(rotation)",
                        ShapeGenerator.polygon(sides: sides, cornerRadius: corner, rotation: rotation)
                    ))
                }
            }
        }
        for points in 3...12 {
            for ratio in [0.2, 0.5, 0.9] {
                for corner in [0.0, 0.5, 1.0] {
                    cases.append((
                        "star \(points) i\(ratio) c\(corner)",
                        ShapeGenerator.star(
                            points: points, innerRatio: ratio, cornerRadius: corner, rotation: 0
                        )
                    ))
                }
            }
        }
        return cases
    }()

    // MARK: - Determinism

    func testEveryFamilyIsDeterministic() {
        for _ in 0..<3 {
            XCTAssertEqual(
                ShapeGenerator.superellipse(roundness: 3.7),
                ShapeGenerator.superellipse(roundness: 3.7)
            )
            XCTAssertEqual(
                ShapeGenerator.roundedRect(topLeft: 0.31, topRight: 0.07, bottomRight: 0.5, bottomLeft: 0),
                ShapeGenerator.roundedRect(topLeft: 0.31, topRight: 0.07, bottomRight: 0.5, bottomLeft: 0)
            )
            XCTAssertEqual(
                ShapeGenerator.scallop(bumpsX: 4, bumpsY: 3, depth: 0.11, cornerRadius: 0.19),
                ShapeGenerator.scallop(bumpsX: 4, bumpsY: 3, depth: 0.11, cornerRadius: 0.19)
            )
            XCTAssertEqual(
                ShapeGenerator.polygon(sides: 7, cornerRadius: 0.44, rotation: 23),
                ShapeGenerator.polygon(sides: 7, cornerRadius: 0.44, rotation: 23)
            )
            XCTAssertEqual(
                ShapeGenerator.star(points: 6, innerRatio: 0.43, cornerRadius: 0.62, rotation: -12),
                ShapeGenerator.star(points: 6, innerRatio: 0.43, cornerRadius: 0.62, rotation: -12)
            )
        }
    }

    func testDistinctParametersProduceDistinctPaths() {
        var seen: Set<String> = []
        for roundness in stride(from: 1.5, through: 12, by: 0.5) {
            XCTAssertTrue(
                seen.insert(ShapeGenerator.superellipse(roundness: roundness)).inserted,
                "roundness \(roundness) collided with another exponent"
            )
        }
        seen.removeAll()
        for sides in 3...12 {
            XCTAssertTrue(
                seen.insert(ShapeGenerator.polygon(sides: sides, cornerRadius: 0.3, rotation: 0)).inserted,
                "\(sides) sides collided"
            )
        }
    }

    func testRotationWrapsRatherThanDrifting() {
        let reference = ShapeGenerator.polygon(sides: 5, cornerRadius: 0.3, rotation: 30)
        XCTAssertEqual(ShapeGenerator.polygon(sides: 5, cornerRadius: 0.3, rotation: 390), reference)
        XCTAssertEqual(ShapeGenerator.polygon(sides: 5, cornerRadius: 0.3, rotation: 720 + 30), reference)
        XCTAssertEqual(
            ShapeGenerator.star(points: 5, innerRatio: 0.5, cornerRadius: 0.3, rotation: 360),
            ShapeGenerator.star(points: 5, innerRatio: 0.5, cornerRadius: 0.3, rotation: 0)
        )
    }

    // MARK: - Invariants across every family

    func testEveryPathParses() throws {
        for (family, path) in Self.spread {
            let commands = try PathData.parse(path)
            XCTAssertGreaterThan(commands.count, 2, family)
            guard case .move = commands.first else { return XCTFail("\(family) must start with a move") }
            XCTAssertEqual(commands.last, .close, family)
            XCTAssertTrue(path.hasPrefix("M"), "\(family): \(path)")
            XCTAssertTrue(path.hasSuffix("Z"), "\(family): \(path)")
        }
    }

    func testEveryCoordinateIsFiniteAndInsideTheUnitSquare() {
        for (family, path) in Self.spread {
            let values = Self.coordinates(in: path)
            XCTAssertFalse(values.isEmpty, family)
            for value in values {
                XCTAssertTrue(value.isFinite, "\(family): \(path)")
                XCTAssertGreaterThanOrEqual(value, -epsilon, "\(family): \(path)")
                XCTAssertLessThanOrEqual(value, 1 + epsilon, "\(family): \(path)")
            }
        }
    }

    func testEveryBoundingBoxIsNormalized() {
        for (family, path) in Self.spread {
            assertNormalized(path, message: family)
        }
    }

    func testEveryOutlineActuallyReachesAllFourEdges() {
        // The box above is measured on control points; this measures the drawn
        // curve, which is what the user sees filling the layer.
        for (family, path) in Self.spread {
            let curve = Self.sample(path, stepsPerCurve: 24)
            XCTAssertFalse(curve.isEmpty, family)
            let slack = max(
                curve.map(\.x).min()!, curve.map(\.y).min()!,
                1 - curve.map(\.x).max()!, 1 - curve.map(\.y).max()!
            )
            // A rounded polygon vertex is the loosest case: its arc's extreme
            // sits just inside the control point that bounds it.
            XCTAssertLessThan(slack, 0.03, "\(family) leaves a \(slack) gap: \(path)")
        }
    }

    // MARK: - Clamping

    func testOutOfRangeParametersClampInsteadOfTrapping() {
        XCTAssertEqual(ShapeGenerator.superellipse(roundness: -4), ShapeGenerator.superellipse(roundness: 1.5))
        XCTAssertEqual(ShapeGenerator.superellipse(roundness: 400), ShapeGenerator.superellipse(roundness: 12))

        XCTAssertEqual(
            ShapeGenerator.roundedRect(topLeft: -1, topRight: 9, bottomRight: 0.2, bottomLeft: -0.001),
            ShapeGenerator.roundedRect(topLeft: 0, topRight: 0.5, bottomRight: 0.2, bottomLeft: 0)
        )

        XCTAssertEqual(
            ShapeGenerator.scallop(bumpsX: -3, bumpsY: 99, depth: 5, cornerRadius: 12),
            ShapeGenerator.scallop(bumpsX: 0, bumpsY: 8, depth: 0.12, cornerRadius: 0.3)
        )

        XCTAssertEqual(
            ShapeGenerator.polygon(sides: 0, cornerRadius: -2, rotation: 0),
            ShapeGenerator.polygon(sides: 3, cornerRadius: 0, rotation: 0)
        )
        XCTAssertEqual(
            ShapeGenerator.polygon(sides: 99, cornerRadius: 7, rotation: 0),
            ShapeGenerator.polygon(sides: 12, cornerRadius: 1, rotation: 0)
        )

        XCTAssertEqual(
            ShapeGenerator.star(points: 1, innerRatio: 0.01, cornerRadius: -5, rotation: 0),
            ShapeGenerator.star(points: 3, innerRatio: 0.2, cornerRadius: 0, rotation: 0)
        )
        XCTAssertEqual(
            ShapeGenerator.star(points: 40, innerRatio: 4, cornerRadius: 3, rotation: 0),
            ShapeGenerator.star(points: 12, innerRatio: 0.9, cornerRadius: 1, rotation: 0)
        )
    }

    func testNonFiniteParametersFallBackInsteadOfPoisoningThePath() {
        // JSON cannot carry these, but a bad in-memory binding can, and one NaN
        // would otherwise spread through normalization into every coordinate.
        let paths = [
            ShapeGenerator.superellipse(roundness: .nan),
            ShapeGenerator.superellipse(roundness: .infinity),
            ShapeGenerator.superellipse(roundness: -.infinity),
            ShapeGenerator.roundedRect(topLeft: .nan, topRight: .infinity, bottomRight: -.infinity, bottomLeft: 0.2),
            ShapeGenerator.scallop(bumpsX: 3, bumpsY: 2, depth: .nan, cornerRadius: .infinity),
            ShapeGenerator.scallop(bumpsX: 3, bumpsY: 2, depth: 0.1, cornerRadius: .nan),
            ShapeGenerator.polygon(sides: 6, cornerRadius: .nan, rotation: .infinity),
            ShapeGenerator.polygon(sides: 6, cornerRadius: .infinity, rotation: .nan),
            ShapeGenerator.star(points: 5, innerRatio: .nan, cornerRadius: .nan, rotation: .nan),
            ShapeGenerator.star(points: 5, innerRatio: 0.5, cornerRadius: 0.3, rotation: -.infinity),
        ]
        for path in paths {
            XCTAssertFalse(path.lowercased().contains("nan"), path)
            XCTAssertFalse(path.lowercased().contains("inf"), path)
            XCTAssertNoThrow(try PathData.parse(path), path)
            assertNormalized(path)
        }

        // A non-finite exponent, radius, or rotation resolves to the family's
        // documented default rather than to whatever the last clamp produced.
        XCTAssertEqual(ShapeGenerator.superellipse(roundness: .nan), ShapeGenerator.superellipse(roundness: 4))
        XCTAssertEqual(
            ShapeGenerator.polygon(sides: 6, cornerRadius: 0.3, rotation: .nan),
            ShapeGenerator.polygon(sides: 6, cornerRadius: 0.3, rotation: 0)
        )
        XCTAssertEqual(
            ShapeGenerator.star(points: 5, innerRatio: .nan, cornerRadius: 0, rotation: 0),
            ShapeGenerator.star(points: 5, innerRatio: 0.5, cornerRadius: 0, rotation: 0)
        )
    }

    // MARK: - Superellipse

    func testSuperellipseIsEightCubics() {
        for roundness in [1.5, 2, 4, 8, 12] {
            let path = ShapeGenerator.superellipse(roundness: roundness)
            XCTAssertEqual(
                path.filter { $0 == "C" }.count, 8,
                "Two cubics per quadrant keeps the whole exponent range reachable: \(path)"
            )
        }
    }

    func testRoundnessTwoIsAnEllipse() {
        let curve = Self.sample(ShapeGenerator.superellipse(roundness: 2), stepsPerCurve: 32)
        XCTAssertFalse(curve.isEmpty)
        for point in curve {
            let x = (point.x - 0.5) / 0.5
            let y = (point.y - 0.5) / 0.5
            let radius = (x * x + y * y).squareRoot()
            XCTAssertEqual(radius, 1, accuracy: 0.002, "(\(point.x), \(point.y)) is off the unit circle")
        }
    }

    func testHigherRoundnessApproachesTheFullBox() {
        // The Chebyshev radius is 0.5 everywhere on a square and dips to
        // 0.3536 at the diagonal of a circle, so its minimum over the curve is
        // a direct read of "how boxy".
        func boxiness(_ roundness: Double) -> Double {
            Self.sample(ShapeGenerator.superellipse(roundness: roundness), stepsPerCurve: 32)
                .map { max(abs($0.x - 0.5), abs($0.y - 0.5)) }
                .min() ?? .nan
        }
        XCTAssertEqual(boxiness(2), 0.5 / 2.0.squareRoot(), accuracy: 0.005, "roundness 2 is a circle")
        XCTAssertGreaterThan(boxiness(12), 0.46, "roundness 12 should be nearly a square")

        var previous = boxiness(1.5)
        for roundness in [2.0, 3, 4, 5, 6, 8, 10, 12] {
            let current = boxiness(roundness)
            XCTAssertGreaterThan(current, previous, "roundness \(roundness) should be boxier than the last")
            previous = current
        }
    }

    // MARK: - Rounded rectangle

    func testZeroRadiiGiveExactlyTheUnitSquare() {
        XCTAssertEqual(
            ShapeGenerator.roundedRect(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            "M0,0 L1,0 L1,1 L0,1 Z"
        )
    }

    func testMaximumUniformRadiusIsACircle() {
        let path = ShapeGenerator.roundedRect(topLeft: 0.5, topRight: 0.5, bottomRight: 0.5, bottomLeft: 0.5)
        XCTAssertEqual(path.filter { $0 == "C" }.count, 4, path)
        XCTAssertEqual(path.filter { $0 == "L" }.count, 0, "Zero-length edges are dropped: \(path)")
        for point in Self.sample(path, stepsPerCurve: 24) {
            let x = (point.x - 0.5) / 0.5
            let y = (point.y - 0.5) / 0.5
            XCTAssertEqual((x * x + y * y).squareRoot(), 1, accuracy: 0.003)
        }
    }

    func testOnlyRequestedCornersAreRounded() {
        for corner in 0..<4 {
            let radii = (0..<4).map { $0 == corner ? 0.4 : 0.0 }
            let path = ShapeGenerator.roundedRect(
                topLeft: radii[0], topRight: radii[1], bottomRight: radii[2], bottomLeft: radii[3]
            )
            XCTAssertEqual(path.filter { $0 == "C" }.count, 1, "corner \(corner): \(path)")
        }
    }

    func testOppositeRadiiOnAnEdgeAreScaledDownTogether() {
        // Per-corner clamping already caps the pair at the edge length, so the
        // proportional pass must be a no-op — never a silent extra shrink.
        let path = ShapeGenerator.roundedRect(
            topLeft: 0.5, topRight: 0.5, bottomRight: 0.5, bottomLeft: 0.5
        )
        XCTAssertEqual(path, ShapeGenerator.roundedRect(
            topLeft: 9, topRight: 9, bottomRight: 9, bottomLeft: 9
        ))
        assertNormalized(path)
    }

    // MARK: - Scallop

    func testNoBumpsIsExactlyAPlainRoundedRect() {
        for radius in [0.0, 0.05, 0.15, 0.3] {
            let expected = ShapeGenerator.roundedRect(
                topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius
            )
            XCTAssertEqual(
                ShapeGenerator.scallop(bumpsX: 0, bumpsY: 0, depth: 0.12, cornerRadius: radius),
                expected, "radius \(radius)"
            )
            XCTAssertEqual(
                ShapeGenerator.scallop(bumpsX: 4, bumpsY: 4, depth: 0, cornerRadius: radius),
                expected, "zero depth is also flat at radius \(radius)"
            )
        }
    }

    func testEachBumpIsOneOutwardLobe() {
        // A bulge touches the top edge only at its apex, so the outline meets
        // y = 0 in exactly `bumpsX` short bursts. Notches cut inward would
        // instead leave the long flat runs between them touching the edge, and
        // a flat edge touches along its whole length — this separates all three.
        func lobes(_ path: String) -> [Int] {
            let curve = Self.sample(path, stepsPerCurve: 16)
            var runs: [Int] = []
            var run = 0
            for point in curve {
                if point.y < 0.004 {
                    run += 1
                } else if run > 0 {
                    runs.append(run)
                    run = 0
                }
            }
            if run > 0 { runs.append(run) }
            // The outline starts partway along the top edge, so a run that
            // wraps the seam would otherwise be counted twice.
            if runs.count > 1, let first = curve.first, let last = curve.last,
               first.y < 0.004, last.y < 0.004 {
                runs[0] += runs.removeLast()
            }
            return runs
        }

        let flat = lobes(ShapeGenerator.scallop(bumpsX: 0, bumpsY: 0, depth: 0, cornerRadius: 0.2))
        XCTAssertEqual(flat.count, 1, "A flat edge is one contact run")

        for bumps in 1...5 {
            let path = ShapeGenerator.scallop(bumpsX: bumps, bumpsY: 2, depth: 0.12, cornerRadius: 0.15)
            let runs = lobes(path)
            XCTAssertEqual(runs.count, bumps, "\(bumps) bumps: \(path)")
            XCTAssertLessThan(runs.max() ?? .max, flat[0], "Each lobe should touch at its apex, not along a flat")
            for point in Self.sample(path, stepsPerCurve: 16) {
                XCTAssertGreaterThanOrEqual(point.x, -epsilon)
                XCTAssertGreaterThanOrEqual(point.y, -epsilon)
                XCTAssertLessThanOrEqual(point.x, 1 + epsilon)
                XCTAssertLessThanOrEqual(point.y, 1 + epsilon)
            }
        }
    }

    func testBumpDepthIsCappedByTheChordItSitsOn() {
        // Past half a chord an arc turns back on itself and neighbouring bulges
        // cross, so crowded edges must saturate rather than self-intersect.
        let crowded = ShapeGenerator.scallop(bumpsX: 8, bumpsY: 8, depth: 0.08, cornerRadius: 0.3)
        XCTAssertEqual(crowded, ShapeGenerator.scallop(bumpsX: 8, bumpsY: 8, depth: 0.12, cornerRadius: 0.3))
        XCTAssertNotEqual(
            ShapeGenerator.scallop(bumpsX: 2, bumpsY: 2, depth: 0.08, cornerRadius: 0.1),
            ShapeGenerator.scallop(bumpsX: 2, bumpsY: 2, depth: 0.12, cornerRadius: 0.1),
            "An uncrowded edge must still respond to depth"
        )
    }

    func testBumpsOnOneAxisOnly() {
        let path = ShapeGenerator.scallop(bumpsX: 0, bumpsY: 4, depth: 0.08, cornerRadius: 0.1)
        assertNormalized(path)
        // Flat top and bottom: the horizontal edges stay straight lines.
        XCTAssertGreaterThan(path.filter { $0 == "L" }.count, 0, path)
        XCTAssertNotEqual(path, ShapeGenerator.scallop(bumpsX: 4, bumpsY: 0, depth: 0.08, cornerRadius: 0.1))
    }

    // MARK: - Polygon and star

    func testUnroundedPolygonIsAllStraightLines() {
        for sides in 3...12 {
            let path = ShapeGenerator.polygon(sides: sides, cornerRadius: 0, rotation: 0)
            XCTAssertEqual(path.filter { $0 == "C" }.count, 0, path)
            XCTAssertEqual(path.filter { $0 == "L" }.count, sides - 1, "Z closes the last edge: \(path)")
        }
    }

    func testRoundedPolygonIsTwoCubicsPerVertex() {
        for sides in 3...12 {
            let path = ShapeGenerator.polygon(sides: sides, cornerRadius: 0.5, rotation: 0)
            XCTAssertEqual(path.filter { $0 == "C" }.count, 2 * sides, path)
        }
    }

    func testStarHasTwiceAsManyVerticesAsPoints() {
        for points in 3...12 {
            let path = ShapeGenerator.star(points: points, innerRatio: 0.5, cornerRadius: 0, rotation: 0)
            XCTAssertEqual(path.filter { $0 == "L" }.count, 2 * points - 1, path)
        }
    }

    func testStarArmsShrinkAsInnerRatioGrows() {
        // A sharper star reaches further from its own centroid at the tips than
        // a blunt one, measured against the mean radius so normalization's
        // stretch cannot flatter either end.
        func spikiness(_ ratio: Double) -> Double {
            let curve = Self.sample(
                ShapeGenerator.star(points: 5, innerRatio: ratio, cornerRadius: 0, rotation: 0),
                stepsPerCurve: 8
            )
            let radii = curve.map {
                (($0.x - 0.5) * ($0.x - 0.5) + ($0.y - 0.5) * ($0.y - 0.5)).squareRoot()
            }
            let mean = radii.reduce(0, +) / Double(radii.count)
            return radii.max()! / mean
        }
        var previous = spikiness(0.2)
        for ratio in [0.35, 0.5, 0.7, 0.9] {
            let current = spikiness(ratio)
            XCTAssertLessThan(current, previous, "innerRatio \(ratio) should be blunter")
            previous = current
        }
    }

    func testRotationTurnsTheOutline() {
        let upright = ShapeGenerator.polygon(sides: 5, cornerRadius: 0, rotation: 0)
        // A vertex sits at the top center when unrotated.
        XCTAssertTrue(upright.hasPrefix("M0.5,0"), upright)
        XCTAssertNotEqual(upright, ShapeGenerator.polygon(sides: 5, cornerRadius: 0, rotation: 36))
    }

    // MARK: - Presets

    func testPresetsAreValidDistinctAndNormalized() throws {
        XCTAssertEqual(ShapeGenerator.presets.count, 12)
        var names: Set<String> = []
        var paths: Set<String> = []
        for preset in ShapeGenerator.presets {
            XCTAssertTrue(names.insert(preset.name).inserted, "Duplicate preset name \(preset.name)")
            XCTAssertTrue(paths.insert(preset.pathData).inserted, "\(preset.name) duplicates another preset")
            XCTAssertTrue(preset.pathData.hasPrefix("M"), preset.name)
            XCTAssertTrue(preset.pathData.hasSuffix("Z"), preset.name)
            XCTAssertNoThrow(try PathData.parse(preset.pathData), preset.name)
            assertNormalized(preset.pathData, message: preset.name)
            // Widget documents are hand-editable JSON; an outline that runs to
            // kilobytes is a sign a generator has fallen back to polylining.
            XCTAssertLessThan(preset.pathData.count, 2000, preset.name)
        }
    }

    func testPresetsCoverEveryFamily() {
        let names = Set(ShapeGenerator.presets.map(\.name))
        for expected in ["Squircle", "Soft Rect", "Pill", "Cloud", "Hexagon", "Star", "Leaf", "Arch"] {
            XCTAssertTrue(names.contains(expected), "Missing preset \(expected)")
        }
    }

    // MARK: - Helpers

    // MARK: - Irregular clouds

    func testIrregularCloudIsDeterministic() {
        // The whole point of seeding rather than randomising: identical output
        // on every render, or a document reshapes itself each redraw.
        XCTAssertEqual(
            ShapeGenerator.scallop(bumpsX: 4, bumpsY: 3, depth: 0.11, cornerRadius: 0.14, irregularity: 0.5, seed: 7),
            ShapeGenerator.scallop(bumpsX: 4, bumpsY: 3, depth: 0.11, cornerRadius: 0.14, irregularity: 0.5, seed: 7)
        )
    }

    func testIrregularityZeroReproducesTheUniformCloud() {
        // The four-argument call defaults irregularity to 0, so every existing
        // caller keeps its identical-lobe shape.
        XCTAssertEqual(
            ShapeGenerator.scallop(bumpsX: 4, bumpsY: 3, depth: 0.11, cornerRadius: 0.14),
            ShapeGenerator.scallop(bumpsX: 4, bumpsY: 3, depth: 0.11, cornerRadius: 0.14, irregularity: 0, seed: 99)
        )
    }

    func testIrregularityAndSeedBothChangeTheShape() {
        let base = ShapeGenerator.scallop(bumpsX: 4, bumpsY: 3, depth: 0.11, cornerRadius: 0.14, irregularity: 0)
        let varied = ShapeGenerator.scallop(bumpsX: 4, bumpsY: 3, depth: 0.11, cornerRadius: 0.14, irregularity: 0.5, seed: 7)
        let otherSeed = ShapeGenerator.scallop(bumpsX: 4, bumpsY: 3, depth: 0.11, cornerRadius: 0.14, irregularity: 0.5, seed: 8)
        XCTAssertNotEqual(base, varied, "irregularity should move the lobes")
        XCTAssertNotEqual(varied, otherSeed, "the seed should pick a different variation")
    }

    func testIrregularCloudsStayNormalisedAndInsideTheBox() {
        for seed in UInt64(0)...12 {
            for irregularity in [0.25, 0.5, 0.75, 1.0] {
                let path = ShapeGenerator.scallop(
                    bumpsX: 4, bumpsY: 3, depth: 0.15, cornerRadius: 0.12,
                    irregularity: irregularity, seed: seed
                )
                assertNormalized(path, message: "seed \(seed) irr \(irregularity)")
            }
        }
    }

    /// The organic clouds must not fold over themselves at any setting — the
    /// same guarantee the uniform family got, extended across the new axis.
    func testIrregularCloudsDoNotSelfIntersect() {
        for seed in UInt64(0)...20 {
            for irregularity in [0.3, 0.6, 1.0] {
                for depth in [0.08, 0.15, 0.18] {
                    let path = ShapeGenerator.scallop(
                        bumpsX: 5, bumpsY: 3, depth: depth, cornerRadius: 0.12,
                        irregularity: irregularity, seed: seed
                    )
                    XCTAssertFalse(
                        Self.selfIntersects(path),
                        "seed \(seed) irr \(irregularity) depth \(depth): \(path)"
                    )
                }
            }
        }
    }

    private func assertNormalized(
        _ path: String,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let values = Self.coordinates(in: path)
        XCTAssertFalse(values.isEmpty, message, file: file, line: line)
        for value in values {
            XCTAssertTrue(value.isFinite, "\(message) \(path)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(value, -epsilon, "\(message) \(path)", file: file, line: line)
            XCTAssertLessThanOrEqual(value, 1 + epsilon, "\(message) \(path)", file: file, line: line)
        }
        let box = Self.boundingBox(of: path)
        XCTAssertEqual(box.minX, 0, accuracy: epsilon, "\(message) \(path)", file: file, line: line)
        XCTAssertEqual(box.maxX, 1, accuracy: epsilon, "\(message) \(path)", file: file, line: line)
        XCTAssertEqual(box.minY, 0, accuracy: epsilon, "\(message) \(path)", file: file, line: line)
        XCTAssertEqual(box.maxY, 1, accuracy: epsilon, "\(message) \(path)", file: file, line: line)
    }

    /// Every number in the path, in emission order. Parsed straight from the
    /// string rather than through `PathData` so these tests fail if the two
    /// ever disagree about the output format.
    private static func coordinates(in path: String) -> [Double] {
        path.split(whereSeparator: { " ,MLCQZ".contains($0) })
            .map { Double($0) ?? .nan }
    }

    private static func boundingBox(of path: String) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let values = coordinates(in: path)
        let xs = values.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let ys = values.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        return (xs.min() ?? .nan, xs.max() ?? .nan, ys.min() ?? .nan, ys.max() ?? .nan)
    }

    /// Points on the drawn curve, not just the control polygon.
    /// Samples the outline and checks every non-adjacent segment pair for a
    /// proper crossing. "Proper" (strict sign changes) ignores shared endpoints
    /// and grazes, so only a real fold-over trips it.
    private static func selfIntersects(_ path: String) -> Bool {
        let points = sample(path, stepsPerCurve: 6)
        let n = points.count
        guard n > 3 else { return false }
        func cross(_ o: (x: Double, y: Double), _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        func crosses(_ p1: (x: Double, y: Double), _ p2: (x: Double, y: Double),
                     _ p3: (x: Double, y: Double), _ p4: (x: Double, y: Double)) -> Bool {
            let d1 = cross(p3, p4, p1), d2 = cross(p3, p4, p2)
            let d3 = cross(p1, p2, p3), d4 = cross(p1, p2, p4)
            return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0))
                && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
        }
        for i in 0..<n {
            let a1 = points[i], a2 = points[(i + 1) % n]
            for j in (i + 1)..<n where j != (i + 1) % n && (j + 1) % n != i {
                if crosses(a1, a2, points[j], points[(j + 1) % n]) { return true }
            }
        }
        return false
    }

    private static func sample(_ path: String, stepsPerCurve: Int) -> [(x: Double, y: Double)] {
        guard let commands = try? PathData.parse(path) else { return [] }
        var points: [(x: Double, y: Double)] = []
        var current = (x: 0.0, y: 0.0)
        var origin = (x: 0.0, y: 0.0)
        for command in commands {
            switch command {
            case .move(let x, let y):
                current = (x, y)
                origin = current
                points.append(current)
            case .line(let x, let y):
                for step in 1...stepsPerCurve {
                    let t = Double(step) / Double(stepsPerCurve)
                    points.append((current.x + (x - current.x) * t, current.y + (y - current.y) * t))
                }
                current = (x, y)
            case .quad(let cx, let cy, let x, let y):
                for step in 1...stepsPerCurve {
                    let t = Double(step) / Double(stepsPerCurve)
                    let u = 1 - t
                    points.append((
                        u * u * current.x + 2 * u * t * cx + t * t * x,
                        u * u * current.y + 2 * u * t * cy + t * t * y
                    ))
                }
                current = (x, y)
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                for step in 1...stepsPerCurve {
                    let t = Double(step) / Double(stepsPerCurve)
                    let u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    points.append((
                        a * current.x + b * c1x + c * c2x + d * x,
                        a * current.y + b * c1y + c * c2y + d * y
                    ))
                }
                current = (x, y)
            case .close:
                current = origin
            }
        }
        return points
    }
}
