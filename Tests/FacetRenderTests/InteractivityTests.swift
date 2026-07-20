import XCTest
import FacetCore
import FacetData
@testable import FacetRender

/// visibleWhen expression gating and tapAction URL resolution.
final class InteractivityTests: XCTestCase {
    private func makeDocument(_ layer: Layer) -> WidgetDocument {
        WidgetDocument(
            name: "Interactive",
            tokens: ThemeTokens(
                colors: ["background": ColorToken(light: .white, dark: .black),
                         "primary": ColorToken(light: .black, dark: .white)],
                fonts: ["body": FontToken(size: 14, weight: .medium)]
            ),
            root: Layer(
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .overlay,
                    background: .token("background"),
                    children: [layer]
                ))
            ),
            sources: ["battery"]
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

    private func resolve(_ document: WidgetDocument) -> ResolvedWidget {
        DocumentResolver.resolve(
            document: document,
            snapshots: snapshots,
            environment: RenderEnvironment(rendition: .systemSmall, colorScheme: .light)
        )
    }

    private func textLayer(visibleWhen: String? = nil, tapAction: TapAction? = nil) -> Layer {
        Layer(
            name: "Label",
            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.8, height: 0.3),
            visibleWhen: visibleWhen,
            tapAction: tapAction,
            content: .text(TextContent(text: "hi", font: .token("body"), color: .token("primary")))
        )
    }

    func testVisibleWhenTrueKeepsLayer() {
        let widget = resolve(makeDocument(textLayer(visibleWhen: "battery.level > 0.5")))
        XCTAssertEqual(widget.root.children.count, 1)
        XCTAssertTrue(widget.diagnostics.isEmpty)
    }

    func testVisibleWhenFalsePrunesLayer() {
        let widget = resolve(makeDocument(textLayer(visibleWhen: "battery.level < 0.2")))
        XCTAssertTrue(widget.root.children.isEmpty)
        XCTAssertTrue(widget.diagnostics.isEmpty)
    }

    func testVisibleWhenErrorFailsOpenWithDiagnostic() {
        let widget = resolve(makeDocument(textLayer(visibleWhen: "nonsense.path >")))
        XCTAssertEqual(widget.root.children.count, 1, "Broken conditions must not blank the widget")
        XCTAssertEqual(widget.diagnostics.count, 1)
        XCTAssertTrue(widget.diagnostics[0].message.contains("visibleWhen"))
    }

    func testVisibleWhenComparesStrings() {
        let visible = resolve(makeDocument(textLayer(visibleWhen: "battery.state == \"charging\"")))
        XCTAssertEqual(visible.root.children.count, 1)
        let pruned = resolve(makeDocument(textLayer(visibleWhen: "battery.state == \"full\"")))
        XCTAssertTrue(pruned.root.children.isEmpty)
    }

    func testTapURLResolvesTemplates() {
        let widget = resolve(makeDocument(textLayer(
            tapAction: TapAction(urlTemplate: "myapp://battery/{percent(battery.level)}")
        )))
        XCTAssertEqual(widget.root.children.first?.tapURL, "myapp://battery/82%")
    }

    func testTapURLErrorReportsDiagnosticAndOmitsURL() {
        let widget = resolve(makeDocument(textLayer(
            tapAction: TapAction(urlTemplate: "myapp://{unclosed")
        )))
        XCTAssertNil(widget.root.children.first?.tapURL)
        XCTAssertEqual(widget.diagnostics.count, 1)
        XCTAssertTrue(widget.diagnostics[0].message.contains("tapAction"))
    }

    func testLayersWithoutInteractivityHaveNoTapURL() {
        let widget = resolve(makeDocument(textLayer()))
        XCTAssertNil(widget.root.children.first?.tapURL)
    }
}
