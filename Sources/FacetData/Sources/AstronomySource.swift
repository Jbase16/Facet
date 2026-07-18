import Foundation

/// Computed sunrise/sunset and moon phase for a fixed coordinate. Pure math —
/// no network, no location permission — so it never fails and costs nothing
/// against the refresh budget beyond its daily cadence.
///
/// Solar times use the standard NOAA sunrise equation (solar declination +
/// hour angle), accurate to a few minutes, which is plenty for a widget. Moon
/// phase is derived from the mean synodic month counted from the new moon of
/// 2000-01-06 18:14 UTC; mean-cycle error is at most a few hours.
public struct AstronomySource: DataSourceProvider {
    public let descriptor = DataSourceDescriptor(
        id: "astronomy",
        displayName: "Astronomy",
        cadence: .daily,
        providedPaths: [
            "astronomy.sunriseTimestamp", "astronomy.sunsetTimestamp",
            "astronomy.dayLengthMinutes", "astronomy.isPolarDay",
            "astronomy.isPolarNight", "astronomy.moonPhase",
            "astronomy.moonPhaseName", "astronomy.moonIllumination",
        ]
    )

    /// Degrees north; south is negative.
    public let latitude: Double
    /// Degrees east; west is negative.
    public let longitude: Double
    private let now: @Sendable () -> Date

    public init(
        latitude: Double,
        longitude: Double,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.now = now
    }

    public func fetch() async throws -> DataSnapshot {
        snapshot(on: now())
    }

    /// Synchronous capture for the UTC day containing `date`, used when
    /// pre-computing timeline entries.
    public func snapshot(on date: Date) -> DataSnapshot {
        let solar = solarEvents(on: date)
        let phase = Self.moonPhase(at: date)

        return DataSnapshot(
            sourceID: descriptor.id,
            fetchedAt: date,
            values: .object([
                "sunriseTimestamp": .number(solar.sunrise.timeIntervalSince1970),
                "sunsetTimestamp": .number(solar.sunset.timeIntervalSince1970),
                "dayLengthMinutes": .number(solar.dayLengthMinutes),
                "isPolarDay": .bool(solar.isPolarDay),
                "isPolarNight": .bool(solar.isPolarNight),
                "moonPhase": .number(phase),
                "moonPhaseName": .string(Self.moonPhaseName(for: phase)),
                "moonIllumination": .number(Self.moonIllumination(for: phase)),
            ])
        )
    }

    // MARK: - Solar position (NOAA sunrise equation)

    struct SolarEvents {
        var sunrise: Date
        var sunset: Date
        var dayLengthMinutes: Double
        var isPolarDay: Bool
        var isPolarNight: Bool
    }

    /// Days per Julian-date unit conversion: Unix epoch as a Julian date.
    private static let unixEpochJulianDate = 2440587.5
    /// Julian date of the J2000 epoch (2000-01-01 12:00 TT).
    private static let j2000 = 2451545.0

    func solarEvents(on date: Date) -> SolarEvents {
        // Anchor the calculation at noon UTC of the date's UTC day so the
        // result is stable regardless of when during the day we compute.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.startOfDay(for: date).addingTimeInterval(12 * 60 * 60)
        let julianDate = noon.timeIntervalSince1970 / 86_400 + Self.unixEpochJulianDate

        // Mean solar time at this longitude, in days since J2000.
        let daysSinceJ2000 = julianDate - Self.j2000 + 0.0008
        let meanSolarTime = daysSinceJ2000 - (-longitude) / 360

        // Solar mean anomaly, equation of the center, ecliptic longitude.
        let meanAnomaly = (357.5291 + 0.985_600_28 * meanSolarTime)
            .truncatingRemainder(dividingBy: 360)
        let center = 1.9148 * sin(radians(meanAnomaly))
            + 0.0200 * sin(radians(2 * meanAnomaly))
            + 0.0003 * sin(radians(3 * meanAnomaly))
        let eclipticLongitude = (meanAnomaly + center + 180 + 102.9372)
            .truncatingRemainder(dividingBy: 360)

        // Solar transit (local solar noon) as a Julian date.
        let transit = Self.j2000 + meanSolarTime
            + 0.0053 * sin(radians(meanAnomaly))
            - 0.0069 * sin(radians(2 * eclipticLongitude))

        // Declination, then the hour angle at which the sun's center sits
        // 0.833° below the horizon (refraction + solar radius).
        let sinDeclination = sin(radians(eclipticLongitude)) * sin(radians(23.4397))
        let cosDeclination = cos(asin(sinDeclination))
        let cosHourAngle = (sin(radians(-0.833)) - sin(radians(latitude)) * sinDeclination)
            / (cos(radians(latitude)) * cosDeclination)

        // |cos ω₀| > 1 means the sun never crosses the horizon today. Clamp
        // so sunrise/sunset stay well-defined (they collapse to transit for
        // polar night, transit ± 12 h for polar day) and flag it.
        let isPolarDay = cosHourAngle < -1
        let isPolarNight = cosHourAngle > 1
        let hourAngle = degrees(acos(min(1, max(-1, cosHourAngle))))

        let sunrise = Date(
            timeIntervalSince1970: (transit - hourAngle / 360 - Self.unixEpochJulianDate) * 86_400
        )
        let sunset = Date(
            timeIntervalSince1970: (transit + hourAngle / 360 - Self.unixEpochJulianDate) * 86_400
        )
        return SolarEvents(
            sunrise: sunrise,
            sunset: sunset,
            dayLengthMinutes: 2 * hourAngle / 360 * 24 * 60,
            isPolarDay: isPolarDay,
            isPolarNight: isPolarNight
        )
    }

    // MARK: - Moon phase

    /// The new moon of 2000-01-06 18:14 UTC, a conventional lunation epoch.
    private static let newMoonEpoch = Date(timeIntervalSince1970: 947_182_440)
    /// Mean synodic month, in days.
    private static let synodicMonth = 29.530_588_67

    /// Fraction of the synodic cycle elapsed at `date`: 0 = new, 0.5 = full.
    static func moonPhase(at date: Date) -> Double {
        let days = date.timeIntervalSince(newMoonEpoch) / 86_400
        let phase = (days / synodicMonth).truncatingRemainder(dividingBy: 1)
        return phase < 0 ? phase + 1 : phase
    }

    /// Illuminated fraction of the disc, from the phase angle. 0 at new
    /// moon, 1 at full.
    static func moonIllumination(for phase: Double) -> Double {
        (1 - cos(2 * .pi * phase)) / 2
    }

    /// The traditional eight phase names, each owning a 1/8-cycle band
    /// centered on its exact moment (so "Full Moon" spans ±1.85 days).
    static func moonPhaseName(for phase: Double) -> String {
        let names = [
            "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
            "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent",
        ]
        return names[Int((phase * 8).rounded()) % 8]
    }
}

private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
