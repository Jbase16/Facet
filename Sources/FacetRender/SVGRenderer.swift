import Foundation
import FacetCore

/// Renders a resolved widget to SVG. This is the debug/preview backend: it
/// runs on Linux CI for golden tests and powers documentation thumbnails.
/// SF Symbols can't be rasterized off-device, so symbols draw as a labeled
/// glyph placeholder; everything else is faithful.
public enum SVGRenderer {
    public static func render(_ widget: ResolvedWidget, cornerRadius: Double = 20) -> String {
        let canvas = widget.canvas
        var body = ""
        var defs: [String] = []
        emit(widget.root, into: &body, defs: &defs, indent: "  ")
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(format(canvas.width))" height="\(format(canvas.height))" \
        viewBox="0 0 \(format(canvas.width)) \(format(canvas.height))">
        <defs>
        <clipPath id="canvas"><rect x="0" y="0" width="\(format(canvas.width))" height="\(format(canvas.height))" rx="\(format(cornerRadius))"/></clipPath>
        \(defs.joined(separator: "\n"))
        </defs>
        <g clip-path="url(#canvas)">
        \(body)</g>
        </svg>
        """
    }

    /// The paint attribute value for a fill: a color literal, or a `url(#…)`
    /// reference to a gradient definition appended to `defs`.
    private static func paint(_ fill: ResolvedFill, defs: inout [String]) -> String {
        switch fill {
        case .solid(let color):
            return cssColor(color)
        case .linearGradient(let stops, let angle):
            let id = "grad\(defs.count)"
            let radians = angle * .pi / 180
            let dx = Darwin_cos(radians) / 2
            let dy = Darwin_sin(radians) / 2
            let stopElements = stops.map {
                "<stop offset=\"\(format($0.position * 100))%\" stop-color=\"\(cssColor($0.color))\"/>"
            }.joined()
            defs.append(
                "<linearGradient id=\"\(id)\" x1=\"\(format(0.5 - dx))\" y1=\"\(format(0.5 - dy))\" x2=\"\(format(0.5 + dx))\" y2=\"\(format(0.5 + dy))\">\(stopElements)</linearGradient>"
            )
            return "url(#\(id))"
        case .radialGradient(let stops):
            let id = "grad\(defs.count)"
            let stopElements = stops.map {
                "<stop offset=\"\(format($0.position * 100))%\" stop-color=\"\(cssColor($0.color))\"/>"
            }.joined()
            defs.append("<radialGradient id=\"\(id)\">\(stopElements)</radialGradient>")
            return "url(#\(id))"
        }
    }

    // Foundation on Linux exposes cos/sin through Glibc; alias for clarity.
    private static func Darwin_cos(_ x: Double) -> Double { Foundation.cos(x) }
    private static func Darwin_sin(_ x: Double) -> Double { Foundation.sin(x) }

    private static func emit(_ node: RenderNode, into output: inout String, defs: inout [String], indent: String) {
        var attributes = ""
        if node.opacity < 1 {
            attributes += " opacity=\"\(format(node.opacity))\""
        }
        if let transform = transformAttribute(node) {
            attributes += " transform=\"\(transform)\""
        }
        var styles: [String] = []
        if let filterID = filterDefinition(node, defs: &defs) {
            attributes += " filter=\"url(#\(filterID))\""
        } else if let shadow = node.shadow {
            // A lone shadow keeps the plain CSS form it has always emitted;
            // only nodes that actually need a filter chain grow one.
            styles.append("filter: drop-shadow(\(format(shadow.offsetX))px \(format(shadow.offsetY))px \(format(shadow.radius))px \(cssColor(shadow.color)))")
        }
        if let blend = cssBlendMode(node.blendMode) {
            styles.append("mix-blend-mode: \(blend)")
        }
        if !styles.isEmpty {
            attributes += " style=\"\(styles.joined(separator: "; "))\""
        }
        output += "\(indent)<g\(attributes)>\n"

        switch node.kind {
        case .group(let background):
            if let background {
                output += "\(indent)  <rect x=\"\(format(node.rect.x))\" y=\"\(format(node.rect.y))\" width=\"\(format(node.rect.width))\" height=\"\(format(node.rect.height))\" rx=\"\(format(node.cornerRadius))\" fill=\"\(paint(background, defs: &defs))\"/>\n"
            }
        case .shape(let shape):
            output += indent + "  " + shapeElement(shape, in: node, defs: &defs) + "\n"
        case .line(let line):
            var dashAttribute = ""
            if let dash = line.dash, !dash.isEmpty {
                dashAttribute = " stroke-dasharray=\"\(dash.map(format).joined(separator: " "))\""
            }
            output += "\(indent)  <line x1=\"\(format(node.rect.x))\" y1=\"\(format(node.rect.midY))\" x2=\"\(format(node.rect.maxX))\" y2=\"\(format(node.rect.midY))\" stroke=\"\(cssColor(line.color))\" stroke-width=\"\(format(line.thickness))\" stroke-linecap=\"round\"\(dashAttribute)/>\n"
        case .chart(let chart):
            output += chartElements(chart, in: node.rect, indent: indent + "  ")
        case .text(let text):
            output += indent + "  " + textElement(text, in: node.rect) + "\n"
        case .symbol(let symbol):
            // Placeholder glyph: a soft square marked with the symbol name.
            let side = symbol.size
            let x = node.rect.midX - side / 2
            let y = node.rect.midY - side / 2
            output += "\(indent)  <rect x=\"\(format(x))\" y=\"\(format(y))\" width=\"\(format(side))\" height=\"\(format(side))\" rx=\"\(format(side * 0.22))\" fill=\"\(cssColor(symbol.color))\" fill-opacity=\"0.25\"/>\n"
            output += "\(indent)  <text x=\"\(format(node.rect.midX))\" y=\"\(format(node.rect.midY))\" text-anchor=\"middle\" dominant-baseline=\"central\" font-family=\"system-ui\" font-size=\"\(format(side * 0.42))\" fill=\"\(cssColor(symbol.color))\">\(escape(shortSymbolLabel(symbol.systemName)))</text>\n"
        case .image(let image):
            output += "\(indent)  <rect x=\"\(format(node.rect.x))\" y=\"\(format(node.rect.y))\" width=\"\(format(node.rect.width))\" height=\"\(format(node.rect.height))\" rx=\"\(format(node.cornerRadius))\" fill=\"#8884\" stroke=\"#8888\" stroke-dasharray=\"4 3\"/>\n"
            output += "\(indent)  <text x=\"\(format(node.rect.midX))\" y=\"\(format(node.rect.midY))\" text-anchor=\"middle\" dominant-baseline=\"central\" font-family=\"system-ui\" font-size=\"10\" fill=\"#888\">\(escape(image.assetName))</text>\n"
        case .gauge(let gauge):
            output += gaugeElements(gauge, in: node.rect, indent: indent + "  ")
        }

        for child in node.children {
            emit(child, into: &output, defs: &defs, indent: indent + "  ")
        }
        // Last, so it sits over the node's own content and its children —
        // the SwiftUI backend applies the border overlay at the same point.
        if let border = node.border {
            output += indent + "  " + borderElement(border, in: node) + "\n"
        }
        output += "\(indent)</g>\n"
    }

    // MARK: - Effects

    /// Rotation, then scale/flip, both pivoted on the layer's centre — the
    /// order the SwiftUI backend applies them in.
    private static func transformAttribute(_ node: RenderNode) -> String? {
        var parts: [String] = []
        if node.rotation != 0 {
            parts.append("rotate(\(format(node.rotation)) \(format(node.rect.midX)) \(format(node.rect.midY)))")
        }
        let scaleX = node.scale * (node.flipHorizontal ? -1 : 1)
        let scaleY = node.scale * (node.flipVertical ? -1 : 1)
        if scaleX != 1 || scaleY != 1 {
            // SVG's scale() is origin-anchored; sandwich it in translations.
            let centerX = node.rect.midX
            let centerY = node.rect.midY
            parts.append(
                "translate(\(format(centerX)) \(format(centerY))) scale(\(format(scaleX)) \(format(scaleY))) translate(\(format(-centerX)) \(format(-centerY)))"
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Colour grading → blur → glow → shadow, chained as filter primitives in
    /// the same order the SwiftUI backend applies them. Returns nil when the
    /// node needs no filter at all, which is the common case.
    ///
    /// Approximations, deliberate: SwiftUI's `.blur(radius:)` is not a
    /// Gaussian sigma (it is roughly twice one), so radii are halved for
    /// `stdDeviation` here and in the drop shadows — close, not identical.
    /// `color-interpolation-filters="sRGB"` is required because SVG filters
    /// otherwise operate in linear RGB, which would grade noticeably darker
    /// than SwiftUI does.
    private static func filterDefinition(_ node: RenderNode, defs: inout [String]) -> String? {
        let adjust = node.colorAdjust
        guard !adjust.isIdentity || node.blur > 0 || node.glow != nil else { return nil }

        var primitives = ""
        if adjust.brightness != 0 || adjust.contrast != 1 {
            // Brightness is additive and contrast multiplies about mid-grey;
            // both are linear in the channel, so one transfer function
            // expresses the pair exactly rather than approximately.
            let slope = adjust.contrast
            let intercept = adjust.contrast * adjust.brightness + 0.5 * (1 - adjust.contrast)
            let transfer = ["R", "G", "B"].map {
                "<feFunc\($0) type=\"linear\" slope=\"\(format(slope))\" intercept=\"\(format(intercept))\"/>"
            }.joined()
            primitives += "<feComponentTransfer>\(transfer)</feComponentTransfer>"
        }
        if adjust.saturation != 1 {
            primitives += "<feColorMatrix type=\"saturate\" values=\"\(format(adjust.saturation))\"/>"
        }
        if adjust.hueRotation != 0 {
            primitives += "<feColorMatrix type=\"hueRotate\" values=\"\(format(adjust.hueRotation))\"/>"
        }
        if node.blur > 0 {
            primitives += "<feGaussianBlur stdDeviation=\"\(format(node.blur / 2))\"/>"
        }
        if let glow = node.glow {
            primitives += dropShadow(offsetX: 0, offsetY: 0, radius: glow.radius, color: glow.color)
        }
        if let shadow = node.shadow {
            primitives += dropShadow(
                offsetX: shadow.offsetX,
                offsetY: shadow.offsetY,
                radius: shadow.radius,
                color: shadow.color
            )
        }

        let id = "fx\(defs.count)"
        // The default filter region (-10%, 120%) clips blur and glow off at
        // the edges; widen it enough that a 50pt spread survives.
        defs.append(
            "<filter id=\"\(id)\" x=\"-50%\" y=\"-50%\" width=\"200%\" height=\"200%\" color-interpolation-filters=\"sRGB\">\(primitives)</filter>"
        )
        return id
    }

    private static func dropShadow(offsetX: Double, offsetY: Double, radius: Double, color: ColorValue) -> String {
        var attributes = "dx=\"\(format(offsetX))\" dy=\"\(format(offsetY))\" stdDeviation=\"\(format(radius / 2))\""
        attributes += " flood-color=\"\(opaqueHex(color))\""
        if color.alpha < 1 {
            attributes += " flood-opacity=\"\(String(format: "%.3f", color.alpha))\""
        }
        return "<feDropShadow \(attributes)/>"
    }

    private static func borderElement(_ border: ResolvedBorder, in node: RenderNode) -> String {
        // SVG strokes straddle the path, SwiftUI's strokeBorder sits inside
        // it; pull the rect in by half the width so both land in the same place.
        let inset = border.inset + border.width / 2
        let radius = max(0, max(0, node.cornerRadius - border.inset) - border.width / 2)
        let rect = node.rect.insetBy(inset)
        return "<rect x=\"\(format(rect.x))\" y=\"\(format(rect.y))\" width=\"\(format(rect.width))\" height=\"\(format(rect.height))\" rx=\"\(format(radius))\" fill=\"none\" stroke=\"\(cssColor(border.color))\" stroke-width=\"\(format(border.width))\"/>"
    }

    /// nil for `.normal`, so unblended nodes emit no style attribute at all.
    ///
    /// `plusLighter` maps to `plus-lighter`, which is Compositing Level 2 and
    /// missing from older SVG rasterizers — those fall back to normal
    /// compositing rather than approximating it. Everything else in the set
    /// is Compositing Level 1 and matches SwiftUI's mode of the same name.
    private static func cssBlendMode(_ mode: BlendMode) -> String? {
        switch mode {
        case .normal: return nil
        case .multiply: return "multiply"
        case .screen: return "screen"
        case .overlay: return "overlay"
        case .darken: return "darken"
        case .lighten: return "lighten"
        case .colorDodge: return "color-dodge"
        case .colorBurn: return "color-burn"
        case .softLight: return "soft-light"
        case .hardLight: return "hard-light"
        case .difference: return "difference"
        case .exclusion: return "exclusion"
        case .hue: return "hue"
        case .saturation: return "saturation"
        case .color: return "color"
        case .luminosity: return "luminosity"
        case .plusLighter: return "plus-lighter"
        }
    }

    private static func shapeElement(_ shape: ResolvedShape, in node: RenderNode, defs: inout [String]) -> String {
        let rect = node.rect
        let fill = paint(shape.fill, defs: &defs)
        var stroke = ""
        if let strokeColor = shape.strokeColor, shape.strokeWidth > 0 {
            stroke = " stroke=\"\(cssColor(strokeColor))\" stroke-width=\"\(format(shape.strokeWidth))\""
        }
        switch shape.kind {
        case .circle:
            let radius = min(rect.width, rect.height) / 2
            return "<circle cx=\"\(format(rect.midX))\" cy=\"\(format(rect.midY))\" r=\"\(format(radius))\" fill=\"\(fill)\"\(stroke)/>"
        case .capsule:
            let radius = min(rect.width, rect.height) / 2
            return "<rect x=\"\(format(rect.x))\" y=\"\(format(rect.y))\" width=\"\(format(rect.width))\" height=\"\(format(rect.height))\" rx=\"\(format(radius))\" fill=\"\(fill)\"\(stroke)/>"
        case .rectangle:
            return "<rect x=\"\(format(rect.x))\" y=\"\(format(rect.y))\" width=\"\(format(rect.width))\" height=\"\(format(rect.height))\" rx=\"\(format(node.cornerRadius))\" fill=\"\(fill)\"\(stroke)/>"
        case .path:
            // Normalized commands scale into the node's rect, so the same
            // outline works at every widget size.
            let commands = shape.path ?? []
            return "<path d=\"\(pathDescription(commands, in: rect))\" fill=\"\(fill)\"\(stroke)/>"
        }
    }

    private static func pathDescription(_ commands: [PathCommand], in rect: Rect) -> String {
        func x(_ value: Double) -> String { format(rect.x + value * rect.width) }
        func y(_ value: Double) -> String { format(rect.y + value * rect.height) }
        return commands.map { command in
            switch command {
            case .move(let px, let py): return "M\(x(px)),\(y(py))"
            case .line(let px, let py): return "L\(x(px)),\(y(py))"
            case .quad(let cx, let cy, let px, let py):
                return "Q\(x(cx)),\(y(cy)) \(x(px)),\(y(py))"
            case .cubic(let c1x, let c1y, let c2x, let c2y, let px, let py):
                return "C\(x(c1x)),\(y(c1y)) \(x(c2x)),\(y(c2y)) \(x(px)),\(y(py))"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }

    private static func chartElements(_ chart: ResolvedChart, in rect: Rect, indent: String) -> String {
        guard chart.normalized.count >= 2 else { return "" }
        let count = chart.normalized.count

        if chart.style == .bars {
            var output = ""
            let gap = rect.width * 0.15 / Double(count)
            let barWidth = (rect.width - gap * Double(count - 1)) / Double(count)
            for (index, value) in chart.normalized.enumerated() {
                let height = max(rect.height * value, barWidth * 0.5)
                let x = rect.x + Double(index) * (barWidth + gap)
                output += "\(indent)<rect x=\"\(format(x))\" y=\"\(format(rect.maxY - height))\" width=\"\(format(barWidth))\" height=\"\(format(height))\" rx=\"\(format(barWidth / 3))\" fill=\"\(cssColor(chart.color))\"/>\n"
            }
            return output
        }

        let step = rect.width / Double(count - 1)
        let points = chart.normalized.enumerated().map { index, value in
            "\(format(rect.x + Double(index) * step)),\(format(rect.maxY - rect.height * value))"
        }
        var output = ""
        if chart.style == .area {
            let areaPoints = points.joined(separator: " ")
                + " \(format(rect.maxX)),\(format(rect.maxY)) \(format(rect.x)),\(format(rect.maxY))"
            output += "\(indent)<polygon points=\"\(areaPoints)\" fill=\"\(cssColor(chart.color))\" fill-opacity=\"0.25\"/>\n"
        }
        output += "\(indent)<polyline points=\"\(points.joined(separator: " "))\" fill=\"none\" stroke=\"\(cssColor(chart.color))\" stroke-width=\"\(format(chart.lineWidth))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
        return output
    }

    private static func textElement(_ text: ResolvedText, in rect: Rect) -> String {
        let anchor: String
        let x: Double
        switch text.alignment {
        case .leading: anchor = "start"; x = rect.x
        case .center: anchor = "middle"; x = rect.midX
        case .trailing: anchor = "end"; x = rect.maxX
        }
        // A chosen family wins over the design, and the design's stack becomes
        // its fallback. Reading `family` only in the `.standard` branch meant a
        // rounded-design token with a custom family silently rendered as the
        // generic rounded stack here while the app drew the real face.
        let family: String
        let designStack: String
        switch text.font.design {
        case .monospaced: designStack = "ui-monospace, SFMono-Regular, monospace"
        case .rounded: designStack = "ui-rounded, system-ui, sans-serif"
        case .serif: designStack = "ui-serif, Georgia, serif"
        case .standard: designStack = "system-ui, -apple-system, sans-serif"
        }
        if let custom = text.font.family {
            family = "\(escape(custom)), \(designStack)"
        } else {
            family = designStack
        }
        let spacing = text.letterSpacing != 0 ? " letter-spacing=\"\(format(text.letterSpacing))\"" : ""
        return "<text x=\"\(format(x))\" y=\"\(format(rect.midY))\" text-anchor=\"\(anchor)\" dominant-baseline=\"central\" font-family=\"\(family)\" font-size=\"\(format(text.font.size))\" font-weight=\"\(cssWeight(text.font.weight))\"\(spacing) fill=\"\(cssColor(text.color))\">\(escape(text.text))</text>"
    }

    private static func gaugeElements(_ gauge: ResolvedGauge, in rect: Rect, indent: String) -> String {
        if let arc = gauge.arc {
            // Drawn into the centred square on the smaller side, matching the
            // SwiftUI backend — a ring stretched to a wide layer is an ellipse.
            let side = min(rect.width, rect.height)
            let originX = rect.x + (rect.width - side) / 2
            let originY = rect.y + (rect.height - side) / 2
            let width = arc.lineWidth * side
            let cap = arc.roundCap ? "round" : "butt"
            func scaled(_ commands: [PathCommand]) -> String {
                pathDescription(commands, in: Rect(x: originX, y: originY, width: side, height: side))
            }
            var output = "\(indent)<path d=\"\(scaled(arc.track))\" fill=\"none\" stroke=\"\(cssColor(gauge.track))\" stroke-width=\"\(format(width))\" stroke-linecap=\"\(cap)\"/>\n"
            if !arc.progress.isEmpty {
                output += "\(indent)<path d=\"\(scaled(arc.progress))\" fill=\"none\" stroke=\"\(cssColor(gauge.tint))\" stroke-width=\"\(format(width))\" stroke-linecap=\"\(cap)\"/>\n"
            }
            return output
        }
        switch gauge.style {
        case .bar:
            let radius = rect.height / 2
            let filledWidth = rect.width * gauge.fraction
            var output = "\(indent)<rect x=\"\(format(rect.x))\" y=\"\(format(rect.y))\" width=\"\(format(rect.width))\" height=\"\(format(rect.height))\" rx=\"\(format(radius))\" fill=\"\(cssColor(gauge.track))\"/>\n"
            if filledWidth > 0 {
                output += "\(indent)<rect x=\"\(format(rect.x))\" y=\"\(format(rect.y))\" width=\"\(format(max(filledWidth, rect.height)))\" height=\"\(format(rect.height))\" rx=\"\(format(radius))\" fill=\"\(cssColor(gauge.tint))\"/>\n"
            }
            return output
        case .ring:
            let radius = min(rect.width, rect.height) / 2 - gauge.lineWidth / 2
            let circumference = 2 * Double.pi * radius
            let dash = circumference * gauge.fraction
            var output = "\(indent)<circle cx=\"\(format(rect.midX))\" cy=\"\(format(rect.midY))\" r=\"\(format(radius))\" fill=\"none\" stroke=\"\(cssColor(gauge.track))\" stroke-width=\"\(format(gauge.lineWidth))\"/>\n"
            if gauge.fraction > 0 {
                // Start at 12 o'clock, sweep clockwise.
                output += "\(indent)<circle cx=\"\(format(rect.midX))\" cy=\"\(format(rect.midY))\" r=\"\(format(radius))\" fill=\"none\" stroke=\"\(cssColor(gauge.tint))\" stroke-width=\"\(format(gauge.lineWidth))\" stroke-linecap=\"round\" stroke-dasharray=\"\(format(dash)) \(format(circumference))\" transform=\"rotate(-90 \(format(rect.midX)) \(format(rect.midY)))\"/>\n"
            }
            return output
        }
    }

    // MARK: - Helpers

    private static func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e12 {
            return String(Int64(value))
        }
        return String(format: "%.2f", value)
    }

    private static func cssColor(_ color: ColorValue) -> String {
        if color.alpha >= 1 { return color.hexString }
        let r = Int((color.red * 255).rounded())
        let g = Int((color.green * 255).rounded())
        let b = Int((color.blue * 255).rounded())
        return "rgba(\(r),\(g),\(b),\(String(format: "%.3f", color.alpha)))"
    }

    /// `flood-color` carries no alpha (that's `flood-opacity`'s job), so the
    /// 8-digit form `hexString` produces would be rejected.
    private static func opaqueHex(_ color: ColorValue) -> String {
        var opaque = color
        opaque.alpha = 1
        return opaque.hexString
    }

    private static func cssWeight(_ weight: FontWeight) -> Int {
        switch weight {
        case .ultraLight: return 200
        case .thin: return 100
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        }
    }

    /// "cloud.sun.fill" → "☁︎"? We can't ship glyphs, so label with a short,
    /// recognizable fragment of the symbol name.
    private static func shortSymbolLabel(_ systemName: String) -> String {
        String(systemName.split(separator: ".").first.map(String.init) ?? systemName)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
