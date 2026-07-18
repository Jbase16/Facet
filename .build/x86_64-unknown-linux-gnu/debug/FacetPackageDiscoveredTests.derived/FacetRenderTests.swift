import XCTest
@testable import FacetRenderTests

fileprivate extension ResolverTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__ResolverTests = [
        ("testAccessoryRenditionsGoMonochrome", testAccessoryRenditionsGoMonochrome),
        ("testBadExpressionDegradesWithDiagnostic", testBadExpressionDegradesWithDiagnostic),
        ("testDarkModeSwitchesTokenColors", testDarkModeSwitchesTokenColors),
        ("testEnvironmentVariables", testEnvironmentVariables),
        ("testGaugeFractionClamped", testGaugeFractionClamped),
        ("testHiddenLayerIsSkipped", testHiddenLayerIsSkipped),
        ("testLayoutGeometry", testLayoutGeometry),
        ("testMissingTokenFallsBackToMagenta", testMissingTokenFallsBackToMagenta),
        ("testRenditionPatchHidesAndResizes", testRenditionPatchHidesAndResizes),
        ("testResolvesBindingsAndTokens", testResolvesBindingsAndTokens),
        ("testStackLayoutDistributesChildren", testStackLayoutDistributesChildren)
    ]
}

fileprivate extension SVGRendererTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__SVGRendererTests = [
        ("testDarkSchemeChangesBackground", testDarkSchemeChangesBackground),
        ("testEscapesTextContent", testEscapesTextContent),
        ("testProducesWellFormedSVG", testProducesWellFormedSVG),
        ("testRendersGaugeAsStrokedCircles", testRendersGaugeAsStrokedCircles)
    ]
}

fileprivate extension StarterTemplateTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__StarterTemplateTests = [
        ("testAllTemplatesResolveCleanlyEverywhere", asyncTest(testAllTemplatesResolveCleanlyEverywhere)),
        ("testTemplateIDsAreUnique", testTemplateIDsAreUnique),
        ("testTemplateSourcesAreOnlyKnownSampleSources", testTemplateSourcesAreOnlyKnownSampleSources),
        ("testTemplatesRoundTripThroughFacetFile", testTemplatesRoundTripThroughFacetFile)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __FacetRenderTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ResolverTests.__allTests__ResolverTests),
        testCase(SVGRendererTests.__allTests__SVGRendererTests),
        testCase(StarterTemplateTests.__allTests__StarterTemplateTests)
    ]
}