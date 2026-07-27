import SwiftUI
import UniformTypeIdentifiers
import FacetCore
import FacetData
import FacetRender

/// The home screen: your widgets, live-previewed with current data, on the
/// dark workspace surface the whole app lives on.
struct GalleryView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(SceneStore.self) private var scenes
    @Environment(\.colorScheme) private var colorScheme

    @State private var editingScene: FacetScene?
    @State private var renamingScene: FacetScene?
    @State private var renamingDocument: WidgetDocument?
    @State private var renameText = ""
    @State private var importing = false
    @State private var importError: String?
    @State private var showingSources = false
    @State private var showingGenerate = false
    @State private var showingPlayground = false
    @State private var path: [UUID] = []

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 18)]
    private static let facetType = UTType(filenameExtension: "facet", conformingTo: .json) ?? .json

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    scenesStrip
                    sectionHeading("Widgets", count: store.documents.count)
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(store.documents) { document in
                            NavigationLink(value: document.id) {
                                GalleryCell(document: document)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { contextMenu(for: document) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(FacetUI.bg)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingGenerate = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .buttonStyle(FacetToolButton())

                    Button {
                        showingSources = true
                    } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(FacetToolButton())

                    Button {
                        importing = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(FacetToolButton())

                    Button {
                        // Create *and* open. Saving silently left you on the
                        // gallery with no sign anything had happened, so the
                        // natural response was to tap again — which is how a
                        // library ends up with nine "Untitled" widgets in it.
                        let document = Self.blankDocument()
                        store.save(document)
                        path = [document.id]
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(FacetToolButton(prominent: true))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let document = store.documents.first(where: { $0.id == id }) {
                    EditorView(document: document)
                }
            }
            .refreshable {
                await store.refreshData()
            }
            .alert("Rename widget", isPresented: Binding(
                get: { renamingDocument != nil },
                set: { if !$0 { renamingDocument = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if var document = renamingDocument, !renameText.isEmpty {
                        document.name = renameText
                        store.save(document)
                    }
                    renamingDocument = nil
                }
                Button("Cancel", role: .cancel) { renamingDocument = nil }
            }
            .alert("Rename scene", isPresented: Binding(
                get: { renamingScene != nil },
                set: { if !$0 { renamingScene = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if var scene = renamingScene, !renameText.isEmpty {
                        scene.name = renameText
                        scenes.save(scene)
                    }
                    renamingScene = nil
                }
                Button("Cancel", role: .cancel) { renamingScene = nil }
            }
            .alert("Import failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [Self.facetType, .json]) { result in
                importDocument(result)
            }
            .sheet(isPresented: $showingSources) {
                DataSourcesView()
            }
            // Full screen, not a sheet: the editor draws a phone-shaped screen
            // to scale, and a sheet's inset would shrink it below life size.
            .fullScreenCover(item: $editingScene) { scene in
                SceneEditorView(scene: scene) { scenes.save($0) }
            }
            .sheet(isPresented: $showingPlayground) {
                ShapePlayground()
            }
            .sheet(isPresented: $showingGenerate) {
                if #available(iOS 26, *) {
                    GenerateWidgetView { document in
                        store.save(document)
                        // Straight into the editor: the point is an editable
                        // result, so land the user on the canvas, not a tile.
                        path = [document.id]
                    }
                } else {
                    // Honest floor: on-device generation needs the iOS 26
                    // Foundation Models. No cloud fallback by design.
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundStyle(FacetUI.inkTertiary)
                        Text("AI generation needs iOS 26")
                            .font(FacetUI.label)
                            .foregroundStyle(FacetUI.ink)
                        Text("Facet designs widgets with Apple's on-device model — nothing leaves your phone.")
                            .font(FacetUI.caption)
                            .foregroundStyle(FacetUI.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .presentationDetents([.height(220)])
                    .presentationBackground(FacetUI.bg)
                }
            }
            .onAppear {
                // Headless smoke tests can open the sources sheet directly:
                // simctl launch booted com.JasonPhillips.app -facet-show-sources
                if ProcessInfo.processInfo.arguments.contains("-facet-show-sources") {
                    showingSources = true
                }
                if ProcessInfo.processInfo.arguments.contains("-facet-shape-playground") {
                    showingPlayground = true
                }
                // A scene laid out from the seeded library, straight into the
                // scene editor:
                //   simctl launch booted com.JasonPhillips.app -facet-open-scene
                if ProcessInfo.processInfo.arguments.contains("-facet-open-scene") {
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        editingScene = Self.demoScene(from: store.documents)
                    }
                }
                // Likewise for the editor (first document), after seeding.
                if ProcessInfo.processInfo.arguments.contains("-facet-open-editor") {
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        if let first = store.documents.first { path = [first.id] }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workspace").facetEyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Facet")
                    .font(FacetUI.title(30))
                    .kerning(-0.4)
                    .foregroundStyle(FacetUI.ink)
                Text("\(scenes.scenes.count) scenes · \(store.documents.count) widgets")
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    private func sectionHeading(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(FacetUI.title(17))
                .foregroundStyle(FacetUI.ink)
            Text("\(count)")
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkTertiary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Scenes

    /// Scenes come first because a scene is the thing you are actually making;
    /// the widgets below it are the parts. A horizontal strip keeps that order
    /// without pushing the widget grid off the first screen.
    private var scenesStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Scenes")
                    .font(FacetUI.title(17))
                    .foregroundStyle(FacetUI.ink)
                Text("whole home screens")
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.inkTertiary)
                Spacer(minLength: 0)
                Button {
                    let scene = FacetScene(name: "New Scene")
                    scenes.save(scene)
                    editingScene = scene
                } label: {
                    Label("New", systemImage: "plus")
                        .font(FacetUI.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FacetUI.accent)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(scenes.scenes) { scene in
                        Button {
                            editingScene = scene
                        } label: {
                            SceneCell(scene: scene, documents: store.documents)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { contextMenu(for: scene) }
                    }
                    if scenes.scenes.isEmpty {
                        emptyScenesHint
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var emptyScenesHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 20))
                .foregroundStyle(FacetUI.inkTertiary)
            Text("Compose a home screen")
                .font(FacetUI.label)
                .foregroundStyle(FacetUI.inkSecondary)
            Text("Place your widgets on a wallpaper and see them together.")
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
        .frame(height: 150)
        .facetPanel()
    }

    @ViewBuilder
    private func contextMenu(for scene: FacetScene) -> some View {
        Button {
            renameText = scene.name
            renamingScene = scene
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            scenes.duplicate(scene)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        // No Share yet, deliberately: a `.facetscene` stores document *ids*, so
        // on someone else's device it would open as a screen of empty slots.
        // Sharing needs a bundle carrying the referenced widgets with it.
        Button(role: .destructive) {
            scenes.delete(scene)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func contextMenu(for document: WidgetDocument) -> some View {
        Button {
            store.selectedForWidget = document.id
        } label: {
            // Each placed widget now picks its own design, so this is only the
            // default a newly added widget starts on — not "the" widget.
            Label("Use as default", systemImage: "square.grid.2x2")
        }
        Button {
            renameText = document.name
            renamingDocument = document
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            store.duplicate(document)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        if let url = exportURL(for: document) {
            ShareLink(item: url) {
                Label("Share .facet", systemImage: "square.and.arrow.up")
            }
        }
        Button(role: .destructive) {
            store.delete(document)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Write the document to a shareable temp file. `.facet` is portable
    /// JSON — this is the whole community-sharing story in one file.
    private func exportURL(for document: WidgetDocument) -> URL? {
        let slug = document.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(slug).facet")
        guard let data = try? FacetFile.encode(document), (try? data.write(to: url)) != nil else {
            return nil
        }
        return url
    }

    private func importDocument(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                var document = try FacetFile.decode(try Data(contentsOf: url))
                // Fresh identity: importing twice shouldn't overwrite.
                document.id = UUID()
                store.save(document)
            } catch {
                importError = "Not a valid .facet file (\(error.localizedDescription))"
            }
        }
    }

    /// A scene laid out by `freeSlot` itself, so the smoke test exercises the
    /// packing rules rather than hand-picked coordinates that can't fail.
    private static func demoScene(from documents: [WidgetDocument]) -> FacetScene {
        var scene = FacetScene(name: "Smoke Test")
        let wanted: [RenditionKind] = [.systemLarge, .systemMedium, .systemSmall, .systemSmall]
        for (index, rendition) in wanted.enumerated() {
            guard !documents.isEmpty,
                  let slot = scene.freeSlot(for: rendition) else { continue }
            let document = documents[index % documents.count]
            scene.placements.append(ScenePlacement(
                documentID: document.id,
                rendition: rendition,
                column: slot.column,
                row: slot.row
            ))
        }
        return scene
    }

    private static func blankDocument() -> WidgetDocument {
        WidgetDocument(
            name: "Untitled",
            tokens: ThemeTokens(
                colors: [
                    "background": ColorToken(light: ColorValue(hex: "#FFFFFF")!, dark: ColorValue(hex: "#1C1C1E")!),
                    "primary": ColorToken(light: ColorValue(hex: "#111111")!, dark: ColorValue(hex: "#F2F2F2")!),
                    "accent": ColorToken(light: ColorValue(hex: "#0A84FF")!, dark: ColorValue(hex: "#409CFF")!),
                ],
                fonts: [
                    "display": FontToken(size: 28, weight: .bold, design: .rounded),
                    "caption": FontToken(size: 11, weight: .medium),
                ]
            ),
            root: Layer(
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("background"),
                    children: [
                        Layer(
                            name: "Title",
                            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.8, height: 0.2),
                            content: .text(TextContent(
                                text: "New widget",
                                font: .token("display"),
                                color: .token("primary")
                            ))
                        ),
                    ]
                ))
            ),
            sources: []
        )
    }
}

/// A scene at thumbnail size: the real wallpaper with the real widgets on it,
/// on the same grid the editor uses. Rendered small rather than drawn as
/// abstract blocks — a scene is about how the pieces look *together*, so a
/// diagram of it would be answering a different question.
struct SceneCell: View {
    let scene: FacetScene
    let documents: [WidgetDocument]

    private static let height = 150.0
    private var scale: Double { Self.height / HomeGrid.screen.height }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                backdrop
                ForEach(scene.placements) { placement in
                    if let document = documents.first(where: { $0.id == placement.documentID }) {
                        widget(placement, document: document)
                    }
                }
            }
            .frame(
                width: HomeGrid.screen.width * scale,
                height: HomeGrid.screen.height * scale
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(FacetUI.hairline, lineWidth: 1)
            }

            HStack(spacing: 6) {
                Text(scene.name)
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(scene.placements.count)")
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.inkTertiary)
            }
            .padding(.top, 8)
            .frame(width: HomeGrid.screen.width * scale)
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if let name = scene.backdrop, let image = AssetStore().thumbnail(name, for: scene.id, maxPixelSize: 240) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [FacetUI.raised, FacetUI.bg],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func widget(_ placement: ScenePlacement, document: WidgetDocument) -> some View {
        let size = placement.rendition.designSize
        let origin = HomeGrid.origin(column: placement.column, row: placement.row)
        return WidgetPreview(document: document, rendition: placement.rendition, colorScheme: .dark)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            // `scaleEffect` shrinks the drawn pixels but leaves the layout size
            // alone, so the frame below has to restate the scaled size and pin
            // it top-leading — otherwise SwiftUI centres the shrunken render in
            // a full-size box and every widget lands offset by half its slack.
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .offset(x: origin.x * scale, y: origin.y * scale)
            .allowsHitTesting(false)
    }
}

struct GalleryCell: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    let document: WidgetDocument

    private var isOnWidget: Bool { store.selectedForWidget == document.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                DotGrid(spacing: 16)
                // Render at the true systemSmall canvas size, then scale the
                // whole thing down — clipping a live render is a lie.
                WidgetPreview(
                    document: document,
                    rendition: .systemSmall,
                    colorScheme: colorScheme == .dark ? .dark : .light
                )
                .frame(width: 158, height: 158)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(FacetUI.hairline, lineWidth: 1)
                }
                .scaleEffect(118.0 / 158.0)
                .frame(width: 118, height: 118)
            }
            .frame(height: 148)
            .frame(maxWidth: .infinity)
            .background(FacetUI.raised.opacity(0.5))

            Divider().overlay(FacetUI.hairline)

            HStack(spacing: 6) {
                Text(document.name)
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isOnWidget {
                    FacetPill(text: "Default", color: FacetUI.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .facetPanel()
        .overlay {
            if isOnWidget {
                RoundedRectangle(cornerRadius: FacetUI.cornerRadius, style: .continuous)
                    .strokeBorder(FacetUI.accent.opacity(0.55), lineWidth: 1.5)
            }
        }
    }
}

/// Resolve + render a document with the current shared-cache data. This is
/// the same pipeline the widget extension runs — previews can't lie.
struct WidgetPreview: View {
    let document: WidgetDocument
    let rendition: RenditionKind
    let colorScheme: FacetCore.ColorScheme

    var body: some View {
        let snapshots = mergedSnapshots()
        let resolved = DocumentResolver.resolve(
            document: document,
            snapshots: snapshots,
            environment: RenderEnvironment(rendition: rendition, colorScheme: colorScheme)
        )
        FacetWidgetView(widget: resolved)
            .environment(\.facetImageProvider, FacetImageProviderFactory.make(documentID: document.id))
    }

    /// Cached device data where we have it, sample data as fallback so a
    /// fresh install never shows an empty preview.
    private func mergedSnapshots() -> SnapshotSet {
        var set = SampleData.snapshotSet()
        let cached = AppGroup.snapshotStore.loadSet(sourceIDs: document.sources)
        for (_, snapshot) in cached.snapshots {
            set.insert(snapshot)
        }
        return set
    }
}
