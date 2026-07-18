import XCTest
import FacetCore
import FacetData
@testable import FacetRender

final class SVGRendererTests: XCTestCase {
    private func resolveSample() -> ResolvedWidget {
        let document = WidgetDocument(
            name: "Sample",
            tokens: ThemeTokens(colors: ["bg": ColorToken(light: .white, dark: .black)]),
            root: Layer(
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .overlay,
                    background: .token("bg"),
                    children: [
                        Layer(
                            name: "Ring",
                            frame: LayerFrame(width: 0.8, height: 0.8),
                            content: .gauge(GaugeContent(
                                value: "0.75",
                                tint: .literal(ColorValue(hex: "#34C759")!),
                                track: .literal(ColorValue(hex: "#44444480")!)
                            ))
                        ),
                        Layer(
                            name: "Label",
                            frame: LayerFrame(width: 0.8, height: 0.3),
                            content: .text(TextContent(
                                text: "75% <charged & \"ready\">",
                                font: .literal(FontToken(size: 20, weight: .semibold)),
                                color: .literal(.black)
                            ))
                        ),
                    ]
                ))
            )
        )
        return DocumentResolver.resolve(
            document: document,
            snapshots: SnapshotSet(),
            environment: RenderEnvironment(rendition: .systemSmall)
        )
    }

    func testProducesWellFormedSVG() {
        let svg = SVGRenderer.render(resolveSample())
        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertTrue(svg.hasSuffix("</svg>"))
        XCTAssertTrue(svg.contains("width=\"158\""))
        XCTAssertTrue(svg.contains("clip-path=\"url(#canvas)\""))
        // Balanced groups.
        XCTAssertEqual(
            svg.components(separatedBy: "<g").count,
            svg.components(separatedBy: "</g>").count
        )
    }

    func testRendersGaugeAsStrokedCircles() {
        let svg = SVGRenderer.render(resolveSample())
        XCTAssertTrue(svg.contains("stroke=\"#34C759\""), "Tint arc present")
        XCTAssertTrue(svg.contains("stroke-dasharray"), "Progress arc uses dash technique")
        XCTAssertTrue(svg.contains("rotate(-90"), "Arc starts at 12 o'clock")
    }

    func testEscapesTextContent() {
        let svg = SVGRenderer.render(resolveSample())
        XCTAssertTrue(svg.contains("75% &lt;charged &amp; &quot;ready&quot;&gt;"))
        XCTAssertFalse(svg.contains("<charged"))
    }

    func testDarkSchemeChangesBackground() {
        let document = WidgetDocument(
            name: "BG",
            tokens: ThemeTokens(colors: ["bg": ColorToken(light: .white, dark: .black)]),
            root: Layer(name: "Canvas", content: .container(ContainerContent(background: .token("bg"))))
        )
        let dark = DocumentResolver.resolve(
            document: document,
            snapshots: SnapshotSet(),
            environment: RenderEnvironment(rendition: .systemSmall, colorScheme: .dark)
        )
        XCTAssertTrue(SVGRenderer.render(dark).contains("fill=\"#000000\""))
    }
}
