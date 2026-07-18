import Foundation

/// How often a source's data meaningfully changes. Facet is honest about
/// iOS's widget reload budget: cadence drives both background fetch
/// scheduling and the freshness expectations shown in the editor.
public enum CadenceClass: String, Codable, CaseIterable, Sendable {
    /// Recomputed at every timeline entry without fetching (time, date).
    case continuous
    /// Worth refreshing every ~15 minutes when budget allows (battery, health).
    case frequent
    /// Refreshing hourly is plenty (weather, calendar).
    case hourly
    /// Once or twice a day (photos, quotes, astronomy).
    case daily

    /// The interval Facet aims to refresh at, in seconds.
    public var targetInterval: TimeInterval {
        switch self {
        case .continuous: return 60
        case .frequent: return 15 * 60
        case .hourly: return 60 * 60
        case .daily: return 12 * 60 * 60
        }
    }

    /// Data older than this is considered stale and flagged in the UI.
    public var staleAfter: TimeInterval {
        targetInterval * 2
    }
}

/// Static description of a data source, shown in the editor's source picker.
public struct DataSourceDescriptor: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var cadence: CadenceClass
    /// Variable paths this source exposes, for editor autocomplete
    /// (e.g. `battery.level`, `battery.state`).
    public var providedPaths: [String]

    public init(id: String, displayName: String, cadence: CadenceClass, providedPaths: [String]) {
        self.id = id
        self.displayName = displayName
        self.cadence = cadence
        self.providedPaths = providedPaths
    }
}

/// A data source: a descriptor plus the fetch that captures a snapshot.
/// On-device implementations wrap WeatherKit, HealthKit, EventKit, etc. The
/// core protocol stays platform-neutral so the pipeline is testable anywhere.
public protocol DataSourceProvider: Sendable {
    var descriptor: DataSourceDescriptor { get }
    func fetch() async throws -> DataSnapshot
}

public enum DataSourceError: Error, Equatable, Sendable {
    case unavailable(String)
    case fetchFailed(String)
}
