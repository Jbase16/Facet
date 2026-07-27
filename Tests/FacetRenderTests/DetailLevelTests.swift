import XCTest
import FacetCore
import FacetData
@testable import FacetRender

/// `LevelOfDetail` support: layers opting out of the reduced rendering the
/// system asks for (iOS 26+), and the stack-layout gap that dropping a layer
/// used to leave behind.
final class DetailLevelTests: XCTestCase {
    private var snapshots: SnapshotSet {
        var set = SnapshotSet()
        set.insert(DataSnapshot(sourceID: "battery", values: .object([
            "level": .number(0.82),
            "state": .string("charging"),
        ])))
        return set
    }

    private func label(
        _ name: String,
        hiddenWhenSimplified: Bool = false,
        visibleWhen: String? = nil
    ) -> Layer {
        Layer(
            name: name,
            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.3, height: 0.3),
            visibleWhen: visibleWhen,
            hiddenWhenSimplified: hiddenWhenSimplified,
            content: .text(TextContent(text: name, font: .token("body"), color: .token("primary")))
        )
    }

    private func document(layout: ContainerLayout, _ children: [Layer]) -> WidgetDocument {
        WidgetDocument(
            name: "Detail",
            tokens: ThemeTokens(
                colors: ["background": ColorToken(light: .white, dark: .black),
                         "primary": ColorToken(light: .black, dark: .white)],
                fonts: ["body": FontToken(size: 14, weight: .medium)]
            ),
            root: Layer(
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: layout,
                    background: .token("background"),
                    children: children
                ))
            ),
            sources: ["battery"]
        )
    }

    private func resolve(_ document: WidgetDocument, detail: DetailLevel) -> ResolvedWidget {
        DocumentResolver.resolve(
            document: document,
            snapshots: snapshots,
            environment: RenderEnvironment(
                rendition: .systemSmall,
                colorScheme: .light,
                detail: detail
            )
        )
    }

    // MARK: - Opting out

    func testFullDetailKeepsEveryLayer() {
        let doc = document(layout: .overlay, [
            label("Reading"),
            label("Ornament", hiddenWhenSimplified: true),
        ])
        XCTAssertEqual(resolve(doc, detail: .full).root.children.count, 2)
    }

    func testSimplifiedDropsOnlyTheOptedOutLayer() {
        let doc = document(layout: .overlay, [
            label("Reading"),
            label("Ornament", hiddenWhenSimplified: true),
        ])
        let widget = resolve(doc, detail: .simplified)
        XCTAssertEqual(widget.root.children.count, 1)
        XCTAssertEqual(widget.root.children.first?.name, "Reading")
    }

    func testNothingIsDroppedWithoutAnExplicitOptOut() {
        // The default must be "render exactly as before" — only the author
        // knows which layers are decoration, so we never guess.
        let doc = document(layout: .overlay, [label("A"), label("B"), label("C")])
        XCTAssertEqual(resolve(doc, detail: .simplified).root.children.count, 3)
    }

    func testOptedOutContainerTakesItsSubtreeWithIt() {
        let group = Layer(
            name: "Group",
            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.9, height: 0.5),
            hiddenWhenSimplified: true,
            content: .container(ContainerContent(
                layout: .overlay,
                children: [label("Inner1"), label("Inner2")]
            ))
        )
        let doc = document(layout: .overlay, [label("Keep"), group])
        let widget = resolve(doc, detail: .simplified)
        XCTAssertEqual(widget.root.children.count, 1)
        XCTAssertEqual(widget.root.children.first?.name, "Keep")
    }

    // MARK: - Stack layout closes the gap

    /// A dropped layer must not leave a hole. The stack sizes its cells from a
    /// pre-pass, and when that pre-pass disagreed with the resolver the space
    /// stayed reserved for a layer that was never drawn.
    func testSimplifiedStackClosesUpInsteadOfLeavingAGap() {
        let three = document(layout: .horizontal, [label("A"), label("B"), label("C")])
        let withOptOut = document(layout: .horizontal, [
            label("A"), label("B", hiddenWhenSimplified: true), label("C"),
        ])

        let twoRemaining = resolve(withOptOut, detail: .simplified)
        XCTAssertEqual(twoRemaining.root.children.count, 2)

        // The two survivors must sit where two children sit, not where the
        // first and third of three would.
        let reference = resolve(document(layout: .horizontal, [label("A"), label("C")]), detail: .full)
        XCTAssertEqual(reference.root.children.count, 2)
        for (actual, expected) in zip(twoRemaining.root.children, reference.root.children) {
            XCTAssertEqual(actual.rect.x, expected.rect.x, accuracy: 0.001)
            XCTAssertEqual(actual.rect.width, expected.rect.width, accuracy: 0.001)
        }

        // And they must not match the three-child layout they came from.
        let threeResolved = resolve(three, detail: .full)
        XCTAssertNotEqual(twoRemaining.root.children[0].rect.x, threeResolved.root.children[0].rect.x)
    }

    /// The same gap existed for `visibleWhen` long before simplified rendering,
    /// since both go through the stack's pre-pass.
    func testVisibleWhenFalseAlsoClosesTheStackGap() {
        let gated = document(layout: .horizontal, [
            label("A"),
            label("B", visibleWhen: "battery.level < 0.2"),
            label("C"),
        ])
        let resolved = resolve(gated, detail: .full)
        XCTAssertEqual(resolved.root.children.count, 2)

        let reference = resolve(document(layout: .horizontal, [label("A"), label("C")]), detail: .full)
        for (actual, expected) in zip(resolved.root.children, reference.root.children) {
            XCTAssertEqual(actual.rect.x, expected.rect.x, accuracy: 0.001)
        }
    }

    func testVerticalStacksCloseTheGapToo() {
        let gated = document(layout: .vertical, [
            label("A"), label("B", hiddenWhenSimplified: true), label("C"),
        ])
        let resolved = resolve(gated, detail: .simplified)
        let reference = resolve(document(layout: .vertical, [label("A"), label("C")]), detail: .full)
        XCTAssertEqual(resolved.root.children.count, 2)
        for (actual, expected) in zip(resolved.root.children, reference.root.children) {
            XCTAssertEqual(actual.rect.y, expected.rect.y, accuracy: 0.001)
            XCTAssertEqual(actual.rect.height, expected.rect.height, accuracy: 0.001)
        }
    }

    /// A broken condition must still fail open in the pre-pass, or a typo
    /// would silently steal a layer's slot instead of just its diagnostic.
    func testBrokenConditionKeepsItsSlotInAStack() {
        let doc = document(layout: .horizontal, [
            label("A"), label("B", visibleWhen: "nonsense >"), label("C"),
        ])
        let resolved = resolve(doc, detail: .full)
        XCTAssertEqual(resolved.root.children.count, 3)
        XCTAssertFalse(resolved.diagnostics.isEmpty)
    }

    // MARK: - Expression variables

    func testDetailIsReadableFromExpressions() {
        let doc = document(layout: .overlay, [
            label("OnlySimple", visibleWhen: "env.simplified"),
            label("OnlyFull", visibleWhen: "!env.simplified"),
        ])
        let simple = resolve(doc, detail: .simplified)
        XCTAssertEqual(simple.root.children.count, 1)
        XCTAssertEqual(simple.root.children.first?.name, "OnlySimple")

        let full = resolve(doc, detail: .full)
        XCTAssertEqual(full.root.children.count, 1)
        XCTAssertEqual(full.root.children.first?.name, "OnlyFull")
    }

    // MARK: - Persistence

    func testFlagSurvivesARoundTrip() throws {
        let doc = document(layout: .overlay, [label("Ornament", hiddenWhenSimplified: true)])
        let decoded = try FacetFile.decode(try FacetFile.encode(doc))
        guard case .container(let root) = decoded.root.content else {
            return XCTFail("Expected a container root")
        }
        XCTAssertTrue(root.children[0].hiddenWhenSimplified)
    }

    func testDocumentsWrittenBeforeTheFlagExistedStillDecode() throws {
        // Absent means false, and absent must stay absent on the way back out
        // so an untouched document round-trips byte-identical.
        let doc = document(layout: .overlay, [label("Plain")])
        let data = try FacetFile.encode(doc)
        XCTAssertFalse(
            String(decoding: data, as: UTF8.self).contains("hiddenWhenSimplified"),
            "An unset flag must not be written"
        )
        let decoded = try FacetFile.decode(data)
        guard case .container(let root) = decoded.root.content else {
            return XCTFail("Expected a container root")
        }
        XCTAssertFalse(root.children[0].hiddenWhenSimplified)
    }
}
