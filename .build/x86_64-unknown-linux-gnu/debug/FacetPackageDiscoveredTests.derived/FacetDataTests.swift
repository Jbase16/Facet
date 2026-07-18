import XCTest
@testable import FacetDataTests

fileprivate extension SnapshotTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__SnapshotTests = [
        ("testDecodeArbitraryJSON", testDecodeArbitraryJSON),
        ("testRoundTrip", testRoundTrip),
        ("testScalarConversion", testScalarConversion),
        ("testSnapshotSetVariableLookup", testSnapshotSetVariableLookup),
        ("testSnapshotSetWorksAsEvaluationContext", testSnapshotSetWorksAsEvaluationContext)
    ]
}

fileprivate extension StoreAndPlannerTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__StoreAndPlannerTests = [
        ("testExecutePlanPersistsSnapshotsAndRecordsFailures", asyncTest(testExecutePlanPersistsSnapshotsAndRecordsFailures)),
        ("testLoadMissingReturnsNil", testLoadMissingReturnsNil),
        ("testLoadSetSkipsMissingSources", testLoadSetSkipsMissingSources),
        ("testNextRefreshRespectsFifteenMinuteFloor", testNextRefreshRespectsFifteenMinuteFloor),
        ("testPlanFetchesMissingAndDueSources", testPlanFetchesMissingAndDueSources),
        ("testSaveLoadRoundTrip", testSaveLoadRoundTrip),
        ("testStaleness", testStaleness),
        ("testTimeSourceMidnightHour12", testTimeSourceMidnightHour12),
        ("testTimeSourceValues", asyncTest(testTimeSourceValues)),
        ("testUnsafeSourceIDsMakeSafeFilenames", testUnsafeSourceIDsMakeSafeFilenames)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __FacetDataTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(SnapshotTests.__allTests__SnapshotTests),
        testCase(StoreAndPlannerTests.__allTests__StoreAndPlannerTests)
    ]
}