import Foundation

/// Date/time values. Continuous cadence: WidgetKit timelines re-render
/// entries on schedule without any fetch, so this source just captures "now"
/// (or an injected date, for tests and timeline pre-computation).
public struct TimeSource: DataSourceProvider {
    public let descriptor = DataSourceDescriptor(
        id: "time",
        displayName: "Date & Time",
        cadence: .continuous,
        providedPaths: [
            "time.timestamp", "time.hour", "time.hour12", "time.minute",
            "time.weekday", "time.day", "time.month", "time.year",
            "time.weekdayName", "time.monthName", "time.isAM",
        ]
    )

    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(now: @escaping @Sendable () -> Date = { Date() }, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    public func fetch() async throws -> DataSnapshot {
        snapshot(at: now())
    }

    /// Synchronous capture, used when pre-computing timeline entries.
    public func snapshot(at date: Date) -> DataSnapshot {
        let components = calendar.dateComponents(
            [.hour, .minute, .weekday, .day, .month, .year],
            from: date
        )
        let hour = components.hour ?? 0
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        let weekdayName = formatter.string(from: date)
        formatter.dateFormat = "MMMM"
        let monthName = formatter.string(from: date)

        return DataSnapshot(
            sourceID: descriptor.id,
            fetchedAt: date,
            values: .object([
                "timestamp": .number(date.timeIntervalSince1970),
                "hour": .number(Double(hour)),
                "hour12": .number(Double(hour % 12 == 0 ? 12 : hour % 12)),
                "minute": .number(Double(components.minute ?? 0)),
                "weekday": .number(Double(components.weekday ?? 1)),
                "day": .number(Double(components.day ?? 1)),
                "month": .number(Double(components.month ?? 1)),
                "year": .number(Double(components.year ?? 2000)),
                "weekdayName": .string(weekdayName),
                "monthName": .string(monthName),
                "isAM": .bool(hour < 12),
            ])
        )
    }
}

/// A fixed-payload source for tests, previews, and template thumbnails.
public struct StaticSource: DataSourceProvider {
    public let descriptor: DataSourceDescriptor
    private let values: SnapshotValue

    public init(descriptor: DataSourceDescriptor, values: SnapshotValue) {
        self.descriptor = descriptor
        self.values = values
    }

    public init(id: String, cadence: CadenceClass = .frequent, values: SnapshotValue) {
        self.descriptor = DataSourceDescriptor(
            id: id,
            displayName: id.capitalized,
            cadence: cadence,
            providedPaths: []
        )
        self.values = values
    }

    public func fetch() async throws -> DataSnapshot {
        snapshot()
    }

    /// Synchronous capture — static payloads have nothing to await.
    public func snapshot() -> DataSnapshot {
        DataSnapshot(sourceID: descriptor.id, values: values)
    }
}

/// Canned sample payloads used by editor previews and the template gallery so
/// designs look real before any permissions are granted. On device, the same
/// source IDs are backed by WeatherKit/HealthKit/UIDevice providers.
public enum SampleData {
    public static let battery = StaticSource(
        id: "battery",
        cadence: .frequent,
        values: .object([
            "level": .number(0.82),
            "state": .string("charging"),
            "lowPowerMode": .bool(false),
        ])
    )

    public static let weather = StaticSource(
        id: "weather",
        cadence: .hourly,
        values: .object([
            "temperature": .number(21.5),
            "condition": .string("Partly Cloudy"),
            "symbol": .string("cloud.sun.fill"),
            "high": .number(24),
            "low": .number(16),
            "humidity": .number(0.48),
            "hourly": .list([16, 17, 19, 21, 22, 24, 23, 21, 19, 18, 17, 16].map(SnapshotValue.number)),
        ])
    )

    public static let health = StaticSource(
        id: "health",
        cadence: .frequent,
        values: .object([
            "steps": .number(7482),
            "stepsGoal": .number(10000),
            "activeEnergy": .number(423),
            "standHours": .number(9),
            "weekSteps": .list([9204, 11321, 6480, 8032, 12440, 5210, 7482].map(SnapshotValue.number)),
        ])
    )

    public static let calendar = StaticSource(
        id: "calendar",
        cadence: .hourly,
        values: .object([
            "nextTitle": .string("Design review"),
            "nextStart": .number(Date().addingTimeInterval(45 * 60).timeIntervalSince1970),
            "todayCount": .number(4),
        ])
    )

    public static var all: [any DataSourceProvider] {
        [TimeSource(), battery, weather, health, calendar]
    }

    /// The full sample snapshot set, synchronously — for previews, template
    /// thumbnails, and tools.
    public static func snapshotSet(now: Date = Date()) -> SnapshotSet {
        var set = SnapshotSet()
        set.insert(TimeSource().snapshot(at: now))
        for source in [battery, weather, health, calendar] {
            set.insert(source.snapshot())
        }
        return set
    }
}
