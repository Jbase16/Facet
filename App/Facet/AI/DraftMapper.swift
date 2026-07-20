import Foundation
import FacetCore

// Draft → document. Pure and total: whatever the model produced, the user
// ends up with a valid, editable WidgetDocument. Bad hexes fall back to
// legible ink, frames are clamped into the canvas, and unknown SF Symbol
// names are kept as-is — the renderer shows a placeholder and the user can
// fix the name in the inspector, which beats silently dropping a layer.
@available(iOS 26.0, *)
enum DraftMapper {

    static func document(from draft: WidgetDraft) -> WidgetDocument {
        var builder = Builder(draft: draft)
        return builder.build()
    }

    /// Point size of the systemSmall canvas — the base rendition every design
    /// is authored against (see GalleryCell). Used to turn normalized frames
    /// into point sizes for symbols.
    private static let canvasPoints = 158.0

    private struct Builder {
        let draft: WidgetDraft

        var colors: [String: ColorToken] = [:]
        /// hex (uppercased) → token name, so repeated colors share one token
        /// and a theme swap restyles every layer that used them.
        var tokenNamesByHex: [String: String] = [:]
        var fonts: [String: FontToken] = [:]

        let backgroundColor: ColorValue
        let backgroundIsDark: Bool

        init(draft: WidgetDraft) {
            self.draft = draft
            backgroundColor = ColorValue(hex: draft.background.hex) ?? ColorValue(hex: "#1C1C1E")!
            backgroundIsDark = luminance(of: backgroundColor) < 0.5
        }

        mutating func build() -> WidgetDocument {
            colors["background"] = ColorToken(light: backgroundColor)
            tokenNamesByHex[backgroundColor.hexString] = "background"
            if let bottom = draft.background.bottomHex.flatMap(ColorValue.init(hex:)) {
                colors["background2"] = ColorToken(light: bottom)
                tokenNamesByHex[bottom.hexString] = "background2"
            }
            assignRoleTokens()

            var children: [Layer] = []
            var kindCounts: [String: Int] = [:]
            for draftLayer in draft.layers {
                let layer = map(draftLayer, kindCounts: &kindCounts)
                children.append(layer)
            }

            let root = Layer(
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: backgroundFill(),
                    children: children
                ))
            )

            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return WidgetDocument(
                name: name.isEmpty ? "Generated Widget" : name,
                tokens: ThemeTokens(colors: colors, fonts: fonts),
                root: root,
                sources: inferredSources()
            )
        }

        // MARK: Colors

        /// Name the draft's colors the way the starter templates do:
        /// primary (first text ink), accent (first non-text tint), then
        /// numbered extras — the same names ThemeEditorView expects.
        mutating func assignRoleTokens() {
            for case .text(let text) in draft.layers {
                if let color = ColorValue(hex: text.hexColor) {
                    claim(color, preferring: "primary")
                    break
                }
            }
            if colors["primary"] == nil {
                let ink = backgroundIsDark ? ColorValue.white : ColorValue(hex: "#111111")!
                colors["primary"] = ColorToken(light: ink)
                tokenNamesByHex[ink.hexString] = "primary"
            }

            for layer in draft.layers {
                let hex: String?
                switch layer {
                case .gauge(let gauge): hex = gauge.hexTint
                case .symbol(let symbol): hex = symbol.hexColor
                case .chart(let chart): hex = chart.hexColor
                case .shape(let shape): hex = shape.hexFill
                case .text: hex = nil
                }
                if let hex, let color = ColorValue(hex: hex),
                   tokenNamesByHex[color.hexString] == nil {
                    claim(color, preferring: "accent")
                    break
                }
            }

            if draft.layers.contains(where: { if case .gauge = $0 { true } else { false } }) {
                let track = backgroundIsDark ? ColorValue(hex: "#3A3A3C")! : ColorValue(hex: "#E5E5EA")!
                colors["track"] = ColorToken(light: track)
                if tokenNamesByHex[track.hexString] == nil {
                    tokenNamesByHex[track.hexString] = "track"
                }
            }
        }

        /// Token for a color, creating a numbered extra when the role names
        /// are taken. Same hex for light and dark: the generator designs one
        /// scheme and the theme editor is where variants get authored.
        @discardableResult
        mutating func claim(_ color: ColorValue, preferring role: String? = nil) -> String {
            if let existing = tokenNamesByHex[color.hexString] { return existing }
            let name: String
            if let role, colors[role] == nil {
                name = role
            } else {
                var index = 2
                while colors["color\(index)"] != nil { index += 1 }
                name = "color\(index)"
            }
            colors[name] = ColorToken(light: color)
            tokenNamesByHex[color.hexString] = name
            return name
        }

        mutating func colorRef(fromHex hex: String) -> ColorRef {
            guard let color = ColorValue(hex: hex) else {
                return .token("primary")
            }
            return .token(claim(color))
        }

        func backgroundFill() -> Fill {
            guard colors["background2"] != nil else { return .token("background") }
            return .linearGradient(GradientFill(
                stops: [
                    GradientStop(position: 0, color: .token("background")),
                    GradientStop(position: 1, color: .token("background2")),
                ],
                angle: 90
            ))
        }

        // MARK: Fonts

        /// One token per size hint (display/body/caption), weight fixed by
        /// its first use; a same-size layer wanting a different weight gets a
        /// numbered variant rather than silently losing its weight.
        mutating func fontRef(size: DraftTextSize, weight: DraftTextWeight) -> FontRef {
            let (baseName, points): (String, Double) = switch size {
            case .large: ("display", 28)
            case .medium: ("body", 15)
            case .small: ("caption", 11)
            }
            let mapped = fontWeight(weight)
            var name = baseName
            var index = 2
            while let existing = fonts[name], existing.weight != mapped {
                name = "\(baseName)\(index)"
                index += 1
            }
            if fonts[name] == nil {
                fonts[name] = FontToken(size: points, weight: mapped, design: .rounded)
            }
            return .token(name)
        }

        func fontWeight(_ weight: DraftTextWeight) -> FontWeight {
            switch weight {
            case .light: .light
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }

        // MARK: Layers

        mutating func map(_ draftLayer: DraftLayer, kindCounts: inout [String: Int]) -> Layer {
            switch draftLayer {
            case .text(let text):
                Layer(
                    name: layerName("Text", counts: &kindCounts),
                    frame: frame(text.frame),
                    content: .text(TextContent(
                        text: text.template,
                        font: fontRef(size: text.size, weight: text.weight),
                        color: colorRef(fromHex: text.hexColor)
                    ))
                )
            case .gauge(let gauge):
                Layer(
                    name: layerName("Gauge", counts: &kindCounts),
                    frame: frame(gauge.frame),
                    content: .gauge(GaugeContent(
                        value: gauge.valueExpression,
                        style: gauge.style == .ring ? .ring : .bar,
                        tint: colorRef(fromHex: gauge.hexTint),
                        track: .token("track"),
                        lineWidth: gauge.style == .ring ? 10 : 6
                    ))
                )
            case .symbol(let symbol):
                Layer(
                    name: layerName("Symbol", counts: &kindCounts),
                    frame: frame(symbol.frame),
                    content: .symbol(SymbolContent(
                        systemName: symbol.sfSymbolName,
                        color: colorRef(fromHex: symbol.hexColor),
                        size: symbolPointSize(for: symbol.frame)
                    ))
                )
            case .shape(let shape):
                Layer(
                    name: layerName("Shape", counts: &kindCounts),
                    frame: frame(shape.frame),
                    style: LayerStyle(cornerRadius: shape.kind == .rect ? shape.cornerRadius.clamped(to: 0...40) : 0),
                    content: .shape(ShapeContent(
                        kind: shape.kind == .circle ? .circle : .rectangle,
                        fill: Fill.color(colorRef(fromHex: shape.hexFill))
                    ))
                )
            case .chart(let chart):
                Layer(
                    name: layerName("Chart", counts: &kindCounts),
                    frame: frame(chart.frame),
                    content: .chart(ChartContent(
                        dataPath: chart.dataPath,
                        style: chart.style == .line ? .line : .bars,
                        color: colorRef(fromHex: chart.hexColor)
                    ))
                )
            }
        }

        func layerName(_ kind: String, counts: inout [String: Int]) -> String {
            let count = (counts[kind] ?? 0) + 1
            counts[kind] = count
            return count == 1 ? kind : "\(kind) \(count)"
        }

        /// Guided generation already ranges these 0-1, but the mapper is the
        /// last line of defense — clamp anyway so a schema change upstream
        /// can never produce an off-canvas layer.
        func frame(_ draft: DraftFrame) -> LayerFrame {
            LayerFrame(
                x: draft.x.clamped(to: 0...1),
                y: draft.y.clamped(to: 0...1),
                width: draft.width.clamped(to: 0.02...1),
                height: draft.height.clamped(to: 0.02...1)
            )
        }

        func symbolPointSize(for draft: DraftFrame) -> Double {
            let side = min(draft.width, draft.height).clamped(to: 0.02...1)
            return (side * DraftMapper.canvasPoints * 0.62).rounded().clamped(to: 12...72)
        }

        // MARK: Sources

        /// A document only refreshes the sources it declares, so scan every
        /// expression-bearing string for the source prefixes it references.
        func inferredSources() -> [String] {
            var haystack = ""
            for layer in draft.layers {
                switch layer {
                case .text(let text): haystack += text.template + "\n"
                case .gauge(let gauge): haystack += gauge.valueExpression + "\n"
                case .chart(let chart): haystack += chart.dataPath + "\n"
                case .symbol, .shape: break
                }
            }
            return ["battery", "weather", "health", "calendar", "time"]
                .filter { haystack.contains($0 + ".") }
        }
    }

    private static func luminance(of color: ColorValue) -> Double {
        0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
