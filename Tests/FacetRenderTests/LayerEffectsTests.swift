import XCTest
import FacetCore
import FacetData
@testable import FacetRender

/// Per-layer visual effects: schema compatibility, resolver clamping, and
/// what each backend emits. The bar these guard is "adding effects costs
/// existing documents nothing" — neither bytes on disk nor SVG output.
final class LayerEffectsTests: XCTestCase {
    private func resolve(_ root: Layer) -> ResolvedWidget {
        DocumentResolver.resolve(
            document: WidgetDocument(name: "T", root: root),
            snapshots: SnapshotSet(),
            environment: RenderEnvironment(rendition: .systemSmall)
        )
    }

    private func node(style: LayerStyle) -> RenderNode {
        resolve(Layer(
            name: "L",
            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            style: style,
            content: .shape(ShapeContent(kind: .rectangle, fill: Fill.literal(.black)))
        )).root
    }

    private let everyEffect = LayerStyle(
        opacity: 0.9,
        rotation: 12,
        cornerRadius: 8,
        shadow: ShadowStyle(color: .literal(.black), radius: 4, offsetX: 1, offsetY: 2),
        blendMode: .softLight,
        blur: 3,
        border: BorderStyle(color: .literal(ColorValue(hex: "#FF0000")!), width: 2, inset: 1),
        scale: 1.5,
        flipHorizontal: true,
        flipVertical: true,
        brightness: 0.2,
        contrast: 1.4,
        saturation: 0.5,
        hueRotation: 45,
        glow: GlowStyle(color: .literal(ColorValue(hex: "#00FFFF")!), radius: 10)
    )

    // MARK: - Schema compatibility

    func testPlainStyleEncodesOnlyTheHistoricalKeys() throws {
        let document = WidgetDocument(
            name: "Plain",
            root: Layer(name: "L", content: .shape(ShapeContent(kind: .circle, fill: Fill.literal(.black))))
        )
        let json = String(decoding: try FacetFile.encode(document), as: UTF8.self)
        for key in [
            "blendMode", "blur", "border", "scale", "flipHorizontal", "flipVertical",
            "brightness", "contrast", "saturation", "hueRotation", "glow",
        ] {
            XCTAssertFalse(json.contains("\"\(key)\""), "Unset effect '\(key)' must not be written")
        }
        XCTAssertTrue(json.contains("\"opacity\""))
        XCTAssertTrue(json.contains("\"rotation\""))
        XCTAssertTrue(json.contains("\"cornerRadius\""))
    }

    func testV1StyleDecodesAndReEncodesUnchanged() throws {
        let json = """
        {"opacity": 0.5, "rotation": 90, "cornerRadius": 4}
        """
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(json.utf8))
        XCTAssertEqual(style.opacity, 0.5)
        XCTAssertEqual(style.rotation, 90)
        XCTAssertEqual(style.cornerRadius, 4)
        XCTAssertNil(style.blendMode)
        XCTAssertNil(style.blur)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let round = String(decoding: try encoder.encode(style), as: UTF8.self)
        XCTAssertEqual(round, "{\"cornerRadius\":4,\"opacity\":0.5,\"rotation\":90}")
    }

    func testEmptyStyleObjectDecodesToPlain() throws {
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data("{}".utf8))
        XCTAssertEqual(style, .plain)
    }

    func testEveryEffectSurvivesADocumentRoundTrip() throws {
        let document = WidgetDocument(
            name: "Effects",
            root: Layer(name: "L", style: everyEffect, content: .text(TextContent(
                text: "hi", font: .literal(FontToken(size: 10)), color: .literal(.black)
            )))
        )
        let decoded = try FacetFile.decode(try FacetFile.encode(document))
        XCTAssertEqual(decoded.root.style, everyEffect)
        XCTAssertEqual(decoded, document)
    }

    func testBorderInsetIsOmittedWhenZero() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let flush = BorderStyle(color: .literal(.black), width: 2)
        XCTAssertFalse(String(decoding: try encoder.encode(flush), as: UTF8.self).contains("inset"))

        let inset = BorderStyle(color: .literal(.black), width: 2, inset: 3)
        let json = try encoder.encode(inset)
        XCTAssertTrue(String(decoding: json, as: UTF8.self).contains("\"inset\":3"))
        XCTAssertEqual(try JSONDecoder().decode(BorderStyle.self, from: json), inset)
    }

    // MARK: - Resolution

    func testPlainLayerResolvesToDefaultEffects() {
        let plain = node(style: .plain)
        XCTAssertEqual(plain.blendMode, .normal)
        XCTAssertEqual(plain.blur, 0)
        XCTAssertNil(plain.border)
        XCTAssertEqual(plain.scale, 1)
        XCTAssertFalse(plain.flipHorizontal)
        XCTAssertFalse(plain.flipVertical)
        XCTAssertEqual(plain.colorAdjust, .identity)
        XCTAssertNil(plain.glow)
    }

    func testEffectsResolveOntoTheNode() {
        let resolved = node(style: everyEffect)
        XCTAssertEqual(resolved.blendMode, .softLight)
        XCTAssertEqual(resolved.blur, 3)
        XCTAssertEqual(resolved.border, ResolvedBorder(color: ColorValue(hex: "#FF0000")!, width: 2, inset: 1))
        XCTAssertEqual(resolved.scale, 1.5)
        XCTAssertTrue(resolved.flipHorizontal)
        XCTAssertTrue(resolved.flipVertical)
        XCTAssertEqual(resolved.colorAdjust, ResolvedColorAdjust(
            brightness: 0.2, contrast: 1.4, saturation: 0.5, hueRotation: 45
        ))
        XCTAssertEqual(resolved.glow, ResolvedGlow(color: ColorValue(hex: "#00FFFF")!, radius: 10))
    }

    func testResolverClampsOutOfRangeValues() {
        let high = node(style: LayerStyle(
            blur: 999, scale: 100, brightness: 9, contrast: 40, saturation: 99, hueRotation: 450
        ))
        XCTAssertEqual(high.blur, 50)
        XCTAssertEqual(high.scale, 4)
        XCTAssertEqual(high.colorAdjust.brightness, 1)
        XCTAssertEqual(high.colorAdjust.contrast, 4)
        XCTAssertEqual(high.colorAdjust.saturation, 4)
        XCTAssertEqual(high.colorAdjust.hueRotation, 90, "Hue is periodic, so it wraps rather than clamps")

        let low = node(style: LayerStyle(
            blur: -5, scale: 0, brightness: -9, contrast: -1, saturation: -1, hueRotation: -30
        ))
        XCTAssertEqual(low.blur, 0)
        XCTAssertEqual(low.scale, 0.1)
        XCTAssertEqual(low.colorAdjust.brightness, -1)
        XCTAssertEqual(low.colorAdjust.contrast, 0)
        XCTAssertEqual(low.colorAdjust.saturation, 0)
        XCTAssertEqual(low.colorAdjust.hueRotation, 330)
    }

    func testNonFiniteValuesFallBackToDefaults() {
        let broken = node(style: LayerStyle(
            blur: .nan,
            border: BorderStyle(color: .literal(.black), width: .infinity, inset: .nan),
            scale: .infinity,
            brightness: .nan,
            contrast: -.infinity,
            saturation: .nan,
            hueRotation: .nan,
            glow: GlowStyle(color: .literal(.black), radius: .nan)
        ))
        XCTAssertEqual(broken.blur, 0)
        XCTAssertEqual(broken.scale, 1)
        XCTAssertEqual(broken.colorAdjust, .identity)
        XCTAssertNil(broken.glow, "A non-finite glow radius degrades to no glow")
        // An infinite width falls back to 0, which is a border that draws
        // nothing — so the whole border is dropped rather than kept as a no-op.
        XCTAssertNil(broken.border)
    }

    func testInvisibleBorderAndGlowAreDropped() {
        let invisible = node(style: LayerStyle(
            border: BorderStyle(color: .literal(.black), width: 0),
            glow: GlowStyle(color: .literal(.black), radius: 0)
        ))
        XCTAssertNil(invisible.border)
        XCTAssertNil(invisible.glow)
    }

    // MARK: - SVG backend

    private func svg(style: LayerStyle) -> String {
        SVGRenderer.render(resolve(Layer(
            name: "L",
            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            style: style,
            content: .shape(ShapeContent(kind: .rectangle, fill: Fill.literal(.black)))
        )))
    }

    func testSVGEmitsNothingExtraWhenEffectsAreUnset() {
        let output = svg(style: .plain)
        for fragment in [
            "filter", "mix-blend-mode", "feGaussianBlur", "feDropShadow",
            "feColorMatrix", "feComponentTransfer", "scale(", "stroke",
        ] {
            XCTAssertFalse(output.contains(fragment), "'\(fragment)' leaked into an effect-free document")
        }
    }

    func testSVGShadowAloneKeepsTheLegacyDropShadowForm() {
        let output = svg(style: LayerStyle(shadow: ShadowStyle(
            color: .literal(.black), radius: 6, offsetX: 0, offsetY: 3
        )))
        XCTAssertTrue(output.contains("style=\"filter: drop-shadow(0px 3px 6px #000000)\""))
        XCTAssertFalse(output.contains("<filter"), "A lone shadow must not grow a filter chain")
    }

    func testSVGEmitsAFilterChainForBlurGlowAndColorGrading() {
        let output = svg(style: LayerStyle(
            shadow: ShadowStyle(color: .literal(.black), radius: 4, offsetY: 2),
            blur: 8,
            brightness: 0.25,
            contrast: 2,
            saturation: 0.4,
            hueRotation: 120,
            glow: GlowStyle(color: .literal(ColorValue(hex: "#00FFFF")!), radius: 12)
        ))
        XCTAssertTrue(output.contains("<filter id=\"fx0\""))
        XCTAssertTrue(output.contains("color-interpolation-filters=\"sRGB\""), "Grading must not run in linear RGB")
        XCTAssertTrue(output.contains("filter=\"url(#fx0)\""))
        XCTAssertTrue(output.contains("<feComponentTransfer>"))
        XCTAssertTrue(output.contains("type=\"saturate\" values=\"0.40\""))
        XCTAssertTrue(output.contains("type=\"hueRotate\" values=\"120\""))
        // SwiftUI's blur radius is roughly twice a Gaussian sigma.
        XCTAssertTrue(output.contains("<feGaussianBlur stdDeviation=\"4\"/>"))
        XCTAssertTrue(output.contains("dx=\"0\" dy=\"0\" stdDeviation=\"6\" flood-color=\"#00FFFF\""), "Glow")
        XCTAssertTrue(output.contains("dx=\"0\" dy=\"2\" stdDeviation=\"2\" flood-color=\"#000000\""), "Shadow")
        XCTAssertFalse(output.contains("style=\"filter:"), "Shadow folds into the chain instead of doubling up")
    }

    func testSVGBlendModeUsesKebabCaseAndSkipsNormal() {
        XCTAssertTrue(svg(style: LayerStyle(blendMode: .colorDodge)).contains("mix-blend-mode: color-dodge"))
        XCTAssertTrue(svg(style: LayerStyle(blendMode: .plusLighter)).contains("mix-blend-mode: plus-lighter"))
        XCTAssertFalse(svg(style: LayerStyle(blendMode: .normal)).contains("mix-blend-mode"))
    }

    func testSVGBorderFollowsTheCornerRadiusInsideTheBounds() {
        let output = svg(style: LayerStyle(
            cornerRadius: 10,
            border: BorderStyle(color: .literal(ColorValue(hex: "#FF0000")!), width: 4, inset: 2)
        ))
        // Layer rect is 79×79 at (39.5, 39.5); the stroke straddles the path,
        // so the rect is pulled in by inset + half the width.
        XCTAssertTrue(
            output.contains("<rect x=\"43.50\" y=\"43.50\" width=\"71\" height=\"71\" rx=\"6\" fill=\"none\" stroke=\"#FF0000\" stroke-width=\"4\"/>"),
            output
        )
    }

    func testSVGScaleAndFlipPivotOnTheLayerCentre() {
        let output = svg(style: LayerStyle(scale: 2, flipHorizontal: true))
        XCTAssertTrue(output.contains("translate(79 79) scale(-2 2) translate(-79 -79)"), output)

        let rotated = svg(style: LayerStyle(rotation: 30, scale: 2))
        XCTAssertTrue(
            rotated.contains("transform=\"rotate(30 79 79) translate(79 79) scale(2 2) translate(-79 -79)\""),
            "Rotation stays outermost, matching the SwiftUI order"
        )
    }

    func testSVGGivesEachFilterAndGradientADistinctID() {
        let root = Layer(name: "Canvas", content: .container(ContainerContent(
            layout: .absolute,
            background: .linearGradient(GradientFill(stops: [
                GradientStop(position: 0, color: .literal(.white)),
                GradientStop(position: 1, color: .literal(.black)),
            ])),
            children: [
                Layer(name: "A", style: LayerStyle(blur: 4),
                      content: .shape(ShapeContent(kind: .circle, fill: Fill.literal(.black)))),
                Layer(name: "B", style: LayerStyle(blur: 6),
                      content: .shape(ShapeContent(kind: .circle, fill: Fill.literal(.black)))),
            ]
        )))
        let output = SVGRenderer.render(resolve(root))
        XCTAssertTrue(output.contains("<filter id=\"fx1\""))
        XCTAssertTrue(output.contains("<filter id=\"fx2\""))
        XCTAssertTrue(output.contains("<linearGradient id=\"grad0\""))
    }
}
