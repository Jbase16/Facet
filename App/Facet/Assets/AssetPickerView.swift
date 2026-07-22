import PhotosUI
import SwiftUI
import UIKit

/// Picks the photo behind an image layer. Import is a commitment to the
/// document's library, not to a layer: the same photo can back several
/// layers, and coming back later should offer what's already there rather
/// than another trip through the photo picker (and another copy on disk).
///
/// Everything shown here is read back out of `AssetStore` after the
/// downsample, so the preview and the byte count are the real stored asset —
/// not the 12 MB original the user thinks they picked.
struct AssetPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let documentID: UUID
    /// Receives the asset name to write into `ImageContent.assetName`.
    let onSelect: (String) -> Void

    @State private var pickedItem: PhotosPickerItem?
    @State private var selectedName: String?
    @State private var entries: [AssetEntry] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var preview: UIImage?
    @State private var status: Status = .idle

    private let store = AssetStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    selectedPanel
                    importSection
                    librarySection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(FacetUI.bg)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(FacetToolButton())
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: use) {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(FacetToolButton(prominent: true))
                    .disabled(selectedName == nil)
                    .opacity(selectedName == nil ? 0.4 : 1)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { refresh() }
        .onChange(of: pickedItem) { _, item in
            Task { await importPicked(item) }
        }
        .onChange(of: selectedName) { _, _ in updatePreview() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Image Layer").facetEyebrow()
            Text("Photo")
                .font(FacetUI.title(26))
                .kerning(-0.3)
                .foregroundStyle(FacetUI.ink)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var selectedPanel: some View {
        if let selectedName, let entry = entries.first(where: { $0.name == selectedName }) {
            VStack(spacing: 0) {
                ZStack {
                    Rectangle().fill(FacetUI.raised)
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .frame(height: 190)

                Divider().overlay(FacetUI.hairline)

                HStack(spacing: 8) {
                    FacetPill(text: Self.sizeText(entry.bytes), color: FacetUI.live, icon: "arrow.down.circle")
                    Text(entry.name)
                        .font(FacetUI.caption)
                        .foregroundStyle(FacetUI.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button { remove(entry) } label: {
                        Text("Remove")
                            .font(FacetUI.caption)
                            .foregroundStyle(FacetUI.sample)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(FacetUI.sample.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
            .facetPanel(radius: 11)
        }
    }

    private var importSection: some View {
        section("Import") {
            PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 6) {
                    if status == .working {
                        ProgressView().tint(FacetUI.accent)
                    } else {
                        Image(systemName: "photo.badge.plus").font(FacetUI.caption)
                    }
                    Text(entries.isEmpty ? "Choose Photo" : "Choose Another Photo")
                }
                .font(FacetUI.label)
                .foregroundStyle(FacetUI.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(FacetUI.accentDim)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(status == .working)

            if case .failed(let message) = status {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message)
                }
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.sample)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .facetPanel(radius: 11)
            }

            Text("Photos are resized to \(AssetStore.maxPixelSize)px on the long edge before they're stored. Widgets get about 30 MB to render in — a full-resolution photo never makes it to the home screen.")
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkTertiary)
        }
    }

    private var librarySection: some View {
        section("In This Widget") {
            if entries.isEmpty {
                Text("No photos yet.")
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .facetPanel(radius: 11)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 78), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(entries) { entry in
                        tile(entry)
                    }
                }
                budgetReadout
            }
        }
    }

    private func tile(_ entry: AssetEntry) -> some View {
        let isSelected = entry.name == selectedName
        return Button {
            selectedName = entry.name
        } label: {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(FacetUI.raised)
                if let thumbnail = thumbnails[entry.name] {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                Text(Self.sizeText(entry.bytes))
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(FacetUI.bg.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(5)
            }
            .frame(height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isSelected ? FacetUI.accent : FacetUI.hairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    /// Weight is invisible until a widget starts getting evicted, so the
    /// document carries its own scale here.
    private var budgetReadout: some View {
        let total = entries.reduce(0) { $0 + $1.bytes }
        let fraction = min(1, Double(total) / Double(AssetStore.recommendedBudgetBytes))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(entries.count) photo\(entries.count == 1 ? "" : "s")")
                Spacer()
                Text(Self.sizeText(total))
            }
            .font(FacetUI.caption)
            .foregroundStyle(FacetUI.inkSecondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(FacetUI.raised)
                    Capsule()
                        .fill(fraction < 1 ? FacetUI.accent : FacetUI.sample)
                        .frame(width: max(2, proxy.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Actions

    private func use() {
        guard let selectedName else { return }
        onSelect(selectedName)
        dismiss()
    }

    @MainActor
    private func importPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        status = .working
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                status = .failed("That photo couldn't be read.")
                return
            }
            // Decoding and re-encoding a 48 MP photo is far too much work for
            // the main actor; only the resulting name comes back across.
            let store = self.store
            let documentID = self.documentID
            let name = try await Task.detached(priority: .userInitiated) {
                try store.save(data, for: documentID)
            }.value
            status = .idle
            selectedName = name
            refresh()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func remove(_ entry: AssetEntry) {
        try? store.delete(entry.name, for: documentID)
        FacetImageProviderFactory.invalidate(assetName: entry.name, documentID: documentID)
        thumbnails[entry.name] = nil
        if selectedName == entry.name { selectedName = nil }
        refresh()
    }

    private func refresh() {
        entries = store.list(for: documentID).map {
            AssetEntry(name: $0, bytes: store.byteCount(of: $0, for: documentID))
        }
        for entry in entries where thumbnails[entry.name] == nil {
            thumbnails[entry.name] = store.thumbnail(entry.name, for: documentID)
        }
        if let selectedName, !entries.contains(where: { $0.name == selectedName }) {
            self.selectedName = nil
        }
        updatePreview()
    }

    private func updatePreview() {
        preview = selectedName.flatMap { store.thumbnail($0, for: documentID, maxPixelSize: 640) }
    }

    // MARK: - Chrome

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).facetEyebrow()
            content()
        }
    }

    private static func sizeText(_ bytes: Int) -> String {
        bytes < 1024 * 1024
            ? "\(max(1, bytes / 1024)) KB"
            : String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

private struct AssetEntry: Identifiable, Equatable {
    let name: String
    let bytes: Int
    var id: String { name }
}

private enum Status: Equatable {
    case idle
    case working
    case failed(String)
}
