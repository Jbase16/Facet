import Foundation
import EventKit
import FacetData

/// Real calendar data via EventKit. Serves the same payload shape as
/// `SampleData.calendar` so widgets designed against sample data render
/// unchanged once access is granted.
struct CalendarSource: DataSourceProvider {
    let descriptor = DataSourceDescriptor(
        id: "calendar",
        displayName: "Calendar",
        cadence: .hourly,
        providedPaths: ["calendar.nextTitle", "calendar.nextStart", "calendar.todayCount"]
    )

    /// How far ahead to look for the "next" event.
    private static let lookahead: TimeInterval = 48 * 60 * 60

    func fetch() async throws -> DataSnapshot {
        guard Self.authorizationGranted else {
            // Throwing keeps the pipeline on its last cached snapshot,
            // which beats overwriting real data with an empty payload.
            throw DataSourceError.unavailable("Calendar access not granted")
        }

        // EKEventStore is not Sendable; scoping it to this fetch keeps the
        // provider itself Sendable.
        let store = EKEventStore()
        let now = Date()

        // The predicate also matches in-progress and all-day events; "next"
        // means a timed event that hasn't started yet. EKEvent's dates are
        // implicitly unwrapped, so pull them out through a guard.
        let upcoming = store.events(
            matching: store.predicateForEvents(
                withStart: now,
                end: now.addingTimeInterval(Self.lookahead),
                calendars: nil
            )
        )
        let next = upcoming
            .filter { !$0.isAllDay }
            .compactMap { event -> (title: String, start: Date)? in
                guard let start = event.startDate, start >= now else { return nil }
                return (event.title ?? "Untitled", start)
            }
            .min { $0.start < $1.start }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(24 * 60 * 60)
        let todayCount = store.events(
            matching: store.predicateForEvents(
                withStart: startOfToday,
                end: endOfToday,
                calendars: nil
            )
        ).count

        return DataSnapshot(
            sourceID: descriptor.id,
            values: .object([
                "nextTitle": .string(next?.title ?? "No events"),
                "nextStart": .number(next?.start.timeIntervalSince1970 ?? 0),
                "todayCount": .number(Double(todayCount)),
            ])
        )
    }

    /// Prompts for full calendar access. The app's UI calls this once;
    /// fetch() never prompts, it only checks.
    static func requestAccess() async throws -> Bool {
        try await EKEventStore().requestFullAccessToEvents()
    }

    /// Whether fetch() can succeed, for the UI's permission status.
    static var authorizationGranted: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }
}
