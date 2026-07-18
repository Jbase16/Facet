import SwiftUI
import FacetCore
import FacetData
import FacetRender

/// The canvas editor. Direct manipulation over a live render of the actual
/// widget: what you drag is what ships. V1 scope: select, move, inspect,
/// per-rendition preview, undo — the foundation the full tool grows on.
struct EditorView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var document: WidgetDocument
    @State private var selectedLayerID: UUID?
    @State private var rendition: RenditionKind = .systemSmall
    @State private var scheme: FacetCore.ColorScheme = .light
    @State private var undoStack: [WidgetDocument] = []
    @State private var dragStartFrame: LayerFrame?
    @State private var showInspector = false

    /// Canvas magnification: widgets are small; editing wants room.
    private let zoom: Double = 2

    init(document: WidgetDocument) {
        _document = State(initialValue: document)
    }

    var body: some View {
        VStack(spacing: 0) {
            canvas
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
        .sheet(isPresented: $showInspector) {
            if let id = selectedLayerID, let layer = document.root.firstLayer(withID: id) {
                InspectorView(layer: layer) { mutation in
                    pushUndo()
                    document.root.updateFirstLayer(withID: id, mutation)
                }
                .presentationDetents([.medium])
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

    private var canvas: some View {
        let widget = resolved
        return ZStack(alignment: .topLeading) {
            FacetWidgetView(widget: widget)
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
    private func selectionOverlay(_ widget: ResolvedWidget) -> some View {
        if let id = selectedLayerID,
           let node = findNode(widget.root, layerID: id) {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .background(Color.accentColor.opacity(0.08))
                .frame(width: node.rect.width, height: node.rect.height)
                .offset(x: node.rect.x, y: node.rect.y)
                .allowsHitTesting(false)
        }
    }

    private func tapToSelect(_ widget: ResolvedWidget) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            let point = (x: value.location.x / zoom, y: value.location.y / zoom)
            selectedLayerID = hitTest(widget.root, x: point.x, y: point.y)?.layerID
            showInspector = selectedLayerID != nil ? showInspector : false
        }
    }

    private func dragSelected(_ widget: ResolvedWidget) -> some Gesture {
        DragGesture(minimumDistance: 3).onChanged { value in
            guard let id = selectedLayerID,
                  let layer = document.root.firstLayer(withID: id) else { return }
            if dragStartFrame == nil {
                pushUndo()
                dragStartFrame = layer.frame
            }
            guard let start = dragStartFrame,
                  let parentRect = parentRect(of: id, in: widget) else { return }
            // Convert the gesture delta (canvas points, zoomed) into the
            // layer's normalized coordinate space within its parent.
            let dx = (value.translation.width / zoom) / parentRect.width
            let dy = (value.translation.height / zoom) / parentRect.height
            document.root.updateFirstLayer(withID: id) { layer in
                layer.frame.x = min(max(start.x + dx, 0), 1)
                layer.frame.y = min(max(start.y + dy, 0), 1)
            }
        }
        .onEnded { _ in
            dragStartFrame = nil
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

            HStack {
                Picker("Scheme", selection: $scheme) {
                    Text("Light").tag(FacetCore.ColorScheme.light)
                    Text("Dark").tag(FacetCore.ColorScheme.dark)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Spacer()

                Button {
                    showInspector = true
                } label: {
                    Label("Inspect", systemImage: "slider.horizontal.3")
                }
                .disabled(selectedLayerID == nil)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Editing machinery

    private func pushUndo() {
        undoStack.append(document)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        document = previous
    }

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

    /// The rect of the container that lays out `layerID`, so drag deltas can
    /// be normalized. (Padding insets are folded into the parent rect only
    /// approximately in v1 — see SPEC M3.)
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

/// Per-layer property editing. V1 exposes the properties that cover most
/// remix edits; the full inspector tracks SPEC §4.1.
struct InspectorView: View {
    let layer: Layer
    let apply: ((inout Layer) -> Void) -> Void

    @State private var opacity: Double = 1
    @State private var text: String = ""
    @State private var expression: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Layer") {
                    LabeledContent("Name", value: layer.name)
                    VStack(alignment: .leading) {
                        Text("Opacity  \(Int(opacity * 100))%")
                        Slider(value: $opacity, in: 0...1) { editing in
                            if !editing {
                                apply { $0.style.opacity = opacity }
                            }
                        }
                    }
                }

                if case .text = layer.content {
                    Section("Text") {
                        TextField("Template", text: $text, axis: .vertical)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit(commitText)
                        Text("Wrap expressions in { }, e.g. {percent(battery.level)}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if case .gauge = layer.content {
                    Section("Gauge value") {
                        TextField("Expression (0–1)", text: $expression)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit(commitExpression)
                    }
                }
            }
            .navigationTitle(layer.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            opacity = layer.style.opacity
            if case .text(let content) = layer.content { text = content.text }
            if case .gauge(let content) = layer.content { expression = content.value }
        }
    }

    private func commitText() {
        // Validate before applying: bad templates degrade the render, so the
        // inspector refuses them at the door instead.
        guard (try? Template(parsing: text)) != nil else { return }
        apply {
            if case .text(var content) = $0.content {
                content.text = text
                $0.content = .text(content)
            }
        }
    }

    private func commitExpression() {
        guard (try? Expression.parse(expression)) != nil else { return }
        apply {
            if case .gauge(var content) = $0.content {
                content.value = expression
                $0.content = .gauge(content)
            }
        }
    }
}
