import XCTest
import FacetCore
import FacetData
import FacetTemplates
@testable import FacetRender

/// Text and symbols paint with a `Fill`, so they can carry gradients the way
/// shapes always could.
///
/// The promotion had to cost existing documents nothing. A solid paint still
/// serializes as the plain string a `ColorRef` wrote, under the same `color`
/// key, so no document needed migrating and the schema did not move; only a
/// gradient writes the new `fill` key. These tests pin that bargain, the
/// gradient geometry both backends have to agree on, and what happens on the
/// Lock Screen, where the system forces monochrome and a gradient cannot
/// survive.
final class GradientTextTests: XCTestCase {

    // MARK: - Fixtures

    private var ramp: GradientFill {
        GradientFill(
            stops: [
                GradientStop(position: 0, color: .literal(ColorValue(hex: "#FFD166")!)),
                GradientStop(position: 1, color: .literal(ColorValue(hex: "#EF476F")!)),
            ],
            angle: 90
        )
    }

    private func document(text: Fill, symbol: Fill? = nil) -> WidgetDocument {
        var children = [
            Layer(
                name: "Label",
                frame: LayerFrame(y: 0.3, width: 0.9, height: 0.4),
                content: .text(TextContent(
                    text: "22°",
                    font: .literal(FontToken(size: 32, weight: .heavy)),
                    fill: text
                ))
            )
        ]
        if let symbol {
            children.append(Layer(
                name: "Icon",
                frame: LayerFrame(y: 0.75, width: 0.4, height: 0.4),
                content: .symbol(SymbolContent(systemName: "cloud.sun.fill", fill: symbol, size: 36))
            ))
        }
        return WidgetDocument(
            name: "Gradient",
            tokens: ThemeTokens(colors: [
                "accent": ColorToken(light: ColorValue(hex: "#F5A623")!, dark: ColorValue(hex: "#FFC94D")!),
                "primary": ColorToken(light: .black, dark: .white),
            ]),
            root: Layer(name: "Canvas", content: .container(ContainerContent(children: children)))
        )
    }

    private func resolve(
        _ document: WidgetDocument,
        rendition: RenditionKind = .systemSmall,
        scheme: ColorScheme = .light
    ) -> ResolvedWidget {
        DocumentResolver.resolve(
            document: document,
            snapshots: SnapshotSet(),
            environment: RenderEnvironment(rendition: rendition, colorScheme: scheme)
        )
    }

    private func node(_ widget: ResolvedWidget, named name: String) -> RenderNode? {
        func search(_ node: RenderNode) -> RenderNode? {
            if node.name == name { return node }
            for child in node.children {
                if let found = search(child) { return found }
            }
            return nil
        }
        return search(widget.root)
    }

    private func textFill(_ widget: ResolvedWidget, named name: String = "Label") -> ResolvedFill? {
        guard case .text(let text)? = node(widget, named: name)?.kind else { return nil }
        return text.fill
    }

    private func symbolFill(_ widget: ResolvedWidget, named name: String = "Icon") -> ResolvedFill? {
        guard case .symbol(let symbol)? = node(widget, named: name)?.kind else { return nil }
        return symbol.fill
    }

    // MARK: - Resolution

    func testGradientTextResolvesToAGradient() {
        let widget = resolve(document(text: .linearGradient(ramp)))
        guard case .linearGradient(let stops, let angle)? = textFill(widget) else {
            return XCTFail("Expected a linear gradient on the text, got \(String(describing: textFill(widget)))")
        }
        XCTAssertEqual(angle, 90)
        XCTAssertEqual(stops.count, 2)
        XCTAssertEqual(stops[0].color, ColorValue(hex: "#FFD166")!)
        XCTAssertEqual(stops[1].color, ColorValue(hex: "#EF476F")!)
    }

    func testGradientSymbolResolvesToAGradient() {
        let widget = resolve(document(text: .token("primary"), symbol: .radialGradient(ramp)))
        guard case .radialGradient(let stops)? = symbolFill(widget) else {
            return XCTFail("Expected a radial gradient on the symbol")
        }
        XCTAssertEqual(stops.count, 2)
    }

    func testTextGradientStopsAreSorted() {
        // Both backends emit stops in order, so an out-of-order list would
        // render differently in each. The resolver is where that is settled —
        // exactly as it already was for shape fills.
        let reversed = GradientFill(stops: [
            GradientStop(position: 1, color: .literal(.black)),
            GradientStop(position: 0, color: .literal(.white)),
        ], angle: 45)
        guard case .linearGradient(let stops, _)? = textFill(resolve(document(text: .linearGradient(reversed)))) else {
            return XCTFail("Expected a linear gradient")
        }
        XCTAssertEqual(stops.map(\.position), [0, 1])
        XCTAssertEqual(stops[0].color, .white)
    }

    func testTextGradientStopsResolveTokensPerColorScheme() {
        // A gradient stop is a ColorRef, so a themed stop has to follow the
        // scheme the same way a solid label's colour does.
        let themed = GradientFill(stops: [
            GradientStop(position: 0, color: .token("accent")),
            GradientStop(position: 1, color: .token("primary")),
        ])
        let doc = document(text: .linearGradient(themed))
        guard case .linearGradient(let light, _)? = textFill(resolve(doc, scheme: .light)),
              case .linearGradient(let dark, _)? = textFill(resolve(doc, scheme: .dark)) else {
            return XCTFail("Expected linear gradients")
        }
        XCTAssertEqual(light[0].color, ColorValue(hex: "#F5A623")!)
        XCTAssertEqual(dark[0].color, ColorValue(hex: "#FFC94D")!)
        XCTAssertEqual(light[1].color, .black)
        XCTAssertEqual(dark[1].color, .white)
    }

    func testSolidTextStillResolvesThroughTokens() {
        let widget = resolve(document(text: .token("primary")), scheme: .dark)
        XCTAssertEqual(textFill(widget), .solid(.white))
    }

    // MARK: - Lock Screen accessories

    // The decision: on an accessory rendition a gradient *collapses* to the
    // vibrant monochrome colour rather than rendering. The Lock Screen tints
    // everything to its own material, so a gradient headline would be flattened
    // by the system anyway; collapsing in the resolver means both backends show
    // the same thing and neither silently renders a ramp the device will not
    // honour. Alpha survives from the first stop, the one lever an accessory
    // layer still has. This is the rule `resolveFill` already applied to shape
    // fills — text and symbols now share it instead of having their own.

    func testAccessoryCollapsesGradientTextToMonochrome() {
        for rendition in [RenditionKind.accessoryCircular, .accessoryRectangular, .accessoryInline] {
            let widget = resolve(document(text: .linearGradient(ramp)), rendition: rendition)
            XCTAssertEqual(textFill(widget), .solid(.white), "\(rendition.rawValue) must go monochrome")
        }
    }

    func testAccessoryCollapsesGradientSymbolToMonochrome() {
        let widget = resolve(
            document(text: .token("primary"), symbol: .radialGradient(ramp)),
            rendition: .accessoryCircular
        )
        XCTAssertEqual(symbolFill(widget), .solid(.white))
    }

    func testAccessoryKeepsTheFirstStopsAlpha() {
        let translucent = GradientFill(stops: [
            GradientStop(position: 0, color: .literal(ColorValue(hex: "#FFD16680")!)),
            GradientStop(position: 1, color: .literal(ColorValue(hex: "#EF476F")!)),
        ])
        let widget = resolve(document(text: .linearGradient(translucent)), rendition: .accessoryRectangular)
        guard case .solid(let color)? = textFill(widget) else {
            return XCTFail("Expected a collapsed solid")
        }
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 1)
        XCTAssertEqual(color.blue, 1)
        XCTAssertEqual(color.alpha, 128.0 / 255.0, accuracy: 0.001, "Alpha comes from the first stop")
    }

    func testAccessorySVGEmitsNoGradientForText() {
        let svg = SVGRenderer.render(resolve(document(text: .linearGradient(ramp)), rendition: .accessoryCircular))
        XCTAssertFalse(svg.contains("linearGradient"), "A collapsed gradient must not leave a definition behind")
        XCTAssertFalse(svg.contains("url(#grad"))
        XCTAssertTrue(svg.contains("fill=\"#FFFFFF\""))
    }

    // MARK: - Old documents

    /// A document written before text could hold a gradient: the paint is a
    /// bare string under `color`, on both the text and the symbol.
    private static let oldFormJSON = """
    {"schemaVersion": 2, "id": "A1B2C3D4-0000-4000-8000-000000000001", "name": "Old",
     "tokens": {"colors": {"primary": {"light": "#0A2540", "dark": "#EAF4FF"}}, "fonts": {}, "spacing": {}},
     "sources": [], "overrides": {},
     "root": {"id": "A1B2C3D4-0000-4000-8000-000000000002", "name": "Canvas", "type": "container",
              "container": {"layout": "absolute", "spacing": 0, "padding": 0, "children": [
                {"id": "A1B2C3D4-0000-4000-8000-000000000003", "name": "Label", "type": "text",
                 "text": {"text": "22°", "font": "display", "color": "token:primary", "alignment": "center"}},
                {"id": "A1B2C3D4-0000-4000-8000-000000000004", "name": "Icon", "type": "symbol",
                 "symbol": {"systemName": "star.fill", "color": "#FF5E3A", "size": 24, "weight": "regular"}}
              ]}}}
    """

    private func oldFormLayers() throws -> (text: TextContent, symbol: SymbolContent) {
        let document = try FacetFile.decode(Data(Self.oldFormJSON.utf8))
        guard case .container(let container) = document.root.content,
              case .text(let text) = container.children[0].content,
              case .symbol(let symbol) = container.children[1].content else {
            throw XCTSkip("Structure lost in decode")
        }
        return (text, symbol)
    }

    func testOldFormDocumentDecodesWithNoMigration() throws {
        let (text, symbol) = try oldFormLayers()
        XCTAssertEqual(text.fill, .color(.token("primary")))
        XCTAssertEqual(symbol.fill, .literal(ColorValue(hex: "#FF5E3A")!))
    }

    func testOldFormDocumentRendersAsItAlwaysDid() throws {
        let document = try FacetFile.decode(Data(Self.oldFormJSON.utf8))
        let widget = resolve(document, scheme: .light)
        XCTAssertEqual(textFill(widget), .solid(ColorValue(hex: "#0A2540")!))
        XCTAssertEqual(symbolFill(widget), .solid(ColorValue(hex: "#FF5E3A")!))

        let svg = SVGRenderer.render(widget)
        XCTAssertTrue(svg.contains("fill=\"#0A2540\""), "Solid text still paints a plain colour")
        XCTAssertFalse(svg.contains("url(#grad"), "and needs no gradient machinery")
    }

    func testOldFormDocumentReEncodesUnchanged() throws {
        let original = try FacetFile.decode(Data(Self.oldFormJSON.utf8))
        let json = try String(decoding: FacetFile.encode(original), as: UTF8.self)
        XCTAssertTrue(json.contains("\"color\" : \"token:primary\""), "Solid paint keeps the legacy key")
        XCTAssertTrue(json.contains("\"color\" : \"#FF5E3A\""))
        XCTAssertFalse(json.contains("\"fill\""), "and never grows a `fill` key it did not have")
        XCTAssertEqual(try FacetFile.decode(Data(json.utf8)), original)
    }

    func testSolidPaintRoundTripsUnderTheLegacyKeyForEveryTemplate() throws {
        // The starter templates are the committed corpus of solid-paint text.
        // If any of them started writing `fill`, every shipped `.facet` and
        // every preview SVG would churn.
        for document in StarterTemplates.all {
            let json = try String(decoding: FacetFile.encode(document), as: UTF8.self)
            XCTAssertFalse(json.contains("\"fill\" :"), "\(document.name) grew a fill key")
            XCTAssertEqual(try FacetFile.decode(Data(json.utf8)), document, document.name)
        }
    }

    func testGradientPaintWritesTheFillKeyAndRoundTrips() throws {
        let original = document(text: .linearGradient(ramp), symbol: .radialGradient(ramp))
        let data = try FacetFile.encode(original)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"fill\""), "A gradient is not a colour and does not pretend to be one")
        XCTAssertTrue(json.contains("linearGradient"))
        XCTAssertTrue(json.contains("radialGradient"))
        XCTAssertEqual(try FacetFile.decode(data), original)
    }

    func testFillKeyWinsWhenBothKeysArePresent() throws {
        // Belt and braces: a document hand-edited to carry both must not have
        // its gradient quietly overruled by a leftover colour.
        let json = """
        {"text": "hi", "font": "body", "alignment": "center", "color": "#00FF00",
         "fill": {"type": "linearGradient",
                  "gradient": {"angle": 90, "stops": [{"position": 0, "color": "#000000"},
                                                      {"position": 1, "color": "#FFFFFF"}]}}}
        """
        let text = try JSONDecoder().decode(TextContent.self, from: Data(json.utf8))
        guard case .linearGradient = text.fill else {
            return XCTFail("The gradient should win over the legacy colour key")
        }
    }

    func testTextWithNoPaintAtAllIsADecodeError() {
        let json = """
        {"text": "hi", "font": "body", "alignment": "center"}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(TextContent.self, from: Data(json.utf8)))
    }

    // MARK: - SVG emission

    /// The `url(#id)` a `fill` attribute points at, if it points at one.
    private func referencedGradientID(in element: String) -> String? {
        guard let range = element.range(of: "fill=\"url(#"),
              let end = element[range.upperBound...].firstIndex(of: ")") else { return nil }
        return String(element[range.upperBound..<end])
    }

    private func line(of svg: String, containing needle: String) -> String? {
        svg.split(separator: "\n").first { $0.contains(needle) }.map(String.init)
    }

    func testSVGTextReferencesAGradientThatActuallyExists() {
        let svg = SVGRenderer.render(resolve(document(text: .linearGradient(ramp))))
        guard let element = line(of: svg, containing: "<text"),
              let id = referencedGradientID(in: element) else {
            return XCTFail("Text should paint with a gradient reference:\n\(svg)")
        }
        // The reference and the definition are produced in different places;
        // a mismatch renders as invisible text rather than an error.
        XCTAssertTrue(
            svg.contains("<linearGradient id=\"\(id)\""),
            "Referenced \(id) but no such definition:\n\(svg)"
        )
        XCTAssertTrue(svg.contains("stop-color=\"#FFD166\""))
        XCTAssertTrue(svg.contains("stop-color=\"#EF476F\""))
    }

    func testSVGTextGradientSpansTheGlyphBoundingBox() {
        // Left in SVG's default `objectBoundingBox` units, so the ramp is
        // mapped onto the text element's own box. In user-space units it would
        // be anchored to the canvas and a short label would sample a slice of
        // it — a flat colour, which is the failure this guards.
        let svg = SVGRenderer.render(resolve(document(text: .linearGradient(ramp))))
        guard let definition = line(of: svg, containing: "<linearGradient") else {
            return XCTFail("No gradient definition")
        }
        XCTAssertFalse(definition.contains("gradientUnits"), "Default units are the text's bounding box")
        // 90° is straight down: the vector runs top-to-bottom of that box.
        XCTAssertTrue(definition.contains("x1=\"0.50\" y1=\"0\" x2=\"0.50\" y2=\"1\""), definition)
    }

    func testSVGRadialTextGradientEmitsARadialDefinition() {
        let svg = SVGRenderer.render(resolve(document(text: .radialGradient(ramp))))
        guard let element = line(of: svg, containing: "<text"),
              let id = referencedGradientID(in: element) else {
            return XCTFail("Text should paint with a gradient reference")
        }
        XCTAssertTrue(svg.contains("<radialGradient id=\"\(id)\""))
    }

    func testSVGSymbolPaintsTileAndLabelWithOneGradient() {
        let svg = SVGRenderer.render(resolve(document(text: .token("primary"), symbol: .linearGradient(ramp))))
        let elements = svg.split(separator: "\n").map(String.init).filter { $0.contains("fill=\"url(#") }
        XCTAssertEqual(elements.count, 2, "The placeholder tile and its label both take the paint")
        let ids = Set(elements.compactMap(referencedGradientID))
        XCTAssertEqual(ids.count, 1, "One definition serves both")
        XCTAssertTrue(svg.contains("<linearGradient id=\"\(ids.first!)\""))
    }

    func testSVGSolidTextEmitsAPlainColourNotAGradient() {
        let svg = SVGRenderer.render(resolve(document(text: .literal(ColorValue(hex: "#123456")!))))
        guard let element = line(of: svg, containing: "<text") else {
            return XCTFail("No text element")
        }
        XCTAssertTrue(element.contains("fill=\"#123456\""))
        XCTAssertNil(referencedGradientID(in: element))
        XCTAssertFalse(svg.contains("<linearGradient"), "No unused definitions")
    }

    func testSVGGivesTextAndShapeGradientsDistinctIDs() {
        // Both go through the same `defs` counter; colliding ids would make one
        // silently take the other's ramp.
        let root = Layer(name: "Canvas", content: .container(ContainerContent(children: [
            Layer(name: "Plate", content: .shape(ShapeContent(kind: .rectangle, fill: .linearGradient(ramp)))),
            Layer(name: "Label", content: .text(TextContent(
                text: "22°",
                font: .literal(FontToken(size: 20)),
                fill: .radialGradient(ramp)
            ))),
        ])))
        let svg = SVGRenderer.render(resolve(WidgetDocument(name: "Both", root: root)))
        let ids = svg.split(separator: "\n").map(String.init)
            .filter { $0.contains("fill=\"url(#") }
            .compactMap(referencedGradientID)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, 2, "Distinct ids: \(ids)")
        for id in ids {
            XCTAssertTrue(svg.contains("id=\"\(id)\""), "\(id) has no definition")
        }
    }
}
