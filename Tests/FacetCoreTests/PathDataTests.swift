import XCTest
@testable import FacetCore

/// The SVG path subset: absolute/relative commands, implicit repeats, and
/// the odd number formats real path strings use.
final class PathDataTests: XCTestCase {
    func testAbsoluteCommands() throws {
        let commands = try PathData.parse("M0,0 L1,0 L1,1 Z")
        XCTAssertEqual(commands, [
            .move(x: 0, y: 0),
            .line(x: 1, y: 0),
            .line(x: 1, y: 1),
            .close,
        ])
    }

    func testRelativeCommandsAccumulate() throws {
        let commands = try PathData.parse("m0.1,0.1 l0.2,0 l0,0.2")
        XCTAssertEqual(commands, [
            .move(x: 0.1, y: 0.1),
            .line(x: 0.30000000000000004, y: 0.1),
            .line(x: 0.30000000000000004, y: 0.30000000000000004),
        ])
    }

    func testHorizontalAndVerticalShorthand() throws {
        let commands = try PathData.parse("M0,0 H1 V1 H0 Z")
        XCTAssertEqual(commands, [
            .move(x: 0, y: 0),
            .line(x: 1, y: 0),
            .line(x: 1, y: 1),
            .line(x: 0, y: 1),
            .close,
        ])
    }

    func testCubicAndQuadratic() throws {
        let commands = try PathData.parse("M0,0 C0.1,0.2 0.3,0.4 0.5,0.5 Q0.7,0.6 1,1")
        XCTAssertEqual(commands, [
            .move(x: 0, y: 0),
            .cubic(c1x: 0.1, c1y: 0.2, c2x: 0.3, c2y: 0.4, x: 0.5, y: 0.5),
            .quad(cx: 0.7, cy: 0.6, x: 1, y: 1),
        ])
    }

    /// "M.5.5" is legal SVG: no separator needed when the next number
    /// starts with a dot.
    func testImplicitSeparators() throws {
        let commands = try PathData.parse("M.5.5L1 1")
        XCTAssertEqual(commands, [.move(x: 0.5, y: 0.5), .line(x: 1, y: 1)])
    }

    /// A repeated coordinate pair after M continues as an implicit L.
    func testImplicitLineAfterMove() throws {
        let commands = try PathData.parse("M0,0 0.5,0.5 1,1")
        XCTAssertEqual(commands, [
            .move(x: 0, y: 0),
            .line(x: 0.5, y: 0.5),
            .line(x: 1, y: 1),
        ])
    }

    func testNegativeAndExponentNumbers() throws {
        let commands = try PathData.parse("M-0.5,1e-1")
        XCTAssertEqual(commands, [.move(x: -0.5, y: 0.1)])
    }

    func testUnsupportedCommandThrows() {
        // Arcs are deliberately out of the grammar.
        XCTAssertThrowsError(try PathData.parse("M0,0 A1,1 0 0 1 1,1"))
    }

    func testMissingNumberThrows() {
        XCTAssertThrowsError(try PathData.parse("M0,"))
    }

    func testLeadingNumberWithoutCommandThrows() {
        XCTAssertThrowsError(try PathData.parse("0.5,0.5"))
    }

    func testEmptyStringYieldsNoCommands() throws {
        XCTAssertEqual(try PathData.parse("   "), [])
    }

    func testRoundTripThroughString() throws {
        let source = "M0,0 C0.25,0.1 0.75,0.9 1,1 Z"
        let commands = try PathData.parse(source)
        let rendered = PathData.string(from: commands)
        XCTAssertEqual(try PathData.parse(rendered), commands)
    }
}
