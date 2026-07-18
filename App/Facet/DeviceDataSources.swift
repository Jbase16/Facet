import Foundation
import UIKit
import FacetData

/// The on-device data source providers. Battery is real hardware data;
/// weather, health, and calendar currently serve the bundled sample payloads
/// until their WeatherKit/HealthKit/EventKit providers land (see SPEC §4.3 —
/// the pipeline, cache, and cadence handling are already the real thing).
enum DeviceDataSources {
    static var providers: [any DataSourceProvider] {
        [
            DeviceBatterySource(),
            SampleData.weather,
            SampleData.health,
            SampleData.calendar,
        ]
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
