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

    /// Whether `resolveLayer` would produce a node for this layer, without
    /// producing one. Stack layout needs the answer up front to size cells,
    /// and any divergence between the two shows up as a hole in the stack.
    ///
    /// Deliberately non-mutating: a bad `visibleWhen` is reported once, when
    /// `resolveLayer` actually runs, rather than twice.
    private func willRender(_ layer: Layer) -> Bool {
        let patch = document.patch(for: layer.id, in: environment.rendition)
        if patch?.isHidden ?? layer.isHidden { return false }
        if environment.detail == .simplified, layer.hiddenWhenSimplified { return false }
        if let condition = layer.visibleWhen, !condition.isEmpty {
            // Fail open on a broken expression, matching `resolveLayer`.
            guard let visible = try? Evaluator.evaluate(condition, context: context).asBool() else {
                return true
            }
            return visible
        }
        return true
    }

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

        // The system asked for less. Layers that opted in drop out entirely —
        // including their subtrees, since a container marked as decoration
        // takes its contents with it.
        if environment.detail == .simplified, layer.hiddenWhenSimplified { return nil }

        // Conditional visibility: expression-gated layers ("low battery
        // warning", "weekend banner"). Errors fail open with a diagnostic —
        // a typo in a condition must never blank the widget.
        if let condition = layer.visibleWhen, !condition.isEmpty {
            do {
                let visible = try Evaluator.evaluate(condition, context: context).asBool()
                guard visible else { return nil }
            } catch {
                report(layer, "visibleWhen: \(error)")
            }
        }

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
            // `resolveFill` already collapses a gradient to the accessory
            // monochrome, so the accessory rule lives in exactly one place.
            kind = .symbol(ResolvedSymbol(
                systemName: content.systemName,
                fill: resolveFill(content.fill),
                size: fontSizeOverride ?? content.size,
                weight: content.weight
            ))
        case .shape(let content):
            var outline: [PathCommand]?
            if content.kind == .path {
                do {
                    outline = try PathData.parse(content.pathData ?? "")
                } catch {
                    // Fall back to a rectangle rather than dropping the
                    // layer: a malformed path should be visible and
                    // diagnosable, not silently absent.
                    report(layer, "path: \(error)")
                }
            }
            kind = .shape(ResolvedShape(
                kind: outline == nil && content.kind == .path ? .rectangle : content.kind,
                fill: resolveFill(content.fill),
                strokeColor: content.strokeColor.map { resolveColor($0) },
                strokeWidth: content.strokeWidth,
                path: outline
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

        // Tap deep links are templates too, so a link can carry live data.
        var tapURL: String?
        if let action = layer.tapAction, !action.urlTemplate.isEmpty {
            do {
                tapURL = try Template.render(action.urlTemplate, context: context)
            } catch {
                report(layer, "tapAction: \(error)")
            }
        }

        let style = layer.style
        return RenderNode(
            layerID: layer.id,
            name: layer.name,
            rect: rect,
            opacity: opacity,
            rotation: style.rotation,
            cornerRadius: style.cornerRadius,
            shadows: style.shadows.map {
                ResolvedShadow(
                    color: resolveColor($0.color),
                    radius: max(0, $0.radius),
                    offsetX: $0.offsetX,
                    offsetY: $0.offsetY,
                    inset: $0.inset
                )
            },
            blendMode: style.blendMode ?? .normal,
            blur: clamp(style.blur, to: 0...50, default: 0),
            border: resolveBorder(style.border),
            scale: clamp(style.scale, to: 0.1...4, default: 1),
            flipHorizontal: style.flipHorizontal ?? false,
            flipVertical: style.flipVertical ?? false,
            colorAdjust: ResolvedColorAdjust(
                brightness: clamp(style.brightness, to: -1...1, default: 0),
                contrast: clamp(style.contrast, to: 0...4, default: 1),
                saturation: clamp(style.saturation, to: 0...4, default: 1),
                hueRotation: wrapDegrees(style.hueRotation)
            ),
            glow: resolveGlow(style.glow),
            mask: resolveMask(style.mask, in: rect, layer: layer),
            tapURL: tapURL,
            kind: kind,
            children: children
        )
    }

    // MARK: - Effects

    /// A zero-width border draws nothing, so drop it here rather than making
    /// every renderer test for it.
    private func resolveBorder(_ border: BorderStyle?) -> ResolvedBorder? {
        guard let border else { return nil }
        let width = clamp(border.width, to: 0...100, default: 0)
        guard width > 0 else { return nil }
        return ResolvedBorder(
            color: resolveColor(border.color),
            width: width,
            inset: clamp(border.inset, to: 0...100, default: 0)
        )
    }

    /// A zero-radius glow sits exactly behind its own layer — invisible, but
    /// still a filter pass. Drop it.
    private func resolveGlow(_ glow: GlowStyle?) -> ResolvedGlow? {
        guard let glow else { return nil }
        let radius = clamp(glow.radius, to: 0...50, default: 0)
        guard radius > 0 else { return nil }
        return ResolvedGlow(color: resolveColor(glow.color), radius: radius)
    }

    /// Flattens a mask into canvas coordinates. The mask's frame is normalized
    /// against the layer it clips, exactly like a child layer's frame, so the
    /// same mental model applies whether you are placing a layer or a window
    /// into it.
    private mutating func resolveMask(_ mask: LayerMask?, in rect: Rect, layer: Layer) -> ResolvedMask? {
        guard let mask, !mask.isNoOp else { return nil }

        let maskRect: Rect
        if let frame = mask.frame {
            maskRect = Rect(
                x: rect.x + frame.x * rect.width - frame.width * rect.width / 2,
                y: rect.y + frame.y * rect.height - frame.height * rect.height / 2,
                width: frame.width * rect.width,
                height: frame.height * rect.height
            )
        } else {
            maskRect = rect
        }

        // A path mask that won't parse would clip the layer away entirely.
        // Failing open — no mask at all — keeps a typo from blanking a widget,
        // the same rule `visibleWhen` and shape outlines already follow, and
        // the diagnostic makes it findable.
        var outline: [PathCommand]?
        if mask.shape == .path {
            guard let data = mask.pathData, !data.isEmpty else { return nil }
            do {
                outline = try PathData.parse(data)
            } catch {
                report(layer, "mask path: \(error)")
                return nil
            }
        }

        return ResolvedMask(
            shape: mask.shape,
            path: outline,
            cornerRadius: clamp(mask.cornerRadius, to: 0...500, default: 0),
            rect: maskRect,
            fade: resolveFade(mask.fade),
            invert: mask.invert
        )
    }

    private func resolveFade(_ fade: MaskFade?) -> ResolvedMask.Fade? {
        guard let fade, !fade.stops.isEmpty else { return nil }
        // Sorted because both backends emit stops in order and an out-of-order
        // list renders differently in each; clamped because an alpha outside
        // 0...1 is meaningless to one and an error to the other.
        let stops = fade.stops
            .map {
                ResolvedMask.FadeStop(
                    position: clamp($0.position, to: 0...1, default: 0),
                    alpha: clamp($0.alpha, to: 0...1, default: 1)
                )
            }
            .sorted { $0.position < $1.position }
        return ResolvedMask.Fade(
            kind: fade.kind,
            angle: wrapDegrees(fade.angle),
            stops: stops
        )
    }

    /// NaN/infinity fall back to the effect's default: one bad expression or
    /// a corrupt file must degrade a single property, not blank the widget.
    private func clamp(_ value: Double?, to range: ClosedRange<Double>, default fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Hue is periodic, so out-of-range is meaningful rather than wrong:
    /// normalize into 0..<360 instead of clamping and losing the intent.
    private func wrapDegrees(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
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
            // This filter has to ask exactly the question `resolveLayer` asks.
            // When it only checked `isHidden`, a layer dropped by `visibleWhen`
            // still got a slot in the stack, so a condition that went false
            // left a gap instead of closing it up.
            let visible = container.children.filter(willRender)
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
        return ResolvedText(
            text: text,
            font: font,
            fill: resolveFill(content.fill),
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
            lineWidth: content.lineWidth,
            arc: resolveGaugeArc(content, fraction: fraction, layer: layer)
        )
    }

    /// Builds the arc outline, but only for gauges that ask for it. The
    /// geometry works in a normalized square, so `lineWidth` (points here) is
    /// expressed against the layer's smaller side before handing it over.
    private mutating func resolveGaugeArc(
        _ content: GaugeContent,
        fraction: Double,
        layer: Layer
    ) -> ResolvedGaugeArc? {
        guard content.usesArcGeometry, content.style == .ring else { return nil }

        let side = min(
            layer.frame.width * environment.canvasWidth,
            layer.frame.height * environment.canvasHeight
        )
        guard side > 0 else { return nil }
        let normalizedWidth = min(max(content.lineWidth / side, 0.01), 0.5)
        let cap = content.cap ?? .butt

        let arc: GaugeArc
        if let segments = content.segments {
            arc = GaugeGeometry.segmented(
                value: fraction,
                segments: segments,
                startAngle: content.startAngle ?? 0,
                sweep: content.sweep ?? 360,
                direction: content.direction ?? .clockwise,
                gapDegrees: content.gapDegrees ?? 4,
                lineWidth: normalizedWidth,
                cap: cap
            )
        } else {
            arc = GaugeGeometry.ring(
                value: fraction,
                startAngle: content.startAngle ?? 0,
                sweep: content.sweep ?? 360,
                direction: content.direction ?? .clockwise,
                cap: cap,
                lineWidth: normalizedWidth
            )
        }

        guard let trackPath = try? PathData.parse(arc.track),
              let progressPath = try? PathData.parse(arc.progress) else {
            report(layer, "gauge: could not parse generated arc")
            return nil
        }
        return ResolvedGaugeArc(
            track: trackPath,
            progress: progressPath,
            roundCap: cap == .round,
            lineWidth: normalizedWidth
        )
    }

    // MARK: - Token resolution

    private func resolveFill(_ fill: Fill) -> ResolvedFill {
        // Accessory surfaces are monochrome; collapse gradients to vibrant
        // white. Deliberately a collapse and not a refusal: the Lock Screen
        // tints everything to the vibrant material anyway, so a gradient
        // headline degrades to the flat accessory colour it would have become
        // regardless, rather than rendering a gradient the system will not
        // honour. Alpha survives from the first stop, which is the one lever
        // an accessory layer still has. Text, symbols, shapes and container
        // backgrounds all arrive here, so the rule is stated once.
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
