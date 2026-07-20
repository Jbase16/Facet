import XCTest
@testable import FacetCore

/// v1/v2 documents predate visibleWhen and tapAction; they must keep
/// decoding, and the new fields must round-trip when present.
final class InteractivitySchemaTests: XCTestCase {
    func testLegacyLayerJSONDecodesWithNilInteractivity() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Old",
            "type": "text",
            "text": {"text": "hi", "font": "token:body", "color": "token:primary", "alignment": "center"}
        }
        """
        let layer = try JSONDecoder().decode(Layer.self, from: Data(json.utf8))
        XCTAssertNil(layer.visibleWhen)
        XCTAssertNil(layer.tapAction)
    }

    func testInteractivityFieldsRoundTrip() throws {
        let layer = Layer(
            name: "New",
            visibleWhen: "battery.level < 0.2",
            tapAction: TapAction(urlTemplate: "shortcuts://run-shortcut?name=Charge"),
            content: .shape(ShapeContent(kind: .rectangle, fill: Fill.literal(ColorValue.black)))
        )
        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(Layer.self, from: data)
        XCTAssertEqual(decoded.visibleWhen, "battery.level < 0.2")
        XCTAssertEqual(decoded.tapAction?.urlTemplate, "shortcuts://run-shortcut?name=Charge")
    }

    func testAbsentFieldsStayAbsentInEncoding() throws {
        let layer = Layer(
            name: "Plain",
            content: .shape(ShapeContent(kind: .rectangle, fill: Fill.literal(ColorValue.black)))
        )
        let data = try JSONEncoder().encode(layer)
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(raw.contains("visibleWhen"))
        XCTAssertFalse(raw.contains("tapAction"))
    }
}
