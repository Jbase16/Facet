import XCTest
@testable import FacetCore

final class BlobPathTests: XCTestCase {
    private let epsilon = 0.0001

    // MARK: - Determinism

    func testSameParametersProduceIdenticalStrings() {
        let parameters = BlobParameters(points: 7, irregularity: 0.45, smoothness: 0.8, seed: 99)
        let first = BlobPath.path(parameters)
        let second = BlobPath.path(parameters)
        let third = BlobPath.path(
            BlobParameters(points: 7, irregularity: 0.45, smoothness: 0.8, seed: 99)
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, third, "An equal value must generate an equal path")
    }

    func testDifferentSeedsProduceDifferentStrings() {
        var seen: Set<String> = []
        for seed in UInt64(0)..<20 {
            let path = BlobPath.path(BlobParameters(irregularity: 0.4, seed: seed))
            XCTAssertTrue(seen.insert(path).inserted, "Seed \(seed) collided with an earlier seed")
        }
    }

    func testParametersRoundTripThroughCodable() throws {
        let parameters = BlobParameters(points: 9, irregularity: 0.21, smoothness: 0.66, seed: 1 << 40)
        let data = try JSONEncoder().encode(parameters)
        let decoded = try JSONDecoder().decode(BlobParameters.self, from: data)
        XCTAssertEqual(decoded, parameters)
        XCTAssertEqual(BlobPath.path(decoded), BlobPath.path(parameters))
    }

    // MARK: - Path shape

    func testPathIsClosedAndHasOneCurvePerPoint() {
        for points in 3...12 {
            let path = BlobPath.path(BlobParameters(points: points, irregularity: 0.35, seed: 4))
            XCTAssertTrue(path.hasPrefix("M"), "\(points) points: \(path)")
            XCTAssertTrue(path.hasSuffix("Z"), "\(points) points: \(path)")
            XCTAssertEqual(
                path.filter { $0 == "C" }.count, points,
                "One cubic per control point closes the loop"
            )
        }
    }

    func testPathParsesAsSupportedCommands() throws {
        let commands = try PathData.parse(BlobPath.path(.default))
        XCTAssertEqual(commands.count, 8, "move + 6 cubics + close")
        guard case .move = commands.first else { return XCTFail("Expected a leading move") }
        XCTAssertEqual(commands.last, .close)
    }

    func testCoordinatesAreFiniteAndWithinTheUnitSquare() {
        for seed in UInt64(0)..<25 {
            for irregularity in [0.0, 0.15, 0.4, 0.75, 1.0] {
                let parameters = BlobParameters(
                    points: 3 + Int(seed) % 10,
                    irregularity: irregularity,
                    seed: seed
                )
                let path = BlobPath.path(parameters)
                let coordinates = Self.coordinates(in: path)
                XCTAssertFalse(coordinates.isEmpty, path)
                for value in coordinates {
                    XCTAssertTrue(value.isFinite, "Non-finite coordinate in \(path)")
                    XCTAssertGreaterThanOrEqual(value, -epsilon, path)
                    XCTAssertLessThanOrEqual(value, 1 + epsilon, path)
                }
            }
        }
    }

    func testBoundingBoxIsNormalized() {
        for seed in UInt64(0)..<25 {
            for irregularity in [0.0, 0.2, 0.5, 0.9] {
                let parameters = BlobParameters(
                    points: 3 + Int(seed) % 10,
                    irregularity: irregularity,
                    seed: seed
                )
                let path = BlobPath.path(parameters)
                let box = Self.boundingBox(of: path)
                XCTAssertEqual(box.minX, 0, accuracy: epsilon, path)
                XCTAssertEqual(box.maxX, 1, accuracy: epsilon, path)
                XCTAssertEqual(box.minY, 0, accuracy: epsilon, path)
                XCTAssertEqual(box.maxY, 1, accuracy: epsilon, path)
            }
        }
    }

    // MARK: - Parameter behaviour

    func testZeroIrregularityIgnoresTheSeed() {
        // Every radius collapses to the same value, so the random stream can
        // no longer reach the geometry — the strongest available check that
        // irregularity 0 really means "all radii equal".
        let reference = BlobPath.path(BlobParameters(irregularity: 0, seed: 0))
        for seed in UInt64(1)..<10 {
            XCTAssertEqual(BlobPath.path(BlobParameters(irregularity: 0, seed: seed)), reference)
        }
    }

    func testZeroIrregularityIsNearlyCircular() {
        for points in 4...12 {
            let path = BlobPath.path(BlobParameters(points: points, irregularity: 0, seed: 3))
            let curve = Self.sample(path, stepsPerCurve: 16)
            // Roundness is measured about the shape's own centroid, not the
            // middle of the frame: normalization centers the bounding box,
            // which leaves the blob a hair off-center.
            let center = (
                x: curve.map(\.x).reduce(0, +) / Double(curve.count),
                y: curve.map(\.y).reduce(0, +) / Double(curve.count)
            )
            let radii = curve.map {
                (($0.x - center.x) * ($0.x - center.x) + ($0.y - center.y) * ($0.y - center.y)).squareRoot()
            }
            let spread = radii.max()! / radii.min()!
            // Not exactly 1: each axis is normalized independently, so the
            // circle stretches by however far the control points bulge past
            // the anchors on that axis.
            XCTAssertLessThan(spread, 1.06, "\(points) points spread \(spread)")
            if points % 4 == 0 {
                // A multiple of 4 puts an anchor on all four edges of the box,
                // and an anchor's own handles run tangent to the circle there —
                // nothing bulges past it, so the stretch vanishes and the
                // generator's true circle shows through.
                XCTAssertEqual(spread, 1, accuracy: 0.005, "\(points) points spread \(spread)")
            }
        }
    }

    func testSmoothnessZeroGivesStraightEdges() {
        // With no handle length the cubics degenerate to the polygon: every
        // control point sits on its own anchor.
        let commands = BlobPath.commands(BlobParameters(points: 6, irregularity: 0.3, smoothness: 0, seed: 1))
        var previous = (x: 0.0, y: 0.0)
        if case .move(let x, let y) = commands[0] { previous = (x, y) }
        for command in commands.dropFirst() {
            guard case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y) = command else { continue }
            XCTAssertEqual(c1x, previous.x, accuracy: epsilon)
            XCTAssertEqual(c1y, previous.y, accuracy: epsilon)
            XCTAssertEqual(c2x, x, accuracy: epsilon)
            XCTAssertEqual(c2y, y, accuracy: epsilon)
            previous = (x, y)
        }
    }

    func testOutOfRangeParametersAreClamped() {
        let cases: [(BlobParameters, BlobParameters)] = [
            (BlobParameters(points: 0), BlobParameters(points: 3)),
            (BlobParameters(points: -5), BlobParameters(points: 3)),
            (BlobParameters(points: 99), BlobParameters(points: 12)),
            (BlobParameters(irregularity: -1), BlobParameters(irregularity: 0)),
            (BlobParameters(irregularity: 2), BlobParameters(irregularity: 1)),
            (BlobParameters(smoothness: -3), BlobParameters(smoothness: 0)),
            (BlobParameters(smoothness: 5), BlobParameters(smoothness: 1)),
        ]
        for (given, expected) in cases {
            XCTAssertEqual(BlobPath.path(given), BlobPath.path(expected), "\(given)")
        }
    }

    func testNonFiniteParametersStillRender() {
        // JSON cannot carry these, but a bad in-memory binding could, and a
        // NaN would otherwise poison every coordinate in the document.
        for parameters in [
            BlobParameters(irregularity: .nan),
            BlobParameters(smoothness: .nan),
            BlobParameters(irregularity: .infinity, smoothness: -.infinity),
        ] {
            let path = BlobPath.path(parameters)
            XCTAssertFalse(path.contains("nan"), path)
            XCTAssertFalse(path.contains("inf"), path)
            assertNormalized(path)
        }
    }

    func testExtremeParametersProduceValidPaths() {
        for points in [3, 12] {
            for irregularity in [0.0, 1.0] {
                for smoothness in [0.0, 1.0] {
                    let path = BlobPath.path(BlobParameters(
                        points: points,
                        irregularity: irregularity,
                        smoothness: smoothness,
                        seed: 17
                    ))
                    XCTAssertEqual(path.filter { $0 == "C" }.count, points, path)
                    assertNormalized(path)
                }
            }
        }
    }

    // MARK: - Presets

    func testPresetsAreValidAndDistinct() {
        XCTAssertEqual(BlobPath.presets.count, 6)
        var names: Set<String> = []
        var paths: Set<String> = []
        for preset in BlobPath.presets {
            XCTAssertTrue(names.insert(preset.name).inserted, "Duplicate preset name \(preset.name)")
            let path = BlobPath.path(preset.parameters)
            XCTAssertTrue(paths.insert(path).inserted, "\(preset.name) duplicates another preset")
            XCTAssertTrue(path.hasPrefix("M"), preset.name)
            XCTAssertTrue(path.hasSuffix("Z"), preset.name)
            XCTAssertEqual(path.filter { $0 == "C" }.count, preset.parameters.points, preset.name)
            XCTAssertNoThrow(try PathData.parse(path), preset.name)
            assertNormalized(path, message: preset.name)
        }
    }

    func testDefaultParameters() {
        XCTAssertEqual(BlobParameters.default.points, 6)
        XCTAssertEqual(BlobParameters.default.irregularity, 0.3)
        XCTAssertEqual(BlobParameters.default.smoothness, 1.0)
        XCTAssertEqual(BlobParameters.default.seed, 0)
        XCTAssertEqual(BlobParameters.default, BlobParameters())
    }

    // MARK: - Helpers

    private func assertNormalized(
        _ path: String,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let coordinates = Self.coordinates(in: path)
        XCTAssertFalse(coordinates.isEmpty, message, file: file, line: line)
        for value in coordinates {
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
        path.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "M" || $0 == "C" || $0 == "Z" })
            .map { Double($0) ?? .nan }
    }

    private static func boundingBox(of path: String) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let values = coordinates(in: path)
        let xs = values.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let ys = values.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        return (xs.min() ?? .nan, xs.max() ?? .nan, ys.min() ?? .nan, ys.max() ?? .nan)
    }

    /// Points on the curve itself, not just the control polygon.
    private static func sample(_ path: String, stepsPerCurve: Int) -> [(x: Double, y: Double)] {
        guard let commands = try? PathData.parse(path) else { return [] }
        var points: [(x: Double, y: Double)] = []
        var current = (x: 0.0, y: 0.0)
        for command in commands {
            switch command {
            case .move(let x, let y):
                current = (x, y)
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                for step in 1...stepsPerCurve {
                    let t = Double(step) / Double(stepsPerCurve)
                    let u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    points.append((
                        x: a * current.x + b * c1x + c * c2x + d * x,
                        y: a * current.y + b * c1y + c * c2y + d * y
                    ))
                }
                current = (x, y)
            default:
                break
            }
        }
        return points
    }
}
