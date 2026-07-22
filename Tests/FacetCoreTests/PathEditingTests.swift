import XCTest
@testable import FacetCore

/// Node editing has two properties users notice immediately when broken:
/// inserting a node must not deform the outline, and dragging the first
/// anchor of a closed shape must not tear it open.
final class PathEditingTests: XCTestCase {
    /// A closed triangle-ish curve to edit.
    private var square: [PathCommand] {
        [.move(x: 0, y: 0), .line(x: 1, y: 0), .line(x: 1, y: 1), .line(x: 0, y: 1), .close]
    }

    private var curved: [PathCommand] {
        [
            .move(x: 0, y: 0.5),
            .cubic(c1x: 0, c1y: 0, c2x: 0.5, c2y: 0, x: 1, y: 0.5),
            .cubic(c1x: 1, c1y: 1, c2x: 0.5, c2y: 1, x: 0, y: 0.5),
            .close,
        ]
    }

    /// Sample a cubic at t, for comparing curves before and after a split.
    private func point(on commands: [PathCommand], segment: Int, t: Double) -> PathPoint {
        guard let start = PathEditing.endpoint(of: commands[segment - 1]),
              case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y) = commands[segment]
        else { return PathPoint(x: .nan, y: .nan) }
        let mt = 1 - t
        let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
        return PathPoint(
            x: a * start.x + b * c1x + c * c2x + d * x,
            y: a * start.y + b * c1y + c * c2y + d * y
        )
    }

    func testNodesExposeAnchorsAndHandles() {
        let nodes = PathEditing.nodes(in: curved)
        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes[0].point, PathPoint(x: 0, y: 0.5))
        // The first anchor's outgoing handle is the next segment's c1.
        XCTAssertEqual(nodes[0].outHandle, PathPoint(x: 0, y: 0))
        XCTAssertEqual(nodes[1].inHandle, PathPoint(x: 0.5, y: 0))
    }

    func testMoveAnchorCarriesItsHandles() {
        var commands = curved
        PathEditing.moveAnchor(&commands, at: 1, to: PathPoint(x: 1.0, y: 0.75))
        guard case .cubic(_, _, let c2x, let c2y, let x, let y) = commands[1] else {
            return XCTFail("expected cubic")
        }
        XCTAssertEqual(x, 1.0, accuracy: 0.0001)
        XCTAssertEqual(y, 0.75, accuracy: 0.0001)
        // c2 shifted by the same delta (0, +0.25) so the curve doesn't kink.
        XCTAssertEqual(c2x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(c2y, 0.25, accuracy: 0.0001)
    }

    /// The closing anchor coincides with the start; moving one must move
    /// both or the shape splits open.
    func testMovingFirstAnchorKeepsClosedShapeClosed() {
        var commands = curved
        PathEditing.moveAnchor(&commands, at: 0, to: PathPoint(x: 0.2, y: 0.4))
        let first = PathEditing.endpoint(of: commands[0])
        let last = PathEditing.endpoint(of: commands[commands.count - 2])
        XCTAssertEqual(first, PathPoint(x: 0.2, y: 0.4))
        XCTAssertEqual(last, first, "closed outline tore open")
    }

    /// De Casteljau: splitting a cubic must leave the drawn curve identical.
    func testInsertNodeOnCurveDoesNotDeformIt() {
        var commands = curved
        let before = stride(from: 0.0, through: 1.0, by: 0.1).map { point(on: commands, segment: 1, t: $0) }
        PathEditing.insertNode(&commands, onSegmentEndingAt: 1)
        XCTAssertEqual(PathEditing.nodes(in: commands).count, 4, "should gain one anchor")

        // The original segment is now two; sampling both halves must
        // retrace the original curve.
        let firstHalf = stride(from: 0.0, through: 1.0, by: 0.2).map { point(on: commands, segment: 1, t: $0) }
        let secondHalf = stride(from: 0.0, through: 1.0, by: 0.2).map { point(on: commands, segment: 2, t: $0) }
        for (index, sample) in firstHalf.enumerated() {
            let expected = before[index]
            XCTAssertEqual(sample.x, expected.x, accuracy: 0.0001)
            XCTAssertEqual(sample.y, expected.y, accuracy: 0.0001)
        }
        for (index, sample) in secondHalf.enumerated() {
            let expected = before[index + 5]
            XCTAssertEqual(sample.x, expected.x, accuracy: 0.0001)
            XCTAssertEqual(sample.y, expected.y, accuracy: 0.0001)
        }
    }

    func testInsertNodeOnLineSplitsAtMidpoint() {
        var commands = square
        PathEditing.insertNode(&commands, onSegmentEndingAt: 1)
        XCTAssertEqual(PathEditing.endpoint(of: commands[1]), PathPoint(x: 0.5, y: 0))
    }

    func testToggleCurveIsShapePreservingThenReversible() {
        var commands = square
        PathEditing.toggleCurve(&commands, at: 1)
        // Handles at the thirds are the identity curve for a straight line.
        guard case .cubic(let c1x, let c1y, _, _, _, _) = commands[1] else {
            return XCTFail("expected cubic")
        }
        XCTAssertEqual(c1x, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(c1y, 0, accuracy: 0.0001)
        PathEditing.toggleCurve(&commands, at: 1)
        XCTAssertEqual(commands[1], .line(x: 1, y: 0))
    }

    func testDeleteNodeRemovesAnchor() {
        var commands = square
        let before = PathEditing.nodes(in: commands).count
        PathEditing.deleteNode(&commands, at: 2)
        XCTAssertEqual(PathEditing.nodes(in: commands).count, before - 1)
    }

    /// Deleting the start anchor must leave a path that still begins with
    /// a move, or the outline stops rendering entirely.
    func testDeletingFirstNodePromotesNextToMove() {
        var commands = square
        PathEditing.deleteNode(&commands, at: 0)
        guard case .move = commands[0] else {
            return XCTFail("path must still start with a move")
        }
        XCTAssertEqual(PathEditing.endpoint(of: commands[0]), PathPoint(x: 1, y: 0))
    }

    func testDeleteRefusesBelowThreeAnchors() {
        var commands: [PathCommand] = [
            .move(x: 0, y: 0), .line(x: 1, y: 0), .line(x: 0.5, y: 1), .close,
        ]
        PathEditing.deleteNode(&commands, at: 1)
        XCTAssertEqual(PathEditing.nodes(in: commands).count, 3, "a shape needs three anchors")
    }

    func testEditsRoundTripThroughPathData() throws {
        var commands = curved
        PathEditing.moveAnchor(&commands, at: 1, to: PathPoint(x: 0.9, y: 0.6))
        PathEditing.insertNode(&commands, onSegmentEndingAt: 1)
        let data = PathEditing.pathData(from: commands)
        XCTAssertEqual(try PathData.parse(data).count, commands.count)
    }

    func testClampAnchorKeepsPointsInsideTheLayer() {
        XCTAssertEqual(PathEditing.clampAnchor(PathPoint(x: -0.5, y: 1.7)), PathPoint(x: 0, y: 1))
    }
}
