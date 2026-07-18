import Foundation

/// Decides what to fetch now and when to ask iOS to wake us again. This is
/// deliberately conservative: iOS grants a limited widget reload budget, and
/// burning it early is how widget apps earn "always stale" reviews.
public struct RefreshPlanner: Sendable {
    public struct Plan: Sendable, Equatable {
        /// Sources whose cached snapshot is missing or older than its target
        /// interval — fetch these in this refresh pass.
        public var sourceIDsToFetch: [String]
        /// When the next background refresh should be requested.
        public var nextRefresh: Date
    }

    private let store: SnapshotStore

    public init(store: SnapshotStore) {
        self.store = store
    }

    public func plan(
        for descriptors: [DataSourceDescriptor],
        now: Date = Date()
    ) -> Plan {
        var toFetch: [String] = []
        var nextDue = now.addingTimeInterval(CadenceClass.daily.targetInterval)

        for descriptor in descriptors where descriptor.cadence != .continuous {
            let interval = descriptor.cadence.targetInterval
            if let snapshot = store.load(sourceID: descriptor.id) {
                let due = snapshot.fetchedAt.addingTimeInterval(interval)
                if due <= now {
                    toFetch.append(descriptor.id)
                    nextDue = min(nextDue, now.addingTimeInterval(interval))
                } else {
                    nextDue = min(nextDue, due)
                }
            } else {
                toFetch.append(descriptor.id)
                nextDue = min(nextDue, now.addingTimeInterval(interval))
            }
        }

        // Never ask iOS for anything sooner than 15 minutes; it won't honor
        // it and it burns goodwill with the scheduler.
        let floor = now.addingTimeInterval(15 * 60)
        return Plan(sourceIDsToFetch: toFetch, nextRefresh: max(nextDue, floor))
    }

    /// Fetch everything due, persisting each snapshot as it lands. Failures
    /// are collected, not fatal — a dead source keeps its last good snapshot.
    @discardableResult
    public func executePlan(
        _ plan: Plan,
        providers: [any DataSourceProvider]
    ) async -> [String: Error] {
        var failures: [String: Error] = [:]
        let byID = Dictionary(uniqueKeysWithValues: providers.map { ($0.descriptor.id, $0) })
        for sourceID in plan.sourceIDsToFetch {
            guard let provider = byID[sourceID] else {
                failures[sourceID] = DataSourceError.unavailable(sourceID)
                continue
            }
            do {
                let snapshot = try await provider.fetch()
                try store.save(snapshot)
            } catch {
                failures[sourceID] = error
            }
        }
        return failures
    }
}
