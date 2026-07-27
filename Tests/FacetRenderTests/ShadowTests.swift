import XCTest
import FacetCore
import FacetData
@testable import FacetRender

/// Multiple shadows and inset shadows — the primitives behind neumorphism,
/// emboss and deboss.
final class ShadowTests: XCTestCase {
    private func document(_ shadows: [FacetCore.ShadowStyle]) -> WidgetDocument {
        WidgetDocument(
            name: "Depth",
            tokens: ThemeTokens(colors: ["surface": ColorToken(light: .white, dark: .black)], fonts: [:]),
            root: Layer(
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("surface"),
                    children: [
                        Layer(
                            name: "Button",
                            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.6, height: 0.4),
                            style: LayerStyle(cornerRadius: 16, shadows: shadows),
                            content: .shape(ShapeContent(kind: .rectangle, fill: .token("surface")))
                        ),
                    ]
                ))
            ),
            sources: []
        )
    }

    private func resolve(_ shadows: [FacetCore.ShadowStyle]) -> ResolvedWidget {
        DocumentResolver.resolve(
            document: document(shadows),
            snapshots: SnapshotSet(),
            environment: RenderEnvironment(rendition: .systemSmall, colorScheme: .light)
        )
    }

    private func node(_ shadows: [FacetCore.ShadowStyle]) -> RenderNode? {
        resolve(shadows).root.children.first
    }

    private let black = ColorRef.literal(ColorValue(red: 0, green: 0, blue: 0, alpha: 0.35))
    private let white = ColorRef.literal(ColorValue(red: 1, green: 1, blue: 1, alpha: 0.7))

    // MARK: - Resolution

    func testNoShadowsByDefault() {
        XCTAssertEqual(node([])?.shadows.count, 0)
    }

    func testShadowsResolveInOrder() throws {
        let resolved = try XCTUnwrap(node([
            FacetCore.ShadowStyle(color: white, radius: 8, offsetX: -4, offsetY: -4),
            FacetCore.ShadowStyle(color: black, radius: 8, offsetX: 4, offsetY: 4),
        ]))
        XCTAssertEqual(resolved.shadows.count, 2)
        XCTAssertEqual(resolved.shadows[0].offsetX, -4)
        XCTAssertEqual(resolved.shadows[1].offsetX, 4)
    }

    func testOuterAndInnerAreSeparated() throws {
        let resolved = try XCTUnwrap(node([
            FacetCore.ShadowStyle(color: black, radius: 6, offsetY: 3),
            FacetCore.ShadowStyle(color: white, radius: 6, offsetY: -3, inset: true),
        ]))
        XCTAssertEqual(resolved.outerShadows.count, 1)
        XCTAssertEqual(resolved.innerShadows.count, 1)
        XCTAssertTrue(resolved.innerShadows[0].inset)
        XCTAssertFalse(resolved.outerShadows[0].inset)
    }

    func testNegativeRadiusIsClampedRatherThanPropagated() throws {
        let resolved = try XCTUnwrap(node([FacetCore.ShadowStyle(color: black, radius: -12)]))
        XCTAssertEqual(resolved.shadows[0].radius, 0)
    }

    // MARK: - Presets

    func testRaisedIsTwoOuterShadowsOnOppositeSides() {
        let shadows = ShadowPreset.raised.shadows()
        XCTAssertEqual(shadows.count, 2)
        XCTAssertTrue(shadows.allSatisfy { !$0.inset })
        // Opposite sides is what makes it read as lit from one direction.
        XCTAssertEqual(shadows[0].offsetX, -shadows[1].offsetX)
        XCTAssertEqual(shadows[0].offsetY, -shadows[1].offsetY)
    }

    func testPressedIsTheSameGeometryTurnedInward() {
        let raised = ShadowPreset.raised.shadows()
        let pressed = ShadowPreset.pressed.shadows()
        XCTAssertTrue(pressed.allSatisfy(\.inset), "Pressed must be entirely inset")
        XCTAssertEqual(pressed.count, raised.count)
        // Same offsets, opposite assignment: the lit side swaps when the
        // surface turns from a bump into a dent.
        XCTAssertEqual(Set(pressed.map(\.offsetX)), Set(raised.map(\.offsetX)))
    }

    func testEmbossedCombinesInnerReliefWithAnOuterShadow() {
        let shadows = ShadowPreset.embossed.shadows()
        XCTAssertTrue(shadows.contains { $0.inset })
        XCTAssertTrue(shadows.contains { !$0.inset })
    }

    func testPresetsAcceptCustomColoursAndDepth() {
        let shadows = ShadowPreset.raised.shadows(light: white, dark: black, distance: 20, softness: 30)
        XCTAssertTrue(shadows.contains { $0.color == white })
        XCTAssertTrue(shadows.contains { $0.color == black })
        XCTAssertTrue(shadows.allSatisfy { $0.radius == 30 })
        XCTAssertTrue(shadows.allSatisfy { abs($0.offsetX) == 20 })
    }

    // MARK: - SVG output

    private func svg(_ shadows: [FacetCore.ShadowStyle]) -> String {
        SVGRenderer.render(resolve(shadows))
    }

    /// The overwhelmingly common case must keep the cheap CSS form it has
    /// always emitted rather than growing a filter chain.
    func testALoneOuterShadowStillUsesPlainDropShadow() {
        let output = svg([FacetCore.ShadowStyle(color: black, radius: 6, offsetY: 3)])
        XCTAssertTrue(output.contains("drop-shadow("))
        XCTAssertFalse(output.contains("<filter"))
    }

    func testTwoOuterShadowsBecomeAFilterChain() {
        let output = svg(ShadowPreset.raised.shadows())
        XCTAssertTrue(output.contains("<filter"))
        XCTAssertEqual(output.components(separatedBy: "<feDropShadow").count - 1, 2)
    }

    func testAnInnerShadowEmitsTheInsetConstruction() {
        let output = svg([FacetCore.ShadowStyle(color: black, radius: 8, offsetY: 4, inset: true)])
        XCTAssertTrue(output.contains("<filter"))
        // Alpha inversion is what turns the outside into the caster.
        XCTAssertTrue(output.contains("tableValues=\"1 0\""))
        // And it must be clipped back inside the silhouette.
        XCTAssertTrue(output.contains("in2=\"SourceAlpha\" operator=\"in\""))
        XCTAssertFalse(output.contains("<feDropShadow"), "An inset shadow is not a drop shadow")
    }

    func testInnerShadowsGetDistinctPrimitiveNames() {
        let output = svg(ShadowPreset.pressed.shadows())
        XCTAssertTrue(output.contains("in0a"))
        XCTAssertTrue(output.contains("in1a"), "A second inset shadow must not reuse the first's result names")
    }

    // MARK: - Persistence

    /// The whole point of keeping the legacy singular key: documents that only
    /// ever had one plain shadow round-trip byte-identical.
    func testALoneOuterShadowRoundTripsThroughTheLegacyKey() throws {
        let doc = document([FacetCore.ShadowStyle(color: black, radius: 6, offsetY: 3)])
        let json = String(decoding: try FacetFile.encode(doc), as: UTF8.self)
        XCTAssertTrue(json.contains("\"shadow\""))
        XCTAssertFalse(json.contains("\"shadows\""))
        let decoded = try FacetFile.decode(try FacetFile.encode(doc))
        guard case .container(let root) = decoded.root.content else { return XCTFail("bad root") }
        XCTAssertEqual(root.children[0].style.shadows.count, 1)
    }

    func testAPairWritesTheListForm() throws {
        let doc = document(ShadowPreset.raised.shadows())
        let json = String(decoding: try FacetFile.encode(doc), as: UTF8.self)
        XCTAssertTrue(json.contains("\"shadows\""))
        let decoded = try FacetFile.decode(try FacetFile.encode(doc))
        guard case .container(let root) = decoded.root.content else { return XCTFail("bad root") }
        XCTAssertEqual(root.children[0].style.shadows, ShadowPreset.raised.shadows())
    }

    func testAnInsetShadowNeverUsesTheLegacyKey() throws {
        // An old build reading `shadow` would draw it outside — wrong enough
        // that the list form is mandatory as soon as anything is inset.
        let doc = document([FacetCore.ShadowStyle(color: black, radius: 6, inset: true)])
        let json = String(decoding: try FacetFile.encode(doc), as: UTF8.self)
        XCTAssertTrue(json.contains("\"shadows\""))
        XCTAssertFalse(json.contains("\"shadow\":"))
    }

    func testDocumentsWrittenBeforeTheListExistedStillDecode() throws {
        let legacy = """
        {"opacity":1,"rotation":0,"cornerRadius":0,
         "shadow":{"color":"#00000059","radius":6,"offsetX":0,"offsetY":3}}
        """
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(legacy.utf8))
        XCTAssertEqual(style.shadows.count, 1)
        XCTAssertEqual(style.shadows[0].radius, 6)
        XCTAssertFalse(style.shadows[0].inset)
    }

    func testTheSingularAccessorStillWorks() {
        var style = LayerStyle()
        XCTAssertNil(style.shadow)
        style.shadow = FacetCore.ShadowStyle(color: black, radius: 4)
        XCTAssertEqual(style.shadows.count, 1)
        style.shadow = nil
        XCTAssertTrue(style.shadows.isEmpty)
    }
}
