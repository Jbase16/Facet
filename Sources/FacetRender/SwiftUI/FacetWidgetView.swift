#if canImport(SwiftUI)
import SwiftUI
import FacetCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Renders a resolved node tree in SwiftUI. Used verbatim by the editor
/// preview and the widget extension: same resolver, same view, no drift.
/// `interactive` arms tap actions (Links + widgetURL) — the widget extension
/// passes true; the editor and gallery leave taps inert so canvas gestures
/// keep working.
public struct FacetWidgetView: View {
    private let widget: ResolvedWidget
    private let interactive: Bool

    public init(widget: ResolvedWidget, interactive: Bool = false) {
        self.widget = widget
        self.interactive = interactive
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            NodeView(node: widget.root)
        }
        .frame(width: widget.canvas.width, height: widget.canvas.height, alignment: .topLeading)
        .clipped()
        .environment(\.facetInteractive, interactive)
        .modifier(RootTapModifier(url: interactive ? firstTapURL(widget.root) : nil))
    }

    /// systemSmall widgets ignore per-view Links; the first tap action in
    /// z-order becomes the whole-widget URL so small sizes still act.
    private func firstTapURL(_ node: RenderNode) -> URL? {
        if let raw = node.tapURL, let url = URL(string: raw) { return url }
        for child in node.children {
            if let found = firstTapURL(child) { return found }
        }
        return nil
    }
}

private struct FacetInteractiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var facetInteractive: Bool {
        get { self[FacetInteractiveKey.self] }
        set { self[FacetInteractiveKey.self] = newValue }
    }
}

/// `.widgetURL` lives in WidgetKit; outside a widget process it's absent,
/// so the modifier degrades to a no-op.
private struct RootTapModifier: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        #if canImport(WidgetKit)
        content.widgetURL(url)
        #else
        content
        #endif
    }
}

private struct NodeView: View {
    @Environment(\.facetInteractive) private var interactive
    let node: RenderNode

    var body: some View {
        if interactive, let raw = node.tapURL, let url = URL(string: raw) {
            // Medium/large widgets honor per-layer Links; small falls back
            // to the root widgetURL applied above.
            Link(destination: url) { styled }
        } else {
            styled
        }
    }

    // Effect order, deliberately the same in SVGRenderer so previews stay
    // truthful. Colour grading acts on the drawn content; the mask cuts it
    // next, so everything after is computed from the masked silhouette — blur
    // softens the cut edge, and a photo clipped to a blob drops a blob-shaped
    // shadow; the border goes on after them so an outline stays crisp on a
    // blurred layer, and traces the layer rather than the cutout; inset
    // shadows sit just before the border because they belong to the layer's
    // surface and must rotate with it, unlike the outer ones;
    // scale/flip/rotation then move the finished layer; glow and shadow are
    // cast by the transformed silhouette in screen space, which keeps a
    // rotated layer's light direction fixed (and preserves how rotation +
    // shadow already rendered); opacity fades layer and shadow together; the
    // blend mode composites the result into what's beneath, so it is last.
    private var styled: some View {
        content
            .modifier(ColorAdjustModifier(adjust: node.colorAdjust))
            .modifier(MaskModifier(node: node))
            .modifier(BlurModifier(radius: node.blur))
            .modifier(InnerShadowsModifier(node: node))
            .modifier(BorderModifier(node: node))
            .modifier(TransformModifier(node: node))
            .modifier(GlowModifier(glow: node.glow))
            .modifier(ShadowModifier(shadows: node.outerShadows))
            .opacity(node.opacity)
            .modifier(BlendModeModifier(mode: node.blendMode))
    }

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .group(let background):
            ZStack(alignment: .topLeading) {
                if let background {
                    RoundedRectangle(cornerRadius: node.cornerRadius, style: .continuous)
                        .fill(shapeStyle(background))
                        .frame(width: node.rect.width, height: node.rect.height)
                        .offset(x: node.rect.x, y: node.rect.y)
                }
                ForEach(Array(node.children.enumerated()), id: \.element.layerID) { _, child in
                    NodeView(node: child)
                }
            }
        case .text(let text):
            // `foregroundStyle` before `frame`, so a gradient resolves against
            // the glyphs' own bounds rather than the layer's box — the same
            // bounding box SVG's `objectBoundingBox` gradient units use on a
            // `<text>` element. Styling after the frame would stretch the ramp
            // across the whole layer and a short label would read as flat.
            Text(text.text)
                .font(font(for: text.font))
                .kerning(text.letterSpacing)
                .foregroundStyle(shapeStyle(text.fill))
                .multilineTextAlignment(alignment(text.alignment))
                .lineLimit(text.maxLines)
                .minimumScaleFactor(0.5)
                .frame(width: node.rect.width, height: node.rect.height, alignment: frameAlignment(text.alignment))
                .offset(x: node.rect.x, y: node.rect.y)
        case .symbol(let symbol):
            Image(systemName: symbol.systemName)
                .font(.system(size: symbol.size, weight: weight(symbol.weight)))
                .foregroundStyle(shapeStyle(symbol.fill))
                .frame(width: node.rect.width, height: node.rect.height)
                .offset(x: node.rect.x, y: node.rect.y)
        case .shape(let shape):
            shapeView(shape)
                .frame(width: node.rect.width, height: node.rect.height)
                .offset(x: node.rect.x, y: node.rect.y)
        case .image(let image):
            // Asset loading is provided by the host app via ImageAssetProvider.
            ImageAssetView(assetName: image.assetName, contentMode: image.contentMode)
                .frame(width: node.rect.width, height: node.rect.height)
                .clipShape(RoundedRectangle(cornerRadius: node.cornerRadius, style: .continuous))
                .offset(x: node.rect.x, y: node.rect.y)
        case .gauge(let gauge):
            gaugeView(gauge)
                .frame(width: node.rect.width, height: node.rect.height)
                .offset(x: node.rect.x, y: node.rect.y)
        case .line(let line):
            Path { path in
                path.move(to: CGPoint(x: 0, y: node.rect.height / 2))
                path.addLine(to: CGPoint(x: node.rect.width, y: node.rect.height / 2))
            }
            .stroke(
                Color(line.color),
                style: StrokeStyle(
                    lineWidth: line.thickness,
                    lineCap: .round,
                    dash: (line.dash ?? []).map { CGFloat($0) }
                )
            )
            .frame(width: node.rect.width, height: node.rect.height)
            .offset(x: node.rect.x, y: node.rect.y)
        case .chart(let chart):
            chartView(chart)
                .frame(width: node.rect.width, height: node.rect.height)
                .offset(x: node.rect.x, y: node.rect.y)
        }
    }

    @ViewBuilder
    private func chartView(_ chart: ResolvedChart) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let count = chart.normalized.count
            if count >= 2 {
                switch chart.style {
                case .bars:
                    let gap = size.width * 0.15 / Double(count)
                    let barWidth = (size.width - gap * Double(count - 1)) / Double(count)
                    ForEach(Array(chart.normalized.enumerated()), id: \.offset) { index, value in
                        let height = max(size.height * value, barWidth * 0.5)
                        RoundedRectangle(cornerRadius: barWidth / 3, style: .continuous)
                            .fill(Color(chart.color))
                            .frame(width: barWidth, height: height)
                            .position(
                                x: Double(index) * (barWidth + gap) + barWidth / 2,
                                y: size.height - height / 2
                            )
                    }
                case .line, .area:
                    let step = size.width / Double(count - 1)
                    let points = chart.normalized.enumerated().map { index, value in
                        CGPoint(x: Double(index) * step, y: size.height * (1 - value))
                    }
                    if chart.style == .area {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: size.height))
                            for point in points { path.addLine(to: point) }
                            path.addLine(to: CGPoint(x: size.width, y: size.height))
                            path.closeSubpath()
                        }
                        .fill(Color(chart.color).opacity(0.25))
                    }
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(
                        Color(chart.color),
                        style: StrokeStyle(lineWidth: chart.lineWidth, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }

    /// Every unit here is a *fraction* of whatever the style is applied to, so
    /// one paint serves a shape filling the layer's rect and a line of text
    /// occupying a fraction of it — which is the only way the SVG backend's
    /// per-element `objectBoundingBox` gradients can be matched.
    private func shapeStyle(_ fill: ResolvedFill) -> AnyShapeStyle {
        switch fill {
        case .solid(let color):
            return AnyShapeStyle(Color(color))
        case .linearGradient(let stops, let angle):
            let radians = angle * .pi / 180
            let dx = cos(radians) / 2
            let dy = sin(radians) / 2
            return AnyShapeStyle(LinearGradient(
                stops: stops.map { .init(color: Color($0.color), location: $0.position) },
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
            ))
        case .radialGradient(let stops):
            // Elliptical, not circular. SVG's `objectBoundingBox` radial maps a
            // unit circle through the element's bounding box, so on a
            // non-square box it *stretches*; `RadialGradient(endRadius:)` takes
            // points and stays round, which put the two backends visibly out of
            // step on every wide or tall layer. `endRadiusFraction: 0.5` is
            // exactly SVG's default `r="50%"`.
            return AnyShapeStyle(EllipticalGradient(
                stops: stops.map { .init(color: Color($0.color), location: $0.position) },
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: 0.5
            ))
        }
    }

    @ViewBuilder
    private func shapeView(_ shape: ResolvedShape) -> some View {
        let fill = shapeStyle(shape.fill)
        let stroke = shape.strokeColor.map(Color.init)
        switch shape.kind {
        case .rectangle:
            RoundedRectangle(cornerRadius: node.cornerRadius, style: .continuous)
                .fill(fill)
                .overlay {
                    if let stroke, shape.strokeWidth > 0 {
                        RoundedRectangle(cornerRadius: node.cornerRadius, style: .continuous)
                            .strokeBorder(stroke, lineWidth: shape.strokeWidth)
                    }
                }
        case .circle:
            Circle().fill(fill).overlay {
                if let stroke, shape.strokeWidth > 0 {
                    Circle().strokeBorder(stroke, lineWidth: shape.strokeWidth)
                }
            }
        case .path:
            let outline = NormalizedPath(commands: shape.path ?? [])
            outline.fill(fill).overlay {
                if let stroke, shape.strokeWidth > 0 {
                    outline.stroke(stroke, lineWidth: shape.strokeWidth)
                }
            }
        case .capsule:
            Capsule().fill(fill).overlay {
                if let stroke, shape.strokeWidth > 0 {
                    Capsule().strokeBorder(stroke, lineWidth: shape.strokeWidth)
                }
            }
        }
    }

    @ViewBuilder
    private func gaugeView(_ gauge: ResolvedGauge) -> some View {
        if let arc = gauge.arc {
            // A gauge's coordinates describe a square, so it is drawn into the
            // square on the layer's smaller side and centred — otherwise a ring
            // on a wide layer would render as an ellipse.
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let stroke = StrokeStyle(
                    lineWidth: arc.lineWidth * side,
                    lineCap: arc.roundCap ? .round : .butt
                )
                ZStack {
                    NormalizedPath(commands: arc.track)
                        .stroke(Color(gauge.track), style: stroke)
                    NormalizedPath(commands: arc.progress)
                        .stroke(Color(gauge.tint), style: stroke)
                }
                .frame(width: side, height: side)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else {
            legacyGaugeView(gauge)
        }
    }

    @ViewBuilder
    private func legacyGaugeView(_ gauge: ResolvedGauge) -> some View {
        switch gauge.style {
        case .ring:
            ZStack {
                Circle()
                    .stroke(Color(gauge.track), lineWidth: gauge.lineWidth)
                Circle()
                    .trim(from: 0, to: gauge.fraction)
                    .stroke(Color(gauge.tint), style: StrokeStyle(lineWidth: gauge.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .padding(gauge.lineWidth / 2)
        case .bar:
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(gauge.track))
                    Capsule()
                        .fill(Color(gauge.tint))
                        .frame(width: max(proxy.size.width * gauge.fraction, proxy.size.height))
                }
            }
        }
    }

    private func font(for token: FontToken) -> Font {
        if let family = token.family {
            // Weight has to be chained on: `.custom` ignores the token's weight
            // entirely, so picking a family used to silently reset a bold label
            // to regular with nothing in the UI to explain it. (Design is a
            // system-font concept and genuinely doesn't apply to a named face.)
            return .custom(family, size: token.size).weight(weight(token.weight))
        }
        return .system(size: token.size, weight: weight(token.weight), design: design(token.design))
    }

    private func weight(_ weight: FontWeight) -> Font.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }

    private func design(_ design: FontDesign) -> Font.Design {
        switch design {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }

    private func alignment(_ alignment: FacetCore.TextAlignment) -> SwiftUI.TextAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func frameAlignment(_ alignment: FacetCore.TextAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

private struct ShadowModifier: ViewModifier {
    let shadows: [ResolvedShadow]

    func body(content: Content) -> some View {
        // Chained rather than merged: each `.shadow` casts from the result of
        // the last, which is what makes a light/dark pair read as one lit
        // object instead of two unrelated smudges.
        shadows.reduce(AnyView(content)) { view, shadow in
            AnyView(view.shadow(
                color: Color(shadow.color),
                radius: shadow.radius,
                x: shadow.offsetX,
                y: shadow.offsetY
            ))
        }
    }
}

/// Inset shadows, drawn over the layer and clipped to its own silhouette.
///
/// SwiftUI has no inset shadow for arbitrary views, so this uses the standard
/// construction: stroke the silhouette with a band twice the blur radius,
/// blur it, slide it, then clip back to the silhouette so only the half that
/// falls *inside* survives. The result hugs the inner edge on the side the
/// light comes from, which is what sells a dent.
///
/// Applied before `TransformModifier`, unlike glow and outer shadow: an inset
/// shadow is part of the layer's surface, so it has to rotate with the layer
/// rather than stay put in screen space.
private struct InnerShadowsModifier: ViewModifier {
    let node: RenderNode

    @ViewBuilder
    func body(content: Content) -> some View {
        let shadows = node.innerShadows
        if shadows.isEmpty {
            content
        } else {
            content.overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(shadows.enumerated()), id: \.offset) { _, shadow in
                        silhouette
                            .stroke(Color(shadow.color), lineWidth: max(shadow.radius, 0.5) * 2)
                            .blur(radius: shadow.radius)
                            .offset(x: shadow.offsetX, y: shadow.offsetY)
                            .frame(width: node.rect.width, height: node.rect.height)
                            .clipShape(silhouette)
                    }
                }
                // Same frame-then-offset placement the border and mask use:
                // `.offset` never moves layout bounds, so an overlay drawn
                // naively lands at the canvas origin.
                .frame(width: node.rect.width, height: node.rect.height)
                .offset(x: node.rect.x, y: node.rect.y)
                .allowsHitTesting(false)
            }
        }
    }

    /// The layer's own outline. Uses the mask's shape when there is one, so a
    /// blob-clipped layer gets a blob-shaped dent rather than a rounded-rect
    /// one floating inside it.
    private var silhouette: some InsettableShape {
        MaskOutline(mask: node.mask, cornerRadius: node.cornerRadius)
    }
}

/// The shape an inset shadow hugs: the mask if the layer has one, otherwise
/// the layer's rounded bounds. `InsettableShape` so it can be stroked.
private struct MaskOutline: InsettableShape {
    let mask: ResolvedMask?
    let cornerRadius: Double
    var insetAmount: Double = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard let mask, !mask.invert else {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: r)
        }
        switch mask.shape {
        case .rectangle:
            return RoundedRectangle(cornerRadius: mask.cornerRadius, style: .continuous).path(in: r)
        case .circle:
            return Circle().path(in: r)
        case .capsule:
            return Capsule(style: .continuous).path(in: r)
        case .path:
            return NormalizedPath(commands: mask.path ?? []).path(in: r)
        }
    }

    func inset(by amount: CGFloat) -> MaskOutline {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// A glow is a shadow with no offset. Separate modifier so a layer can carry
/// both a rim light and a cast shadow.
private struct GlowModifier: ViewModifier {
    let glow: ResolvedGlow?

    func body(content: Content) -> some View {
        if let glow {
            content.shadow(color: Color(glow.color), radius: glow.radius, x: 0, y: 0)
        } else {
            content
        }
    }
}

// Each of these short-circuits on the identity case: an unused effect must
// not cost an off-screen compositing pass in a widget extension living inside
// a ~30 MB budget.

private struct ColorAdjustModifier: ViewModifier {
    let adjust: ResolvedColorAdjust

    @ViewBuilder
    func body(content: Content) -> some View {
        if adjust.isIdentity {
            content
        } else {
            content
                .brightness(adjust.brightness)
                .contrast(adjust.contrast)
                .saturation(adjust.saturation)
                .hueRotation(.degrees(adjust.hueRotation))
        }
    }
}

private struct BlurModifier: ViewModifier {
    let radius: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if radius > 0 {
            content.blur(radius: radius)
        } else {
            content
        }
    }
}

private struct BlendModeModifier: ViewModifier {
    let mode: FacetCore.BlendMode

    @ViewBuilder
    func body(content: Content) -> some View {
        if mode == .normal {
            content
        } else {
            content.blendMode(swiftUIBlendMode(mode))
        }
    }

    private func swiftUIBlendMode(_ mode: FacetCore.BlendMode) -> SwiftUI.BlendMode {
        switch mode {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .darken: return .darken
        case .lighten: return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .difference: return .difference
        case .exclusion: return .exclusion
        case .hue: return .hue
        case .saturation: return .saturation
        case .color: return .color
        case .luminosity: return .luminosity
        case .plusLighter: return .plusLighter
        }
    }
}

/// The border is drawn as its own overlay placed with the same frame/offset
/// the content uses, because `.offset` doesn't move a view's layout bounds —
/// a plain `.overlay` would land at the node's unoffset origin.
private struct BorderModifier: ViewModifier {
    let node: RenderNode

    @ViewBuilder
    func body(content: Content) -> some View {
        if let border = node.border {
            content.overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: max(0, node.cornerRadius - border.inset), style: .continuous)
                    .strokeBorder(Color(border.color), lineWidth: border.width)
                    .frame(
                        width: max(0, node.rect.width - border.inset * 2),
                        height: max(0, node.rect.height - border.inset * 2)
                    )
                    .offset(x: node.rect.x + border.inset, y: node.rect.y + border.inset)
            }
        } else {
            content
        }
    }
}

/// Clips a layer to its mask.
///
/// Built with the same frame-then-offset placement `BorderModifier` uses, and
/// for the same reason: `.mask` aligns its content with the *layout* bounds,
/// which sit at the node's unoffset origin, so a mask drawn naively lands in
/// the top-left corner of the canvas instead of over the layer.
///
/// The mask view is opaque white where content survives. Inverting draws the
/// shape as a hole punched out of an opaque field with `.destinationOut`,
/// which needs its own `compositingGroup` or the blend escapes into the layer
/// beneath.
private struct MaskModifier: ViewModifier {
    let node: RenderNode

    @ViewBuilder
    func body(content: Content) -> some View {
        if let mask = node.mask {
            content.mask(alignment: .topLeading) {
                if mask.invert {
                    Rectangle()
                        .fill(.white)
                        .frame(width: node.rect.width, height: node.rect.height)
                        .offset(x: node.rect.x, y: node.rect.y)
                        .overlay(alignment: .topLeading) {
                            maskShape(mask)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                } else {
                    maskShape(mask)
                }
            }
        } else {
            content
        }
    }

    /// The shape itself, painted with the fade if there is one. A radial ramp
    /// is inscribed in the shape's rect so it reaches the corners the same way
    /// the SVG backend's `objectBoundingBox` radial does.
    @ViewBuilder
    private func maskShape(_ mask: ResolvedMask) -> some View {
        let shape = MaskShapeView(shape: mask.shape, path: mask.path, cornerRadius: mask.cornerRadius)
        Group {
            if let fade = mask.fade {
                shape.foregroundStyle(fadeStyle(fade))
            } else {
                shape.foregroundStyle(.white)
            }
        }
        .frame(width: mask.rect.width, height: mask.rect.height)
        .offset(x: mask.rect.x, y: mask.rect.y)
    }

    private func fadeStyle(_ fade: ResolvedMask.Fade) -> AnyShapeStyle {
        let stops = fade.stops.map {
            Gradient.Stop(color: .white.opacity($0.alpha), location: $0.position)
        }
        switch fade.kind {
        case .linear:
            // Same angle convention as GradientFill and the SVG backend:
            // 0 points right, 90 down.
            let radians = fade.angle * .pi / 180
            let dx = cos(radians) / 2
            let dy = sin(radians) / 2
            return AnyShapeStyle(LinearGradient(
                stops: stops,
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
            ))
        case .radial:
            // Elliptical, not circular, for the same reason `shapeStyle` is:
            // SVG's `<radialGradient>` defaults to objectBoundingBox units, so
            // the ramp stretches through the element's box. A point radius
            // would leave a vignette circular in SwiftUI and oval in SVG on
            // every non-square layer. `endRadiusFraction: 0.5` is exactly
            // SVG's `r="50%"`, and being a fraction it needs no rect at all.
            return AnyShapeStyle(EllipticalGradient(
                stops: stops,
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: 0.5
            ))
        }
    }
}

/// The mask's geometry as a fillable view, so `maskShape` can paint it with a
/// flat colour or a gradient without duplicating the shape switch.
private struct MaskShapeView: View {
    let shape: ShapeKind
    let path: [PathCommand]?
    let cornerRadius: Double

    var body: some View {
        switch shape {
        case .rectangle:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        case .circle:
            // `Circle`, not `Ellipse` — inscribed, matching both the shape
            // renderer above and SVG's `r = min(width, height) / 2`. An
            // ellipse stretches to fill, so on any non-square layer the two
            // backends would cut different silhouettes.
            Circle()
        case .capsule:
            Capsule(style: .continuous)
        case .path:
            NormalizedPath(commands: path ?? [])
        }
    }
}

/// Scale, flip and rotation as one affine pivoted on the layer's own centre.
/// `.rotationEffect` and `.scaleEffect` anchor on the *layout* frame, but
/// every node draws itself with `.offset` into absolute canvas coordinates,
/// so the layout centre is not the layer's centre — a rotated off-centre
/// layer orbits the canvas origin instead of spinning in place. Pivoting
/// explicitly is also what makes SwiftUI agree with SVGRenderer, which has
/// always rotated about `rect.midX/midY`.
private struct TransformModifier: ViewModifier {
    let node: RenderNode

    @ViewBuilder
    func body(content: Content) -> some View {
        let scaleX = node.scale * (node.flipHorizontal ? -1 : 1)
        let scaleY = node.scale * (node.flipVertical ? -1 : 1)
        if scaleX == 1, scaleY == 1, node.rotation == 0 {
            content
        } else {
            let centerX = node.rect.midX
            let centerY = node.rect.midY
            content.transformEffect(
                CGAffineTransform(translationX: centerX, y: centerY)
                    .rotated(by: node.rotation * .pi / 180)
                    .scaledBy(x: scaleX, y: scaleY)
                    .translatedBy(x: -centerX, y: -centerY)
            )
        }
    }
}

/// Draws resolved path commands, scaling normalized 0...1 coordinates into
/// whatever rect SwiftUI hands it. A `Shape` rather than a drawn `Path` so
/// it composes with `.fill`, `.stroke`, and clipping like any other shape.
struct NormalizedPath: Shape {
    let commands: [PathCommand]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        for command in commands {
            switch command {
            case .move(let x, let y):
                path.move(to: point(x, y))
            case .line(let x, let y):
                path.addLine(to: point(x, y))
            case .quad(let cx, let cy, let x, let y):
                path.addQuadCurve(to: point(x, y), control: point(cx, cy))
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                path.addCurve(to: point(x, y), control1: point(c1x, c1y), control2: point(c2x, c2y))
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}

/// Host apps register how document image assets load (from the document's
/// asset bundle in the App Group container).
public struct ImageAssetView: View {
    @Environment(\.facetImageProvider) private var provider
    let assetName: String
    let contentMode: ImageContent.ContentMode

    public var body: some View {
        if let image = provider?.load(assetName) {
            image
                .resizable()
                .aspectRatio(contentMode: contentMode == .fit ? .fit : .fill)
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}

// A manual environment key rather than @Entry: the macro flags stored
// closures as always-invalidating; identity comparison via a reference
// wrapper keeps environment updates cheap.
public final class FacetImageProvider: Equatable, Sendable {
    public let load: @Sendable (String) -> Image?

    public init(_ load: @escaping @Sendable (String) -> Image?) {
        self.load = load
    }

    public static func == (lhs: FacetImageProvider, rhs: FacetImageProvider) -> Bool {
        lhs === rhs
    }
}

private struct FacetImageProviderKey: EnvironmentKey {
    static let defaultValue: FacetImageProvider? = nil
}

public extension EnvironmentValues {
    var facetImageProvider: FacetImageProvider? {
        get { self[FacetImageProviderKey.self] }
        set { self[FacetImageProviderKey.self] = newValue }
    }
}

public extension Color {
    init(_ value: ColorValue) {
        self.init(
            .sRGB,
            red: value.red,
            green: value.green,
            blue: value.blue,
            opacity: value.alpha
        )
    }
}
#endif
