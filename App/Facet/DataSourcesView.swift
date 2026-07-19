import SwiftUI
import FacetData

/// Connection status for every on-device data source: what's live, what's
/// still showing seeded sample data, and the permission prompts to fix it.
/// Freshness is shown honestly — pretending stale data is live is how widget
/// apps lose trust.
struct DataSourcesView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var refreshing = false
    @State private var locationAuthorized = LocationProvider.shared.isAuthorized
    @State private var healthPrompted = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    sourceRow(id: "battery", name: "Battery", detail: "No permission needed")
                } footer: {
                    Text("Battery reads directly from the device.")
                }

                Section {
                    sourceRow(id: "weather", name: "Weather", detail: "Apple Weather via your location")
                    if !locationAuthorized {
                        Button("Allow Location Access") {
                            LocationProvider.shared.requestPermission()
                        }
                    }
                }

                Section {
                    sourceRow(id: "health", name: "Health", detail: "Steps, energy, stand hours")
                    // HealthKit hides read-grant status by design; "the prompt
                    // has been shown" is the strongest signal there is, so the
                    // button disappears after the user has answered it once.
                    if HealthSource.isAvailable && !healthPrompted {
                        Button("Connect Apple Health") {
                            connect { try await HealthSource.requestAuthorization() }
                        }
                    }
                }

                Section {
                    sourceRow(id: "calendar", name: "Calendar", detail: "Next event and today's count")
                    if !CalendarSource.authorizationGranted {
                        Button("Allow Calendar Access") {
                            connect { _ = try await CalendarSource.requestAccess() }
                        }
                    }
                }
            }
            .navigationTitle("Data Sources")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        connect {}
                    } label: {
                        if refreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(refreshing)
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )) { _ in
                // Permission dialogs foreground over the app; re-check on return.
                locationAuthorized = LocationProvider.shared.isAuthorized
            }
            .task {
                healthPrompted = await HealthSource.authorizationStatusKnown()
            }
        }
    }

    /// Run a permission request, then refresh so newly granted sources go
    /// live immediately instead of waiting for the next cadence window.
    private func connect(_ request: @escaping () async throws -> Void) {
        refreshing = true
        Task {
            try? await request()
            await store.refreshData()
            locationAuthorized = LocationProvider.shared.isAuthorized
            healthPrompted = await HealthSource.authorizationStatusKnown()
            refreshing = false
        }
    }

    @ViewBuilder
    private func sourceRow(id: String, name: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(for: id)
        }
    }

    @ViewBuilder
    private func statusBadge(for sourceID: String) -> some View {
        let snapshot = AppGroup.snapshotStore.load(sourceID: sourceID)
        if let snapshot, snapshot.fetchedAt > .distantPast {
            VStack(alignment: .trailing, spacing: 2) {
                Label("Live", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                Text(snapshot.fetchedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("Sample", systemImage: "sparkles")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        }
    }
}
