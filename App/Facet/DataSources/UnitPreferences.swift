import Foundation

/// Which scale weather temperatures are captured in. Snapshots store bare
/// numbers — templates bind `weather.temperature`, not a `Measurement` — so
/// the unit is applied at fetch time, not at render time. Changing it means
/// refetching, not re-reading.
enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case celsius
    case fahrenheit

    var unit: UnitTemperature {
        switch self {
        case .celsius: return .celsius
        case .fahrenheit: return .fahrenheit
        }
    }

    /// Chrome copy for the picker. The degree sign on a widget belongs to
    /// the layer's text template, never to the stored value.
    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}

/// Unit choices, stored in App Group defaults alongside the snapshot cache so
/// the widget extension and the app always agree on what a stored number
/// means.
enum UnitPreferences {
    private static let temperatureKey = "temperatureUnit"

    /// Falls back to the device's region rather than to a hardcoded scale, so
    /// a US phone reads 88°F on first launch without anyone opening settings.
    static var temperature: TemperatureUnit {
        get {
            AppGroup.defaults.string(forKey: temperatureKey)
                .flatMap(TemperatureUnit.init(rawValue:)) ?? localeDefault
        }
        set { AppGroup.defaults.set(newValue.rawValue, forKey: temperatureKey) }
    }

    /// US → Fahrenheit, everyone else → Celsius. The UK measurement system is
    /// mixed, but its temperatures are metric, so it lands with the majority.
    static var localeDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }
}
