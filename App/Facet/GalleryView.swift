import SwiftUI
import UniformTypeIdentifiers
import FacetCore
import FacetData
import FacetRender

/// The home screen: your widgets, live-previewed with current data, on the
/// dark workspace surface the whole app lives on.
struct GalleryView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    @State private var renamingDocument: WidgetDocument?
    @State private var renameText = ""
    @State private var importing = false
    @State private var importError: String?
    @State private var showingSources = false
    @State private var showingGenerate = false
    @State private var path: [UUID] = []

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 18)]
    private static let facetType = UTType(filenameExtension: "facet", conformingTo: .json) ?? .json

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
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
                        store.save(Self.blankDocument())
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
                Text("\(store.documents.count) widgets")
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func contextMenu(for document: WidgetDocument) -> some View {
        Button {
            store.selectedForWidget = document.id
        } label: {
            Label("Show in Widget", systemImage: "square.grid.2x2")
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
                    FacetPill(text: "On widget", color: FacetUI.accent)
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
