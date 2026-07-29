import XCTest
@testable import FacetCore

/// The corner outline generator: the geometry each style actually produces,
/// the fitting rules that keep any combination of radii drawable, and the
/// on-disk form that has to keep every existing document readable.
final class CornerProfileTests: XCTestCase {

    // MARK: - Helpers

    /// Samples a command list into points, flattening curves so a test can ask
    /// where the outline actually goes rather than where its handles are.
    private func points(_ commands: [PathCommand], steps: Int = 200) -> [(x: Double, y: Double)] {
        var result: [(x: Double, y: Double)] = []
        var current = (x: 0.0, y: 0.0)
        var start = (x: 0.0, y: 0.0)
        func bezier(_ p0: (x: Double, y: Double), _ p1: (x: Double, y: Double),
                    _ p2: (x: Double, y: Double), _ p3: (x: Double, y: Double)) {
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                let u = 1 - t
                let x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
                let y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
                result.append((x, y))
            }
        }
        for command in commands {
            switch command {
            case .move(let x, let y):
                current = (x, y); start = current; result.append(current)
            case .line(let x, let y):
                current = (x, y); result.append(current)
            case .quad(let cx, let cy, let x, let y):
                bezier(current, (cx, cy), (cx, cy), (x, y)); current = (x, y)
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                bezier(current, (c1x, c1y), (c2x, c2y), (x, y)); current = (x, y)
            case .close:
                // `Z` draws a real line back to the start — a chamfer's last
                // bevel is exactly that line — so it has to be sampled too.
                for step in 1...steps {
                    let t = Double(step) / Double(steps)
                    result.append((current.x + (start.x - current.x) * t,
                                   current.y + (start.y - current.y) * t))
                }
                current = start
            }
        }
        return result
    }

    /// Where the outline crosses the diagonal out of the top-left corner, in
    /// points. That single number separates all four styles: a rounded corner
    /// sits at r(√2−1), a chamfer at r/√2, an inverted arc at exactly r, and a
    /// scallop at r√2.
    private func diagonalDepth(_ profile: CornerProfile, size: Double = 100) -> Double {
        let sampled = points(profile.outline(width: size, height: size))
            .filter { $0.x < 0.5 && $0.y < 0.5 }
        guard let onDiagonal = sampled.min(by: { abs($0.x - $0.y) < abs($1.x - $1.y) }) else { return 0 }
        return hypot(onDiagonal.x, onDiagonal.y) * size
    }

    // MARK: - Shape of each style

    func testASquareProfileIsFourPointsAndNoCurves() {
        let commands = CornerProfile.square.outline(width: 100, height: 100)
        XCTAssertEqual(commands, [
            .move(x: 0, y: 0), .line(x: 1, y: 0), .line(x: 1, y: 1), .line(x: 0, y: 1), .close,
        ])
    }

    func testARoundedProfileMatchesTheShapeGeneratorsRoundedRect() throws {
        // Same corner, same kappa: the two generators must not disagree about
        // what "rounded" means, or a shape layer and its own border would.
        let generated = CornerProfile(style: .rounded, radius: 25).outline(width: 100, height: 100)
        let reference = try PathData.parse(ShapeGenerator.roundedRect(
            topLeft: 0.25, topRight: 0.25, bottomRight: 0.25, bottomLeft: 0.25
        ))
        XCTAssertEqual(generated.count, reference.count)
        for (a, b) in zip(generated, reference) {
            switch (a, b) {
            case (.cubic(let a1, let a2, let a3, let a4, let a5, let a6),
                  .cubic(let b1, let b2, let b3, let b4, let b5, let b6)):
                for (x, y) in [(a1, b1), (a2, b2), (a3, b3), (a4, b4), (a5, b5), (a6, b6)] {
                    XCTAssertEqual(x, y, accuracy: 1e-4)
                }
            default:
                XCTAssertEqual(a, b)
            }
        }
    }

    func testChamferIsAStraightLineBetweenTheTangentPoints() {
        let commands = CornerProfile(style: .chamfered, radius: 20).outline(width: 100, height: 100)
        XCTAssertFalse(commands.contains { if case .cubic = $0 { return true }; return false },
                       "A bevel is a line; a curve here means the wrong style ran")
        // Move, four edges, three bevels, close — the fourth bevel is the
        // closing line `Z` already draws, so emitting it too would be a
        // duplicate segment rather than a corner.
        XCTAssertEqual(commands.count, 9)
    }

    func testTheFourStylesCutDifferentDepths() {
        // rounded keeps the most material at the corner, chamfered shaves a
        // flat off it, inverted bites a quarter circle out, scalloped scoops
        // deeper still. Ordering them is the cheapest way to catch two styles
        // that have quietly become the same drawing.
        let rounded = diagonalDepth(CornerProfile(style: .rounded, radius: 20))
        let chamfered = diagonalDepth(CornerProfile(style: .chamfered, radius: 20))
        let inverted = diagonalDepth(CornerProfile(style: .inverted, radius: 20))
        let scalloped = diagonalDepth(CornerProfile(style: .scalloped, radius: 20))

        XCTAssertLessThan(rounded, chamfered)
        XCTAssertLessThan(chamfered, inverted)
        XCTAssertLessThan(inverted, scalloped)

        // And the exact geometry, not just the ordering.
        XCTAssertEqual(rounded, 20 * (2.0.squareRoot() - 1), accuracy: 0.1)
        XCTAssertEqual(chamfered, 20 / 2.0.squareRoot(), accuracy: 0.1)
        XCTAssertEqual(inverted, 20, accuracy: 0.1)
        XCTAssertEqual(scalloped, 20 * 2.0.squareRoot(), accuracy: 0.1)
    }

    func testEveryStyleTouchesTheTangentPointsExactly() {
        // Whatever happens between them, a corner has to start and end on the
        // edges — otherwise the straight runs and the corners don't meet.
        for style in CornerStyle.allCases {
            let commands = CornerProfile(style: style, radius: 25).outline(width: 100, height: 200)
            let sampled = points(commands)
            // The top edge runs from x = 0.25 to x = 0.75 at y = 0 (radius 25
            // of 100 wide); the left edge from y = 0.125 to 0.875 at x = 0.
            XCTAssertTrue(sampled.contains { abs($0.x - 0.25) < 1e-6 && abs($0.y) < 1e-6 }, "\(style)")
            XCTAssertTrue(sampled.contains { abs($0.x) < 1e-6 && abs($0.y - 0.125) < 1e-6 }, "\(style)")
        }
    }

    func testCornersStayCircularOnANonSquareLayer() {
        // The whole reason `outline` takes a size: a corner is a circle in
        // points, so on a 300×100 layer it has to be an ellipse in normalized
        // space. An `Ellipse()`-style shortcut here is exactly the bug the
        // mask pass shipped once already.
        let commands = CornerProfile(style: .rounded, radius: 20).outline(width: 300, height: 100)
        guard case .line(let x, _) = commands[1] else { return XCTFail("Expected a top edge") }
        XCTAssertEqual(x, 1 - 20.0 / 300, accuracy: 1e-9)
        guard case .cubic(_, _, _, _, _, let y) = commands[2] else { return XCTFail("Expected a corner") }
        XCTAssertEqual(y, 20.0 / 100, accuracy: 1e-9)
    }

    // MARK: - Per-corner radii

    func testEachCornerGetsItsOwnRadius() {
        let profile = CornerProfile(style: .rounded, radii: CornerRadii(
            topLeading: 40, topTrailing: 0, bottomLeading: 0, bottomTrailing: 10
        ))
        let commands = profile.outline(width: 100, height: 100)
        // Starts partway along the top edge (the top-leading radius) and the
        // square top-trailing corner emits no curve at all.
        guard case .move(let x, let y) = commands[0] else { return XCTFail("Expected a move") }
        XCTAssertEqual(x, 0.4, accuracy: 1e-9)
        XCTAssertEqual(y, 0, accuracy: 1e-9)
        let curves = commands.filter { if case .cubic = $0 { return true }; return false }
        XCTAssertEqual(curves.count, 2, "Only the two rounded corners should curve")
    }

    // MARK: - Fitting

    func testOversizedRadiiScaleDownTogetherInsteadOfOverlapping() {
        // 80 + 80 on a 100pt edge cannot both fit; CSS's rule scales every
        // radius by one shared factor rather than singling one out.
        let profile = CornerProfile(style: .rounded, radius: 80)
        let sampled = points(profile.outline(width: 100, height: 100))
        for point in sampled {
            XCTAssertTrue((-1e-6...1.000001).contains(point.x), "x escaped: \(point.x)")
            XCTAssertTrue((-1e-6...1.000001).contains(point.y), "y escaped: \(point.y)")
        }
        // Scaled to exactly half the edge each, which is a capsule.
        guard case .move(let x, _) = profile.outline(width: 100, height: 100)[0] else {
            return XCTFail("Expected a move")
        }
        XCTAssertEqual(x, 0.5, accuracy: 1e-9)
    }

    func testEveryStyleStaysInsideTheUnitSquareAtEverySize() {
        // The scallop overshoots its own radius by ~21%, so it is fitted more
        // tightly than the rest; this is the check that says so.
        for style in CornerStyle.allCases {
            for radius in [0.0, 1, 7, 40, 100, 1000] {
                for (w, h) in [(100.0, 100.0), (300.0, 60.0), (40.0, 220.0), (1.0, 1.0)] {
                    let sampled = points(CornerProfile(style: style, radius: radius).outline(width: w, height: h))
                    for point in sampled {
                        XCTAssertTrue(
                            (-1e-6...1.000001).contains(point.x) && (-1e-6...1.000001).contains(point.y),
                            "\(style) r=\(radius) \(w)×\(h) left the box at \(point)"
                        )
                    }
                }
            }
        }
    }

    func testNonFiniteAndNegativeRadiiDegradeToSquare() {
        for bad in [Double.nan, .infinity, -.infinity, -12] {
            let commands = CornerProfile(style: .scalloped, radius: bad).outline(width: 100, height: 100)
            XCTAssertEqual(commands, CornerProfile.square.outline(width: 100, height: 100), "\(bad)")
        }
        // And a degenerate layer size does not divide by zero into NaN.
        let sampled = points(CornerProfile(style: .rounded, radius: 10).outline(width: 0, height: 0))
        XCTAssertFalse(sampled.contains { $0.x.isNaN || $0.y.isNaN })
    }

    // MARK: - The fast path

    func testOnlyAUniformRoundedProfileTakesTheFastPath() {
        XCTAssertEqual(CornerProfile.square.simpleRadius, 0)
        XCTAssertEqual(CornerProfile(style: .rounded, radius: 12).simpleRadius, 12)
        // A style with nothing to cut is still a right angle, so it stays on
        // the cheap path rather than generating a rectangle the long way.
        XCTAssertEqual(CornerProfile(style: .scalloped, radius: 0).simpleRadius, 0)
        XCTAssertNil(CornerProfile(style: .chamfered, radius: 12).simpleRadius)
        XCTAssertNil(CornerProfile(
            style: .rounded,
            radii: CornerRadii(topLeading: 12, topTrailing: 4, bottomLeading: 12, bottomTrailing: 12)
        ).simpleRadius)
        // A NaN radius sanitizes to square, so it stays on the fast path too —
        // a corrupt document renders as a plain rectangle, not as a generated
        // path full of NaN coordinates.
        XCTAssertEqual(CornerProfile(style: .rounded, radius: .nan).simpleRadius, 0)
        XCTAssertEqual(CornerProfile(style: .chamfered, radius: -5).simpleRadius, 0)
    }

    func testInsettingShrinksConvexCornersAndHoldsConcaveOnes() {
        let rounded = CornerProfile(style: .rounded, radius: 10).inset(by: 4)
        XCTAssertEqual(rounded.radii.uniform, 6)
        XCTAssertEqual(CornerProfile(style: .rounded, radius: 2).inset(by: 9).radii.uniform, 0)
        // A notch does not shrink when the boundary moves into the material —
        // the offset of a concave arc grows, so holding is the closer answer.
        XCTAssertEqual(CornerProfile(style: .inverted, radius: 10).inset(by: 4).radii.uniform, 10)
        XCTAssertEqual(CornerProfile(style: .scalloped, radius: 10).inset(by: 4).radii.uniform, 10)
    }

    // MARK: - Persistence

    func testAProfileThatIsOnlyARadiusEncodesAsOnlyARadius() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(
            String(decoding: try encoder.encode(CornerProfile(style: .rounded, radius: 12)), as: UTF8.self),
            "{\"radius\":12}"
        )
        XCTAssertEqual(
            String(decoding: try encoder.encode(CornerProfile.square), as: UTF8.self),
            "{}"
        )
        XCTAssertEqual(
            String(decoding: try encoder.encode(CornerProfile(style: .chamfered, radius: 12)), as: UTF8.self),
            "{\"radius\":12,\"style\":\"chamfered\"}"
        )
    }

    func testProfilesRoundTripIncludingPerCornerRadii() throws {
        let profiles = [
            CornerProfile.square,
            CornerProfile(style: .rounded, radius: 12),
            CornerProfile(style: .inverted, radius: 3.5),
            CornerProfile(style: .scalloped, radii: CornerRadii(
                topLeading: 40, topTrailing: 0, bottomLeading: 6, bottomTrailing: 6
            )),
        ]
        for profile in profiles {
            let data = try JSONEncoder().encode(profile)
            XCTAssertEqual(try JSONDecoder().decode(CornerProfile.self, from: data), profile)
        }
    }

    func testAPartialProfileFillsInFromTheRadiusShorthand() throws {
        let profile = try JSONDecoder().decode(
            CornerProfile.self,
            from: Data(#"{"style":"inverted","radius":8,"topTrailing":20}"#.utf8)
        )
        XCTAssertEqual(profile.style, .inverted)
        XCTAssertEqual(profile.radii.topLeading, 8)
        XCTAssertEqual(profile.radii.topTrailing, 20)
        XCTAssertEqual(profile.radii.bottomTrailing, 8)

        // An empty object is a square rounded profile: what an absent key means.
        XCTAssertEqual(try JSONDecoder().decode(CornerProfile.self, from: Data("{}".utf8)), .square)
    }
}
