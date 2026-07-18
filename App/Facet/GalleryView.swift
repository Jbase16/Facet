import SwiftUI
import UniformTypeIdentifiers
import FacetCore
import FacetData
import FacetRender

/// The home screen: your widgets, live-previewed with current data.
struct GalleryView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    @State private var renamingDocument: WidgetDocument?
    @State private var renameText = ""
    @State private var importing = false
    @State private var importError: String?

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 20)]
    private static let facetType = UTType(filenameExtension: "facet", conformingTo: .json) ?? .json

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(store.documents) { document in
                        NavigationLink(value: document.id) {
                            GalleryCell(document: document)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { contextMenu(for: document) }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Facet")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        importing = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Button {
                        store.save(Self.blankDocument())
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
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
        }
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

    var body: some View {
        VStack(spacing: 10) {
            WidgetPreview(
                document: document,
                rendition: .systemSmall,
                colorScheme: colorScheme == .dark ? .dark : .light
            )
            .frame(width: 158, height: 158)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)

            HStack(spacing: 4) {
                Text(document.name)
                    .font(.footnote.weight(.medium))
                if store.selectedForWidget == document.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
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
