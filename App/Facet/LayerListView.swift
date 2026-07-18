import SwiftUI
import FacetCore

/// The layer panel: the document tree with selection, visibility, z-order,
/// duplicate, and delete. Reordering uses explicit up/down actions rather
/// than drag — unambiguous in a tree rendered as an indented list.
struct LayerListView: View {
    let document: WidgetDocument
    let selectedLayerID: UUID?
    let onSelect: (UUID) -> Void
    /// Applies a document mutation with undo recorded by the editor.
    let mutate: ((inout WidgetDocument) -> Void) -> Void

    var body: some View {
        NavigationStack {
            List {
                rows(for: document.root, depth: 0)
            }
            .listStyle(.plain)
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func rows(for layer: Layer, depth: Int) -> some View {
        row(for: layer, depth: depth)
        if case .container(let container) = layer.content {
            // Draw order is back-to-front; list shows front-most on top.
            ForEach(container.children.reversed()) { child in
                AnyView(rows(for: child, depth: depth + 1))
            }
        }
    }

    private func row(for layer: Layer, depth: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: layer.contentSymbolName)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name)
                    .font(.callout.weight(layer.id == selectedLayerID ? .semibold : .regular))
                Text(layer.contentTypeName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if layer.isHidden {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if layer.id == selectedLayerID {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.leading, CGFloat(depth) * 18)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(layer.id) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if layer.id != document.root.id {
                Button(role: .destructive) {
                    mutate { $0.root.removeFirstLayer(withID: layer.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button {
                mutate { $0.root.updateFirstLayer(withID: layer.id) { $0.isHidden.toggle() } }
            } label: {
                Label(layer.isHidden ? "Show" : "Hide", systemImage: layer.isHidden ? "eye" : "eye.slash")
            }
        }
        .contextMenu {
            if layer.id != document.root.id, let parent = document.root.parentContainerID(of: layer.id) {
                Button {
                    mutate { document in
                        var copy = layer.withFreshIDs()
                        copy.name = layer.name + " copy"
                        copy.frame.x = min(copy.frame.x + 0.04, 1)
                        copy.frame.y = min(copy.frame.y + 0.04, 1)
                        document.root.insert(copy, intoContainer: parent)
                    }
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button {
                    mutate { $0.root.moveChild(withID: layer.id, inContainer: parent, by: 1) }
                } label: {
                    Label("Bring Forward", systemImage: "square.2.layers.3d.top.filled")
                }
                Button {
                    mutate { $0.root.moveChild(withID: layer.id, inContainer: parent, by: -1) }
                } label: {
                    Label("Send Backward", systemImage: "square.2.layers.3d.bottom.filled")
                }
            }
        }
    }
}
