import XCTest
import FacetCore
import FacetData
@testable import FacetRender

/// Layer masks: resolution into canvas coordinates, failure modes, and the
/// SVG backend's emitted structure.
final class MaskTests: XCTestCase {
    private func document(_ style: LayerStyle) -> WidgetDocument {
        WidgetDocument(
            name: "Masked",
            tokens: ThemeTokens(
                colors: ["background": ColorToken(light: .white, dark: .black),
                         "primary": ColorToken(light: .black, dark: .white)],
                fonts: ["body": FontToken(size: 14, weight: .medium)]
            ),
            root: Layer(
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("background"),
                    children: [
                        Layer(
                            name: "Photo",
                            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                            style: style,
                            content: .shape(ShapeContent(kind: .rectangle, fill: .token("primary")))
                        ),
                    ]
                ))
            ),
            sources: []
        )
    }

    private func resolve(_ style: LayerStyle) -> ResolvedWidget {
        DocumentResolver.resolve(
            document: document(style),
            snapshots: SnapshotSet(),
            environment: RenderEnvironment(rendition: .systemSmall, colorScheme: .light)
        )
    }

    private func maskedNode(_ style: LayerStyle) -> RenderNode? {
        resolve(style).root.children.first
    }

    // MARK: - Resolution

    func testNoMaskByDefault() {
        XCTAssertNil(maskedNode(.plain)?.mask)
    }

    func testMaskResolvesToTheLayerRectWhenItHasNoFrame() throws {
        let node = try XCTUnwrap(maskedNode(LayerStyle(mask: LayerMask(shape: .circle))))
        let mask = try XCTUnwrap(node.mask)
        XCTAssertEqual(mask.rect.x, node.rect.x, accuracy: 0.001)
        XCTAssertEqual(mask.rect.y, node.rect.y, accuracy: 0.001)
        XCTAssertEqual(mask.rect.width, node.rect.width, accuracy: 0.001)
        XCTAssertEqual(mask.rect.height, node.rect.height, accuracy: 0.001)
    }

    /// The mask frame is normalized against the layer, the same way a child
    /// layer's frame is — one mental model, not two.
    func testMaskFrameIsNormalizedAgainstTheLayerNotTheCanvas() throws {
        let mask = LayerMask(
            shape: .circle,
            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        )
        let node = try XCTUnwrap(maskedNode(LayerStyle(mask: mask)))
        let resolved = try XCTUnwrap(node.mask)
        XCTAssertEqual(resolved.rect.width, node.rect.width / 2, accuracy: 0.001)
        XCTAssertEqual(resolved.rect.midX, node.rect.midX, accuracy: 0.001)
        XCTAssertEqual(resolved.rect.midY, node.rect.midY, accuracy: 0.001)
    }

    func testANoOpMaskIsDroppedRatherThanResolved() {
        // A full-bleed square-cornered rectangle clips nothing. Carrying it
        // would cost a compositing group in SwiftUI and a <mask> in SVG for
        // no visual difference.
        XCTAssertNil(maskedNode(LayerStyle(mask: LayerMask(shape: .rectangle)))?.mask)
    }

    func testAnInvertedRectangleIsNotANoOp() {
        // Inverted, the same mask hides everything — very much not a no-op.
        XCTAssertNotNil(maskedNode(LayerStyle(mask: LayerMask(shape: .rectangle, invert: true)))?.mask)
    }

    func testRoundedRectangleAndFadeAreNotNoOps() {
        XCTAssertNotNil(maskedNode(LayerStyle(mask: LayerMask(cornerRadius: 12)))?.mask)
        XCTAssertNotNil(maskedNode(LayerStyle(mask: LayerMask(fade: .fadeOut())))?.mask)
    }

    // MARK: - Failing open

    func testAnUnparseablePathMaskIsDroppedWithADiagnostic() {
        let widget = resolve(LayerStyle(mask: LayerMask(shape: .path, pathData: "M ,, Z ###")))
        XCTAssertNil(widget.root.children.first?.mask, "A broken mask must not clip the layer away")
        XCTAssertEqual(widget.root.children.count, 1, "The layer itself must survive")
        XCTAssertTrue(widget.diagnostics.contains { $0.message.contains("mask path") })
    }

    func testAnEmptyPathMaskIsDroppedSilently() {
        // Nothing was authored yet — that is not an error worth reporting.
        let widget = resolve(LayerStyle(mask: LayerMask(shape: .path, pathData: "")))
        XCTAssertNil(widget.root.children.first?.mask)
        XCTAssertTrue(widget.diagnostics.isEmpty)
    }

    func testFadeStopsAreSortedAndClamped() throws {
        let fade = MaskFade(kind: .linear, angle: 90, stops: [
            MaskFade.Stop(position: 0.9, alpha: 4),
            MaskFade.Stop(position: 0.1, alpha: -2),
        ])
        let node = try XCTUnwrap(maskedNode(LayerStyle(mask: LayerMask(fade: fade))))
        let stops = try XCTUnwrap(node.mask?.fade?.stops)
        XCTAssertEqual(stops.map(\.position), [0.1, 0.9])
        XCTAssertEqual(stops.map(\.alpha), [0, 1])
    }

    func testANonFiniteCornerRadiusFallsBackInsteadOfPropagating() throws {
        let node = try XCTUnwrap(maskedNode(LayerStyle(mask: LayerMask(cornerRadius: .nan, fade: .fadeOut()))))
        XCTAssertEqual(node.mask?.cornerRadius, 0)
    }

    // MARK: - SVG output

    private func svg(_ style: LayerStyle) -> String {
        SVGRenderer.render(resolve(style))
    }

    func testSVGEmitsNoMaskMachineryWhenThereIsNoMask() {
        let output = svg(.plain)
        XCTAssertFalse(output.contains("<mask"))
        XCTAssertFalse(output.contains("mask=\"url("))
    }

    func testSVGWrapsMaskedContentInItsOwnGroup() {
        let output = svg(LayerStyle(mask: LayerMask(shape: .circle)))
        XCTAssertTrue(output.contains("<mask id=\"mask"))
        XCTAssertTrue(output.contains("maskUnits=\"userSpaceOnUse\""))
        XCTAssertTrue(output.contains("mask=\"url(#mask"))
        // White keeps: the circle is the window.
        XCTAssertTrue(output.contains("<circle"))
    }

    func testSVGInvertedMaskPaintsAWhiteFieldAndABlackHole() {
        let output = svg(LayerStyle(mask: LayerMask(shape: .circle, invert: true)))
        let maskBody = try? XCTUnwrap(output.range(of: "<mask id=").map { range in
            String(output[range.lowerBound...].prefix(400))
        })
        let body = maskBody ?? ""
        XCTAssertTrue(body.contains("fill=\"#fff\""), "Inverted masks need an opaque field to cut from")
        XCTAssertTrue(body.contains("fill=\"#000\""), "The shape is the hole")
    }

    func testSVGFadeBecomesAGradientOfWhiteStopOpacities() {
        let output = svg(LayerStyle(mask: LayerMask(fade: .fadeOut())))
        XCTAssertTrue(output.contains("<linearGradient id=\"mask0fade\""))
        XCTAssertTrue(output.contains("stop-color=\"#fff\""))
        XCTAssertTrue(output.contains("stop-opacity=\"1\""))
        XCTAssertTrue(output.contains("stop-opacity=\"0\""))
    }

    /// A circle mask is inscribed, not stretched. The SwiftUI backend draws
    /// `Circle()` for the same reason; an `Ellipse` would fill the rect and
    /// the two backends would cut different silhouettes on any non-square
    /// layer — which is exactly what a first cut of this got wrong.
    func testSVGCircleMaskIsInscribedRatherThanStretched() throws {
        // A deliberately wide, short mask so a circle and an ellipse differ.
        let mask = LayerMask(
            shape: .circle,
            frame: LayerFrame(x: 0.5, y: 0.5, width: 1.0, height: 0.4)
        )
        let node = try XCTUnwrap(maskedNode(LayerStyle(mask: mask)))
        let rect = try XCTUnwrap(node.mask).rect
        XCTAssertNotEqual(rect.width, rect.height, "The fixture must be non-square to be meaningful")

        let output = svg(LayerStyle(mask: mask))
        // Mirrors SVGRenderer.format: whole numbers print bare, others to 2dp.
        let radius = min(rect.width, rect.height) / 2
        let printed = radius == radius.rounded()
            ? String(Int64(radius))
            : String(format: "%.2f", radius)
        XCTAssertTrue(
            output.contains("r=\"\(printed)\""),
            "Expected an inscribed radius of \(printed) in:\n\(output)"
        )
    }

    func testSVGRadialFadeUsesARadialGradient() {
        let output = svg(LayerStyle(mask: LayerMask(fade: .vignette)))
        XCTAssertTrue(output.contains("<radialGradient id=\"mask0fade\""))
    }

    /// A mask ramp and a fill gradient at the same angle must point the same
    /// way, or "fade toward the same corner" would mean two different things
    /// depending on which control you reached for.
    func testMaskFadeAndFillGradientShareAnAngleConvention() {
        let fadeSVG = svg(LayerStyle(mask: LayerMask(fade: MaskFade(kind: .linear, angle: 0, stops: [
            MaskFade.Stop(position: 0, alpha: 1),
            MaskFade.Stop(position: 1, alpha: 0),
        ]))))

        // A horizontal fill gradient, rendered through the same code path.
        let gradientDoc = WidgetDocument(
            name: "Gradient",
            tokens: ThemeTokens(
                colors: ["a": ColorToken(light: .black, dark: .white)],
                fonts: [:]
            ),
            root: Layer(
                name: "Canvas",
                content: .shape(ShapeContent(
                    kind: .rectangle,
                    fill: .linearGradient(GradientFill(
                        stops: [GradientStop(position: 0, color: .token("a")),
                                GradientStop(position: 1, color: .token("a"))],
                        angle: 0
                    ))
                ))
            ),
            sources: []
        )
        let fillSVG = SVGRenderer.render(DocumentResolver.resolve(
            document: gradientDoc,
            snapshots: SnapshotSet(),
            environment: RenderEnvironment(rendition: .systemSmall, colorScheme: .light)
        ))

        func axis(_ svg: String) -> String? {
            guard let start = svg.range(of: "x1=\"") else { return nil }
            return String(svg[start.lowerBound...].prefix(60))
        }
        XCTAssertEqual(axis(fadeSVG), axis(fillSVG))
    }

    // MARK: - Persistence

    func testMaskRoundTrips() throws {
        let mask = LayerMask(
            shape: .path,
            pathData: "M0,0 L1,0 L1,1 Z",
            cornerRadius: 8,
            frame: LayerFrame(x: 0.4, y: 0.6, width: 0.5, height: 0.7),
            fade: .vignette,
            invert: true
        )
        let decoded = try FacetFile.decode(try FacetFile.encode(document(LayerStyle(mask: mask))))
        guard case .container(let root) = decoded.root.content else {
            return XCTFail("Expected a container root")
        }
        XCTAssertEqual(root.children[0].style.mask, mask)
    }

    func testDocumentsWithoutMasksStayFreeOfMaskKeys() throws {
        let data = try FacetFile.encode(document(.plain))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"mask\""))
    }

    func testMaskDefaultsFillInForPartialJSON() throws {
        // Everything but the shape is optional, so a hand-written or
        // older-format mask still decodes.
        let json = #"{"shape":"circle"}"#
        let mask = try JSONDecoder().decode(LayerMask.self, from: Data(json.utf8))
        XCTAssertEqual(mask.shape, .circle)
        XCTAssertNil(mask.frame)
        XCTAssertNil(mask.fade)
        XCTAssertFalse(mask.invert)
        XCTAssertEqual(mask.cornerRadius, 0)
    }
}
