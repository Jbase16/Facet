import XCTest
@testable import FacetCore

final class GaugeGeometryTests: XCTestCase {
    private let epsilon = 0.0001

    /// One representative spread over the whole parameter space, reused by the
    /// invariant tests so that "parses", "stays in the layer", and "clears the
    /// stroke inset" are all checked over the same corners.
    private static let spread: [(name: String, arc: GaugeArc, lineWidth: Double)] = {
        var cases: [(String, GaugeArc, Double)] = []
        for value in [0.0, 0.25, 0.5, 0.75, 1.0] {
            for sweep in [360.0, 270, 180, 90, 1] {
                for direction in [GaugeDirection.clockwise, .counterClockwise] {
                    for cap in [GaugeCap.butt, .round] {
                        for start in [0.0, 45, 180, -90] {
                            for width in [0.0, 0.08, 0.25, 0.5] {
                                cases.append((
                                    "ring v\(value) s\(sweep) \(direction) \(cap) @\(start) w\(width)",
                                    GaugeGeometry.ring(
                                        value: value, startAngle: start, sweep: sweep,
                                        direction: direction, cap: cap, lineWidth: width
                                    ),
                                    width
                                ))
                            }
                        }
                    }
                }
            }
            for cap in [GaugeCap.butt, .round] {
                for width in [0.0, 0.08, 0.5] {
                    cases.append((
                        "bar v\(value) \(cap) w\(width)",
                        GaugeGeometry.bar(value: value, cap: cap, lineWidth: width),
                        width
                    ))
                }
            }
            for segments in [2, 5, 12, 60] {
                for sweep in [360.0, 270, 180] {
                    for gap in [0.0, 4, 20] {
                        for direction in [GaugeDirection.clockwise, .counterClockwise] {
                            for cap in [GaugeCap.butt, .round] {
                                cases.append((
                                    "segmented v\(value) n\(segments) s\(sweep) g\(gap) \(direction) \(cap)",
                                    GaugeGeometry.segmented(
                                        value: value, segments: segments, startAngle: 0, sweep: sweep,
                                        direction: direction, gapDegrees: gap, lineWidth: 0.12, cap: cap
                                    ),
                                    0.12
                                ))
                            }
                        }
                    }
                }
            }
        }
        return cases
    }()

    // MARK: - Determinism

    func testEveryFamilyIsDeterministic() {
        for _ in 0..<3 {
            XCTAssertEqual(
                GaugeGeometry.ring(value: 0.37, startAngle: 23, sweep: 271, direction: .clockwise, cap: .round, lineWidth: 0.11),
                GaugeGeometry.ring(value: 0.37, startAngle: 23, sweep: 271, direction: .clockwise, cap: .round, lineWidth: 0.11)
            )
            XCTAssertEqual(
                GaugeGeometry.bar(value: 0.63, cap: .butt, lineWidth: 0.09),
                GaugeGeometry.bar(value: 0.63, cap: .butt, lineWidth: 0.09)
            )
            XCTAssertEqual(
                GaugeGeometry.segmented(value: 0.41, segments: 9, startAngle: -17, sweep: 233, direction: .counterClockwise, gapDegrees: 5.5, lineWidth: 0.13),
                GaugeGeometry.segmented(value: 0.41, segments: 9, startAngle: -17, sweep: 233, direction: .counterClockwise, gapDegrees: 5.5, lineWidth: 0.13)
            )
        }
    }

    func testDistinctParametersProduceDistinctPaths() {
        var seen: Set<String> = []
        for value in stride(from: 0.05, through: 1, by: 0.05) {
            let arc = GaugeGeometry.ring(
                value: value, startAngle: 0, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1
            )
            XCTAssertTrue(seen.insert(arc.progress).inserted, "value \(value) collided")
        }
        seen.removeAll()
        for sweep in stride(from: 30.0, through: 360, by: 30) {
            let arc = GaugeGeometry.ring(
                value: 0.5, startAngle: 0, sweep: sweep, direction: .clockwise, cap: .butt, lineWidth: 0.1
            )
            XCTAssertTrue(seen.insert(arc.track).inserted, "sweep \(sweep) collided")
        }
    }

    // MARK: - Invariants across every family

    func testEveryPathParses() throws {
        for (name, arc, _) in Self.spread {
            for (role, path) in [("track", arc.track), ("progress", arc.progress)] {
                let commands = try PathData.parse(path)
                guard !path.isEmpty else {
                    XCTAssertTrue(commands.isEmpty, "\(name) \(role)")
                    continue
                }
                XCTAssertTrue(path.hasPrefix("M"), "\(name) \(role): \(path)")
                guard case .move = commands.first else {
                    return XCTFail("\(name) \(role) must start with a move")
                }
            }
        }
    }

    func testTrackIsNeverEmpty() {
        // Every gauge has a track to draw even at value 0; only the fill goes away.
        for (name, arc, _) in Self.spread {
            XCTAssertFalse(arc.track.isEmpty, name)
        }
    }

    func testEveryCoordinateIsFiniteAndInsideTheLayer() {
        for (name, arc, _) in Self.spread {
            for path in [arc.track, arc.progress] where !path.isEmpty {
                let values = Self.coordinates(in: path)
                XCTAssertFalse(values.isEmpty, name)
                for value in values {
                    XCTAssertTrue(value.isFinite, "\(name): \(path)")
                    XCTAssertGreaterThanOrEqual(value, -epsilon, "\(name): \(path)")
                    XCTAssertLessThanOrEqual(value, 1 + epsilon, "\(name): \(path)")
                }
            }
        }
    }

    /// The reason the arc radius insets at all: half the stroke hangs outside
    /// the path, so a path running along the layer edge would be clipped.
    /// Control points count — a Bézier hull that pokes out is a stroke that
    /// pokes out.
    func testLineWidthInsetKeepsTheStrokeInsideTheLayer() {
        for (name, arc, lineWidth) in Self.spread {
            let margin = lineWidth / 2 - epsilon
            for path in [arc.track, arc.progress] where !path.isEmpty {
                for value in Self.coordinates(in: path) {
                    XCTAssertGreaterThanOrEqual(value, margin, "\(name) crowds the edge: \(path)")
                    XCTAssertLessThanOrEqual(value, 1 - margin, "\(name) crowds the edge: \(path)")
                }
            }
        }
    }

    /// A gauge must stay concentric with its layer — no bounding-box
    /// normalization — or a partial arc would drift off the value label sitting
    /// at the layer's centre.
    func testPartialArcsStayConcentricRatherThanFillingTheBox() {
        let radius = 0.5 - 0.1 / 2
        for sweep in [360.0, 300, 270, 180, 120, 90, 30] {
            for start in [0.0, 45, 137, -90] {
                let arc = GaugeGeometry.ring(
                    value: 1, startAngle: start, sweep: sweep,
                    direction: .clockwise, cap: .butt, lineWidth: 0.1
                )
                for point in Self.sample(arc.track, stepsPerCurve: 16) {
                    let dx = point.x - 0.5
                    let dy = point.y - 0.5
                    XCTAssertEqual(
                        (dx * dx + dy * dy).squareRoot(), radius, accuracy: 0.001,
                        "sweep \(sweep) @\(start) left the circle: \(arc.track)"
                    )
                }
            }
        }
    }

    // MARK: - Value

    func testValueZeroDrawsNothing() {
        for sweep in [360.0, 270, 180] {
            XCTAssertEqual(GaugeGeometry.ring(
                value: 0, startAngle: 0, sweep: sweep, direction: .clockwise, cap: .round, lineWidth: 0.1
            ).progress, "")
        }
        XCTAssertEqual(GaugeGeometry.bar(value: 0, cap: .round, lineWidth: 0.1).progress, "")
        XCTAssertEqual(GaugeGeometry.segmented(
            value: 0, segments: 8, startAngle: 0, sweep: 360,
            direction: .clockwise, gapDegrees: 6, lineWidth: 0.12
        ).progress, "")
    }

    func testValueOneFillsExactlyTheTrack() {
        for sweep in [360.0, 270, 180, 90] {
            for direction in [GaugeDirection.clockwise, .counterClockwise] {
                let arc = GaugeGeometry.ring(
                    value: 1, startAngle: 37, sweep: sweep,
                    direction: direction, cap: .butt, lineWidth: 0.1
                )
                XCTAssertEqual(arc.progress, arc.track, "sweep \(sweep) \(direction)")
            }
        }
        let bar = GaugeGeometry.bar(value: 1, cap: .butt, lineWidth: 0.1)
        XCTAssertEqual(bar.progress, bar.track)
        let segmented = GaugeGeometry.segmented(
            value: 1, segments: 7, startAngle: 0, sweep: 300,
            direction: .clockwise, gapDegrees: 8, lineWidth: 0.12
        )
        XCTAssertEqual(segmented.progress, segmented.track)
    }

    func testProgressLengthGrowsMonotonicallyWithValue() {
        for sweep in [360.0, 270, 180] {
            for direction in [GaugeDirection.clockwise, .counterClockwise] {
                var previous = -1.0
                for value in stride(from: 0.0, through: 1.0, by: 0.05) {
                    let arc = GaugeGeometry.ring(
                        value: value, startAngle: 20, sweep: sweep,
                        direction: direction, cap: .butt, lineWidth: 0.1
                    )
                    let length = Self.length(of: arc.progress)
                    XCTAssertGreaterThan(
                        length, previous,
                        "sweep \(sweep) \(direction) stalled at value \(value)"
                    )
                    previous = length
                }
                // And the full sweep is exactly the track's own length.
                let full = GaugeGeometry.ring(
                    value: 1, startAngle: 20, sweep: sweep,
                    direction: direction, cap: .butt, lineWidth: 0.1
                )
                XCTAssertEqual(previous, Self.length(of: full.track), accuracy: 1e-6)
            }
        }
    }

    func testProgressLengthIsTheExpectedFractionOfTheTrack() {
        for sweep in [360.0, 270, 180, 90] {
            let track = Self.length(of: GaugeGeometry.ring(
                value: 1, startAngle: 0, sweep: sweep, direction: .clockwise, cap: .butt, lineWidth: 0.1
            ).track)
            for value in [0.1, 0.25, 0.5, 0.75, 0.9] {
                let filled = Self.length(of: GaugeGeometry.ring(
                    value: value, startAngle: 0, sweep: sweep, direction: .clockwise, cap: .butt, lineWidth: 0.1
                ).progress)
                XCTAssertEqual(filled / track, value, accuracy: 0.002, "sweep \(sweep) at \(value)")
            }
        }
    }

    // MARK: - Angles

    func testZeroDegreesIsTwelveOClockAndPositiveIsClockwise() {
        let arc = GaugeGeometry.ring(
            value: 0.25, startAngle: 0, sweep: 360, direction: .clockwise, cap: .butt, lineWidth: 0.1
        )
        let points = Self.sample(arc.progress, stepsPerCurve: 8)
        let radius = 0.45
        // Starts at the top...
        XCTAssertEqual(points.first!.x, 0.5, accuracy: epsilon)
        XCTAssertEqual(points.first!.y, 0.5 - radius, accuracy: epsilon)
        // ...and a quarter turn clockwise ends at 3 o'clock.
        XCTAssertEqual(points.last!.x, 0.5 + radius, accuracy: epsilon)
        XCTAssertEqual(points.last!.y, 0.5, accuracy: epsilon)

        // 180° starts at the bottom, the natural place for a half-dial.
        let dial = GaugeGeometry.ring(
            value: 0, startAngle: 180, sweep: 180, direction: .clockwise, cap: .butt, lineWidth: 0.1
        )
        let start = Self.sample(dial.track, stepsPerCurve: 4).first!
        XCTAssertEqual(start.x, 0.5, accuracy: epsilon)
        XCTAssertEqual(start.y, 0.5 + radius, accuracy: epsilon)
    }

    func testDirectionReversesTheSweep() {
        for sweep in [360.0, 270, 180] {
            for value in [0.25, 0.5, 0.8] {
                let clockwise = GaugeGeometry.ring(
                    value: value, startAngle: 0, sweep: sweep, direction: .clockwise, cap: .butt, lineWidth: 0.1
                )
                let counter = GaugeGeometry.ring(
                    value: value, startAngle: 0, sweep: sweep, direction: .counterClockwise, cap: .butt, lineWidth: 0.1
                )
                XCTAssertNotEqual(clockwise.progress, counter.progress, "sweep \(sweep) at \(value)")

                // Reversing from a start angle at 12 o'clock is a mirror about
                // the vertical axis, point for point.
                let forward = Self.sample(clockwise.progress, stepsPerCurve: 12)
                let backward = Self.sample(counter.progress, stepsPerCurve: 12)
                XCTAssertEqual(forward.count, backward.count, "sweep \(sweep)")
                for (a, b) in zip(forward, backward) {
                    XCTAssertEqual(a.x, 1 - b.x, accuracy: 0.001, "sweep \(sweep) at \(value)")
                    XCTAssertEqual(a.y, b.y, accuracy: 0.001, "sweep \(sweep) at \(value)")
                }
            }
        }
    }

    func testStartAngleRotatesWithoutChangingArcLength() {
        for sweep in [360.0, 270, 180, 90] {
            let reference = Self.length(of: GaugeGeometry.ring(
                value: 0.6, startAngle: 0, sweep: sweep, direction: .clockwise, cap: .butt, lineWidth: 0.1
            ).progress)
            let starts: [Double] = [17, 45, 90, 137, 180, 275, 359, -60]
            for start in starts {
                let arc = GaugeGeometry.ring(
                    value: 0.6, startAngle: start, sweep: sweep, direction: .clockwise, cap: .butt, lineWidth: 0.1
                )
                XCTAssertEqual(
                    Self.length(of: arc.progress), reference, accuracy: reference * 0.002,
                    "start \(start) changed the arc length at sweep \(sweep)"
                )
            }
        }
    }

    func testStartAngleWrapsRatherThanDrifting() {
        let reference = GaugeGeometry.ring(
            value: 0.5, startAngle: 30, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1
        )
        let wrapping: [Double] = [390, 750, 30 + 360 * 4]
        for start in wrapping {
            XCTAssertEqual(
                GaugeGeometry.ring(
                    value: 0.5, startAngle: start, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1
                ),
                reference,
                "start \(start)"
            )
        }
    }

    func testFullSweepIsAClosedRing() {
        for direction in [GaugeDirection.clockwise, .counterClockwise] {
            let arc = GaugeGeometry.ring(
                value: 1, startAngle: 0, sweep: 360, direction: direction, cap: .butt, lineWidth: 0.1
            )
            XCTAssertTrue(arc.track.hasSuffix("Z"), arc.track)
            XCTAssertEqual(arc.track.filter { $0 == "C" }.count, 4, "one cubic per quadrant: \(arc.track)")
            let points = Self.sample(arc.track, stepsPerCurve: 24)
            XCTAssertEqual(points.first!.x, points.last!.x, accuracy: epsilon)
            XCTAssertEqual(points.first!.y, points.last!.y, accuracy: epsilon)
            // Circumference of the inset circle, within Bézier tolerance.
            XCTAssertEqual(Self.length(of: arc.track), 2 * .pi * 0.45, accuracy: 0.002)
        }

        // A partial sweep is open — no `Z` butting two caps together at a seam.
        for sweep in [359.0, 270, 180, 90] {
            let arc = GaugeGeometry.ring(
                value: 1, startAngle: 0, sweep: sweep, direction: .clockwise, cap: .round, lineWidth: 0.1
            )
            XCTAssertFalse(arc.track.contains("Z"), "sweep \(sweep): \(arc.track)")
        }
    }

    func testSweepControlsHowMuchOfTheCircleTheGaugeSpans() {
        let circumference = 2 * .pi * 0.45
        for sweep in [360.0, 270, 180, 90, 45] {
            let arc = GaugeGeometry.ring(
                value: 1, startAngle: 0, sweep: sweep, direction: .clockwise, cap: .butt, lineWidth: 0.1
            )
            XCTAssertEqual(
                Self.length(of: arc.track), circumference * sweep / 360, accuracy: 0.002,
                "sweep \(sweep)"
            )
        }
    }

    // MARK: - Bar

    func testBarIsAStraightRunAcrossTheMiddle() {
        let arc = GaugeGeometry.bar(value: 0.5, cap: .round, lineWidth: 0.2)
        XCTAssertEqual(arc.track, "M0.1,0.5 L0.9,0.5")
        XCTAssertEqual(arc.progress, "M0.1,0.5 L0.5,0.5")
        XCTAssertEqual(arc.cap, .round)

        // The inset exists so a round cap does not bulge past the layer edge.
        XCTAssertEqual(GaugeGeometry.bar(value: 1, cap: .butt, lineWidth: 0).track, "M0,0.5 L1,0.5")
    }

    func testBarProgressGrowsMonotonically() {
        var previous = -1.0
        for value in stride(from: 0.0, through: 1.0, by: 0.05) {
            let length = Self.length(of: GaugeGeometry.bar(value: value, cap: .butt, lineWidth: 0.1).progress)
            XCTAssertGreaterThan(length, previous, "stalled at \(value)")
            previous = length
        }
    }

    // MARK: - Segmented

    func testSegmentedProducesOnePiecePerSegment() {
        for segments in [2, 3, 5, 8, 12, 60] {
            for sweep in [360.0, 270, 180] {
                for gap in [0.0, 3, 12] {
                    let arc = GaugeGeometry.segmented(
                        value: 1, segments: segments, startAngle: 0, sweep: sweep,
                        direction: .clockwise, gapDegrees: gap, lineWidth: 0.12
                    )
                    XCTAssertEqual(
                        arc.track.filter { $0 == "M" }.count, segments,
                        "n\(segments) s\(sweep) g\(gap): \(arc.track)"
                    )
                }
            }
        }
    }

    func testSegmentedLightsWholeTicksAsTheValueReachesThem() {
        // 8 ticks: the fill is a count, not a smooth arc, so a value part-way
        // into a tick lights all of it.
        let expected: [(value: Double, lit: Int)] = [
            (0.0, 0), (0.001, 1), (0.124, 1), (0.125, 1), (0.126, 2),
            (0.25, 2), (0.3, 3), (0.5, 4), (0.51, 5), (0.99, 8), (1.0, 8),
        ]
        for (value, lit) in expected {
            let arc = GaugeGeometry.segmented(
                value: value, segments: 8, startAngle: 0, sweep: 360,
                direction: .clockwise, gapDegrees: 6, lineWidth: 0.12
            )
            XCTAssertEqual(arc.progress.filter { $0 == "M" }.count, lit, "value \(value): \(arc.progress)")
        }
    }

    func testSegmentedLitCountNeverDecreases() {
        for segments in [2, 5, 12, 60] {
            var previous = 0
            for value in stride(from: 0.0, through: 1.0, by: 0.01) {
                let arc = GaugeGeometry.segmented(
                    value: value, segments: segments, startAngle: 0, sweep: 270,
                    direction: .counterClockwise, gapDegrees: 4, lineWidth: 0.12
                )
                let lit = arc.progress.filter { $0 == "M" }.count
                XCTAssertGreaterThanOrEqual(lit, previous, "n\(segments) at \(value)")
                XCTAssertLessThanOrEqual(lit, segments, "n\(segments) at \(value)")
                previous = lit
            }
            XCTAssertEqual(previous, segments, "n\(segments) never filled")
        }
    }

    func testSegmentedGapsAddUpToTheRequestedSweep() {
        // A full turn wraps, so it carries one gap per tick; a partial arc has
        // one fewer and therefore starts and ends exactly on the plain ring's
        // ends at the same sweep.
        for segments in [2, 5, 12] {
            for (sweep, gapCount) in [(360.0, segments), (270.0, segments - 1), (180.0, segments - 1)] {
                let gap = 4.0
                let arc = GaugeGeometry.segmented(
                    value: 1, segments: segments, startAngle: 0, sweep: sweep,
                    direction: .clockwise, gapDegrees: gap, lineWidth: 0.1
                )
                let drawn = Self.length(of: arc.track)
                let expected = 2 * .pi * 0.45 * (sweep - gap * Double(gapCount)) / 360
                XCTAssertEqual(drawn, expected, accuracy: 0.003, "n\(segments) s\(sweep)")
            }
        }

        // The ends of a partial segmented arc coincide with the plain ring's.
        let ring = GaugeGeometry.ring(
            value: 1, startAngle: 20, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1
        )
        let segmented = GaugeGeometry.segmented(
            value: 1, segments: 6, startAngle: 20, sweep: 270,
            direction: .clockwise, gapDegrees: 6, lineWidth: 0.1
        )
        let ringPoints = Self.sample(ring.track, stepsPerCurve: 8)
        let segmentPoints = Self.sample(segmented.track, stepsPerCurve: 8)
        XCTAssertEqual(ringPoints.first!.x, segmentPoints.first!.x, accuracy: 0.001)
        XCTAssertEqual(ringPoints.first!.y, segmentPoints.first!.y, accuracy: 0.001)
        XCTAssertEqual(ringPoints.last!.x, segmentPoints.last!.x, accuracy: 0.001)
        XCTAssertEqual(ringPoints.last!.y, segmentPoints.last!.y, accuracy: 0.001)
    }

    func testSegmentedGapIsClampedSoATickNeverVanishes() {
        for segments in [2, 8, 60] {
            for sweep in [360.0, 180] {
                let arc = GaugeGeometry.segmented(
                    value: 1, segments: segments, startAngle: 0, sweep: sweep,
                    direction: .clockwise, gapDegrees: 9_000, lineWidth: 0.1
                )
                XCTAssertEqual(arc.track.filter { $0 == "M" }.count, segments)
                XCTAssertGreaterThan(Self.length(of: arc.track), 0, "n\(segments) s\(sweep)")
            }
        }
    }

    // MARK: - Clamping

    func testOutOfRangeParametersClampInsteadOfTrapping() {
        // Values outside 0...1 pin to the ends rather than overshooting the ring.
        XCTAssertEqual(
            GaugeGeometry.ring(value: -3, startAngle: 0, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1),
            GaugeGeometry.ring(value: 0, startAngle: 0, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1)
        )
        XCTAssertEqual(
            GaugeGeometry.ring(value: 4, startAngle: 0, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1),
            GaugeGeometry.ring(value: 1, startAngle: 0, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1)
        )
        // A hand-edited document asking for two turns gets one.
        XCTAssertEqual(
            GaugeGeometry.ring(value: 1, startAngle: 0, sweep: 720, direction: .clockwise, cap: .butt, lineWidth: 0.1),
            GaugeGeometry.ring(value: 1, startAngle: 0, sweep: 360, direction: .clockwise, cap: .butt, lineWidth: 0.1)
        )
        XCTAssertEqual(
            GaugeGeometry.ring(value: 1, startAngle: 0, sweep: -50, direction: .clockwise, cap: .butt, lineWidth: 0.1),
            GaugeGeometry.ring(value: 1, startAngle: 0, sweep: 1, direction: .clockwise, cap: .butt, lineWidth: 0.1)
        )
        // A stroke thicker than the layer becomes a disc, not an inverted ring.
        XCTAssertEqual(
            GaugeGeometry.ring(value: 1, startAngle: 0, sweep: 360, direction: .clockwise, cap: .butt, lineWidth: 40),
            GaugeGeometry.ring(value: 1, startAngle: 0, sweep: 360, direction: .clockwise, cap: .butt, lineWidth: 0.5)
        )
        XCTAssertEqual(
            GaugeGeometry.bar(value: 2, cap: .butt, lineWidth: -1),
            GaugeGeometry.bar(value: 1, cap: .butt, lineWidth: 0)
        )
        XCTAssertEqual(
            GaugeGeometry.segmented(value: 9, segments: 1, startAngle: 0, sweep: 900, direction: .clockwise, gapDegrees: -4, lineWidth: 0.1),
            GaugeGeometry.segmented(value: 1, segments: 2, startAngle: 0, sweep: 360, direction: .clockwise, gapDegrees: 0, lineWidth: 0.1)
        )
        XCTAssertEqual(
            GaugeGeometry.segmented(value: 0.5, segments: 900, startAngle: 0, sweep: 180, direction: .clockwise, gapDegrees: 2, lineWidth: 0.1),
            GaugeGeometry.segmented(value: 0.5, segments: 60, startAngle: 0, sweep: 180, direction: .clockwise, gapDegrees: 2, lineWidth: 0.1)
        )
    }

    func testNonFiniteParametersFallBackInsteadOfPoisoningThePath() {
        // JSON cannot carry these, but a bad in-memory binding can, and one NaN
        // would otherwise reach the renderer as an undrawable coordinate.
        let arcs = [
            GaugeGeometry.ring(value: .nan, startAngle: .nan, sweep: .nan, direction: .clockwise, cap: .butt, lineWidth: .nan),
            GaugeGeometry.ring(value: .infinity, startAngle: -.infinity, sweep: .infinity, direction: .counterClockwise, cap: .round, lineWidth: .infinity),
            GaugeGeometry.ring(value: 0.5, startAngle: .infinity, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1),
            GaugeGeometry.bar(value: .nan, cap: .round, lineWidth: .infinity),
            GaugeGeometry.segmented(value: .nan, segments: 8, startAngle: .nan, sweep: .nan, direction: .clockwise, gapDegrees: .nan, lineWidth: .nan),
            GaugeGeometry.segmented(value: 0.5, segments: 8, startAngle: 0, sweep: 360, direction: .clockwise, gapDegrees: -.infinity, lineWidth: 0.12),
        ]
        for arc in arcs {
            for path in [arc.track, arc.progress] {
                XCTAssertFalse(path.lowercased().contains("nan"), path)
                XCTAssertFalse(path.lowercased().contains("inf"), path)
                XCTAssertNoThrow(try PathData.parse(path), path)
                for value in Self.coordinates(in: path) {
                    XCTAssertTrue(value.isFinite, path)
                    XCTAssertGreaterThanOrEqual(value, -epsilon, path)
                    XCTAssertLessThanOrEqual(value, 1 + epsilon, path)
                }
            }
        }

        // Each non-finite input resolves to its documented default, not to
        // whatever the last clamp happened to produce.
        XCTAssertEqual(
            GaugeGeometry.ring(value: .nan, startAngle: 0, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1).progress,
            ""
        )
        XCTAssertEqual(
            GaugeGeometry.ring(value: 1, startAngle: .nan, sweep: .nan, direction: .clockwise, cap: .butt, lineWidth: .nan),
            GaugeGeometry.ring(value: 1, startAngle: 0, sweep: 360, direction: .clockwise, cap: .butt, lineWidth: 0.1)
        )
        XCTAssertEqual(
            GaugeGeometry.bar(value: 1, cap: .butt, lineWidth: .nan),
            GaugeGeometry.bar(value: 1, cap: .butt, lineWidth: 0.1)
        )
        XCTAssertEqual(
            GaugeGeometry.segmented(value: 1, segments: 6, startAngle: 0, sweep: 360, direction: .clockwise, gapDegrees: .nan, lineWidth: 0.1),
            GaugeGeometry.segmented(value: 1, segments: 6, startAngle: 0, sweep: 360, direction: .clockwise, gapDegrees: 0, lineWidth: 0.1)
        )
    }

    // MARK: - Cap

    func testCapIsCarriedThroughForTheRenderer() {
        for cap in [GaugeCap.butt, .round] {
            XCTAssertEqual(GaugeGeometry.ring(
                value: 0.5, startAngle: 0, sweep: 270, direction: .clockwise, cap: cap, lineWidth: 0.1
            ).cap, cap)
            XCTAssertEqual(GaugeGeometry.bar(value: 0.5, cap: cap, lineWidth: 0.1).cap, cap)
            XCTAssertEqual(GaugeGeometry.segmented(
                value: 0.5, segments: 6, startAngle: 0, sweep: 360,
                direction: .clockwise, gapDegrees: 5, lineWidth: 0.1, cap: cap
            ).cap, cap)
        }
        // For a ring the cap changes nothing but how the renderer strokes it.
        XCTAssertEqual(
            GaugeGeometry.ring(value: 0.5, startAngle: 0, sweep: 270, direction: .clockwise, cap: .butt, lineWidth: 0.1).progress,
            GaugeGeometry.ring(value: 0.5, startAngle: 0, sweep: 270, direction: .clockwise, cap: .round, lineWidth: 0.1).progress
        )
    }

    /// The one place a cap has to change the geometry. A round cap paints half
    /// a line width past each end, so ticks are shortened by exactly that much
    /// — otherwise an 8-tick ring with a 6° gap and a 0.12 stroke draws as a
    /// solid ring and the gap looks broken.
    func testRoundCapsShortenTicksSoTheGapsSurvive() {
        let lineWidth = 0.12
        for segments in [5, 8, 12] {
            // Gaps chosen so the tick is still longer than the two caps; past
            // that point it floors to a dot, which the next test covers.
            for gap in [4.0, 6, 10] {
                let butt = GaugeGeometry.segmented(
                    value: 1, segments: segments, startAngle: 0, sweep: 360,
                    direction: .clockwise, gapDegrees: gap, lineWidth: lineWidth, cap: .butt
                )
                let round = GaugeGeometry.segmented(
                    value: 1, segments: segments, startAngle: 0, sweep: 360,
                    direction: .clockwise, gapDegrees: gap, lineWidth: lineWidth, cap: .round
                )
                XCTAssertEqual(round.track.filter { $0 == "M" }.count, segments)
                // Each tick gives back one whole line width of path, which the
                // two caps then paint back on: same painted extent, gaps intact.
                XCTAssertEqual(
                    Self.length(of: round.track) + Double(segments) * lineWidth,
                    Self.length(of: butt.track),
                    accuracy: 0.01,
                    "n\(segments) gap\(gap)"
                )
            }
        }
    }

    func testRoundCapsNeverInvertAShortTick() {
        // 60 ticks at the widest gap the clamp allows leaves far less arc than
        // the cap overhang; the tick floors to a dot instead of running backwards.
        for sweep in [360.0, 180, 1] {
            let arc = GaugeGeometry.segmented(
                value: 1, segments: 60, startAngle: 0, sweep: sweep,
                direction: .clockwise, gapDegrees: 9_000, lineWidth: 0.5, cap: .round
            )
            XCTAssertEqual(arc.track.filter { $0 == "M" }.count, 60, "sweep \(sweep)")
            XCTAssertGreaterThan(Self.length(of: arc.track), 0, "sweep \(sweep)")
            for value in Self.coordinates(in: arc.track) {
                XCTAssertTrue(value.isFinite, arc.track)
                XCTAssertGreaterThanOrEqual(value, 0.25 - epsilon, arc.track)
                XCTAssertLessThanOrEqual(value, 0.75 + epsilon, arc.track)
            }
        }
    }

    func testCapAndDirectionRoundTripThroughCodable() throws {
        // These land in `.facet` JSON, so their spellings are part of the format.
        let encoder = JSONEncoder()
        XCTAssertEqual(String(data: try encoder.encode(GaugeCap.round), encoding: .utf8), "\"round\"")
        XCTAssertEqual(String(data: try encoder.encode(GaugeCap.butt), encoding: .utf8), "\"butt\"")
        XCTAssertEqual(
            String(data: try encoder.encode(GaugeDirection.counterClockwise), encoding: .utf8),
            "\"counterClockwise\""
        )
        XCTAssertEqual(GaugeCap(rawValue: "round"), .round)
        XCTAssertEqual(GaugeDirection(rawValue: "clockwise"), .clockwise)
    }

    // MARK: - Helpers

    /// Every number in a path, in emission order. Parsed straight from the
    /// string rather than through `PathData` so these tests fail if the two
    /// ever disagree about the output format.
    private static func coordinates(in path: String) -> [Double] {
        path.split(whereSeparator: { " ,MLCQZ".contains($0) })
            .map { Double($0) ?? .nan }
    }

    /// Length of the drawn curve, measured by sampling — the only measurement
    /// that catches a Bézier whose control points are right but whose arc is
    /// the wrong shape.
    private static func length(of path: String) -> Double {
        var total = 0.0
        for run in samples(path, stepsPerCurve: 48) {
            for index in 1..<max(run.count, 1) {
                let dx = run[index].x - run[index - 1].x
                let dy = run[index].y - run[index - 1].y
                total += (dx * dx + dy * dy).squareRoot()
            }
        }
        return total
    }

    private static func sample(_ path: String, stepsPerCurve: Int) -> [(x: Double, y: Double)] {
        samples(path, stepsPerCurve: stepsPerCurve).flatMap { $0 }
    }

    /// Points on the drawn curve, one array per subpath — segmented gauges are
    /// several disconnected runs and joining them would invent length that is
    /// not drawn.
    private static func samples(_ path: String, stepsPerCurve: Int) -> [[(x: Double, y: Double)]] {
        guard let commands = try? PathData.parse(path) else { return [] }
        var runs: [[(x: Double, y: Double)]] = []
        var run: [(x: Double, y: Double)] = []
        var current = (x: 0.0, y: 0.0)
        var origin = (x: 0.0, y: 0.0)
        for command in commands {
            switch command {
            case .move(let x, let y):
                if !run.isEmpty { runs.append(run) }
                run = []
                current = (x, y)
                origin = current
                run.append(current)
            case .line(let x, let y):
                for step in 1...stepsPerCurve {
                    let t = Double(step) / Double(stepsPerCurve)
                    run.append((current.x + (x - current.x) * t, current.y + (y - current.y) * t))
                }
                current = (x, y)
            case .quad(let cx, let cy, let x, let y):
                for step in 1...stepsPerCurve {
                    let t = Double(step) / Double(stepsPerCurve)
                    let u = 1 - t
                    run.append((
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
                    run.append((
                        a * current.x + b * c1x + c * c2x + d * x,
                        a * current.y + b * c1y + c * c2y + d * y
                    ))
                }
                current = (x, y)
            case .close:
                // The ring's ends already coincide, so `Z` adds no length.
                current = origin
            }
        }
        if !run.isEmpty { runs.append(run) }
        return runs
    }
}
