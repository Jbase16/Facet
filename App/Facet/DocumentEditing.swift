import Foundation
import FacetCore

// Document-tree editing helpers for the editor. App-side on purpose:
// FacetCore stays a stable model/serialization layer.
extension Layer {
    /// Remove the first layer matching `id` anywhere below this layer.
    @discardableResult
    mutating func removeFirstLayer(withID id: UUID) -> Layer? {
        guard case .container(var container) = content else { return nil }
        if let index = container.children.firstIndex(where: { $0.id == id }) {
            let removed = container.children.remove(at: index)
            content = .container(container)
            return removed
        }
        for index in container.children.indices {
            if let removed = container.children[index].removeFirstLayer(withID: id) {
                content = .container(container)
                return removed
            }
        }
        return nil
    }

    /// The ID of the container that directly holds `id`.
    func parentContainerID(of id: UUID) -> UUID? {
        guard case .container(let container) = content else { return nil }
        if container.children.contains(where: { $0.id == id }) { return self.id }
        for child in container.children {
            if let found = child.parentContainerID(of: id) { return found }
        }
        return nil
    }

    /// Insert `layer` into the container with `containerID`. Falls back to
    /// appending; clamps the index.
    @discardableResult
    mutating func insert(_ layer: Layer, intoContainer containerID: UUID, at index: Int? = nil) -> Bool {
        var inserted = false
        updateFirstLayer(withID: containerID) { target in
            guard case .container(var container) = target.content else { return }
            let position = min(index ?? container.children.count, container.children.count)
            container.children.insert(layer, at: position)
            target.content = .container(container)
            inserted = true
        }
        return inserted
    }

    /// Move a direct child of `containerID` one step forward/back in z-order.
    mutating func moveChild(withID id: UUID, inContainer containerID: UUID, by offset: Int) {
        updateFirstLayer(withID: containerID) { target in
            guard case .container(var container) = target.content,
                  let index = container.children.firstIndex(where: { $0.id == id }) else { return }
            let destination = index + offset
            guard container.children.indices.contains(destination) else { return }
            container.children.swapAt(index, destination)
            target.content = .container(container)
        }
    }

    /// A deep copy with all-new IDs (recursively), for duplication.
    func withFreshIDs() -> Layer {
        var copy = self
        copy.id = UUID()
        if case .container(var container) = copy.content {
            container.children = container.children.map { $0.withFreshIDs() }
            copy.content = .container(container)
        }
        return copy
    }

    /// Editor label for the content type.
    var contentTypeName: String {
        switch content {
        case .text: return "Text"
        case .symbol: return "Symbol"
        case .shape: return "Shape"
        case .image: return "Image"
        case .gauge: return "Gauge"
        case .line: return "Line"
        case .chart: return "Chart"
        case .container: return "Group"
        }
    }

    var contentSymbolName: String {
        switch content {
        case .text: return "textformat"
        case .symbol: return "star"
        case .shape: return "square.on.circle"
        case .image: return "photo"
        case .gauge: return "gauge.with.needle"
        case .line: return "line.diagonal"
        case .chart: return "chart.xyaxis.line"
        case .container: return "square.stack.3d.up"
        }
    }
}

/// Factory defaults for the add-layer palette.
enum NewLayerFactory {
    static func make(_ kind: String) -> Layer? {
        switch kind {
        case "Text":
            return Layer(
                name: "Text",
                frame: LayerFrame(x: 0.5, y: 0.5, width: 0.7, height: 0.16),
                content: .text(TextContent(
                    text: "New text",
                    font: .literal(FontToken(size: 17, weight: .semibold, design: .rounded)),
                    color: .literal(.white)
                ))
            )
        case "Symbol":
            return Layer(
                name: "Symbol",
                frame: LayerFrame(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
                content: .symbol(SymbolContent(systemName: "star.fill", color: .literal(.white), size: 24))
            )
        case "Shape":
            return Layer(
                name: "Shape",
                frame: LayerFrame(x: 0.5, y: 0.5, width: 0.3, height: 0.3),
                content: .shape(ShapeContent(kind: .circle, fill: Fill.literal(ColorValue(hex: "#0A84FF")!)))
            )
        case "Gauge":
            return Layer(
                name: "Gauge",
                frame: LayerFrame(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                content: .gauge(GaugeContent(
                    value: "battery.level",
                    tint: .literal(ColorValue(hex: "#30D158")!),
                    track: .literal(ColorValue(hex: "#3A3A3C")!)
                ))
            )
        case "Line":
            return Layer(
                name: "Line",
                frame: LayerFrame(x: 0.5, y: 0.5, width: 0.7, height: 0.02),
                content: .line(LineContent(color: .literal(.white), thickness: 2))
            )
        case "Chart":
            return Layer(
                name: "Chart",
                frame: LayerFrame(x: 0.5, y: 0.6, width: 0.7, height: 0.3),
                content: .chart(ChartContent(dataPath: "health.weekSteps", style: .bars, color: .literal(ColorValue(hex: "#FF9F0A")!)))
            )
        case "Image":
            return Layer(
                name: "Image",
                frame: LayerFrame(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
                content: .image(ImageContent(assetName: "photo"))
            )
        case "Group":
            return Layer(
                name: "Group",
                frame: LayerFrame(x: 0.5, y: 0.5, width: 0.8, height: 0.4),
                content: .container(ContainerContent(layout: .horizontal, spacing: 6))
            )
        case "App Launcher":
            return launcher()
        case "Blob":
            return Layer(
                name: "Blob",
                frame: LayerFrame(x: 0.5, y: 0.5, width: 0.8, height: 0.8),
                content: .shape(ShapeContent(
                    kind: .path,
                    fill: Fill.literal(ColorValue(hex: "#1C1C2E")!),
                    pathData: BlobPath.path(.default)
                ))
            )
        default:
            return nil
        }
    }

    /// A themed app tile: rounded background, glyph, label, and a tap that
    /// deep-links to the app. Composed from ordinary layers rather than a
    /// bespoke content type — which means it inherits everything the
    /// renderer already does (theming, shapes, glows, per-size overrides)
    /// and stays editable piece by piece.
    static func launcher(
        name: String = "App",
        symbol: String = "app.dashed",
        urlScheme: String? = nil,
        tint: ColorValue = ColorValue(hex: "#FF7A3D")!
    ) -> Layer {
        Layer(
            name: name,
            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.34, height: 0.34),
            tapAction: urlScheme.map { TapAction(urlTemplate: $0) },
            content: .container(ContainerContent(
                layout: .absolute,
                background: Fill.literal(ColorValue(hex: "#141420")!),
                children: [
                    Layer(
                        name: "Glyph",
                        frame: LayerFrame(x: 0.5, y: 0.42, width: 0.5, height: 0.4),
                        content: .symbol(SymbolContent(
                            systemName: symbol, color: .literal(tint), size: 26
                        ))
                    ),
                    Layer(
                        name: "Label",
                        frame: LayerFrame(x: 0.5, y: 0.82, width: 0.9, height: 0.2),
                        content: .text(TextContent(
                            text: name,
                            font: .literal(FontToken(size: 9, weight: .medium)),
                            color: .literal(ColorValue(hex: "#B8B8C4")!)
                        ))
                    ),
                ]
            ))
        )
    }

    static let kinds = [
        "Text", "Symbol", "Shape", "Gauge", "Line", "Chart",
        "Image", "Group", "App Launcher", "Blob",
    ]
}
