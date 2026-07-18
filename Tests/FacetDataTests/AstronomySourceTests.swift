import XCTest
@testable import FacetData

final class AstronomySourceTests: XCTestCase {
    // London, 2025-06-21 (summer solstice). Published times: sunrise
    // 04:43 BST (03:43 UTC), sunset 21:21 BST (20:21 UTC).
    private static let london = (latitude: 51.5074, longitude: -0.1278)
    private static let solstice2025 = Date(timeIntervalSince1970: 1_750_464_000) // 00:00 UTC

    func testLondonSolsticeSunriseSunset() async throws {
        let source = AstronomySource(
            latitude: Self.london.latitude,
            longitude: Self.london.longitude,
            now: { Self.solstice2025 }
        )
        let snapshot = try await source.fetch()

        let publishedSunrise = Self.solstice2025.addingTimeInterval(3 * 3600 + 43 * 60)
        let publishedSunset = Self.solstice2025.addingTimeInterval(20 * 3600 + 21 * 60)
        guard
            case .number(let sunrise)? = snapshot.values.value(atPath: "sunriseTimestamp"),
            case .number(let sunset)? = snapshot.values.value(atPath: "sunsetTimestamp"),
            case .number(let dayLength)? = snapshot.values.value(atPath: "dayLengthMinutes")
        else {
            return XCTFail("Missing solar values in snapshot")
        }

        XCTAssertEqual(sunrise, publishedSunrise.timeIntervalSince1970, accuracy: 600)
        XCTAssertEqual(sunset, publishedSunset.timeIntervalSince1970, accuracy: 600)
        XCTAssertEqual(dayLength, (sunset - sunrise) / 60, accuracy: 0.01)
        XCTAssertEqual(dayLength, 16 * 60 + 38, accuracy: 20, "~16h38m of daylight at the solstice")
        XCTAssertEqual(snapshot.values.value(atPath: "isPolarDay"), .bool(false))
        XCTAssertEqual(snapshot.values.value(atPath: "isPolarNight"), .bool(false))
    }

    func testPolarDayAndNightInSvalbard() {
        let svalbard = AstronomySource(latitude: 78.2232, longitude: 15.6267)

        let june = svalbard.snapshot(on: Self.solstice2025)
        XCTAssertEqual(june.values.value(atPath: "isPolarDay"), .bool(true))
        XCTAssertEqual(june.values.value(atPath: "dayLengthMinutes"), .number(24 * 60))

        // 2025-12-21, midwinter.
        let december = svalbard.snapshot(on: Date(timeIntervalSince1970: 1_766_275_200))
        XCTAssertEqual(december.values.value(atPath: "isPolarNight"), .bool(true))
        XCTAssertEqual(december.values.value(atPath: "dayLengthMinutes"), .number(0))
    }

    func testFullMoonDate() {
        // Full moon of 2024-01-25 17:54 UTC.
        let fullMoon = Date(timeIntervalSince1970: 1_706_205_240)
        let snapshot = AstronomySource(latitude: 0, longitude: 0).snapshot(on: fullMoon)

        guard
            case .number(let phase)? = snapshot.values.value(atPath: "moonPhase"),
            case .number(let illumination)? = snapshot.values.value(atPath: "moonIllumination")
        else {
            return XCTFail("Missing moon values in snapshot")
        }
        // The mean synodic cycle drifts a few hours from true full moon:
        // allow ±0.02 of a cycle (~14 hours).
        XCTAssertEqual(phase, 0.5, accuracy: 0.02)
        XCTAssertGreaterThan(illumination, 0.98)
        XCTAssertEqual(snapshot.values.value(atPath: "moonPhaseName"), .string("Full Moon"))
    }

    func testNewMoonAtEpoch() {
        // The epoch itself: 2000-01-06 18:14 UTC.
        let epoch = Date(timeIntervalSince1970: 947_182_440)
        let snapshot = AstronomySource(latitude: 0, longitude: 0).snapshot(on: epoch)

        XCTAssertEqual(snapshot.values.value(atPath: "moonPhase"), .number(0))
        XCTAssertEqual(snapshot.values.value(atPath: "moonIllumination"), .number(0))
        XCTAssertEqual(snapshot.values.value(atPath: "moonPhaseName"), .string("New Moon"))
    }

    func testMoonPhaseNameBands() {
        XCTAssertEqual(AstronomySource.moonPhaseName(for: 0.25), "First Quarter")
        XCTAssertEqual(AstronomySource.moonPhaseName(for: 0.375), "Waxing Gibbous")
        XCTAssertEqual(AstronomySource.moonPhaseName(for: 0.625), "Waning Gibbous")
        XCTAssertEqual(AstronomySource.moonPhaseName(for: 0.75), "Last Quarter")
        XCTAssertEqual(AstronomySource.moonPhaseName(for: 0.96), "New Moon", "Band wraps around the cycle")
    }

    func testDescriptorAdvertisesPaths() {
        let descriptor = AstronomySource(latitude: 0, longitude: 0).descriptor
        XCTAssertEqual(descriptor.cadence, .daily)
        XCTAssertTrue(descriptor.providedPaths.contains("astronomy.sunriseTimestamp"))
        XCTAssertTrue(descriptor.providedPaths.contains("astronomy.moonPhaseName"))
    }
}
