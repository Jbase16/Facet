import Foundation
import UIKit
import FacetCore
import FacetData

/// The on-device data source providers. Battery, weather, health, calendar,
/// and reminders are all real hardware/framework data; each throws
/// `DataSourceError.unavailable` until its permission is granted, and the
/// refresh pipeline keeps the last cached snapshot on failure. Astronomy and
/// user-defined URL sources need no permission at all.
enum DeviceDataSources {
    /// Main-actor because the astronomy coordinate comes from
    /// LocationProvider; every caller (refresh, the sources sheet) already
    /// lives there.
    @MainActor
    static var providers: [any DataSourceProvider] {
        var providers: [any DataSourceProvider] = [
            DeviceBatterySource(),
            WeatherSource(),
            HealthSource(),
            CalendarSource(),
            RemindersSource(),
        ]
        // Astronomy is pure math but needs a coordinate. Reuse the last
        // CoreLocation fix when one exists — no prompt, no fetch. Without
        // one, fall back to 0°/0°: sun times are generic but well-defined,
        // and they correct themselves once Weather's location grant lands.
        let coordinate = LocationProvider.shared.lastKnownLocation?.coordinate
        providers.append(AstronomySource(
            latitude: coordinate?.latitude ?? 0,
            longitude: coordinate?.longitude ?? 0
        ))
        providers.append(contentsOf: CustomSourceStore().providers())
        return providers
    }

    /// Seed the cache with backdated sample snapshots for any source that has
    /// never fetched. Templates keep rendering something believable before
    /// permissions are granted, and because the seeds are already stale the
    /// planner tries the real fetch on the very next pass.
    static func seedSampleSnapshotsIfNeeded(store: SnapshotStore) {
        let samples: [StaticSource] = [SampleData.weather, SampleData.health, SampleData.calendar]
        for sample in samples where store.load(sourceID: sample.descriptor.id) == nil {
            var snapshot = sample.snapshot()
            snapshot.fetchedAt = .distantPast
            try? store.save(snapshot)
        }
    }
}

struct DeviceBatterySource: DataSourceProvider {
    let descriptor = DataSourceDescriptor(
        id: "battery",
        displayName: "Battery",
        cadence: .frequent,
        providedPaths: ["battery.level", "battery.state", "battery.lowPowerMode"]
    )

    func fetch() async throws -> DataSnapshot {
        await MainActor.run {
            let device = UIDevice.current
            let wasMonitoring = device.isBatteryMonitoringEnabled
            device.isBatteryMonitoringEnabled = true
            defer { device.isBatteryMonitoringEnabled = wasMonitoring }

            let level = device.batteryLevel >= 0 ? Double(device.batteryLevel) : 1.0
            let state: String
            switch device.batteryState {
            case .charging: state = "charging"
            case .full: state = "full"
            case .unplugged: state = "unplugged"
            default: state = "unknown"
            }
            return DataSnapshot(
                sourceID: descriptor.id,
                values: .object([
                    "level": .number(level),
                    "state": .string(state),
                    "lowPowerMode": .bool(ProcessInfo.processInfo.isLowPowerModeEnabled),
                ])
            )
        }
    }
}
