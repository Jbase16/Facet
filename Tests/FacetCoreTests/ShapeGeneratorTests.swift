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
        for puffs in 3...7 {
            for puffiness in [0.1, 0.25, 0.4] {
                for irregularity in [0.0, 0.5, 1.0] {
                    cases.append((
                        "cloud \(puffs) p\(puffiness) i\(irregularity)",
                        ShapeGenerator.cloud(
                            puffs: puffs, puffiness: puffiness, irregularity: irregularity, seed: 3
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
                ShapeGenerator.cloud(puffs: 5, puffiness: 0.28, irregularity: 0.5, seed: 7),
                ShapeGenerator.cloud(puffs: 5, puffiness: 0.28, irregularity: 0.5, seed: 7)
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
            ShapeGenerator.cloud(puffs: -3, puffiness: 5, irregularity: 9, seed: 1),
            ShapeGenerator.cloud(puffs: 3, puffiness: 0.5, irregularity: 1, seed: 1)
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
            ShapeGenerator.cloud(puffs: 5, puffiness: .nan, irregularity: .infinity, seed: 2),
            ShapeGenerator.cloud(puffs: 4, puffiness: 0.3, irregularity: .nan, seed: 5),
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

    // MARK: - Cloud

    func testCloudHasAFlatBottom() {
        // The defining feature: the bottom edge is one straight run, not bumps.
        // After normalization the baseline maps to y = 1, so a wide band of the
        // outline sits on that line.
        let path = ShapeGenerator.cloud(puffs: 5, puffiness: 0.28, irregularity: 0.3, seed: 7)
        let onBottom = Self.sample(path, stepsPerCurve: 10).filter { $0.y > 1 - 0.01 }
        let spanX = (onBottom.map(\.x).max() ?? 0) - (onBottom.map(\.x).min() ?? 0)
        XCTAssertGreaterThan(spanX, 0.85, "the cloud should rest on a wide flat base: \(path)")
    }

    func testCloudTopIsBumpierThanItsBottom() {
        // Puffs live on top; the bottom is flat. So the upper half of the outline
        // should wander in y far more than the lower half.
        let curve = Self.sample(ShapeGenerator.cloud(puffs: 5, puffiness: 0.3, irregularity: 0.4, seed: 2), stepsPerCurve: 12)
        let topSpread = curve.filter { $0.y < 0.5 }.map(\.y)
        let bottomSpread = curve.filter { $0.y >= 0.5 }.map(\.y)
        let topRange = (topSpread.max() ?? 0) - (topSpread.min() ?? 0)
        let bottomRange = (bottomSpread.max() ?? 0) - (bottomSpread.min() ?? 0)
        XCTAssertGreaterThan(topRange, bottomRange, "the top should be the bumpy half")
    }

    /// The property the arc-walk could not hold: no cloud folds over itself, at
    /// any puff count, puffiness, irregularity, or seed. The generator's whole
    /// construction (an x-monotone upper envelope) exists to guarantee this.
    func testCloudsNeverSelfIntersect() {
        for puffs in 3...7 {
            for seed in UInt64(0)..<24 {
                for irregularity in [0.0, 0.5, 1.0] {
                    for puffiness in [0.1, 0.3, 0.5] {
                        let path = ShapeGenerator.cloud(
                            puffs: puffs, puffiness: puffiness, irregularity: irregularity, seed: seed
                        )
                        XCTAssertFalse(
                            Self.selfIntersects(path),
                            "puffs \(puffs) seed \(seed) irr \(irregularity) pf \(puffiness): \(path)"
                        )
                    }
                }
            }
        }
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

    func testCloudSeedAndParametersChangeTheShape() {
        let base = ShapeGenerator.cloud(puffs: 5, puffiness: 0.28, irregularity: 0.5, seed: 7)
        XCTAssertEqual(base, ShapeGenerator.cloud(puffs: 5, puffiness: 0.28, irregularity: 0.5, seed: 7),
                       "same inputs must be byte-identical")
        XCTAssertNotEqual(base, ShapeGenerator.cloud(puffs: 5, puffiness: 0.28, irregularity: 0.5, seed: 8),
                          "the seed should pick a different cloud")
        XCTAssertNotEqual(base, ShapeGenerator.cloud(puffs: 6, puffiness: 0.28, irregularity: 0.5, seed: 7),
                          "puff count should change the cloud")
    }

    // MARK: - Helpers

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
