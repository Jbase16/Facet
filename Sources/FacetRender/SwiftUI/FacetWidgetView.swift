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

    private var styled: some View {
        content
            .opacity(node.opacity)
            .rotationEffect(.degrees(node.rotation))
            .modifier(ShadowModifier(shadow: node.shadow))
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
            Text(text.text)
                .font(font(for: text.font))
                .kerning(text.letterSpacing)
                .foregroundStyle(Color(text.color))
                .multilineTextAlignment(alignment(text.alignment))
                .lineLimit(text.maxLines)
                .minimumScaleFactor(0.5)
                .frame(width: node.rect.width, height: node.rect.height, alignment: frameAlignment(text.alignment))
                .offset(x: node.rect.x, y: node.rect.y)
        case .symbol(let symbol):
            Image(systemName: symbol.systemName)
                .font(.system(size: symbol.size, weight: weight(symbol.weight)))
                .foregroundStyle(Color(symbol.color))
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
            return AnyShapeStyle(RadialGradient(
                stops: stops.map { .init(color: Color($0.color), location: $0.position) },
                center: .center,
                startRadius: 0,
                endRadius: max(node.rect.width, node.rect.height) / 2
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
            return .custom(family, size: token.size)
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
    let shadow: ResolvedShadow?

    func body(content: Content) -> some View {
        if let shadow {
            content.shadow(
                color: Color(shadow.color),
                radius: shadow.radius,
                x: shadow.offsetX,
                y: shadow.offsetY
            )
        } else {
            content
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
