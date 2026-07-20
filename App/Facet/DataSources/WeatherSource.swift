import CoreLocation
import Foundation
import FacetData
import WeatherKit

/// Real weather via WeatherKit at the device's current location. Values are
/// shaped to match `SampleData.weather` exactly, so every template binding
/// (`weather.temperature`, `weather.hourly.3`, …) works unchanged once the
/// user grants location access.
struct WeatherSource: DataSourceProvider {
    let descriptor = DataSourceDescriptor(
        id: "weather",
        displayName: "Weather",
        cadence: .hourly,
        providedPaths: [
            "weather.temperature", "weather.condition", "weather.symbol",
            "weather.high", "weather.low", "weather.humidity", "weather.hourly",
        ]
    )

    func fetch() async throws -> DataSnapshot {
        let location = try await LocationProvider.shared.currentLocation()
        let (current, daily, hourly) = try await WeatherService.shared.weather(
            for: location,
            including: .current, .daily, .hourly
        )

        guard let today = daily.forecast.first else {
            throw DataSourceError.fetchFailed("WeatherKit returned no daily forecast")
        }

        // Templates chart exactly 12 points; from the current hour forward.
        let now = Date()
        let upcoming = hourly.forecast.filter { $0.date >= now.addingTimeInterval(-30 * 60) }
        let hourlyTemps = upcoming.prefix(12).map {
            SnapshotValue.number($0.temperature.converted(to: .celsius).value.rounded())
        }

        return DataSnapshot(
            sourceID: descriptor.id,
            values: .object([
                "temperature": .number(current.temperature.converted(to: .celsius).value),
                "condition": .string(current.condition.description),
                "symbol": .string(current.symbolName),
                "high": .number(today.highTemperature.converted(to: .celsius).value),
                "low": .number(today.lowTemperature.converted(to: .celsius).value),
                "humidity": .number(current.humidity),
                "hourly": .list(Array(hourlyTemps)),
            ])
        )
    }
}

/// One-shot location fixes for data sources. CLLocationManager wants a run
/// loop and delivers delegate callbacks off the main thread, so the manager
/// lives on the main actor and hands results back through a continuation.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var continuations: [CheckedContinuation<CLLocation, Error>] = []

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// The most recent fix CoreLocation has on hand, if any. Never prompts;
    /// astronomy math tolerates kilometers of error, so stale is fine.
    var lastKnownLocation: CLLocation? {
        manager.location
    }

    var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Prompt for when-in-use access. Safe to call repeatedly; iOS only
    /// shows the dialog while the status is .notDetermined.
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func currentLocation() async throws -> CLLocation {
        guard isAuthorized else {
            throw DataSourceError.unavailable("Location access not granted")
        }
        // A recent cached fix is plenty for weather — city-level is enough.
        if let cached = manager.location, cached.timestamp > Date().addingTimeInterval(-15 * 60) {
            return cached
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            let waiting = self.continuations
            self.continuations.removeAll()
            for continuation in waiting { continuation.resume(returning: location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let waiting = self.continuations
            self.continuations.removeAll()
            for continuation in waiting { continuation.resume(throwing: error) }
        }
    }
}
