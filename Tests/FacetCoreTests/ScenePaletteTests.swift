import XCTest
@testable import FacetCore

/// Scene palettes: merge semantics, and the guarantees that let one palette be
/// applied to widgets that were never designed together.
final class ScenePaletteTests: XCTestCase {
    private func color(_ hex: String) -> ColorToken {
        ColorToken(light: ColorValue(hex: hex)!, dark: ColorValue(hex: hex)!)
    }

    private func document(colors: [String: ColorToken], fonts: [String: FontToken] = [:]) -> WidgetDocument {
        WidgetDocument(
            name: "Doc",
            tokens: ThemeTokens(colors: colors, fonts: fonts),
            root: Layer(
                name: "Canvas",
                content: .shape(ShapeContent(kind: .rectangle, fill: .token("accent")))
            ),
            sources: []
        )
    }

    // MARK: - Merge semantics

    func testAnEmptyPaletteChangesNothing() {
        let tokens = ThemeTokens(colors: ["accent": color("#FF0000")])
        XCTAssertEqual(tokens.merging(.empty), tokens)
    }

    func testTheOverrideWins() {
        let base = ThemeTokens(colors: ["accent": color("#FF0000")])
        let merged = base.merging(ThemeTokens(colors: ["accent": color("#00FF00")]))
        XCTAssertEqual(merged.colors["accent"], color("#00FF00"))
    }

    /// The property that makes a shared palette usable at all: a scene naming
    /// one token must not wipe the others.
    func testUnnamedTokensSurvive() {
        let base = ThemeTokens(
            colors: ["accent": color("#FF0000"), "background": color("#111111")],
            fonts: ["display": FontToken(size: 28, weight: .bold)]
        )
        let merged = base.merging(ThemeTokens(colors: ["accent": color("#00FF00")]))
        XCTAssertEqual(merged.colors["background"], color("#111111"))
        XCTAssertEqual(merged.fonts["display"]?.size, 28)
        XCTAssertEqual(merged.colors.count, 2)
    }

    func testAPaletteCanIntroduceATokenTheDocumentLacks() {
        let merged = ThemeTokens.empty.merging(ThemeTokens(colors: ["accent": color("#00FF00")]))
        XCTAssertEqual(merged.colors["accent"], color("#00FF00"))
    }

    func testMergingIsIdempotent() {
        let base = ThemeTokens(colors: ["accent": color("#FF0000")])
        let palette = ThemeTokens(colors: ["accent": color("#00FF00")])
        XCTAssertEqual(base.merging(palette), base.merging(palette).merging(palette))
    }

    func testFontsAndSpacingMergeToo() {
        let base = ThemeTokens(
            colors: [:],
            fonts: ["display": FontToken(size: 28, weight: .bold)],
            spacing: ["gap": 8]
        )
        let merged = base.merging(ThemeTokens(
            colors: [:],
            fonts: ["display": FontToken(size: 40, weight: .black)],
            spacing: ["gap": 16]
        ))
        XCTAssertEqual(merged.fonts["display"]?.size, 40)
        XCTAssertEqual(merged.spacing["gap"], 16)
    }

    func testIsEmpty() {
        XCTAssertTrue(ThemeTokens.empty.isEmpty)
        XCTAssertFalse(ThemeTokens(colors: ["a": color("#FFFFFF")]).isEmpty)
        XCTAssertFalse(ThemeTokens(colors: [:], spacing: ["gap": 4]).isEmpty)
    }

    // MARK: - Applying to a document

    func testApplyingReturnsACopyAndLeavesTheOriginalAlone() {
        let original = document(colors: ["accent": color("#FF0000")])
        let themed = original.applying(palette: ThemeTokens(colors: ["accent": color("#00FF00")]))
        XCTAssertEqual(original.tokens.colors["accent"], color("#FF0000"), "The widget itself must not change")
        XCTAssertEqual(themed.tokens.colors["accent"], color("#00FF00"))
    }

    /// The same design placed in two scenes shows each scene's colours — which
    /// is the whole reason a placement stores a reference and not a copy.
    func testOneDocumentTakesOnEachScenesPalette() {
        let shared = document(colors: ["accent": color("#FF0000")])
        let warm = shared.applying(palette: ThemeTokens(colors: ["accent": color("#FF8800")]))
        let cool = shared.applying(palette: ThemeTokens(colors: ["accent": color("#0088FF")]))
        XCTAssertEqual(warm.tokens.colors["accent"], color("#FF8800"))
        XCTAssertEqual(cool.tokens.colors["accent"], color("#0088FF"))
        XCTAssertNotEqual(warm.tokens.colors["accent"], cool.tokens.colors["accent"])
    }

    func testApplyingAnEmptyPaletteIsIdentity() {
        let original = document(colors: ["accent": color("#FF0000")])
        XCTAssertEqual(original.applying(palette: .empty), original)
    }

    func testApplyingPreservesEverythingElseAboutTheDocument() {
        var original = document(colors: ["accent": color("#FF0000")])
        original.name = "Keep me"
        original.sources = ["battery"]
        let themed = original.applying(palette: ThemeTokens(colors: ["accent": color("#00FF00")]))
        XCTAssertEqual(themed.id, original.id)
        XCTAssertEqual(themed.name, "Keep me")
        XCTAssertEqual(themed.sources, ["battery"])
        XCTAssertEqual(themed.root, original.root)
    }

    func testSceneRoundTripKeepsThePalette() throws {
        var scene = FacetScene(name: "Themed")
        scene.palette = ThemeTokens(colors: ["accent": color("#00FF00")])
        let decoded = try SceneFile.decode(try SceneFile.encode(scene))
        XCTAssertEqual(decoded.palette.colors["accent"], color("#00FF00"))
    }
}
