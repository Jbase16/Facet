import Foundation
import HealthKit
import FacetData

/// Real activity data via HealthKit. Serves the same payload shape as
/// `SampleData.health` so widgets designed against sample data render
/// unchanged once access is granted.
struct HealthSource: DataSourceProvider {
    let descriptor = DataSourceDescriptor(
        id: "health",
        displayName: "Health",
        cadence: .frequent,
        providedPaths: [
            "health.steps", "health.stepsGoal", "health.activeEnergy",
            "health.standHours", "health.weekSteps",
        ]
    )

    /// Everything fetch() reads. Computed rather than stored so the struct
    /// holds no HealthKit objects and stays trivially Sendable.
    private static var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.appleStandHour),
        ]
    }

    func fetch() async throws -> DataSnapshot {
        guard Self.isAvailable else {
            throw DataSourceError.unavailable("Health data not available on this device")
        }

        // HKHealthStore is scoped to this fetch, keeping the provider Sendable.
        let store = HKHealthStore()

        // HealthKit never reveals whether *read* access was granted — denied
        // reads silently return no samples. The most we can check is whether
        // the permission sheet has been presented. Throwing before then keeps
        // the pipeline on its last cached snapshot, which beats overwriting
        // real data with zeros.
        let requestStatus = try await store.statusForAuthorizationRequest(
            toShare: [], read: Self.readTypes
        )
        guard requestStatus == .unnecessary else {
            throw DataSourceError.unavailable("Health access not requested yet")
        }

        let now = Date()
        // `steps` and today's entry in `weekSteps` must agree, so both come
        // from the one collection query instead of two racing queries.
        let weekSteps = try await dailyStepSums(days: 7, store: store, now: now)
        let activeEnergy = try await todaySum(
            of: HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), store: store, now: now
        )
        let standHours = try await todayStandHours(store: store, now: now)

        return DataSnapshot(
            sourceID: descriptor.id,
            values: .object([
                "steps": .number(weekSteps.last ?? 0),
                // HealthKit has no user-set steps goal to read; 10 000 is the
                // conventional default until Facet grows its own setting.
                "stepsGoal": .number(10000),
                "activeEnergy": .number(activeEnergy),
                "standHours": .number(standHours),
                "weekSteps": .list(weekSteps.map(SnapshotValue.number)),
            ])
        )
    }

    // MARK: - Authorization

    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Prompts for read access. The app's UI calls this once; fetch() never
    /// prompts, it only checks.
    static func requestAuthorization() async throws {
        guard isAvailable else {
            throw DataSourceError.unavailable("Health data not available on this device")
        }
        try await HKHealthStore().requestAuthorization(toShare: [], read: readTypes)
    }

    /// Whether the permission sheet has been presented, for the UI's status
    /// row. True does not mean granted — HealthKit hides read denials by
    /// design, so "known" is the strongest signal available.
    static func authorizationStatusKnown() async -> Bool {
        guard isAvailable else { return false }
        let status = try? await HKHealthStore().statusForAuthorizationRequest(
            toShare: [], read: readTypes
        )
        return status == .unnecessary
    }

    // MARK: - Queries

    /// Sum of a cumulative quantity from local midnight to now.
    private func todaySum(
        of type: HKQuantityType, unit: HKUnit, store: HKHealthStore, now: Date
    ) async throws -> Double {
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: now, options: .strictStartDate
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error, !error.isHealthKitNoData {
                    continuation.resume(throwing: DataSourceError.fetchFailed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    /// Daily step sums for the trailing `days` days, oldest first, today
    /// last. Days with no samples read as zero so charts keep 7 points.
    private func dailyStepSums(days: Int, store: HKHealthStore, now: Date) async throws -> [Double] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) else {
            throw DataSourceError.fetchFailed("Could not compute the week window")
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: windowStart, end: now, options: .strictStartDate
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: windowStart,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error, !error.isHealthKitNoData {
                    continuation.resume(throwing: DataSourceError.fetchFailed(error.localizedDescription))
                    return
                }
                let sums = (0..<days).map { offset -> Double in
                    guard let day = calendar.date(byAdding: .day, value: offset, to: windowStart),
                          let sum = collection?.statistics(for: day)?.sumQuantity()
                    else { return 0 }
                    return sum.doubleValue(for: .count())
                }
                continuation.resume(returning: sums)
            }
            store.execute(query)
        }
    }

    /// Activity-ring stand hours: the count of today's hour buckets marked
    /// "stood". (`appleStandHour` is the ring metric; `appleStandTime` is
    /// minutes stood, a different thing.) iPhones without a paired Watch
    /// have no samples, so this reads as zero rather than failing.
    private func todayStandHours(store: HKHealthStore, now: Date) async throws -> Double {
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: now, options: .strictStartDate
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.appleStandHour),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error, !error.isHealthKitNoData {
                    continuation.resume(throwing: DataSourceError.fetchFailed(error.localizedDescription))
                    return
                }
                let stood = (samples ?? [])
                    .compactMap { $0 as? HKCategorySample }
                    .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
                    .count
                continuation.resume(returning: Double(stood))
            }
            store.execute(query)
        }
    }
}

private extension Error {
    /// HealthKit reports an empty result set as an error; for daily
    /// activity sums "no data" just means zero.
    var isHealthKitNoData: Bool {
        (self as? HKError)?.code == .errorNoData
    }
}
