import SwiftUI
import FacetCore
import FacetData
import FacetRender

/// The canvas editor: direct manipulation over a live render of the actual
/// widget. Select, move, resize with handles, snap to guides, inspect,
/// reorder layers, edit the theme — with undo throughout.
///
/// Rendition awareness: `systemSmall` is the base design. In any other
/// rendition, geometry edits (move/resize/hide/font size) are recorded as
/// sparse `LayerPatch` overrides instead of mutating the base — the same
/// document adapts per surface rather than being rebuilt.
struct EditorView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var document: WidgetDocument
    @State private var selectedLayerID: UUID?
    @State private var rendition: RenditionKind = .systemSmall
    @State private var scheme: FacetCore.ColorScheme = .light
    @State private var undoStack: [WidgetDocument] = []
    @State private var lastUndoPush: Date = .distantPast
    @State private var dragStartFrame: LayerFrame?
    @State private var activeSheet: Sheet?
    @State private var snappedX = false
    @State private var snappedY = false

    private enum Sheet: String, Identifiable {
        case inspector, layers, theme
        var id: String { rawValue }
    }

    /// Canvas magnification: widgets are small; editing wants room.
    private let zoom: Double = 2
    private let snapStops: [Double] = [0, 0.25, 0.5, 0.75, 1]
    private let snapThreshold = 0.02

    init(document: WidgetDocument) {
        _document = State(initialValue: document)
    }

    var body: some View {
        VStack(spacing: 0) {
            canvasArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            controls
        }
        .navigationTitle(document.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(undoStack.isEmpty)

                Button("Save") {
                    store.save(document)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .inspector:
                if let id = selectedLayerID, let layer = document.root.firstLayer(withID: id) {
                    InspectorView(
                        layer: layer,
                        tokens: document.tokens,
                        scheme: scheme,
                        hasOverride: document.patch(for: id, in: rendition) != nil,
                        apply: { mutation in
                            mutateDocument { $0.root.updateFirstLayer(withID: id, mutation) }
                        },
                        clearOverride: { clearOverride(for: id) }
                    )
                    .presentationDetents([.medium, .large])
                }
            case .layers:
                LayerListView(
                    document: document,
                    selectedLayerID: selectedLayerID,
                    onSelect: { selectedLayerID = $0 },
                    mutate: { mutation in mutateDocument(mutation) }
                )
                .presentationDetents([.medium, .large])
            case .theme:
                ThemeEditorView(
                    tokens: document.tokens,
                    mutate: { mutation in
                        mutateDocument { mutation(&$0.tokens) }
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Canvas

    private var resolved: ResolvedWidget {
        DocumentResolver.resolve(
            document: document,
            snapshots: SampleData.snapshotSet(),
            environment: RenderEnvironment(rendition: rendition, colorScheme: scheme)
        )
    }

    private var canvasArea: some View {
        let widget = resolved
        return ZStack(alignment: .topLeading) {
            FacetWidgetView(widget: widget)
            snapGuides(widget)
            selectionOverlay(widget)
        }
        .frame(width: widget.canvas.width, height: widget.canvas.height)
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .scaleEffect(zoom)
        .contentShape(Rectangle())
        .gesture(tapToSelect(widget))
        .gesture(dragSelected(widget))
    }

    @ViewBuilder
    private func snapGuides(_ widget: ResolvedWidget) -> some View {
        if snappedX {
            Rectangle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: 0.75, height: widget.canvas.height)
                .offset(x: currentSnapPosition(widget).x)
        }
        if snappedY {
            Rectangle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: widget.canvas.width, height: 0.75)
                .offset(y: currentSnapPosition(widget).y)
        }
    }

    private func currentSnapPosition(_ widget: ResolvedWidget) -> (x: Double, y: Double) {
        guard let id = selectedLayerID, let node = findNode(widget.root, layerID: id) else { return (0, 0) }
        return (node.rect.midX, node.rect.midY)
    }

    @ViewBuilder
    private func selectionOverlay(_ widget: ResolvedWidget) -> some View {
        if let id = selectedLayerID, let node = findNode(widget.root, layerID: id) {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .background(Color.accentColor.opacity(0.06))
                .frame(width: node.rect.width, height: node.rect.height)
                .offset(x: node.rect.x, y: node.rect.y)
                .allowsHitTesting(false)
            if document.patch(for: id, in: rendition) != nil {
                Text("override")
                    .font(.system(size: 6, weight: .bold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .offset(x: node.rect.x, y: node.rect.y - 8)
                    .allowsHitTesting(false)
            }
            ForEach(ResizeHandle.allCases, id: \.self) { handle in
                handleView(handle, node: node, in: widget)
            }
        }
    }

    // MARK: - Resize handles

    private enum ResizeHandle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var unit: (x: Double, y: Double) {
            switch self {
            case .topLeft: return (0, 0)
            case .top: return (0.5, 0)
            case .topRight: return (1, 0)
            case .right: return (1, 0.5)
            case .bottomRight: return (1, 1)
            case .bottom: return (0.5, 1)
            case .bottomLeft: return (0, 1)
            case .left: return (0, 0.5)
            }
        }

        /// Which axes this handle resizes (edges resize one, corners both).
        var affects: (width: Bool, height: Bool) {
            switch self {
            case .top, .bottom: return (false, true)
            case .left, .right: return (true, false)
            default: return (true, true)
            }
        }

        /// Direction sign so dragging outward always grows the layer.
        var sign: (x: Double, y: Double) {
            (unit.x == 0 ? -1 : 1, unit.y == 0 ? -1 : 1)
        }
    }

    private func handleView(_ handle: ResizeHandle, node: RenderNode, in widget: ResolvedWidget) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.2))
            .frame(width: 7, height: 7)
            .offset(
                x: node.rect.x + node.rect.width * handle.unit.x - 3.5,
                y: node.rect.y + node.rect.height * handle.unit.y - 3.5
            )
            .gesture(resizeGesture(handle, in: widget))
    }

    private func resizeGesture(_ handle: ResizeHandle, in widget: ResolvedWidget) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard let id = selectedLayerID else { return }
                if dragStartFrame == nil {
                    pushUndo()
                    dragStartFrame = effectiveFrame(of: id)
                }
                guard let start = dragStartFrame,
                      let parentRect = parentRect(of: id, in: widget) else { return }
                var frame = start
                let dx = (value.translation.width / zoom) / parentRect.width * handle.sign.x
                let dy = (value.translation.height / zoom) / parentRect.height * handle.sign.y
                if handle.affects.width {
                    frame.width = min(max(start.width + dx, 0.02), 1)
                }
                if handle.affects.height {
                    frame.height = min(max(start.height + dy, 0.02), 1)
                }
                setFrame(frame, for: id)
            }
            .onEnded { _ in dragStartFrame = nil }
    }

    // MARK: - Gestures

    private func tapToSelect(_ widget: ResolvedWidget) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            let x = value.location.x / zoom
            let y = value.location.y / zoom
            selectedLayerID = hitTest(widget.root, x: x, y: y)?.layerID
        }
    }

    private func dragSelected(_ widget: ResolvedWidget) -> some Gesture {
        DragGesture(minimumDistance: 3).onChanged { value in
            guard let id = selectedLayerID else { return }
            if dragStartFrame == nil {
                pushUndo()
                dragStartFrame = effectiveFrame(of: id)
            }
            guard let start = dragStartFrame,
                  let parentRect = parentRect(of: id, in: widget) else { return }
            let dx = (value.translation.width / zoom) / parentRect.width
            let dy = (value.translation.height / zoom) / parentRect.height
            var frame = start
            frame.x = min(max(start.x + dx, 0), 1)
            frame.y = min(max(start.y + dy, 0), 1)

            snappedX = false
            snappedY = false
            for stop in snapStops {
                if abs(frame.x - stop) < snapThreshold {
                    frame.x = stop
                    snappedX = true
                }
                if abs(frame.y - stop) < snapThreshold {
                    frame.y = stop
                    snappedY = true
                }
            }
            setFrame(frame, for: id)
        }
        .onEnded { _ in
            dragStartFrame = nil
            snappedX = false
            snappedY = false
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Rendition", selection: $rendition) {
                Text("Small").tag(RenditionKind.systemSmall)
                Text("Medium").tag(RenditionKind.systemMedium)
                Text("Large").tag(RenditionKind.systemLarge)
                Text("Lock ◯").tag(RenditionKind.accessoryCircular)
                Text("Lock ▭").tag(RenditionKind.accessoryRectangular)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 14) {
                Picker("Scheme", selection: $scheme) {
                    Text("Light").tag(FacetCore.ColorScheme.light)
                    Text("Dark").tag(FacetCore.ColorScheme.dark)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)

                Spacer()

                AddLayerMenu { layer in
                    addLayer(layer)
                }

                Button {
                    activeSheet = .layers
                } label: {
                    Image(systemName: "square.3.layers.3d")
                }

                Button {
                    activeSheet = .theme
                } label: {
                    Image(systemName: "paintpalette")
                }

                Button {
                    activeSheet = .inspector
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(selectedLayerID == nil)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Editing machinery

    /// All document mutations funnel through here so undo stays coherent.
    /// Rapid slider streams coalesce into one undo step per second.
    private func mutateDocument(_ mutation: (inout WidgetDocument) -> Void) {
        pushUndo()
        mutation(&document)
    }

    private func pushUndo() {
        let now = Date()
        if now.timeIntervalSince(lastUndoPush) > 1 {
            undoStack.append(document)
            if undoStack.count > 80 { undoStack.removeFirst() }
            lastUndoPush = now
        }
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        document = previous
        lastUndoPush = .distantPast
    }

    private func addLayer(_ layer: Layer) {
        mutateDocument { document in
            let target = selectedLayerID.flatMap { selected -> UUID? in
                guard let selectedLayer = document.root.firstLayer(withID: selected),
                      case .container = selectedLayer.content else { return nil }
                return selected
            } ?? document.root.id
            document.root.insert(layer, intoContainer: target)
        }
        selectedLayerID = layer.id
    }

    /// The frame the user is currently looking at: the override's, when one
    /// exists for this rendition, else the base frame.
    private func effectiveFrame(of layerID: UUID) -> LayerFrame? {
        if let patch = document.patch(for: layerID, in: rendition), let frame = patch.frame {
            return frame
        }
        return document.root.firstLayer(withID: layerID)?.frame
    }

    /// Geometry edits land on the base design in systemSmall, and as a
    /// rendition override everywhere else.
    private func setFrame(_ frame: LayerFrame, for layerID: UUID) {
        if rendition == .systemSmall {
            document.root.updateFirstLayer(withID: layerID) { $0.frame = frame }
        } else {
            var patches = document.overrides[rendition] ?? []
            if let index = patches.firstIndex(where: { $0.layerID == layerID }) {
                patches[index].frame = frame
            } else {
                patches.append(LayerPatch(layerID: layerID, frame: frame))
            }
            document.overrides[rendition] = patches
        }
    }

    private func clearOverride(for layerID: UUID) {
        mutateDocument { document in
            document.overrides[rendition]?.removeAll { $0.layerID == layerID }
            if document.overrides[rendition]?.isEmpty == true {
                document.overrides.removeValue(forKey: rendition)
            }
        }
    }

    // MARK: - Hit testing

    /// Topmost (last-drawn) leaf node containing the point.
    private func hitTest(_ node: RenderNode, x: Double, y: Double) -> RenderNode? {
        for child in node.children.reversed() {
            if let hit = hitTest(child, x: x, y: y) { return hit }
        }
        let inside = x >= node.rect.x && x <= node.rect.maxX
            && y >= node.rect.y && y <= node.rect.maxY
        if inside, node.children.isEmpty { return node }
        return nil
    }

    private func findNode(_ node: RenderNode, layerID: UUID) -> RenderNode? {
        if node.layerID == layerID { return node }
        for child in node.children {
            if let found = findNode(child, layerID: layerID) { return found }
        }
        return nil
    }

    /// The rect of the container that lays out `layerID`, so gesture deltas
    /// can be normalized into the layer's coordinate space.
    private func parentRect(of layerID: UUID, in widget: ResolvedWidget) -> Rect? {
        func search(_ node: RenderNode) -> Rect? {
            for child in node.children {
                if child.layerID == layerID { return node.rect }
                if let found = search(child) { return found }
            }
            return nil
        }
        return search(widget.root) ?? widget.canvas
    }
}

/// The add-layer palette.
struct AddLayerMenu: View {
    let onAdd: (Layer) -> Void

    var body: some View {
        Menu {
            ForEach(NewLayerFactory.kinds, id: \.self) { kind in
                Button {
                    if let layer = NewLayerFactory.make(kind) {
                        onAdd(layer)
                    }
                } label: {
                    Label(kind, systemImage: NewLayerFactory.make(kind)?.contentSymbolName ?? "plus")
                }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
        }
    }
}
