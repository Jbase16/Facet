#if canImport(SwiftUI)
import SwiftUI
import FacetCore

/// Renders a resolved node tree in SwiftUI. Used verbatim by the editor
/// preview and the widget extension: same resolver, same view, no drift.
public struct FacetWidgetView: View {
    private let widget: ResolvedWidget

    public init(widget: ResolvedWidget) {
        self.widget = widget
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            NodeView(node: widget.root)
        }
        .frame(width: widget.canvas.width, height: widget.canvas.height, alignment: .topLeading)
        .clipped()
    }
}

private struct NodeView: View {
    let node: RenderNode

    var body: some View {
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
                style: StrokeStyle(lineWidth: line.thickness, lineCap: .round, dash: line.dash ?? [])
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

/// Host apps register how document image assets load (from the document's
/// asset bundle in the App Group container).
public struct ImageAssetView: View {
    @Environment(\.facetImageProvider) private var provider
    let assetName: String
    let contentMode: ImageContent.ContentMode

    public var body: some View {
        if let image = provider?(assetName) {
            image
                .resizable()
                .aspectRatio(contentMode: contentMode == .fit ? .fit : .fill)
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}

public extension EnvironmentValues {
    @Entry var facetImageProvider: (@Sendable (String) -> Image?)? = nil
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
