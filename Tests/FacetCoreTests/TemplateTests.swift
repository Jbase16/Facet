import XCTest
@testable import FacetCore

final class TemplateTests: XCTestCase {
    private let context = DictionaryContext([
        "battery.level": .number(0.82),
        "name": .string("Facet"),
    ])

    func testPlainLiteral() throws {
        XCTAssertEqual(try Template.render("Hello world", context: context), "Hello world")
    }

    func testSingleExpression() throws {
        XCTAssertEqual(try Template.render("{battery.level * 100}", context: context), "82")
    }

    func testMixedSegments() throws {
        XCTAssertEqual(
            try Template.render("⚡ {percent(battery.level)} — {name}", context: context),
            "⚡ 82% — Facet"
        )
    }

    func testEscapedBraces() throws {
        XCTAssertEqual(try Template.render("{{literal}}", context: context), "{literal}")
        XCTAssertEqual(try Template.render("a {{ b }} c", context: context), "a { b } c")
    }

    func testUnclosedBraceThrows() {
        XCTAssertThrowsError(try Template.render("oops {battery.level", context: context))
    }

    func testUnmatchedCloseBraceThrows() {
        XCTAssertThrowsError(try Template.render("oops } here", context: context))
    }

    func testExpressionErrorPropagates() {
        XCTAssertThrowsError(try Template.render("{missing.var}", context: context))
    }

    func testEmptyTemplate() throws {
        XCTAssertEqual(try Template.render("", context: context), "")
    }
}
