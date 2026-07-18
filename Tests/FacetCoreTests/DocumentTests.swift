import XCTest
@testable import FacetCore

final class DocumentTests: XCTestCase {
    private func sampleDocument() -> WidgetDocument {
        let textLayer = Layer(
            name: "Percent",
            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.8, height: 0.3),
            content: .text(TextContent(
                text: "{percent(battery.level)}",
                font: .token("display"),
                color: .token("accent")
            ))
        )
        let gaugeLayer = Layer(
            name: "Ring",
            content: .gauge(GaugeContent(
                value: "battery.level",
                tint: .token("accent"),
                track: .literal(ColorValue(hex: "#33333380")!)
            ))
        )
        let root = Layer(
            name: "Canvas",
            content: .container(ContainerContent(
                layout: .overlay,
                background: .token("background"),
                children: [gaugeLayer, textLayer]
            ))
        )
        return WidgetDocument(
            name: "Battery Ring",
            tokens: ThemeTokens(
                colors: [
                    "accent": ColorToken(light: ColorValue(hex: "#34C759")!, dark: ColorValue(hex: "#30D158")!),
                    "background": ColorToken(light: .white, dark: .black),
                ],
                fonts: ["display": FontToken(size: 28, weight: .bold, design: .rounded)]
            ),
            root: root,
            sources: ["battery"],
            overrides: [
                .accessoryCircular: [LayerPatch(layerID: textLayer.id, fontSize: 14)],
            ]
        )
    }

    func testRoundTrip() throws {
        let document = sampleDocument()
        let data = try FacetFile.encode(document)
        let decoded = try FacetFile.decode(data)
        XCTAssertEqual(decoded, document)
    }

    func testEncodedFormIsStableAndReadable() throws {
        let document = sampleDocument()
        let json = String(data: try FacetFile.encode(document), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"schemaVersion\" : 2"))
        XCTAssertTrue(json.contains("\"type\" : \"container\""))
        XCTAssertTrue(json.contains("\"type\" : \"gauge\""))
        XCTAssertTrue(json.contains("token:accent"), "Color token refs serialize as token:name")
        XCTAssertTrue(json.contains("#34C759"), "Colors serialize as hex")
        // Encoding twice yields identical bytes (sorted keys) — documents diff cleanly.
        XCTAssertEqual(try FacetFile.encode(document), try FacetFile.encode(document))
    }

    func testUnknownLayerTypeFailsCleanly() {
        let json = """
        {"id": "6E4460D5-0F91-4C7C-8E7B-9A2749748C6C", "name": "X", "type": "hologram"}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(Layer.self, from: Data(json.utf8)))
    }

    func testFutureSchemaVersionRejected() throws {
        var document = sampleDocument()
        document.schemaVersion = 999
        let data = try FacetFile.encode(document)
        XCTAssertThrowsError(try FacetFile.decode(data)) { error in
            XCTAssertEqual(error as? DocumentError, .unsupportedSchemaVersion(999))
        }
    }

    func testColorHexParsing() {
        XCTAssertEqual(ColorValue(hex: "#FF0000")?.hexString, "#FF0000")
        XCTAssertEqual(ColorValue(hex: "FF0000")?.hexString, "#FF0000")
        XCTAssertEqual(ColorValue(hex: "#FF000080")?.alpha ?? 0, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertNil(ColorValue(hex: "#FF00"))
        XCTAssertNil(ColorValue(hex: "not-a-color"))
    }

    func testColorTokenSchemeResolution() {
        let token = ColorToken(light: .white, dark: .black)
        XCTAssertEqual(token.resolved(for: .light), .white)
        XCTAssertEqual(token.resolved(for: .dark), .black)
        let single = ColorToken(light: .white)
        XCTAssertEqual(single.resolved(for: .dark), .white, "Dark defaults to light when unspecified")
    }

    func testFirstLayerSearch() {
        let document = sampleDocument()
        guard case .container(let container) = document.root.content else {
            return XCTFail("Root should be a container")
        }
        let target = container.children[1]
        XCTAssertEqual(document.root.firstLayer(withID: target.id)?.name, "Percent")
        XCTAssertNil(document.root.firstLayer(withID: UUID()))
    }

    func testUpdateFirstLayerMutatesDeepChild() {
        var document = sampleDocument()
        guard case .container(let container) = document.root.content else {
            return XCTFail("Root should be a container")
        }
        let targetID = container.children[1].id
        let updated = document.root.updateFirstLayer(withID: targetID) { layer in
            layer.frame.x = 0.25
            layer.isHidden = true
        }
        XCTAssertTrue(updated)
        let found = document.root.firstLayer(withID: targetID)
        XCTAssertEqual(found?.frame.x, 0.25)
        XCTAssertEqual(found?.isHidden, true)
        XCTAssertFalse(document.root.updateFirstLayer(withID: UUID()) { _ in })
    }

    func testPatchLookup() {
        let document = sampleDocument()
        guard case .container(let container) = document.root.content else {
            return XCTFail("Root should be a container")
        }
        let textID = container.children[1].id
        XCTAssertEqual(document.patch(for: textID, in: .accessoryCircular)?.fontSize, 14)
        XCTAssertNil(document.patch(for: textID, in: .systemSmall))
    }
}
