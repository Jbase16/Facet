import PhotosUI
import SwiftUI
import FacetCore
import FacetData
import FacetRender

/// A whole home screen, edited in place: the wallpaper, every widget standing
/// on it, and where each one sits.
///
/// `HomeScreenPreview` answers "what does this widget look like where it will
/// live". This answers the question Facet is actually about — "do these
/// widgets look like one screen together" — which you cannot answer while
/// designing them one at a time in isolation.
///
/// The scene is edited on a private copy and handed back through `onSave`, so
/// abandoning the editor leaves the stored scene untouched.
struct SceneEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var scene: FacetScene
    private let onSave: (FacetScene) -> Void

    /// Every document in the library, so a placement can be drawn and the add
    /// sheet can list them without re-reading the container per row.
    @State private var library: [WidgetDocument] = []
    @State private var documentsByID: [UUID: WidgetDocument] = [:]

    @State private var selection: UUID?
    /// Live drag state. The placement keeps its stored slot until the drag
    /// ends — a rejected move must leave the model exactly as it was.
    @State private var draggingID: UUID?
    @State private var dragTranslation: CGSize = .zero

    @State private var wallpaper: UIImage?
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var pickingWallpaper = false
    @State private var addingWidget = false
    @State private var editingPalette = false
    @State private var scheme: FacetCore.ColorScheme = .dark
    @State private var notice: String?

    init(scene: FacetScene, onSave: @escaping (FacetScene) -> Void) {
        _scene = State(initialValue: scene)
        self.onSave = onSave
    }

    // Grid geometry lives in `HomeGrid` (App/Facet/HomeGrid.swift), shared with
    // the single-widget preview: a scene has to land on exactly the same grid,
    // or the two surfaces disagree about where a widget sits.

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                phone(in: geo.size)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { noticeToast }
            tools
        }
        .background(FacetUI.bg)
        .task {
            loadLibrary()
            // simctl launch booted com.JasonPhillips.app -facet-open-scene -facet-scene-palette
            if ProcessInfo.processInfo.arguments.contains("-facet-scene-palette") {
                editingPalette = true
            }
        }
        .task(id: scene.backdrop) { loadWallpaper() }
        .photosPicker(isPresented: $pickingWallpaper, selection: $wallpaperItem, matching: .images)
        .onChange(of: wallpaperItem) { importWallpaper() }
        .sheet(isPresented: $editingPalette) {
            // Only the placed widgets define what is worth overriding, so the
            // sheet is driven by the scene's own contents.
            ScenePaletteView(
                palette: $scene.palette,
                documents: scene.placements.compactMap { documentsByID[$0.documentID] }
            )
        }
        .sheet(isPresented: $addingWidget) {
            AddPlacementSheet(
                documents: library,
                palette: scene.palette,
                scheme: scheme,
                hasRoom: { scene.freeSlot(for: $0) != nil },
                onAdd: { document, rendition in add(document, rendition: rendition) }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scene").facetEyebrow()
                Text(scene.name)
                    .font(FacetUI.title(20))
                    .foregroundStyle(FacetUI.ink)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(FacetToolButton())
                .accessibilityLabel("Close")

                Button {
                    onSave(scene)
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(FacetToolButton(prominent: true))
                .accessibilityLabel("Save scene")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - The screen

    private func phone(in available: CGSize) -> some View {
        // Fit a phone-shaped frame into whatever room is left after the header
        // and tool bar have taken theirs.
        let scale = min(
            available.width / HomeGrid.screen.width,
            available.height / HomeGrid.screen.height
        )
        let snapshots = SampleData.snapshotSet()

        return ZStack(alignment: .topLeading) {
            wallpaperLayer
            // Above the wallpaper, below the widgets: tapping bare screen
            // clears the selection instead of doing nothing.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selection = nil }
            chrome(scale: scale)
            ForEach(scene.placements) { placement in
                widgetLayer(placement, snapshots: snapshots, scale: scale)
            }
            dropTarget(scale: scale)
        }
        .frame(width: HomeGrid.screen.width * scale, height: HomeGrid.screen.height * scale)
        .clipShape(RoundedRectangle(cornerRadius: 44 * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 44 * scale, style: .continuous)
                .strokeBorder(FacetUI.hairlineStrong, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .frame(width: available.width, height: available.height)
        .animation(.snappy(duration: 0.22), value: scene.placements)
    }

    @ViewBuilder
    private var wallpaperLayer: some View {
        if let wallpaper {
            Image(uiImage: wallpaper)
                .resizable()
                .scaledToFill()   // wallpapers fill the screen; never letterbox
        } else {
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.06)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    /// Status bar, icon placeholders, page dots and dock. Purely decorative, so
    /// none of it may swallow a tap meant for a widget or the deselect layer
    /// underneath.
    private func chrome(scale: Double) -> some View {
        ZStack(alignment: .topLeading) {
            statusBar(scale: scale)

            // Placeholders only where no placement stands — the icons are
            // context for the widgets, so they must not draw through them.
            ForEach(0..<HomeGrid.rows, id: \.self) { row in
                ForEach(0..<HomeGrid.columns, id: \.self) { column in
                    if !isCovered(column: column, row: row) {
                        iconPlaceholder(scale: scale)
                            .offset(
                                x: (HomeGrid.gridOrigin.x + Double(column) * HomeGrid.columnPitch) * scale,
                                y: (HomeGrid.gridOrigin.y + Double(row) * HomeGrid.rowPitch) * scale
                            )
                    }
                }
            }

            pageDots(scale: scale)
            dock(scale: scale)
        }
        .allowsHitTesting(false)
    }

    /// Rendered through the same resolver and view the extension uses, at the
    /// rendition's natural design size and then scaled — what you see is the
    /// real widget shrunk, not an approximation drawn small.
    private func widgetLayer(
        _ placement: ScenePlacement,
        snapshots: SnapshotSet,
        scale: Double
    ) -> some View {
        let size = placement.rendition.designSize
        let origin = cellOrigin(column: placement.column, row: placement.row)
        let isSelected = selection == placement.id
        let drag = draggingID == placement.id ? dragTranslation : .zero

        return ZStack(alignment: .topLeading) {
            content(for: placement, snapshots: snapshots)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                .scaleEffect(scale, anchor: .topLeading)
                // `scaleEffect` shrinks the drawing but not the layout box, so
                // this frame holds a box larger than itself — and its default
                // centre alignment would shove the widget up and left by half
                // the difference, hard enough to clip it off the bezel. Pinning
                // to topLeading keeps `origin` meaning the widget's true
                // top-left.
                .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                .allowsHitTesting(false)

            // Gestures ride on a plain rectangle over the widget rather than on
            // the render itself: a document can contain tappable layers, and a
            // tap here always means "select this block", never "press what's
            // drawn inside it".
            Color.clear
                .frame(width: size.width * scale, height: size.height * scale)
                .contentShape(Rectangle())
                .onTapGesture { selection = placement.id }
                .gesture(moveGesture(placement, scale: scale))
        }
        .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 21 * scale, style: .continuous)
                    .strokeBorder(FacetUI.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .offset(x: origin.x * scale + drag.width, y: origin.y * scale + drag.height)
        .zIndex(draggingID == placement.id ? 1 : 0)
    }

    @ViewBuilder
    private func content(for placement: ScenePlacement, snapshots: SnapshotSet) -> some View {
        if let document = documentsByID[placement.documentID] {
            // Themed by the scene, not by the widget: this is where a Scene
            // stops being a layout and starts being a look.
            let resolved = DocumentResolver.resolve(
                document: document.applying(palette: scene.palette),
                snapshots: snapshots,
                environment: RenderEnvironment(rendition: placement.rendition, colorScheme: scheme)
            )
            FacetWidgetView(widget: resolved)
                .environment(\.facetImageProvider, FacetImageProviderFactory.make(documentID: document.id))
        } else {
            // The document was deleted out from under the scene. Say so rather
            // than leaving a hole the user can't explain.
            ZStack {
                Rectangle().fill(FacetUI.surface.opacity(0.9))
                VStack(spacing: 6) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 22, weight: .light))
                    Text("Missing widget").font(FacetUI.caption)
                }
                .foregroundStyle(FacetUI.inkTertiary)
            }
        }
    }

    /// Where a dragged widget would land, drawn under the finger. Overlap
    /// rejection is otherwise invisible — the widget just springs back and the
    /// user has to guess why.
    @ViewBuilder
    private func dropTarget(scale: Double) -> some View {
        if let id = draggingID, let placement = scene.placements.first(where: { $0.id == id }) {
            let slot = snappedSlot(for: placement, translation: dragTranslation, scale: scale)
            let size = placement.rendition.designSize
            let origin = cellOrigin(column: slot.column, row: slot.row)
            RoundedRectangle(cornerRadius: 21 * scale, style: .continuous)
                .strokeBorder(
                    canPlace(placement, at: slot) ? FacetUI.accent : FacetUI.sample,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                )
                .frame(width: size.width * scale, height: size.height * scale)
                .offset(x: origin.x * scale, y: origin.y * scale)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Move

    private func moveGesture(_ placement: ScenePlacement, scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggingID != placement.id {
                    draggingID = placement.id
                    selection = placement.id
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                commitMove(placement, translation: value.translation, scale: scale)
                draggingID = nil
                dragTranslation = .zero
            }
    }

    /// The nearest legal slot to where the drag left the widget. Widgets snap
    /// to whole two-row bands, and anything wider than two columns starts at
    /// the left margin — the same rule `FacetScene.freeSlot` applies, and the
    /// same one iOS itself does.
    private func snappedSlot(
        for placement: ScenePlacement,
        translation: CGSize,
        scale: Double
    ) -> (column: Int, row: Int) {
        let span = placement.span
        // Measured from the grid origin, so it cancels out of both sides.
        let x = Double(placement.column) * HomeGrid.columnPitch + translation.width / scale
        let y = Double(placement.row) * HomeGrid.rowPitch + translation.height / scale

        let columnStep = 2
        let column = span.columns > columnStep
            ? 0
            : Int((x / (HomeGrid.columnPitch * Double(columnStep))).rounded()) * columnStep
        let row = Int((y / (HomeGrid.rowPitch * 2)).rounded()) * 2

        return (
            min(max(column, 0), HomeGrid.columns - span.columns),
            min(max(row, 0), HomeGrid.rows - span.rows)
        )
    }

    /// True when `placement` can occupy `slot` without landing on anything
    /// else. Its own block is excluded, or every widget would collide with
    /// where it already is.
    private func canPlace(_ placement: ScenePlacement, at slot: (column: Int, row: Int)) -> Bool {
        var candidate = placement
        candidate.column = slot.column
        candidate.row = slot.row
        return !scene.placements.contains { $0.id != placement.id && $0.overlaps(candidate) }
    }

    private func commitMove(_ placement: ScenePlacement, translation: CGSize, scale: Double) {
        guard let index = scene.placements.firstIndex(where: { $0.id == placement.id }) else { return }
        let slot = snappedSlot(for: placement, translation: translation, scale: scale)
        guard slot.column != placement.column || slot.row != placement.row else { return }
        // Refuse rather than stack: two widgets in one block is a state the
        // home screen cannot represent, so it must not be reachable here.
        guard canPlace(placement, at: slot) else {
            flash("Another widget is already there.")
            return
        }
        scene.placements[index].column = slot.column
        scene.placements[index].row = slot.row
    }

    // MARK: - Add, resize, remove

    private func add(_ document: WidgetDocument, rendition: RenditionKind) {
        guard let slot = scene.freeSlot(for: rendition) else {
            flash("This screen is full — remove a widget first.")
            return
        }
        let placement = ScenePlacement(
            documentID: document.id,
            rendition: rendition,
            column: slot.column,
            row: slot.row
        )
        scene.placements.append(placement)
        selection = placement.id
    }

    private func resizeSelection(to rendition: RenditionKind) {
        guard let id = selection,
              let index = scene.placements.firstIndex(where: { $0.id == id }) else { return }
        var candidate = scene.placements[index]
        guard candidate.rendition != rendition else { return }
        candidate.rendition = rendition

        // A bigger block can hang off the bottom or the right edge from where
        // the smaller one sat, so pull it back inside the grid before asking
        // about collisions.
        let span = candidate.span
        candidate.column = span.columns > 2 ? 0 : min(candidate.column, HomeGrid.columns - span.columns)
        candidate.row = min(candidate.row, HomeGrid.rows - span.rows)

        if canPlace(candidate, at: (candidate.column, candidate.row)) {
            scene.placements[index] = candidate
            return
        }

        // Growing into an occupied block is the common case, and springing
        // back to the old size is a worse answer than moving: ask the scene
        // where this size fits with the old block taken out of the picture.
        var rest = scene
        rest.placements.remove(at: index)
        guard let slot = rest.freeSlot(for: rendition) else {
            flash("No room for a \(Self.label(for: rendition).lowercased()) widget.")
            return
        }
        candidate.column = slot.column
        candidate.row = slot.row
        scene.placements[index] = candidate
        flash("Moved to fit.")
    }

    private func removeSelection() {
        guard let id = selection else { return }
        scene.placements.removeAll { $0.id == id }
        selection = nil
    }

    // MARK: - Tools

    private var tools: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkTertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                addingWidget = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(FacetToolButton(prominent: true))
            .accessibilityLabel("Add widget")

            Button {
                pickingWallpaper = true
            } label: {
                Image(systemName: wallpaper == nil ? "photo" : "photo.fill")
            }
            .buttonStyle(FacetToolButton())
            .accessibilityLabel("Choose wallpaper")

            Button {
                editingPalette = true
            } label: {
                Image(systemName: scene.palette.colors.isEmpty ? "paintpalette" : "paintpalette.fill")
            }
            .buttonStyle(FacetToolButton(prominent: !scene.palette.colors.isEmpty))
            .accessibilityLabel("Scene palette")

            Button {
                scheme = scheme == .dark ? .light : .dark
            } label: {
                Image(systemName: "circle.lefthalf.filled")
            }
            .buttonStyle(FacetToolButton())
            .accessibilityLabel("Toggle appearance")

            if selectedPlacement != nil {
                sizeMenu

                Button {
                    removeSelection()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(FacetToolButton())
                .accessibilityLabel("Remove widget")
            }
        }
        .padding(14)
        .facetPanel(radius: 20)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    /// Menus ignore `ButtonStyle`, so the label carries the chrome itself —
    /// the pattern `AddLayerMenu` established in the widget editor.
    private var sizeMenu: some View {
        Menu {
            ForEach(Self.sizes, id: \.self) { rendition in
                Button {
                    resizeSelection(to: rendition)
                } label: {
                    Label(
                        Self.label(for: rendition),
                        systemImage: selectedPlacement?.rendition == rendition ? "checkmark" : "square"
                    )
                }
            }
        } label: {
            Image(systemName: "aspectratio")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(FacetUI.ink)
                .frame(width: 34, height: 34)
                .background(FacetUI.raised)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(FacetUI.hairline, lineWidth: 1) }
        }
        .accessibilityLabel("Widget size")
    }

    private var selectedPlacement: ScenePlacement? {
        selection.flatMap { id in scene.placements.first { $0.id == id } }
    }

    private var statusText: String {
        guard let placement = selectedPlacement else {
            return scene.placements.isEmpty
                ? "Add a widget to start the scene."
                : "Tap a widget to select it, drag to move."
        }
        let name = documentsByID[placement.documentID]?.name ?? "Missing widget"
        return "\(name) · \(Self.label(for: placement.rendition))"
    }

    @ViewBuilder
    private var noticeToast: some View {
        if let notice {
            Text(notice)
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(FacetUI.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(FacetUI.hairline, lineWidth: 1))
                .padding(.top, 6)
                .transition(.opacity)
        }
    }

    private func flash(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            await MainActor.run {
                if notice == text { withAnimation { notice = nil } }
            }
        }
    }

    // MARK: - Wallpaper

    private func loadWallpaper() {
        guard let name = scene.backdrop else {
            wallpaper = nil
            return
        }
        // Assets are namespaced by owning-object id; a scene owns its wallpaper
        // the same way a document owns its image layers.
        wallpaper = AssetStore().load(name, for: scene.id)
    }

    private func importWallpaper() {
        guard let item = wallpaperItem else { return }
        let sceneID = scene.id
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let name = try? AssetStore().save(data, for: sceneID) else { return }
            await MainActor.run {
                scene.backdrop = name
                loadWallpaper()
            }
        }
    }

    // MARK: - Library

    private func loadLibrary() {
        library = SharedDocumentRepository().loadAll()
        // Two files can carry the same document id (a hand-copied `.facet`),
        // and a duplicate key would trap rather than merely look odd.
        documentsByID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Cells

    private func cellOrigin(column: Int, row: Int) -> CGPoint {
        CGPoint(
            x: HomeGrid.gridOrigin.x + Double(column) * HomeGrid.columnPitch,
            y: HomeGrid.gridOrigin.y + Double(row) * HomeGrid.rowPitch
        )
    }

    private func isCovered(column: Int, row: Int) -> Bool {
        scene.placements.contains { placement in
            let span = placement.span
            return column >= placement.column && column < placement.column + span.columns
                && row >= placement.row && row < placement.row + span.rows
        }
    }

    // MARK: - Chrome pieces (copied from HomeScreenPreview)

    private func statusBar(scale: Double) -> some View {
        HStack {
            Text("9:41")
                .font(.system(size: 15 * scale, weight: .semibold))
            Spacer()
            HStack(spacing: 5 * scale) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 15 * scale, height: 10 * scale)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 34 * scale)
        .offset(y: 20 * scale)
    }

    private func iconPlaceholder(scale: Double) -> some View {
        VStack(spacing: 6 * scale) {
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .fill(.white.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
                .frame(width: HomeGrid.iconGlyph * scale, height: HomeGrid.iconGlyph * scale)
            Capsule()
                .fill(.white.opacity(0.22))
                .frame(width: 34 * scale, height: 4 * scale)
        }
        // Width only: constraining the height too would push the glyph off its
        // row and break the alignment with the widget beside it.
        .frame(width: HomeGrid.iconCell * scale, alignment: .top)
    }

    private func pageDots(scale: Double) -> some View {
        HStack(spacing: 7 * scale) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == 0 ? 0.9 : 0.35))
                    .frame(width: 7 * scale, height: 7 * scale)
            }
        }
        .frame(maxWidth: .infinity)
        .offset(y: 690 * scale)
    }

    private func dock(scale: Double) -> some View {
        RoundedRectangle(cornerRadius: 34 * scale, style: .continuous)
            .fill(.white.opacity(0.14))
            .overlay {
                HStack(spacing: 30 * scale) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                            .fill(.white.opacity(0.2))
                            .frame(width: HomeGrid.iconGlyph * scale, height: HomeGrid.iconGlyph * scale)
                    }
                }
            }
            .frame(width: 354 * scale, height: 84 * scale)
            .offset(x: 18 * scale, y: 716 * scale)
    }

    // MARK: - Sizes

    /// Home-screen sizes only: a scene is a home screen, so Lock Screen
    /// accessories have nowhere to stand on it.
    fileprivate static let sizes: [RenditionKind] = [.systemSmall, .systemMedium, .systemLarge]

    fileprivate static func label(for rendition: RenditionKind) -> String {
        switch rendition {
        case .systemSmall: return "Small"
        case .systemMedium: return "Medium"
        case .systemLarge: return "Large"
        default: return "Small"
        }
    }
}

// MARK: - Add sheet

/// Pick a widget and a size. Availability is checked as the size changes rather
/// than on tap, so "the screen is full" is visible before you commit to a
/// document instead of arriving as a rejection afterwards.
private struct AddPlacementSheet: View {
    let documents: [WidgetDocument]
    /// The scene's palette, so every row previews the widget as it will look
    /// once placed rather than as it looks alone.
    let palette: ThemeTokens
    let scheme: FacetCore.ColorScheme
    let hasRoom: (RenditionKind) -> Bool
    let onAdd: (WidgetDocument, RenditionKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rendition: RenditionKind = .systemSmall

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add widget").facetEyebrow()
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(FacetToolButton())
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Picker("Size", selection: $rendition) {
                ForEach(SceneEditorView.sizes, id: \.self) { size in
                    Text(SceneEditorView.label(for: size)).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            if !hasRoom(rendition) {
                Text("No room for a \(SceneEditorView.label(for: rendition).lowercased()) widget on this screen.")
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.sample)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            if documents.isEmpty {
                Spacer()
                Text("No widgets yet — design one first.")
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.inkSecondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(documents) { document in
                            Button {
                                onAdd(document, rendition)
                                dismiss()
                            } label: {
                                row(document)
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasRoom(rendition))
                            .opacity(hasRoom(rendition) ? 1 : 0.4)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(FacetUI.bg)
        .presentationDetents([.medium, .large])
        .presentationBackground(FacetUI.bg)
    }

    private func row(_ document: WidgetDocument) -> some View {
        HStack(spacing: 12) {
            thumbnail(document)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.ink)
                    .lineLimit(1)
                Text(SceneEditorView.label(for: rendition))
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.inkTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(FacetUI.accent)
        }
        .padding(10)
        .facetPanel()
    }

    /// A live render rather than a stored image: the list has to show what the
    /// widget looks like *now*, and the resolver is cheap at this size.
    private func thumbnail(_ document: WidgetDocument) -> some View {
        let resolved = DocumentResolver.resolve(
            // The picker previews what the widget will look like *in this
            // scene*, so you choose against the palette you'll actually get.
            document: document.applying(palette: palette),
            snapshots: SampleData.snapshotSet(),
            environment: RenderEnvironment(rendition: .systemSmall, colorScheme: scheme)
        )
        return FacetWidgetView(widget: resolved)
            .environment(\.facetImageProvider, FacetImageProviderFactory.make(documentID: document.id))
            .frame(width: 158, height: 158)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .scaleEffect(52.0 / 158.0)
            .frame(width: 52, height: 52)
            .allowsHitTesting(false)
    }
}
