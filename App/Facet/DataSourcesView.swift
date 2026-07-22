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
    @State private var focusAuthorized = FocusSource.authorizationGranted
    @State private var temperatureUnit = UnitPreferences.temperature
    @State private var customConfigs = CustomSourceStore().load()
    @State private var editorTarget: EditorTarget?

    /// Sheet routing: `config == nil` means "create new".
    private struct EditorTarget: Identifiable {
        var config: URLSourceConfig?
        var id: String { config?.id ?? "new" }
    }

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
                            temperatureUnitPicker
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
                        sourceCard(
                            id: "reminders", icon: "checklist",
                            name: "Reminders", detail: "Due today, overdue, next due",
                            missingText: "Pending", missingIcon: "clock"
                        ) {
                            if !RemindersSource.authorizationGranted {
                                connectButton("Allow Reminders Access") {
                                    connect { _ = try await RemindersSource.requestAccess() }
                                }
                            }
                        }
                        // Honest detail copy: iOS shares *that* a Focus is
                        // on, never which one. Promising "Deep Work" here
                        // would be a promise the API can't keep.
                        sourceCard(
                            id: "focus", icon: "moon.circle.fill",
                            name: "Focus", detail: "Whether a Focus is on (not which one)",
                            missingText: "Pending", missingIcon: "clock"
                        ) {
                            if !focusAuthorized {
                                connectButton("Allow Focus Status") {
                                    connect { _ = await FocusSource.requestAccess() }
                                }
                            }
                        }
                        // No permission and no seeded sample: computed on
                        // device, so it goes Live on the first refresh pass.
                        sourceCard(
                            id: "astronomy", icon: "moon.stars.fill",
                            name: "Astronomy", detail: "Sunrise, sunset, moon phase",
                            missingText: "Pending", missingIcon: "clock"
                        )
                    }

                    customSourcesSection

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
                // Permission dialogs foreground over the app; re-check on
                // return. Focus is doubly worth re-reading — its grant can
                // also be revoked from Settings while the app is backgrounded.
                locationAuthorized = LocationProvider.shared.isAuthorized
                focusAuthorized = FocusSource.authorizationGranted
            }
            .task {
                healthPrompted = await HealthSource.authorizationStatusKnown()
            }
            .sheet(item: $editorTarget) { target in
                CustomSourceEditorView(existing: target.config) { config in
                    CustomSourceStore().save(config)
                    customConfigs = CustomSourceStore().load()
                    // Refresh so the new source fetches now instead of at
                    // the next cadence window.
                    connect {}
                }
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
            focusAuthorized = FocusSource.authorizationGranted
            healthPrompted = await HealthSource.authorizationStatusKnown()
            refreshing = false
        }
    }

    /// Temperature scale for the Weather card. Snapshots hold converted
    /// numbers, so switching units can't be a re-render — the old reading is
    /// aged out and refetched in the new scale on the spot, rather than
    /// leaving the widget in the wrong unit until the next hourly window.
    private var temperatureUnitPicker: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(FacetUI.hairline)
                .frame(height: 1)

            HStack(spacing: 8) {
                Text("Units")
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.inkTertiary)
                Spacer(minLength: 8)
                ForEach(TemperatureUnit.allCases, id: \.self) { candidate in
                    Button {
                        guard candidate != temperatureUnit else { return }
                        temperatureUnit = candidate
                        UnitPreferences.temperature = candidate
                        WeatherSource.invalidateCachedSnapshot()
                        connect {}
                    } label: {
                        Text(candidate.symbol)
                            .font(FacetUI.caption)
                            .foregroundStyle(
                                candidate == temperatureUnit ? FacetUI.accent : FacetUI.inkSecondary
                            )
                            .frame(minWidth: 34)
                            .padding(.vertical, 7)
                            .background(
                                candidate == temperatureUnit ? FacetUI.accentDim : FacetUI.raised
                            )
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().strokeBorder(
                                    candidate == temperatureUnit
                                        ? FacetUI.accent.opacity(0.4) : FacetUI.hairline,
                                    lineWidth: 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(refreshing)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func sourceCard(
        id: String, icon: String, name: String, detail: String,
        missingText: String = "Sample", missingIcon: String = "sparkles",
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
                statusBadge(for: id, missingText: missingText, missingIcon: missingIcon)
            }
            .padding(14)

            action()
        }
        .facetPanel()
    }

    // MARK: - Custom sources

    private var customSourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Custom Sources").facetEyebrow()
                Spacer()
                Button {
                    editorTarget = EditorTarget(config: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(FacetToolButton())
            }

            if customConfigs.isEmpty {
                Text("Turn any JSON API into widget data. Add a URL and Facet fetches it on the shared refresh budget.")
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .facetPanel()
            } else {
                ForEach(customConfigs) { config in
                    sourceCard(
                        id: config.id, icon: "link",
                        name: config.displayName,
                        detail: "\(config.url.host() ?? config.url.absoluteString) · \(config.cadence.displayName)",
                        missingText: "Pending", missingIcon: "clock"
                    )
                    .contextMenu {
                        Button {
                            editorTarget = EditorTarget(config: config)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            CustomSourceStore().delete(id: config.id)
                            customConfigs = CustomSourceStore().load()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
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

    /// Built-ins fall back to "Sample" (they're seeded with placeholder
    /// data); sources with no seed fall back to "Pending" — nothing cached
    /// yet is not the same as showing designed sample data.
    @ViewBuilder
    private func statusBadge(
        for sourceID: String, missingText: String = "Sample", missingIcon: String = "sparkles"
    ) -> some View {
        let snapshot = AppGroup.snapshotStore.load(sourceID: sourceID)
        if let snapshot, snapshot.fetchedAt > .distantPast {
            VStack(alignment: .trailing, spacing: 3) {
                FacetPill(text: "Live", color: FacetUI.live, icon: "checkmark")
                Text(snapshot.fetchedAt, style: .relative)
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.inkTertiary)
            }
        } else {
            FacetPill(text: missingText, color: FacetUI.sample, icon: missingIcon)
        }
    }
}
