import XCTest
import FacetCore
import FacetData
@testable import FacetRender

final class SchemaV2Tests: XCTestCase {
    private var snapshots: SnapshotSet {
        var set = SnapshotSet()
        set.insert(DataSnapshot(sourceID: "weather", values: .object([
            "hourly": .list([10, 20, 15, 30].map(SnapshotValue.number)),
            "flat": .list([5, 5, 5].map(SnapshotValue.number)),
        ])))
        return set
    }

    private func resolve(_ root: Layer, snapshots: SnapshotSet? = nil, scheme: ColorScheme = .light) -> ResolvedWidget {
        DocumentResolver.resolve(
            document: WidgetDocument(name: "T", root: root),
            snapshots: snapshots ?? self.snapshots,
            environment: RenderEnvironment(rendition: .systemSmall, colorScheme: scheme)
        )
    }

    // MARK: - Fills

    func testSolidFillDecodesFromV1StringForm() throws {
        let json = "\"#FF0000\""
        let fill = try JSONDecoder().decode(Fill.self, from: Data(json.utf8))
        XCTAssertEqual(fill, .color(.literal(ColorValue(hex: "#FF0000")!)))

        let token = try JSONDecoder().decode(Fill.self, from: Data("\"token:accent\"".utf8))
        XCTAssertEqual(token, .color(.token("accent")))
    }

    func testGradientFillRoundTrips() throws {
        let fill = Fill.linearGradient(GradientFill(
            stops: [
                GradientStop(position: 0, color: .literal(ColorValue(hex: "#FF5E3A")!)),
                GradientStop(position: 1, color: .literal(ColorValue(hex: "#2A0845")!)),
            ],
            angle: 135
        ))
        let data = try JSONEncoder().encode(fill)
        XCTAssertEqual(try JSONDecoder().decode(Fill.self, from: data), fill)
    }

    func testV1DocumentDecodesUnderV2() throws {
        // A v1-era document: string fills, no alignment/letterSpacing keys.
        let json = """
        {"schemaVersion": 1, "id": "6E4460D5-0F91-4C7C-8E7B-9A2749748C6C", "name": "Old",
         "root": {"id": "6E4460D5-0F91-4C7C-8E7B-9A2749748C6D", "name": "Canvas",
                  "type": "container",
                  "container": {"layout": "overlay", "spacing": 0, "padding": 0,
                                "background": "token:bg",
                                "children": [
                                  {"id": "6E4460D5-0F91-4C7C-8E7B-9A2749748C6E", "name": "S",
                                   "type": "shape",
                                   "shape": {"kind": "circle", "fill": "#112233", "strokeWidth": 0}}
                                ]}}}
        """
        let document = try FacetFile.decode(Data(json.utf8))
        guard case .container(let container) = document.root.content,
              case .shape(let shape) = container.children[0].content else {
            return XCTFail("Structure lost in decode")
        }
        XCTAssertEqual(container.background, .token("bg"))
        XCTAssertEqual(shape.fill, Fill.literal(ColorValue(hex: "#112233")!))
    }

    func testGradientResolvesAndSortsStops() {
        let root = Layer(name: "Canvas", content: .container(ContainerContent(
            background: .linearGradient(GradientFill(stops: [
                GradientStop(position: 1, color: .literal(.black)),
                GradientStop(position: 0, color: .literal(.white)),
            ], angle: 90))
        )))
        let widget = resolve(root)
        guard case .group(.linearGradient(let stops, let angle)?) = widget.root.kind else {
            return XCTFail("Expected linear gradient background")
        }
        XCTAssertEqual(angle, 90)
        XCTAssertEqual(stops.map(\.position), [0, 1], "Stops sorted by position")
        XCTAssertEqual(stops[0].color, .white)
    }

    func testAccessoryCollapsesGradientToMonochrome() {
        let root = Layer(name: "Canvas", content: .container(ContainerContent(
            background: .radialGradient(GradientFill(stops: [
                GradientStop(position: 0, color: .literal(ColorValue(hex: "#FF0000")!)),
            ]))
        )))
        let widget = DocumentResolver.resolve(
            document: WidgetDocument(name: "T", root: root),
            snapshots: SnapshotSet(),
            environment: RenderEnvironment(rendition: .accessoryCircular)
        )
        guard case .group(.solid(let color)?) = widget.root.kind else {
            return XCTFail("Expected solid monochrome background")
        }
        XCTAssertEqual(color.red, 1)
        XCTAssertEqual(color.green, 1)
        XCTAssertEqual(color.blue, 1)
    }

    // MARK: - Charts

    func testChartNormalizesValues() {
        let root = Layer(name: "Chart", content: .chart(ChartContent(
            dataPath: "weather.hourly", color: .literal(.black)
        )))
        let widget = resolve(root)
        guard case .chart(let chart) = widget.root.kind else {
            return XCTFail("Expected chart node")
        }
        XCTAssertEqual(chart.normalized, [0, 0.5, 0.25, 1])
        XCTAssertTrue(widget.diagnostics.isEmpty)
    }

    func testChartFlatSeriesCentersAndMissingPathDegrades() {
        let flat = resolve(Layer(name: "Flat", content: .chart(ChartContent(
            dataPath: "weather.flat", color: .literal(.black)
        ))))
        guard case .chart(let flatChart) = flat.root.kind else { return XCTFail("Expected chart") }
        XCTAssertEqual(flatChart.normalized, [0.5, 0.5, 0.5])

        let missing = resolve(Layer(name: "Missing", content: .chart(ChartContent(
            dataPath: "nope.nothing", color: .literal(.black)
        ))))
        guard case .chart(let missingChart) = missing.root.kind else { return XCTFail("Expected chart") }
        XCTAssertTrue(missingChart.normalized.isEmpty)
        XCTAssertEqual(missing.diagnostics.count, 1)
    }

    func testSnapshotSetNumberList() {
        XCTAssertEqual(snapshots.numberList(forVariable: "weather.hourly"), [10, 20, 15, 30])
        XCTAssertNil(snapshots.numberList(forVariable: "weather.missing"))
        XCTAssertNil(snapshots.numberList(forVariable: "weather"), "Object is not a list")
    }

    // MARK: - Text & layout

    func testTextCaseAndLetterSpacing() {
        let root = Layer(name: "Label", content: .text(TextContent(
            text: "hello",
            font: .literal(FontToken(size: 12)),
            color: .literal(.black),
            letterSpacing: 3,
            textCase: .uppercase
        )))
        let widget = resolve(root)
        guard case .text(let text) = widget.root.kind else { return XCTFail("Expected text") }
        XCTAssertEqual(text.text, "HELLO")
        XCTAssertEqual(text.letterSpacing, 3)
    }

    func testStackAlignmentStart() {
        let child = Layer(
            name: "Chip",
            frame: LayerFrame(width: 0.5, height: 0.25),
            content: .shape(ShapeContent(kind: .rectangle, fill: Fill.literal(.black)))
        )
        let root = Layer(name: "Row", content: .container(ContainerContent(
            layout: .horizontal, alignment: .start, children: [child]
        )))
        let widget = resolve(root)
        let node = widget.root.children[0]
        XCTAssertEqual(node.rect.y, 0, accuracy: 0.001, "start-aligned child sits at the top")
    }

    // MARK: - SVG

    func testSVGEmitsGradientDefsLineAndChart() {
        let root = Layer(name: "Canvas", content: .container(ContainerContent(
            layout: .absolute,
            background: .linearGradient(GradientFill(stops: [
                GradientStop(position: 0, color: .literal(ColorValue(hex: "#FF5E3A")!)),
                GradientStop(position: 1, color: .literal(ColorValue(hex: "#2A0845")!)),
            ], angle: 90)),
            children: [
                Layer(name: "Divider", frame: LayerFrame(y: 0.3, height: 0.02),
                      content: .line(LineContent(color: .literal(.white), thickness: 2, dash: [4, 3]))),
                Layer(name: "Spark", frame: LayerFrame(y: 0.7, width: 0.8, height: 0.3),
                      content: .chart(ChartContent(dataPath: "weather.hourly", style: .area, color: .literal(.white)))),
            ]
        )))
        let svg = SVGRenderer.render(resolve(root))
        XCTAssertTrue(svg.contains("<linearGradient id=\"grad0\""))
        XCTAssertTrue(svg.contains("fill=\"url(#grad0)\""))
        XCTAssertTrue(svg.contains("stop-color=\"#FF5E3A\""))
        XCTAssertTrue(svg.contains("stroke-dasharray=\"4 3\""))
        XCTAssertTrue(svg.contains("<polyline"))
        XCTAssertTrue(svg.contains("<polygon"), "Area charts fill under the line")
    }

    // MARK: - Expressions

    func testNewBuiltins() throws {
        let context = EmptyContext()
        XCTAssertEqual(try Evaluator.evaluate("lerp(0, 10, 0.25)", context: context), .number(2.5))
        XCTAssertEqual(try Evaluator.evaluate("sign(-4)", context: context), .number(-1))
        XCTAssertEqual(try Evaluator.evaluate("substr('facet', 1, 3)", context: context), .string("ace"))
        XCTAssertEqual(try Evaluator.evaluate("startsWith('charging', 'ch')", context: context), .bool(true))
        XCTAssertEqual(try Evaluator.evaluate("endsWith('charging', 'ing')", context: context), .bool(true))
    }
}
