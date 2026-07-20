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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connections").facetEyebrow()
                        Text("Data Sources")
                            .font(FacetUI.title(26))
                            .kerning(-0.3)
                            .foregroundStyle(FacetUI.ink)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        sourceCard(
                            id: "battery", icon: "battery.75percent",
                            name: "Battery", detail: "Reads directly from the device"
                        )
                        sourceCard(
                            id: "weather", icon: "cloud.sun.fill",
                            name: "Weather", detail: "Apple Weather via your location"
                        ) {
                            if !locationAuthorized {
                                connectButton("Allow Location Access") {
                                    LocationProvider.shared.requestPermission()
                                }
                            }
                        }
                        sourceCard(
                            id: "health", icon: "heart.fill",
                            name: "Health", detail: "Steps, energy, stand hours"
                        ) {
                            // HealthKit hides read-grant status by design;
                            // "the prompt has been shown" is the strongest
                            // signal there is, so the button disappears after
                            // the user has answered it once.
                            if HealthSource.isAvailable && !healthPrompted {
                                connectButton("Connect Apple Health") {
                                    connect { try await HealthSource.requestAuthorization() }
                                }
                            }
                        }
                        sourceCard(
                            id: "calendar", icon: "calendar",
                            name: "Calendar", detail: "Next event and today's count"
                        ) {
                            if !CalendarSource.authorizationGranted {
                                connectButton("Allow Calendar Access") {
                                    connect { _ = try await CalendarSource.requestAccess() }
                                }
                            }
                        }
                    }

                    Text("Sources marked Sample show designed placeholder data until their permission is granted. Widgets update from the shared cache on the system's refresh budget.")
                        .font(FacetUI.caption)
                        .foregroundStyle(FacetUI.inkTertiary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(FacetUI.bg)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(FacetToolButton())
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        connect {}
                    } label: {
                        if refreshing {
                            ProgressView().tint(FacetUI.ink)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(FacetToolButton())
                    .disabled(refreshing)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
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
        .preferredColorScheme(.dark)
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
    private func sourceCard(
        id: String, icon: String, name: String, detail: String,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FacetUI.inkSecondary)
                    .frame(width: 38, height: 38)
                    .background(FacetUI.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(FacetUI.label)
                        .foregroundStyle(FacetUI.ink)
                    Text(detail)
                        .font(FacetUI.caption)
                        .foregroundStyle(FacetUI.inkTertiary)
                }
                Spacer(minLength: 8)
                statusBadge(for: id)
            }
            .padding(14)

            action()
        }
        .facetPanel()
    }

    private func connectButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FacetUI.label)
                .foregroundStyle(FacetUI.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(FacetUI.accentDim)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusBadge(for sourceID: String) -> some View {
        let snapshot = AppGroup.snapshotStore.load(sourceID: sourceID)
        if let snapshot, snapshot.fetchedAt > .distantPast {
            VStack(alignment: .trailing, spacing: 3) {
                FacetPill(text: "Live", color: FacetUI.live, icon: "checkmark")
                Text(snapshot.fetchedAt, style: .relative)
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.inkTertiary)
            }
        } else {
            FacetPill(text: "Sample", color: FacetUI.sample, icon: "sparkles")
        }
    }
}
