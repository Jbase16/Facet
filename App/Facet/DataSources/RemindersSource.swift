import Foundation
import EventKit
import FacetData

/// Real reminder data via EventKit. Only incomplete reminders count —
/// completed ones are history, not glanceable state — and reminders without
/// a due date are skipped because none of the provided paths can place them.
struct RemindersSource: DataSourceProvider {
    let descriptor = DataSourceDescriptor(
        id: "reminders",
        displayName: "Reminders",
        cadence: .hourly,
        providedPaths: [
            "reminders.dueTodayCount", "reminders.overdueCount",
            "reminders.nextTitle", "reminders.nextDue",
        ]
    )

    func fetch() async throws -> DataSnapshot {
        guard Self.authorizationGranted else {
            // Throwing keeps the pipeline on its last cached snapshot,
            // which beats overwriting real data with an empty payload.
            throw DataSourceError.unavailable("Reminders access not granted")
        }

        // EKEventStore is not Sendable; scoping it to this fetch keeps the
        // provider itself Sendable.
        let store = EKEventStore()
        let now = Date()

        // fetchReminders is callback-only and EKReminder is not Sendable, so
        // reduce to plain values inside the callback and resume the
        // continuation with only the Sendable summary.
        let summary: Summary = await withCheckedContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: nil
            )
            // fetchReminders returns a cancellation token; nothing here
            // outlives the fetch, so it is safely ignored.
            _ = store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: Self.summarize(reminders ?? [], now: now))
            }
        }

        return DataSnapshot(
            sourceID: descriptor.id,
            values: .object([
                "dueTodayCount": .number(Double(summary.dueTodayCount)),
                "overdueCount": .number(Double(summary.overdueCount)),
                "nextTitle": .string(summary.nextTitle),
                "nextDue": .number(summary.nextDue),
            ])
        )
    }

    private struct Summary: Sendable {
        var dueTodayCount = 0
        var overdueCount = 0
        var nextTitle = "None"
        var nextDue: Double = 0
    }

    private static func summarize(_ reminders: [EKReminder], now: Date) -> Summary {
        let calendar = Calendar.current
        var summary = Summary()
        var next: (title: String, due: Date)?
        for reminder in reminders {
            guard let components = reminder.dueDateComponents,
                  let due = calendar.date(from: components) else { continue }
            if calendar.isDate(due, inSameDayAs: now) { summary.dueTodayCount += 1 }
            if due < now { summary.overdueCount += 1 }
            if due >= now, next.map({ due < $0.due }) ?? true {
                next = (reminder.title ?? "Untitled", due)
            }
        }
        if let next {
            summary.nextTitle = next.title
            summary.nextDue = next.due.timeIntervalSince1970
        }
        return summary
    }

    /// Prompts for full reminders access. The app's UI calls this once;
    /// fetch() never prompts, it only checks.
    static func requestAccess() async throws -> Bool {
        try await EKEventStore().requestFullAccessToReminders()
    }

    /// Whether fetch() can succeed, for the UI's permission status.
    static var authorizationGranted: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }
}
