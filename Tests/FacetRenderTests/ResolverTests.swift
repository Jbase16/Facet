import XCTest
import FacetCore
import FacetData
@testable import FacetRender

final class ResolverTests: XCTestCase {
    // MARK: - Fixtures

    private let percentLayer = Layer(
        name: "Percent",
        frame: LayerFrame(x: 0.5, y: 0.5, width: 0.8, height: 0.3),
        content: .text(TextContent(
            text: "{percent(battery.level)}",
            font: .token("display"),
            color: .token("accent")
        ))
    )
    private let ringLayer = Layer(
        name: "Ring",
        frame: LayerFrame(x: 0.5, y: 0.5, width: 0.9, height: 0.9),
        content: .gauge(GaugeContent(
            value: "battery.level",
            tint: .token("accent"),
            track: .literal(ColorValue(hex: "#44444480")!)
        ))
    )

    private func makeDocument(overrides: [RenditionKind: [LayerPatch]] = [:]) -> WidgetDocument {
        WidgetDocument(
            name: "Battery",
            tokens: ThemeTokens(
                colors: [
                    "accent": ColorToken(light: ColorValue(hex: "#34C759")!, dark: ColorValue(hex: "#30D158")!),
                    "background": ColorToken(light: .white, dark: .black),
                ],
                fonts: ["display": FontToken(size: 28, weight: .bold)]
            ),
            root: Layer(
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .overlay,
                    background: .token("background"),
                    children: [ringLayer, percentLayer]
                ))
            ),
            sources: ["battery"],
            overrides: overrides
        )
    }

    private var snapshots: SnapshotSet {
        var set = SnapshotSet()
        set.insert(DataSnapshot(sourceID: "battery", values: .object([
            "level": .number(0.82),
            "state": .string("charging"),
        ])))
        return set
    }

    private func resolve(
        _ document: WidgetDocument,
        rendition: RenditionKind = .systemSmall,
        scheme: ColorScheme = .light,
        snapshots: SnapshotSet? = nil
    ) -> ResolvedWidget {
        DocumentResolver.resolve(
            document: document,
            snapshots: snapshots ?? self.snapshots,
            environment: RenderEnvironment(rendition: rendition, colorScheme: scheme)
        )
    }

    private func findNode(_ root: RenderNode, named name: String) -> RenderNode? {
        if root.name == name { return root }
        for child in root.children {
            if let found = findNode(child, named: name) { return found }
        }
        return nil
    }

    // MARK: - Tests

    func testResolvesBindingsAndTokens() {
        let widget = resolve(makeDocument())
        XCTAssertTrue(widget.diagnostics.isEmpty)

        guard case .text(let text)? = findNode(widget.root, named: "Percent")?.kind else {
            return XCTFail("Percent layer missing")
        }
        XCTAssertEqual(text.text, "82%")
        XCTAssertEqual(text.color.hexString, "#34C759")
        XCTAssertEqual(text.font.size, 28)

        guard case .gauge(let gauge)? = findNode(widget.root, named: "Ring")?.kind else {
            return XCTFail("Ring layer missing")
        }
        XCTAssertEqual(gauge.fraction, 0.82, accuracy: 0.0001)
    }

    func testDarkModeSwitchesTokenColors() {
        let widget = resolve(makeDocument(), scheme: .dark)
        guard case .text(let text)? = findNode(widget.root, named: "Percent")?.kind else {
            return XCTFail("Percent layer missing")
        }
        XCTAssertEqual(text.color.hexString, "#30D158")
        guard case .group(let background) = widget.root.kind else {
            return XCTFail("Root should be a group")
        }
        XCTAssertEqual(background, .solid(.black))
    }

    func testLayoutGeometry() {
        let widget = resolve(makeDocument())
        XCTAssertEqual(widget.canvas.width, 158)
        let percent = findNode(widget.root, named: "Percent")!
        // 0.8 × 158 wide, centered.
        XCTAssertEqual(percent.rect.width, 126.4, accuracy: 0.01)
        XCTAssertEqual(percent.rect.midX, 79, accuracy: 0.01)
        XCTAssertEqual(percent.rect.midY, 79, accuracy: 0.01)
    }

    func testHiddenLayerIsSkipped() {
        var document = makeDocument()
        guard case .container(var container) = document.root.content else {
            return XCTFail("Root should be a container")
        }
        container.children[1].isHidden = true
        document.root.content = .container(container)
        let widget = resolve(document)
        XCTAssertNil(findNode(widget.root, named: "Percent"))
        XCTAssertNotNil(findNode(widget.root, named: "Ring"))
    }

    func testRenditionPatchHidesAndResizes() {
        let document = makeDocument(overrides: [
            .accessoryCircular: [
                LayerPatch(layerID: ringLayer.id, isHidden: true),
                LayerPatch(layerID: percentLayer.id, fontSize: 12),
            ],
        ])
        let widget = resolve(document, rendition: .accessoryCircular)
        XCTAssertNil(findNode(widget.root, named: "Ring"), "Patched hidden for this rendition")
        guard case .text(let text)? = findNode(widget.root, named: "Percent")?.kind else {
            return XCTFail("Percent layer missing")
        }
        XCTAssertEqual(text.font.size, 12)
        // Base document unaffected in other renditions.
        let home = resolve(document, rendition: .systemSmall)
        XCTAssertNotNil(findNode(home.root, named: "Ring"))
    }

    func testAccessoryRenditionsGoMonochrome() {
        let widget = resolve(makeDocument(), rendition: .accessoryCircular)
        guard case .text(let text)? = findNode(widget.root, named: "Percent")?.kind else {
            return XCTFail("Percent layer missing")
        }
        XCTAssertEqual(text.color.red, 1)
        XCTAssertEqual(text.color.green, 1)
        XCTAssertEqual(text.color.blue, 1)
    }

    func testBadExpressionDegradesWithDiagnostic() {
        let widget = resolve(makeDocument(), snapshots: SnapshotSet())
        XCTAssertEqual(widget.diagnostics.count, 2, "Text and gauge both reference battery data")
        guard case .text(let text)? = findNode(widget.root, named: "Percent")?.kind else {
            return XCTFail("Percent layer missing")
        }
        XCTAssertEqual(text.text, "⚠︎", "Broken binding degrades, widget still renders")
        guard case .gauge(let gauge)? = findNode(widget.root, named: "Ring")?.kind else {
            return XCTFail("Ring layer missing")
        }
        XCTAssertEqual(gauge.fraction, 0)
    }

    func testMissingTokenFallsBackToMagenta() {
        var document = makeDocument()
        document.tokens.colors.removeValue(forKey: "accent")
        let widget = resolve(document)
        guard case .text(let text)? = findNode(widget.root, named: "Percent")?.kind else {
            return XCTFail("Percent layer missing")
        }
        XCTAssertEqual(text.color.hexString, "#FF00FF")
    }

    func testGaugeFractionClamped() {
        var document = makeDocument()
        guard case .container(var container) = document.root.content else {
            return XCTFail("Root should be a container")
        }
        guard case .gauge(var gauge) = container.children[0].content else {
            return XCTFail("First child should be the gauge")
        }
        gauge.value = "battery.level * 10"
        container.children[0].content = .gauge(gauge)
        document.root.content = .container(container)

        let widget = resolve(document)
        guard case .gauge(let resolved)? = findNode(widget.root, named: "Ring")?.kind else {
            return XCTFail("Ring layer missing")
        }
        XCTAssertEqual(resolved.fraction, 1.0)
    }

    func testEnvironmentVariables() {
        var document = makeDocument()
        guard case .container(var container) = document.root.content else {
            return XCTFail("Root should be a container")
        }
        guard case .text(var text) = container.children[1].content else {
            return XCTFail("Second child should be the text layer")
        }
        text.text = "{env.dark ? 'night' : 'day'} on {env.rendition}"
        container.children[1].content = .text(text)
        document.root.content = .container(container)

        let widget = resolve(document, scheme: .dark)
        guard case .text(let resolved)? = findNode(widget.root, named: "Percent")?.kind else {
            return XCTFail("Percent layer missing")
        }
        XCTAssertEqual(resolved.text, "night on systemSmall")
    }

    func testStackLayoutDistributesChildren() {
        let left = Layer(
            name: "Left",
            frame: LayerFrame(width: 0.25, height: 0.5),
            content: .shape(ShapeContent(kind: .circle, fill: Fill.literal(.black)))
        )
        let right = Layer(
            name: "Right",
            frame: LayerFrame(width: 0.25, height: 0.5),
            content: .shape(ShapeContent(kind: .circle, fill: Fill.literal(.black)))
        )
        let document = WidgetDocument(
            name: "Stack",
            root: Layer(
                name: "Row",
                content: .container(ContainerContent(
                    layout: .horizontal,
                    spacing: 10,
                    padding: 8,
                    children: [left, right]
                ))
            )
        )
        let widget = resolve(document, rendition: .systemMedium)
        let leftNode = findNode(widget.root, named: "Left")!
        let rightNode = findNode(widget.root, named: "Right")!

        // Content width = 338 - 16 = 322; each child 0.25 × 322 = 80.5;
        // run = 80.5 + 10 + 80.5 = 171, centered in the content box.
        XCTAssertEqual(leftNode.rect.width, 80.5, accuracy: 0.01)
        XCTAssertEqual(leftNode.rect.x, 8 + (322 - 171) / 2, accuracy: 0.01)
        XCTAssertEqual(rightNode.rect.x, leftNode.rect.maxX + 10, accuracy: 0.01)
        XCTAssertEqual(leftNode.rect.midY, 79, accuracy: 0.01, "Centered on the cross axis")
    }
}
