import XCTest
import FacetCore
@testable import FacetData

final class StoreAndPlannerTests: XCTestCase {
    private var directory: URL!
    private var store: SnapshotStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("facet-tests-\(UUID().uuidString)")
        store = SnapshotStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveLoadRoundTrip() throws {
        let snapshot = DataSnapshot(
            sourceID: "battery",
            fetchedAt: Date(timeIntervalSince1970: 1_784_332_800),
            values: .object(["level": .number(0.5)])
        )
        try store.save(snapshot)
        let loaded = store.load(sourceID: "battery")
        XCTAssertEqual(loaded?.values, snapshot.values)
        XCTAssertEqual(
            loaded?.fetchedAt.timeIntervalSince1970 ?? 0,
            snapshot.fetchedAt.timeIntervalSince1970,
            accuracy: 1
        )
    }

    func testLoadMissingReturnsNil() {
        XCTAssertNil(store.load(sourceID: "nothing"))
    }

    func testLoadSetSkipsMissingSources() throws {
        try store.save(DataSnapshot(sourceID: "battery", values: .object(["level": .number(1)])))
        let set = store.loadSet(sourceIDs: ["battery", "weather"])
        XCTAssertNotNil(set.snapshot(for: "battery"))
        XCTAssertNil(set.snapshot(for: "weather"))
    }

    func testStaleness() throws {
        let now = Date()
        try store.save(DataSnapshot(
            sourceID: "weather",
            fetchedAt: now.addingTimeInterval(-3 * 60 * 60),
            values: .object([:])
        ))
        XCTAssertTrue(store.isStale(sourceID: "weather", cadence: .hourly, now: now))
        XCTAssertFalse(store.isStale(sourceID: "weather", cadence: .daily, now: now))
        XCTAssertTrue(store.isStale(sourceID: "never-fetched", cadence: .daily, now: now))
    }

    func testUnsafeSourceIDsMakeSafeFilenames() throws {
        try store.save(DataSnapshot(sourceID: "../evil/../../path", values: .object([:])))
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(contents.count, 1)
        XCTAssertFalse(contents[0].contains(".."))
        XCTAssertFalse(contents[0].contains("/"))
    }

    // MARK: - Planner

    func testPlanFetchesMissingAndDueSources() throws {
        let now = Date()
        // Weather: fresh. Battery: overdue. Health: never fetched.
        try store.save(DataSnapshot(sourceID: "weather", fetchedAt: now, values: .object([:])))
        try store.save(DataSnapshot(
            sourceID: "battery",
            fetchedAt: now.addingTimeInterval(-30 * 60),
            values: .object([:])
        ))
        let descriptors = [
            DataSourceDescriptor(id: "weather", displayName: "Weather", cadence: .hourly, providedPaths: []),
            DataSourceDescriptor(id: "battery", displayName: "Battery", cadence: .frequent, providedPaths: []),
            DataSourceDescriptor(id: "health", displayName: "Health", cadence: .frequent, providedPaths: []),
            DataSourceDescriptor(id: "time", displayName: "Time", cadence: .continuous, providedPaths: []),
        ]
        let plan = RefreshPlanner(store: store).plan(for: descriptors, now: now)
        XCTAssertEqual(Set(plan.sourceIDsToFetch), ["battery", "health"])
        XCTAssertFalse(plan.sourceIDsToFetch.contains("time"), "Continuous sources are never fetched")
    }

    func testNextRefreshRespectsFifteenMinuteFloor() throws {
        let now = Date()
        try store.save(DataSnapshot(
            sourceID: "battery",
            fetchedAt: now.addingTimeInterval(-14 * 60),
            values: .object([:])
        ))
        let descriptors = [
            DataSourceDescriptor(id: "battery", displayName: "Battery", cadence: .frequent, providedPaths: []),
        ]
        let plan = RefreshPlanner(store: store).plan(for: descriptors, now: now)
        // Due in 1 minute, but iOS won't honor that — floor at 15.
        XCTAssertGreaterThanOrEqual(plan.nextRefresh.timeIntervalSince(now), 15 * 60 - 1)
    }

    func testExecutePlanPersistsSnapshotsAndRecordsFailures() async throws {
        let plan = RefreshPlanner.Plan(
            sourceIDsToFetch: ["battery", "ghost"],
            nextRefresh: Date()
        )
        let failures = await RefreshPlanner(store: store).executePlan(
            plan,
            providers: [SampleData.battery]
        )
        XCTAssertNotNil(store.load(sourceID: "battery"))
        XCTAssertEqual(failures.count, 1)
        XCTAssertNotNil(failures["ghost"])
    }

    // MARK: - Time source

    func testTimeSourceValues() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-07-18 14:30:00 UTC — a Saturday afternoon.
        let date = Date(timeIntervalSince1970: 1_784_385_000)
        let source = TimeSource(now: { date }, calendar: calendar)
        let snapshot = try await source.fetch()

        XCTAssertEqual(snapshot.values.value(atPath: "hour"), .number(14))
        XCTAssertEqual(snapshot.values.value(atPath: "hour12"), .number(2))
        XCTAssertEqual(snapshot.values.value(atPath: "minute"), .number(30))
        XCTAssertEqual(snapshot.values.value(atPath: "isAM"), .bool(false))
        XCTAssertEqual(snapshot.values.value(atPath: "day"), .number(18))
        XCTAssertEqual(snapshot.values.value(atPath: "month"), .number(7))
        XCTAssertEqual(snapshot.values.value(atPath: "year"), .number(2026))
    }

    func testTimeSourceMidnightHour12() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Midnight UTC.
        let date = Date(timeIntervalSince1970: 1_784_332_800)
        let snapshot = TimeSource(calendar: calendar).snapshot(at: date)
        XCTAssertEqual(snapshot.values.value(atPath: "hour12"), .number(12), "0h shows as 12 on a 12-hour clock")
        XCTAssertEqual(snapshot.values.value(atPath: "isAM"), .bool(true))
    }
}
