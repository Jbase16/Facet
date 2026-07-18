import SwiftUI
import FacetCore
import FacetData
import FacetRender

/// The home screen: your widgets, live-previewed with current data.
struct GalleryView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 20)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(store.documents) { document in
                        NavigationLink(value: document.id) {
                            GalleryCell(document: document)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                store.selectedForWidget = document.id
                            } label: {
                                Label("Show in Widget", systemImage: "square.grid.2x2")
                            }
                            Button {
                                store.duplicate(document)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            Button(role: .destructive) {
                                store.delete(document)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Facet")
            .navigationDestination(for: UUID.self) { id in
                if let document = store.documents.first(where: { $0.id == id }) {
                    EditorView(document: document)
                }
            }
            .refreshable {
                await store.refreshData()
            }
        }
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
