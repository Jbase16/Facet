import XCTest
import FacetCore
@testable import FacetData

final class SnapshotTests: XCTestCase {
    func testDecodeArbitraryJSON() throws {
        let json = """
        {"temperature": 21.5, "condition": "Cloudy", "alerts": ["wind", "rain"],
         "detail": {"humidity": 0.48, "severe": false}}
        """
        let value = try JSONDecoder().decode(SnapshotValue.self, from: Data(json.utf8))
        XCTAssertEqual(value.value(atPath: "temperature"), .number(21.5))
        XCTAssertEqual(value.value(atPath: "condition"), .string("Cloudy"))
        XCTAssertEqual(value.value(atPath: "alerts.1"), .string("rain"))
        XCTAssertEqual(value.value(atPath: "detail.humidity"), .number(0.48))
        XCTAssertEqual(value.value(atPath: "detail.severe"), .bool(false))
        XCTAssertNil(value.value(atPath: "missing"))
        XCTAssertNil(value.value(atPath: "alerts.9"))
        XCTAssertNil(value.value(atPath: "temperature.deeper"))
    }

    func testRoundTrip() throws {
        let value = SnapshotValue.object([
            "a": .number(1),
            "b": .list([.bool(true), .string("x")]),
        ])
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(SnapshotValue.self, from: data), value)
    }

    func testScalarConversion() {
        XCTAssertEqual(SnapshotValue.number(1).scalar, .number(1))
        XCTAssertEqual(SnapshotValue.string("x").scalar, .string("x"))
        XCTAssertEqual(SnapshotValue.bool(true).scalar, .bool(true))
        XCTAssertNil(SnapshotValue.list([]).scalar)
        XCTAssertNil(SnapshotValue.object([:]).scalar)
    }

    func testSnapshotSetVariableLookup() {
        var set = SnapshotSet()
        set.insert(DataSnapshot(
            sourceID: "battery",
            values: .object(["level": .number(0.82), "state": .string("charging")])
        ))
        XCTAssertEqual(set.value(forVariable: "battery.level"), .number(0.82))
        XCTAssertEqual(set.value(forVariable: "battery.state"), .string("charging"))
        XCTAssertNil(set.value(forVariable: "battery.missing"))
        XCTAssertNil(set.value(forVariable: "weather.temperature"))
        XCTAssertNil(set.value(forVariable: "battery"), "Bare source name is an object, not a scalar")
    }

    func testSnapshotSetWorksAsEvaluationContext() throws {
        var set = SnapshotSet()
        set.insert(DataSnapshot(sourceID: "health", values: .object([
            "steps": .number(7482), "stepsGoal": .number(10000),
        ])))
        let result = try Evaluator.evaluate("health.steps / health.stepsGoal", context: set)
        XCTAssertEqual(try result.asNumber(), 0.7482, accuracy: 0.0001)
    }
}
