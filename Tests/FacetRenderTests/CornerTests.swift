import XCTest
import FacetCore
import FacetData
@testable import FacetRender
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Corner profiles across the two backends. The bar here is the one CLAUDE.md
/// sets after the `Ellipse`-vs-inscribed-circle bug: a green suite is not
/// evidence unless something actually compares what the two renderers draw.
final class CornerTests: XCTestCase {

    // MARK: - Fixtures

    private func resolve(_ style: LayerStyle, content: LayerContent? = nil) -> ResolvedWidget {
        DocumentResolver.resolve(
            document: WidgetDocument(name: "T", root: Layer(
                name: "L",
                frame: LayerFrame(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                style: style,
                content: content ?? .shape(ShapeContent(kind: .rectangle, fill: Fill.literal(.black)))
            )),
            snapshots: SnapshotSet(),
            environment: RenderEnvironment(rendition: .systemSmall)
        )
    }

    private func svg(_ style: LayerStyle, content: LayerContent? = nil) -> String {
        SVGRenderer.render(resolve(style, content: content))
    }

    /// The layer rect the fixture above produces: 79×79 at (39.5, 39.5).
    private let layerRect = Rect(x: 39.5, y: 39.5, width: 79, height: 79)

    private func firstPathData(in svg: String) -> String? {
        guard let start = svg.range(of: "<path d=\"") else { return nil }
        let rest = svg[start.upperBound...]
        guard let end = rest.range(of: "\"") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    // MARK: - Compatibility

    func testAV1DocumentWithACornerRadiusDecodesToAUniformRoundedProfile() throws {
        let style = try JSONDecoder().decode(
            LayerStyle.self,
            from: Data(#"{"opacity":1,"rotation":0,"cornerRadius":12}"#.utf8)
        )
        XCTAssertEqual(style.corners, CornerProfile(style: .rounded, radius: 12))
        XCTAssertEqual(style.cornerRadius, 12)
        XCTAssertEqual(style.corners.style, .rounded)
    }

    func testAUniformRoundedProfileStillWritesOnlyTheLegacyKey() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let round = String(decoding: try encoder.encode(LayerStyle(cornerRadius: 12)), as: UTF8.self)
        XCTAssertEqual(round, "{\"cornerRadius\":12,\"opacity\":1,\"rotation\":0}")
        XCTAssertFalse(round.contains("corners"), "Nothing changed, so nothing new goes on disk")
    }

    func testAShapedProfileWritesCornersAndRoundTrips() throws {
        let styles = [
            LayerStyle(corners: CornerProfile(style: .chamfered, radius: 14)),
            LayerStyle(corners: CornerProfile(style: .rounded, radii: CornerRadii(
                topLeading: 20, topTrailing: 0, bottomLeading: 0, bottomTrailing: 20
            ))),
            LayerStyle(corners: CornerProfile(style: .scalloped, radius: 9)),
        ]
        for style in styles {
            let data = try JSONEncoder().encode(style)
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"corners\""))
            XCTAssertEqual(try JSONDecoder().decode(LayerStyle.self, from: data), style)
        }
    }

    func testEveryStarterTemplateStillWritesTheLegacyCornerKey() throws {
        // The compatibility promise, checked against the real documents rather
        // than a fixture: nothing shipped has a profile, so nothing shipped
        // grows a `corners` object.
        let document = WidgetDocument(
            name: "Plain",
            root: Layer(name: "L", content: .shape(ShapeContent(kind: .rectangle, fill: Fill.literal(.black))))
        )
        let json = String(decoding: try FacetFile.encode(document), as: UTF8.self)
        XCTAssertTrue(json.contains("\"cornerRadius\""))
        XCTAssertFalse(json.contains("\"corners\""))
    }

    func testALegacyMaskCornerRadiusDecodesAndReEncodesUnchanged() throws {
        let mask = try JSONDecoder().decode(
            LayerMask.self,
            from: Data(#"{"shape":"rectangle","cornerRadius":8}"#.utf8)
        )
        XCTAssertEqual(mask.corners, CornerRadii(8))
        XCTAssertNil(mask.cornerStyle, "An old mask names no style, so it follows the layer's")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(
            String(decoding: try encoder.encode(mask), as: UTF8.self),
            "{\"cornerRadius\":8,\"shape\":\"rectangle\"}"
        )
    }

    // MARK: - Resolver

    func testTheResolverSanitizesRadiiInsteadOfPassingNaNToTheRenderers() {
        let node = resolve(LayerStyle(corners: CornerProfile(
            style: .rounded,
            radii: CornerRadii(topLeading: .nan, topTrailing: -8, bottomLeading: .infinity, bottomTrailing: 6)
        ))).root
        XCTAssertEqual(node.corners.radii.topLeading, 0)
        XCTAssertEqual(node.corners.radii.topTrailing, 0)
        XCTAssertEqual(node.corners.radii.bottomLeading, 0)
        XCTAssertEqual(node.corners.radii.bottomTrailing, 6)
    }

    func testAMaskWithNoStyleOfItsOwnFollowsTheLayers() throws {
        let node = resolve(LayerStyle(
            corners: CornerProfile(style: .chamfered, radius: 20),
            mask: LayerMask(shape: .rectangle, cornerRadius: 20)
        )).root
        XCTAssertEqual(try XCTUnwrap(node.mask).corners.style, .chamfered)
        XCTAssertEqual(try XCTUnwrap(node.mask).corners.radii, CornerRadii(20))
    }

    func testAMaskCanOverrideTheLayersCornerStyle() throws {
        let node = resolve(LayerStyle(
            corners: CornerProfile(style: .chamfered, radius: 20),
            mask: LayerMask(shape: .rectangle, cornerRadius: 20, cornerStyle: .rounded)
        )).root
        XCTAssertEqual(try XCTUnwrap(node.mask).corners.style, .rounded)
    }

    func testASquareRectangleMaskIsStillANoOpWhateverStyleItNames() {
        // The style alone clips nothing, so it must not resurrect a mask the
        // resolver has always dropped — that would cost a compositing group
        // and an SVG <mask> for no visual difference.
        XCTAssertNil(resolve(LayerStyle(
            corners: CornerProfile(style: .scalloped, radius: 20),
            mask: LayerMask(shape: .rectangle, cornerStyle: .scalloped)
        )).root.mask)
    }

    // MARK: - SVG output: the fast path

    func testAUniformRoundedLayerStillEmitsAPlainRoundedRect() {
        let output = svg(LayerStyle(cornerRadius: 12))
        XCTAssertTrue(
            output.contains("<rect x=\"39.50\" y=\"39.50\" width=\"79\" height=\"79\" rx=\"12\" fill=\"#000000\"/>"),
            output
        )
        XCTAssertFalse(output.contains("<path"), "The common case must not grow a generated outline")
    }

    func testAStyledLayerEmitsAGeneratedPathInsteadOfARect() {
        for style in [CornerStyle.chamfered, .inverted, .scalloped] {
            let output = svg(LayerStyle(corners: CornerProfile(style: style, radius: 12)))
            XCTAssertTrue(output.contains("<path d=\"M"), "\(style): \(output)")
            XCTAssertFalse(output.contains("rx=\"12\""), "\(style) must not fall back to a rounded rect")
        }
    }

    func testAZeroRadiusStyledLayerStaysOnTheFastPath() {
        let output = svg(LayerStyle(corners: CornerProfile(style: .scalloped, radius: 0)))
        XCTAssertTrue(output.contains("rx=\"0\""), output)
        XCTAssertFalse(output.contains("<path"))
    }

    func testTheBorderFollowsTheProfileAndTheHistoricalRadiusMaths() {
        // Unchanged for a rounded layer — inset 2 and half of a 4pt stroke
        // come off both the rect and the radius.
        let rounded = svg(LayerStyle(
            cornerRadius: 10,
            border: BorderStyle(color: .literal(ColorValue(hex: "#FF0000")!), width: 4, inset: 2)
        ))
        XCTAssertTrue(
            rounded.contains("<rect x=\"43.50\" y=\"43.50\" width=\"71\" height=\"71\" rx=\"6\" fill=\"none\" stroke=\"#FF0000\" stroke-width=\"4\"/>"),
            rounded
        )
        // Chamfered, the border becomes a bevelled path over the same rect.
        let chamfered = svg(LayerStyle(
            corners: CornerProfile(style: .chamfered, radius: 10),
            border: BorderStyle(color: .literal(ColorValue(hex: "#FF0000")!), width: 4, inset: 2)
        ))
        XCTAssertTrue(
            chamfered.contains("fill=\"none\" stroke=\"#FF0000\" stroke-width=\"4\""),
            chamfered
        )
        // The stroked element is a path, not a rect: a bevelled border drawn
        // as a rounded rectangle would trace a silhouette the layer doesn't
        // have. (The one `rx=` left in the document is the canvas clip.)
        XCTAssertFalse(
            chamfered.contains("rx=\"6\" fill=\"none\""),
            "A bevelled border must not fall back to a rounded rect"
        )
        XCTAssertEqual(chamfered.components(separatedBy: "rx=").count - 1, 1, chamfered)
    }

    func testAGroupBackgroundAndAnImageClipBothFollowTheProfile() {
        let group = SVGRenderer.render(DocumentResolver.resolve(
            document: WidgetDocument(name: "T", root: Layer(
                name: "Canvas",
                style: LayerStyle(corners: CornerProfile(style: .inverted, radius: 16)),
                content: .container(ContainerContent(background: Fill.literal(.black)))
            )),
            snapshots: SnapshotSet(),
            environment: RenderEnvironment(rendition: .systemSmall)
        ))
        XCTAssertTrue(group.contains("<path d=\"M"), group)

        let image = svg(
            LayerStyle(corners: CornerProfile(style: .inverted, radius: 16)),
            content: .image(ImageContent(assetName: "photo"))
        )
        XCTAssertTrue(image.contains("<path d=\"M"), image)
    }

    func testARectangleMaskFollowsTheProfileInSVG() {
        let output = svg(LayerStyle(
            corners: CornerProfile(style: .scalloped, radius: 18),
            mask: LayerMask(shape: .rectangle, cornerRadius: 18)
        ))
        XCTAssertTrue(output.contains("<mask id="), output)
        // Two paths inside the mask definition and the shape itself, both
        // scalloped — a mask that ignored the style would emit `rx="18"`.
        XCTAssertFalse(output.contains("rx=\"18\""), output)
    }

    // MARK: - The two backends actually agreeing

    #if canImport(SwiftUI)
    /// Walks a SwiftUI `Path` back into the same command vocabulary the SVG
    /// side speaks, in canvas points, so the two can be compared number for
    /// number instead of by eye.
    private func elements(of path: Path) -> [(String, [CGPoint])] {
        var result: [(String, [CGPoint])] = []
        path.cgPath.applyWithBlock { element in
            let kind = element.pointee.type
            let points = element.pointee.points
            switch kind {
            case .moveToPoint: result.append(("M", [points[0]]))
            case .addLineToPoint: result.append(("L", [points[0]]))
            case .addQuadCurveToPoint: result.append(("Q", [points[0], points[1]]))
            case .addCurveToPoint: result.append(("C", [points[0], points[1], points[2]]))
            case .closeSubpath: result.append(("Z", []))
            @unknown default: result.append(("?", []))
            }
        }
        return result
    }

    private func elements(ofSVG data: String) throws -> [(String, [CGPoint])] {
        try PathData.parse(data).map { command in
            switch command {
            case .move(let x, let y): return ("M", [CGPoint(x: x, y: y)])
            case .line(let x, let y): return ("L", [CGPoint(x: x, y: y)])
            case .quad(let cx, let cy, let x, let y):
                return ("Q", [CGPoint(x: cx, y: cy), CGPoint(x: x, y: y)])
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                return ("C", [CGPoint(x: c1x, y: c1y), CGPoint(x: c2x, y: c2y), CGPoint(x: x, y: y)])
            case .close: return ("Z", [])
            }
        }
    }

    func testBothBackendsDrawTheSameOutlineForEveryStyle() throws {
        // The check the ellipse bug needed: take one document, render it
        // through SVG, and compare the emitted outline against the Path the
        // SwiftUI backend builds for the same node — same rect, same commands,
        // same numbers.
        for style in [CornerStyle.chamfered, .inverted, .scalloped] {
            for radii in [CornerRadii(18),
                          CornerRadii(topLeading: 30, topTrailing: 4, bottomLeading: 0, bottomTrailing: 12)] {
                let profile = CornerProfile(style: style, radii: radii)
                let output = svg(LayerStyle(corners: profile))
                let emitted = try elements(ofSVG: XCTUnwrap(firstPathData(in: output), "\(style)"))

                let rect = CGRect(x: layerRect.x, y: layerRect.y, width: layerRect.width, height: layerRect.height)
                let drawn = elements(of: CornerShape(profile: profile).path(in: rect))

                XCTAssertEqual(emitted.map(\.0), drawn.map(\.0), "\(style) command kinds diverged")
                for (a, b) in zip(emitted, drawn) {
                    for (p, q) in zip(a.1, b.1) {
                        // SVG formats to 2dp, so that is the agreement bar.
                        XCTAssertEqual(p.x, q.x, accuracy: 0.01, "\(style) x")
                        XCTAssertEqual(p.y, q.y, accuracy: 0.01, "\(style) y")
                    }
                }
            }
        }
    }

    func testTheUniformRoundedFastPathIsTakenOnBothSides() {
        // Here the two backends deliberately differ — SwiftUI has always drawn
        // `.continuous` squircles where SVG writes a circular `rx=` — so what
        // is pinned is that both still take their own native fast path rather
        // than one of them quietly switching to a generated outline.
        let profile = CornerProfile(style: .rounded, radius: 12)
        let rect = CGRect(x: 0, y: 0, width: 79, height: 79)
        XCTAssertEqual(
            CornerShape(profile: profile).path(in: rect).description,
            RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect).description
        )
        XCTAssertTrue(svg(LayerStyle(cornerRadius: 12)).contains("rx=\"12\""))
    }

    func testTheSwiftUIOutlineTracksTheRectItIsGivenNotTheLayersNominalSize() {
        // `strokeBorder` and the border overlay both hand `CornerShape` a
        // smaller rect than the layer. A corner has to stay circular in points
        // in that rect, which it only does if the outline is regenerated for
        // it — the bug a cached normalized path would reintroduce.
        let profile = CornerProfile(style: .chamfered, radius: 20)
        let wide = CornerShape(profile: profile).path(in: CGRect(x: 0, y: 0, width: 300, height: 100))
        guard case ("M", let move) = elements(of: wide)[0] else { return XCTFail("Expected a move") }
        XCTAssertEqual(move[0].x, 20, accuracy: 1e-6)
        XCTAssertEqual(move[0].y, 0, accuracy: 1e-6)

        let inset = CornerShape(profile: profile).inset(by: 5).path(in: CGRect(x: 0, y: 0, width: 300, height: 100))
        guard case ("M", let insetMove) = elements(of: inset)[0] else { return XCTFail("Expected a move") }
        XCTAssertEqual(insetMove[0].x, 5 + 15, accuracy: 1e-6, "Radius and rect both pull in by the inset")
    }
    #endif
}
