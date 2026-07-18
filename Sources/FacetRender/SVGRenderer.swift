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
        emit(widget.root, into: &body, indent: "  ")
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(format(canvas.width))" height="\(format(canvas.height))" \
        viewBox="0 0 \(format(canvas.width)) \(format(canvas.height))">
        <defs>
        <clipPath id="canvas"><rect x="0" y="0" width="\(format(canvas.width))" height="\(format(canvas.height))" rx="\(format(cornerRadius))"/></clipPath>
        </defs>
        <g clip-path="url(#canvas)">
        \(body)</g>
        </svg>
        """
    }

    private static func emit(_ node: RenderNode, into output: inout String, indent: String) {
        var attributes = ""
        if node.opacity < 1 {
            attributes += " opacity=\"\(format(node.opacity))\""
        }
        if node.rotation != 0 {
            attributes += " transform=\"rotate(\(format(node.rotation)) \(format(node.rect.midX)) \(format(node.rect.midY)))\""
        }
        if let shadow = node.shadow {
            attributes += " style=\"filter: drop-shadow(\(format(shadow.offsetX))px \(format(shadow.offsetY))px \(format(shadow.radius))px \(cssColor(shadow.color)))\""
        }
        output += "\(indent)<g\(attributes)>\n"

        switch node.kind {
        case .group(let background):
            if let background {
                output += "\(indent)  <rect x=\"\(format(node.rect.x))\" y=\"\(format(node.rect.y))\" width=\"\(format(node.rect.width))\" height=\"\(format(node.rect.height))\" rx=\"\(format(node.cornerRadius))\" fill=\"\(cssColor(background))\"/>\n"
            }
        case .shape(let shape):
            output += indent + "  " + shapeElement(shape, in: node) + "\n"
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
            emit(child, into: &output, indent: indent + "  ")
        }
        output += "\(indent)</g>\n"
    }

    private static func shapeElement(_ shape: ResolvedShape, in node: RenderNode) -> String {
        let rect = node.rect
        var stroke = ""
        if let strokeColor = shape.strokeColor, shape.strokeWidth > 0 {
            stroke = " stroke=\"\(cssColor(strokeColor))\" stroke-width=\"\(format(shape.strokeWidth))\""
        }
        switch shape.kind {
        case .circle:
            let radius = min(rect.width, rect.height) / 2
            return "<circle cx=\"\(format(rect.midX))\" cy=\"\(format(rect.midY))\" r=\"\(format(radius))\" fill=\"\(cssColor(shape.fill))\"\(stroke)/>"
        case .capsule:
            let radius = min(rect.width, rect.height) / 2
            return "<rect x=\"\(format(rect.x))\" y=\"\(format(rect.y))\" width=\"\(format(rect.width))\" height=\"\(format(rect.height))\" rx=\"\(format(radius))\" fill=\"\(cssColor(shape.fill))\"\(stroke)/>"
        case .rectangle:
            return "<rect x=\"\(format(rect.x))\" y=\"\(format(rect.y))\" width=\"\(format(rect.width))\" height=\"\(format(rect.height))\" rx=\"\(format(node.cornerRadius))\" fill=\"\(cssColor(shape.fill))\"\(stroke)/>"
        }
    }

    private static func textElement(_ text: ResolvedText, in rect: Rect) -> String {
        let anchor: String
        let x: Double
        switch text.alignment {
        case .leading: anchor = "start"; x = rect.x
        case .center: anchor = "middle"; x = rect.midX
        case .trailing: anchor = "end"; x = rect.maxX
        }
        let family: String
        switch text.font.design {
        case .monospaced: family = "ui-monospace, SFMono-Regular, monospace"
        case .rounded: family = "ui-rounded, system-ui, sans-serif"
        case .serif: family = "ui-serif, Georgia, serif"
        case .standard: family = text.font.family ?? "system-ui, -apple-system, sans-serif"
        }
        return "<text x=\"\(format(x))\" y=\"\(format(rect.midY))\" text-anchor=\"\(anchor)\" dominant-baseline=\"central\" font-family=\"\(family)\" font-size=\"\(format(text.font.size))\" font-weight=\"\(cssWeight(text.font.weight))\" fill=\"\(cssColor(text.color))\">\(escape(text.text))</text>"
    }

    private static func gaugeElements(_ gauge: ResolvedGauge, in rect: Rect, indent: String) -> String {
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
