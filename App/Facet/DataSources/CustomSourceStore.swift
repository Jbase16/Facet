import Foundation
import FacetData

/// Persists user-defined URL sources in App Group defaults so the widget
/// extension sees the same catalog as the app. `URLSourceConfig` is already
/// plain Codable JSON; this store just owns the defaults slot and keeps
/// source IDs unique.
struct CustomSourceStore: Sendable {
    private static let key = "customURLSources"

    /// Built-in provider IDs. A custom slug colliding with one of these
    /// would shadow the real source in the snapshot cache.
    private static let reservedIDs: Set<String> = [
        "time", "battery", "weather", "health", "calendar", "reminders", "astronomy", "focus",
    ]

    func load() -> [URLSourceConfig] {
        guard let data = AppGroup.defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([URLSourceConfig].self, from: data)) ?? []
    }

    /// Insert or replace by ID. Catalog order is preserved so list rows
    /// don't jump around after an edit.
    func save(_ config: URLSourceConfig) {
        var configs = load()
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        persist(configs)
    }

    func delete(id: String) {
        persist(load().filter { $0.id != id })
    }

    /// Providers for every stored config; DeviceDataSources appends these
    /// to the built-ins so the refresh pipeline treats them identically.
    func providers() -> [any DataSourceProvider] {
        load().map { URLJSONSource(config: $0) }
    }

    /// A unique source ID derived from the display name ("My API" → "myapi").
    /// IDs double as expression-path prefixes (`myapi.data.temp`), so they
    /// stay short lowercase alphanumerics; collisions get a numeric suffix.
    func makeID(for displayName: String) -> String {
        let base = displayName.lowercased().filter { $0.isLetter || $0.isNumber }
        let slug = base.isEmpty ? "custom" : String(base.prefix(24))
        let taken = Set(load().map(\.id)).union(Self.reservedIDs)
        guard taken.contains(slug) else { return slug }
        var counter = 2
        while taken.contains("\(slug)\(counter)") { counter += 1 }
        return "\(slug)\(counter)"
    }

    private func persist(_ configs: [URLSourceConfig]) {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        AppGroup.defaults.set(data, forKey: Self.key)
    }
}

extension CadenceClass {
    /// Editor-facing name; the raw case names are API, not copy.
    var displayName: String {
        switch self {
        case .continuous: return "Continuous"
        case .frequent: return "Every 15 min"
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        }
    }
}
