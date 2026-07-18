import XCTest
@testable import FacetCore

final class ExpressionTests: XCTestCase {
    private let context = DictionaryContext([
        "battery.level": .number(0.82),
        "battery.state": .string("charging"),
        "health.steps": .number(7482),
        "health.stepsGoal": .number(10000),
        "flag.on": .bool(true),
    ])

    private func eval(_ source: String) throws -> Value {
        try Evaluator.evaluate(source, context: context)
    }

    // MARK: - Arithmetic & precedence

    func testArithmeticPrecedence() throws {
        XCTAssertEqual(try eval("2 + 3 * 4"), .number(14))
        XCTAssertEqual(try eval("(2 + 3) * 4"), .number(20))
        XCTAssertEqual(try eval("10 - 4 - 3"), .number(3), "Subtraction is left-associative")
        XCTAssertEqual(try eval("2 * 3 + 4"), .number(10))
        XCTAssertEqual(try eval("7 % 3"), .number(1))
        XCTAssertEqual(try eval("-5 + 3"), .number(-2))
        XCTAssertEqual(try eval("10 / 4"), .number(2.5))
    }

    func testDivisionByZero() {
        XCTAssertThrowsError(try eval("1 / 0")) { error in
            XCTAssertEqual(error as? ExpressionError, .divisionByZero)
        }
        XCTAssertThrowsError(try eval("1 % 0"))
    }

    // MARK: - Comparisons & logic

    func testComparisons() throws {
        XCTAssertEqual(try eval("battery.level > 0.5"), .bool(true))
        XCTAssertEqual(try eval("health.steps >= 7482"), .bool(true))
        XCTAssertEqual(try eval("1 == 2"), .bool(false))
        XCTAssertEqual(try eval("'a' < 'b'"), .bool(true))
        XCTAssertEqual(try eval("battery.state == 'charging'"), .bool(true))
        XCTAssertEqual(try eval("battery.state != 'full'"), .bool(true))
    }

    func testLogicShortCircuits() throws {
        XCTAssertEqual(try eval("true || undefined.var > 1"), .bool(true))
        XCTAssertEqual(try eval("false && undefined.var > 1"), .bool(false))
        XCTAssertEqual(try eval("flag.on && battery.level > 0.5"), .bool(true))
        XCTAssertEqual(try eval("!flag.on"), .bool(false))
    }

    func testTernary() throws {
        XCTAssertEqual(try eval("battery.level > 0.2 ? 'ok' : 'low'"), .string("ok"))
        XCTAssertEqual(try eval("1 > 2 ? 'a' : 2 > 1 ? 'b' : 'c'"), .string("b"), "Ternary nests right")
    }

    // MARK: - Strings

    func testStringConcatenation() throws {
        XCTAssertEqual(try eval("'Steps: ' + health.steps"), .string("Steps: 7482"))
        XCTAssertEqual(try eval("health.steps + ' steps'"), .string("7482 steps"))
        XCTAssertEqual(try eval("'a' + 'b'"), .string("ab"))
    }

    // MARK: - Functions

    func testMathFunctions() throws {
        XCTAssertEqual(try eval("abs(-3)"), .number(3))
        XCTAssertEqual(try eval("floor(2.9)"), .number(2))
        XCTAssertEqual(try eval("ceil(2.1)"), .number(3))
        XCTAssertEqual(try eval("round(2.5)"), .number(3))
        XCTAssertEqual(try eval("round(3.14159, 2)"), .number(3.14))
        XCTAssertEqual(try eval("min(3, 1, 2)"), .number(1))
        XCTAssertEqual(try eval("max(3, 1, 2)"), .number(3))
        XCTAssertEqual(try eval("clamp(5, 0, 1)"), .number(1))
        XCTAssertEqual(try eval("clamp(-1, 0, 1)"), .number(0))
        XCTAssertEqual(try eval("sqrt(16)"), .number(4))
        XCTAssertEqual(try eval("pow(2, 10)"), .number(1024))
    }

    func testFormattingFunctions() throws {
        XCTAssertEqual(try eval("format(3.14159, 1)"), .string("3.1"))
        XCTAssertEqual(try eval("percent(battery.level)"), .string("82%"))
        XCTAssertEqual(try eval("percent(0.5013, 1)"), .string("50.1%"))
        XCTAssertEqual(try eval("str(42)"), .string("42"))
        XCTAssertEqual(try eval("str(42.5)"), .string("42.5"))
        XCTAssertEqual(try eval("num('12.5')"), .number(12.5))
        XCTAssertEqual(try eval("pad(7, 2)"), .string("07"))
        XCTAssertEqual(try eval("pad(123, 2)"), .string("123"))
    }

    func testStringFunctions() throws {
        XCTAssertEqual(try eval("upper('abc')"), .string("ABC"))
        XCTAssertEqual(try eval("lower('ABC')"), .string("abc"))
        XCTAssertEqual(try eval("trim('  x  ')"), .string("x"))
        XCTAssertEqual(try eval("len('hello')"), .number(5))
        XCTAssertEqual(try eval("contains('charging', 'charg')"), .bool(true))
        XCTAssertEqual(try eval("replace('a-b', '-', '+')"), .string("a+b"))
    }

    func testUnitConversions() throws {
        XCTAssertEqual(try eval("cToF(0)"), .number(32))
        XCTAssertEqual(try eval("cToF(100)"), .number(212))
        XCTAssertEqual(try eval("fToC(32)"), .number(0))
        XCTAssertEqual(try eval("round(kmToMi(10), 2)"), .number(6.21))
    }

    func testDateFormat() throws {
        // 2026-07-18 00:00:00 UTC is a Saturday.
        XCTAssertEqual(try eval("dateFormat(1784332800, 'yyyy')"), .string("2026"))
    }

    func testHas() throws {
        XCTAssertEqual(try eval("has('battery.level')"), .bool(true))
        XCTAssertEqual(try eval("has('nope.nothing')"), .bool(false))
        XCTAssertEqual(try eval("has('battery.level') ? battery.level : 0"), .number(0.82))
    }

    // MARK: - Errors

    func testUnknownVariable() {
        XCTAssertThrowsError(try eval("missing.value")) { error in
            XCTAssertEqual(error as? ExpressionError, .unknownVariable("missing.value"))
        }
    }

    func testUnknownFunction() {
        XCTAssertThrowsError(try eval("nope(1)")) { error in
            XCTAssertEqual(error as? ExpressionError, .unknownFunction("nope"))
        }
    }

    func testArityErrors() {
        XCTAssertThrowsError(try eval("abs()"))
        XCTAssertThrowsError(try eval("abs(1, 2)"))
        XCTAssertThrowsError(try eval("clamp(1)"))
    }

    func testTypeMismatch() {
        XCTAssertThrowsError(try eval("'a' * 2"))
        XCTAssertThrowsError(try eval("!5"))
        XCTAssertThrowsError(try eval("upper(5)"))
    }

    func testSyntaxErrors() {
        XCTAssertThrowsError(try eval("1 +"))
        XCTAssertThrowsError(try eval("(1 + 2"))
        XCTAssertThrowsError(try eval("1 ? 2"))
        XCTAssertThrowsError(try eval("'unterminated"))
        XCTAssertThrowsError(try eval("1 = 2"))
        XCTAssertThrowsError(try eval("1 2"))
    }

    func testNumberDisplayDropsTrailingZero() {
        XCTAssertEqual(Value.number(80).displayString, "80")
        XCTAssertEqual(Value.number(80.5).displayString, "80.5")
        XCTAssertEqual(Value.number(-3).displayString, "-3")
    }
}
