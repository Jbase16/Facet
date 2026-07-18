import Foundation
import FacetCore
import FacetData

/// Turns `(document, data, environment)` into a concrete render tree.
/// Pure and deterministic — the editor preview, the SVG debug renderer, and
/// the widget extension all call exactly this, so previews are truthful.
public struct DocumentResolver {
    private let document: WidgetDocument
    private let environment: RenderEnvironment
    private let context: ResolutionContext
    private var diagnostics: [RenderDiagnostic] = []

    public static func resolve(
        document: WidgetDocument,
        snapshots: SnapshotSet,
        environment: RenderEnvironment
    ) -> ResolvedWidget {
        var resolver = DocumentResolver(document: document, snapshots: snapshots, environment: environment)
        let canvas = Rect(x: 0, y: 0, width: environment.canvasWidth, height: environment.canvasHeight)
        let root = resolver.resolveLayer(document.root, in: canvas)
            ?? RenderNode(
                layerID: document.root.id,
                name: document.root.name,
                rect: canvas,
                kind: .group(background: nil)
            )
        return ResolvedWidget(root: root, canvas: canvas, diagnostics: resolver.diagnostics)
    }

    private init(document: WidgetDocument, snapshots: SnapshotSet, environment: RenderEnvironment) {
        self.document = document
        self.environment = environment
        self.context = ResolutionContext(snapshots: snapshots, environment: environment)
    }

    // MARK: - Layer resolution

    private mutating func resolveLayer(_ layer: Layer, in parentRect: Rect) -> RenderNode? {
        var frame = layer.frame
        var hidden = layer.isHidden
        var opacity = layer.style.opacity
        var fontSizeOverride: Double?

        if let patch = document.patch(for: layer.id, in: environment.rendition) {
            if let patchedFrame = patch.frame { frame = patchedFrame }
            if let patchedHidden = patch.isHidden { hidden = patchedHidden }
            if let patchedOpacity = patch.opacity { opacity = patchedOpacity }
            fontSizeOverride = patch.fontSize
        }
        guard !hidden else { return nil }

        let rect = Rect(
            x: parentRect.x + frame.x * parentRect.width - frame.width * parentRect.width / 2,
            y: parentRect.y + frame.y * parentRect.height - frame.height * parentRect.height / 2,
            width: frame.width * parentRect.width,
            height: frame.height * parentRect.height
        )

        let kind: RenderNode.Kind
        var children: [RenderNode] = []

        switch layer.content {
        case .text(let content):
            kind = .text(resolveText(content, layer: layer, fontSizeOverride: fontSizeOverride))
        case .symbol(let content):
            var resolved = ResolvedSymbol(
                systemName: content.systemName,
                color: resolveColor(content.color),
                size: fontSizeOverride ?? content.size,
                weight: content.weight
            )
            if environment.rendition.isAccessory { resolved.color = accessoryColor(resolved.color) }
            kind = .symbol(resolved)
        case .shape(let content):
            kind = .shape(ResolvedShape(
                kind: content.kind,
                fill: resolveFill(content.fill),
                strokeColor: content.strokeColor.map { resolveColor($0) },
                strokeWidth: content.strokeWidth
            ))
        case .image(let content):
            kind = .image(ResolvedImage(assetName: content.assetName, contentMode: content.contentMode))
        case .gauge(let content):
            kind = .gauge(resolveGauge(content, layer: layer))
        case .line(let content):
            var color = resolveColor(content.color)
            if environment.rendition.isAccessory { color = accessoryColor(color) }
            kind = .line(ResolvedLine(color: color, thickness: content.thickness, dash: content.dash))
        case .chart(let content):
            kind = .chart(resolveChart(content, layer: layer))
        case .container(let content):
            kind = .group(background: content.background.map { resolveFill($0) })
            children = resolveChildren(content, in: rect)
        }

        return RenderNode(
            layerID: layer.id,
            name: layer.name,
            rect: rect,
            opacity: opacity,
            rotation: layer.style.rotation,
            cornerRadius: layer.style.cornerRadius,
            shadow: layer.style.shadow.map {
                ResolvedShadow(
                    color: resolveColor($0.color),
                    radius: $0.radius,
                    offsetX: $0.offsetX,
                    offsetY: $0.offsetY
                )
            },
            kind: kind,
            children: children
        )
    }

    private mutating func resolveChildren(_ container: ContainerContent, in rect: Rect) -> [RenderNode] {
        let content = rect.insetBy(container.padding)
        switch container.layout {
        case .absolute:
            return container.children.compactMap { resolveLayer($0, in: content) }

        case .overlay:
            return container.children.compactMap { child in
                var centered = child
                centered.frame.x = 0.5
                centered.frame.y = 0.5
                return resolveLayer(centered, in: content)
            }

        case .horizontal, .vertical:
            let isHorizontal = container.layout == .horizontal
            let visible = container.children.filter { child in
                let patch = document.patch(for: child.id, in: environment.rendition)
                return !(patch?.isHidden ?? child.isHidden)
            }
            guard !visible.isEmpty else { return [] }

            let mainAvailable = isHorizontal ? content.width : content.height
            let mainSizes = visible.map { child -> Double in
                (isHorizontal ? child.frame.width : child.frame.height) * mainAvailable
            }
            let totalMain = mainSizes.reduce(0, +) + container.spacing * Double(visible.count - 1)
            var cursor = (mainAvailable - totalMain) / 2

            let crossFactor: Double
            switch container.alignment ?? .center {
            case .start: crossFactor = 0
            case .center: crossFactor = 0.5
            case .end: crossFactor = 1
            }

            var nodes: [RenderNode] = []
            for (child, mainSize) in zip(visible, mainSizes) {
                let crossSize = (isHorizontal ? child.frame.height * content.height
                                             : child.frame.width * content.width)
                let cell: Rect
                if isHorizontal {
                    cell = Rect(
                        x: content.x + cursor,
                        y: content.y + (content.height - crossSize) * crossFactor,
                        width: mainSize,
                        height: crossSize
                    )
                } else {
                    cell = Rect(
                        x: content.x + (content.width - crossSize) * crossFactor,
                        y: content.y + cursor,
                        width: crossSize,
                        height: mainSize
                    )
                }
                // The child fills the cell computed for it: its normalized
                // frame already spent its meaning on sizing the cell.
                var filled = child
                filled.frame = .full
                if let node = resolveLayer(filled, in: cell) {
                    nodes.append(node)
                }
                cursor += mainSize + container.spacing
            }
            return nodes
        }
    }

    // MARK: - Content resolution

    private mutating func resolveText(
        _ content: TextContent,
        layer: Layer,
        fontSizeOverride: Double?
    ) -> ResolvedText {
        var text: String
        do {
            text = try Template.render(content.text, context: context)
        } catch {
            report(layer, "\(error)")
            text = "⚠︎"
        }
        switch content.textCase {
        case .uppercase: text = text.uppercased()
        case .lowercase: text = text.lowercased()
        case nil: break
        }
        var font = resolveFont(content.font)
        if let fontSizeOverride { font.size = fontSizeOverride }
        var color = resolveColor(content.color)
        if environment.rendition.isAccessory { color = accessoryColor(color) }
        return ResolvedText(
            text: text,
            font: font,
            color: color,
            alignment: content.alignment,
            maxLines: content.maxLines,
            letterSpacing: content.letterSpacing ?? 0
        )
    }

    private mutating func resolveChart(_ content: ChartContent, layer: Layer) -> ResolvedChart {
        var color = resolveColor(content.color)
        if environment.rendition.isAccessory { color = accessoryColor(color) }
        guard let values = context.snapshots.numberList(forVariable: content.dataPath),
              values.count >= 2 else {
            report(layer, "No list of numbers at '\(content.dataPath)'")
            return ResolvedChart(normalized: [], style: content.style, color: color, lineWidth: content.lineWidth)
        }
        let low = values.min()!
        let high = values.max()!
        let span = high - low
        let normalized = span == 0
            ? values.map { _ in 0.5 }
            : values.map { ($0 - low) / span }
        return ResolvedChart(
            normalized: normalized,
            style: content.style,
            color: color,
            lineWidth: content.lineWidth
        )
    }

    private mutating func resolveGauge(_ content: GaugeContent, layer: Layer) -> ResolvedGauge {
        var fraction: Double
        do {
            fraction = try Evaluator.evaluate(content.value, context: context).asNumber()
        } catch {
            report(layer, "\(error)")
            fraction = 0
        }
        fraction = min(max(fraction, 0), 1)
        var tint = resolveColor(content.tint)
        var track = resolveColor(content.track)
        if environment.rendition.isAccessory {
            tint = accessoryColor(tint)
            track = accessoryColor(track)
        }
        return ResolvedGauge(
            fraction: fraction,
            style: content.style,
            tint: tint,
            track: track,
            lineWidth: content.lineWidth
        )
    }

    // MARK: - Token resolution

    private func resolveFill(_ fill: Fill) -> ResolvedFill {
        // Accessory surfaces are monochrome; collapse gradients to vibrant white.
        if environment.rendition.isAccessory {
            return .solid(accessoryColor(primaryColor(of: fill)))
        }
        switch fill {
        case .color(let ref):
            return .solid(resolveColor(ref))
        case .linearGradient(let gradient):
            return .linearGradient(stops: resolveStops(gradient.stops), angle: gradient.angle)
        case .radialGradient(let gradient):
            return .radialGradient(stops: resolveStops(gradient.stops))
        }
    }

    private func resolveStops(_ stops: [GradientStop]) -> [ResolvedGradientStop] {
        stops
            .sorted { $0.position < $1.position }
            .map { ResolvedGradientStop(position: $0.position, color: resolveColor($0.color)) }
    }

    private func primaryColor(of fill: Fill) -> ColorValue {
        switch fill {
        case .color(let ref): return resolveColor(ref)
        case .linearGradient(let gradient), .radialGradient(let gradient):
            return gradient.stops.first.map { resolveColor($0.color) } ?? .black
        }
    }

    private func resolveColor(_ ref: ColorRef) -> ColorValue {
        switch ref {
        case .literal(let color):
            return color
        case .token(let name):
            guard let token = document.tokens.colors[name] else {
                // Unmistakably-wrong magenta beats silently rendering black.
                return ColorValue(red: 1, green: 0, blue: 1)
            }
            return token.resolved(for: environment.colorScheme)
        }
    }

    private func resolveFont(_ ref: FontRef) -> FontToken {
        switch ref {
        case .literal(let font):
            return font
        case .token(let name):
            return document.tokens.fonts[name] ?? FontToken(size: 15)
        }
    }

    /// Lock Screen accessories render vibrant/monochrome: keep alpha, drop hue.
    private func accessoryColor(_ color: ColorValue) -> ColorValue {
        ColorValue(red: 1, green: 1, blue: 1, alpha: color.alpha)
    }

    private mutating func report(_ layer: Layer, _ message: String) {
        diagnostics.append(RenderDiagnostic(layerID: layer.id, layerName: layer.name, message: message))
    }
}
