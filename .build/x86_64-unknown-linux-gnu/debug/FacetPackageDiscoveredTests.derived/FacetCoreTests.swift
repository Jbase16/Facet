import XCTest
@testable import FacetCoreTests

fileprivate extension DocumentTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__DocumentTests = [
        ("testColorHexParsing", testColorHexParsing),
        ("testColorTokenSchemeResolution", testColorTokenSchemeResolution),
        ("testEncodedFormIsStableAndReadable", testEncodedFormIsStableAndReadable),
        ("testFirstLayerSearch", testFirstLayerSearch),
        ("testFutureSchemaVersionRejected", testFutureSchemaVersionRejected),
        ("testPatchLookup", testPatchLookup),
        ("testRoundTrip", testRoundTrip),
        ("testUnknownLayerTypeFailsCleanly", testUnknownLayerTypeFailsCleanly)
    ]
}

fileprivate extension ExpressionTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__ExpressionTests = [
        ("testArithmeticPrecedence", testArithmeticPrecedence),
        ("testArityErrors", testArityErrors),
        ("testComparisons", testComparisons),
        ("testDateFormat", testDateFormat),
        ("testDivisionByZero", testDivisionByZero),
        ("testFormattingFunctions", testFormattingFunctions),
        ("testHas", testHas),
        ("testLogicShortCircuits", testLogicShortCircuits),
        ("testMathFunctions", testMathFunctions),
        ("testNumberDisplayDropsTrailingZero", testNumberDisplayDropsTrailingZero),
        ("testStringConcatenation", testStringConcatenation),
        ("testStringFunctions", testStringFunctions),
        ("testSyntaxErrors", testSyntaxErrors),
        ("testTernary", testTernary),
        ("testTypeMismatch", testTypeMismatch),
        ("testUnitConversions", testUnitConversions),
        ("testUnknownFunction", testUnknownFunction),
        ("testUnknownVariable", testUnknownVariable)
    ]
}

fileprivate extension TemplateTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__TemplateTests = [
        ("testEmptyTemplate", testEmptyTemplate),
        ("testEscapedBraces", testEscapedBraces),
        ("testExpressionErrorPropagates", testExpressionErrorPropagates),
        ("testMixedSegments", testMixedSegments),
        ("testPlainLiteral", testPlainLiteral),
        ("testSingleExpression", testSingleExpression),
        ("testUnclosedBraceThrows", testUnclosedBraceThrows),
        ("testUnmatchedCloseBraceThrows", testUnmatchedCloseBraceThrows)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __FacetCoreTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DocumentTests.__allTests__DocumentTests),
        testCase(ExpressionTests.__allTests__ExpressionTests),
        testCase(TemplateTests.__allTests__TemplateTests)
    ]
}