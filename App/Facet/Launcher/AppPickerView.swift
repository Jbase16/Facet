import SwiftUI

/// Picks the app a launcher tile opens.
///
/// Search stays pinned above the scroll so the list never scrolls away from
/// the field, and every row is a 56pt full-width target — this is a sheet
/// people poke at one-handed while holding the phone, not a settings pane.
struct AppPickerView: View {
    @Environment(\.dismiss) private var dismiss

    /// Highlights the row already wired to this layer, if any.
    var selectedID: String? = nil
    let onSelect: (CatalogApp) -> Void

    @State private var query = ""
    @State private var verifiedOnly = false
    @State private var showingCustom = false
    @State private var customName = ""
    @State private var customScheme = ""
    @State private var customSymbol = "app.dashed"
    @FocusState private var searchFocused: Bool

    private static let customSymbols = [
        "app.dashed", "square.grid.2x2.fill", "star.fill", "heart.fill",
        "bolt.fill", "music.note", "camera.fill", "cart.fill",
        "gamecontroller.fill", "book.fill", "car.fill", "bubble.left.fill",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        customSection
                        if isSearching {
                            searchResults
                        } else {
                            ForEach(sections) { section in
                                Section {
                                    ForEach(section.apps) { row($0) }
                                } header: {
                                    sectionHeader(section.category.displayName, count: section.apps.count)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
            .background(FacetUI.bg)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(FacetToolButton())
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Query

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Verified-first ordering comes from the catalog; this only trims.
    private var filtered: [CatalogApp] {
        let base = isSearching ? AppCatalog.search(query) : AppCatalog.all
        return verifiedOnly ? base.filter(\.isVerified) : base
    }

    /// Swift has no key path to a tuple element, so the catalog's
    /// `(Category, [CatalogApp])` pairs get an Identifiable wrapper for ForEach.
    private var sections: [CategorySection] {
        AppCatalog.grouped(filtered).map { CategorySection(category: $0.0, apps: $0.1) }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Launcher Tile").facetEyebrow()
                Text("Choose App")
                    .font(FacetUI.title(26))
                    .kerning(-0.3)
                    .foregroundStyle(FacetUI.ink)
            }

            searchField

            HStack(spacing: 8) {
                filterChip("All \(AppCatalog.all.count)", active: !verifiedOnly) {
                    verifiedOnly = false
                }
                filterChip("Verified \(AppCatalog.verified.count)", active: verifiedOnly) {
                    verifiedOnly = true
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(FacetUI.label)
                .foregroundStyle(searchFocused ? FacetUI.accent : FacetUI.inkTertiary)
            TextField("Search apps", text: $query)
                .font(FacetUI.label)
                .foregroundStyle(FacetUI.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(FacetUI.inkTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, query.isEmpty ? 12 : 2)
        .frame(minHeight: 48)
        .background(FacetUI.raised)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    searchFocused ? FacetUI.accent.opacity(0.5) : FacetUI.hairline,
                    lineWidth: 1
                )
        }
    }

    private func filterChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FacetUI.caption)
                .foregroundStyle(active ? FacetUI.accent : FacetUI.inkSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(active ? FacetUI.accentDim : FacetUI.raised)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        active ? FacetUI.accent.opacity(0.4) : FacetUI.hairline,
                        lineWidth: 1
                    )
                }
                // Chip reads as 36pt but the tap region clears 44.
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).facetEyebrow()
            Spacer()
            Text("\(count)")
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(FacetUI.bg)
    }

    // MARK: - Rows

    private func row(_ app: CatalogApp) -> some View {
        Button {
            onSelect(app)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                glyph(app.sfSymbol, tint: app.isVerified ? FacetUI.ink : FacetUI.inkSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(FacetUI.label)
                        .foregroundStyle(FacetUI.ink)
                    Text(app.isVerified ? app.urlScheme : "\(app.urlScheme) · unverified scheme")
                        .font(FacetUI.caption)
                        .foregroundStyle(app.isVerified ? FacetUI.inkTertiary : FacetUI.sample.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if app.id == selectedID {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FacetUI.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(FacetRowButton())
    }

    private func glyph(_ symbol: String, tint: Color = FacetUI.ink) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(FacetUI.raised)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(FacetUI.hairline, lineWidth: 1)
            }
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResults: some View {
        if filtered.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nothing named “\(query.trimmingCharacters(in: .whitespaces))”")
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.ink)
                Text("Facet can't see which apps you have installed — iOS doesn't expose that. If you know the app's URL scheme, enter it by hand.")
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.inkTertiary)
                Button {
                    customName = query.trimmingCharacters(in: .whitespaces)
                    withAnimation(.spring(duration: 0.22)) { showingCustom = true }
                } label: {
                    Text("Enter a custom scheme")
                        .font(FacetUI.label)
                        .foregroundStyle(FacetUI.accent)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(FacetUI.accentDim)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .facetPanel(radius: 11)
            .padding(.top, 18)
        } else {
            Section {
                ForEach(filtered) { row($0) }
            } header: {
                sectionHeader("Results", count: filtered.count)
            }
        }
    }

    // MARK: - Custom entry

    @ViewBuilder
    private var customSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.22)) { showingCustom.toggle() }
                searchFocused = false
            } label: {
                HStack(spacing: 12) {
                    glyph("app.dashed", tint: FacetUI.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom…")
                            .font(FacetUI.label)
                            .foregroundStyle(FacetUI.ink)
                        Text("Point a tile at any URL scheme")
                            .font(FacetUI.caption)
                            .foregroundStyle(FacetUI.inkTertiary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: showingCustom ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FacetUI.inkTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(FacetRowButton())

            if showingCustom { customEditor }
        }
        .padding(.top, 4)
    }

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Name (e.g. Bandcamp)", text: $customName)
            field("Scheme (e.g. bandcamp://)", text: $customScheme)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Text("Glyph").facetEyebrow().padding(.top, 2)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.customSymbols, id: \.self) { symbol in
                        Button { customSymbol = symbol } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(customSymbol == symbol ? FacetUI.accent : FacetUI.inkSecondary)
                                .frame(width: 44, height: 44)
                                .background(customSymbol == symbol ? FacetUI.accentDim : FacetUI.raised)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            customSymbol == symbol ? FacetUI.accent.opacity(0.5) : FacetUI.hairline,
                                            lineWidth: 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)

            Text("Facet can't verify a hand-entered scheme — iOS gives no way to ask whether an app is installed. If the tile does nothing when tapped, the scheme is wrong.")
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkTertiary)

            Button {
                guard let app = draftCustom else { return }
                onSelect(app)
                dismiss()
            } label: {
                Text("Use This App")
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(FacetUI.accentDim)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(draftCustom == nil)
            .opacity(draftCustom == nil ? 0.4 : 1)
        }
        .padding(14)
        .facetPanel(radius: 11)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var draftCustom: CatalogApp? {
        CatalogApp.custom(
            displayName: customName,
            urlScheme: customScheme,
            sfSymbol: customSymbol
        )
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(FacetUI.label)
            .foregroundStyle(FacetUI.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(FacetUI.raised)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(FacetUI.hairline, lineWidth: 1)
            }
    }
}

private struct CategorySection: Identifiable {
    let category: CatalogApp.Category
    let apps: [CatalogApp]
    var id: String { category.rawValue }
}

/// Full-bleed list row press state. Stock `.plain` gives no feedback and
/// `.borderless` tints the whole row blue — neither belongs here.
private struct FacetRowButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? FacetUI.raised.opacity(0.9) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    AppPickerView(selectedID: "spotify") { _ in }
}
