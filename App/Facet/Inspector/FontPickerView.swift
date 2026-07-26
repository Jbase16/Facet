import SwiftUI
import FacetCore

/// Picks the font family a text layer draws in.
///
/// The point of a font picker is seeing the faces, so every row renders its
/// own name in its own font and a strip up top shows the pending choice at
/// widget scale. Tapping a row selects; the footer commits — browsing twenty
/// families costs the document one edit instead of twenty, and the sheet's
/// close button stays a real cancel.
struct FontPickerView: View {
    @Environment(\.dismiss) private var dismiss

    private let onSelect: (FontToken) -> Void

    @State private var draft: FontToken
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    init(selection: FontToken, onSelect: @escaping (FontToken) -> Void) {
        _draft = State(initialValue: selection)
        self.onSelect = onSelect
    }

    /// Digits and a clock, because that is what most widgets are made of.
    private static let sample = "Widget 123 9:41"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if isSearching {
                            searchResults
                        } else {
                            systemRow
                            Section {
                                ForEach(FontCatalog.curated) { familyRow($0) }
                            } header: {
                                sectionHeader("Picks", count: FontCatalog.curated.count)
                            }
                            ForEach(sections) { section in
                                Section {
                                    ForEach(section.families) { familyRow($0) }
                                } header: {
                                    sectionHeader(section.id, count: section.families.count)
                                }
                            }
                            ceilingNote
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
                footer
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

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    /// Curated hits float to the top of a search the same way they do in the
    /// browse list. Two passes rather than a sort so ordering stays stable.
    private var results: [FontFamily] {
        let hits = FontCatalog.search(trimmedQuery)
        return hits.filter { FontCatalog.curatedIDs.contains($0.id) }
            + hits.filter { !FontCatalog.curatedIDs.contains($0.id) }
    }

    private var systemMatches: Bool {
        "System".range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private var sections: [LetterSection] {
        FontCatalog.grouped(FontCatalog.families).map { LetterSection(id: $0.0, families: $0.1) }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Type").facetEyebrow()
                Text("Font")
                    .font(FacetUI.title(26))
                    .kerning(-0.3)
                    .foregroundStyle(FacetUI.ink)
            }

            previewStrip
            searchField
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var previewStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.sample)
                .font(previewFont(size: 27))
                .foregroundStyle(FacetUI.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            HStack(spacing: 5) {
                Text(draft.family ?? "System")
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.accent)
                    .lineLimit(1)
                Text(draft.family == nil
                     ? "· \(draft.weight.rawValue) · \(Int(draft.size))pt"
                     : "· a family draws in its own weight")
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.inkTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .facetPanel(radius: 11)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(FacetUI.label)
                .foregroundStyle(searchFocused ? FacetUI.accent : FacetUI.inkTertiary)
            TextField("Search fonts", text: $query)
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

    /// The commit lives at the bottom, in thumb reach, and names what it will
    /// do — the close button above is a cancel and has to stay one.
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(FacetUI.hairline)
                .frame(height: 1)
            Button {
                onSelect(draft)
                dismiss()
            } label: {
                Text(commitTitle)
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.accent)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(FacetUI.accentDim)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
        .background(FacetUI.surface)
    }

    private var commitTitle: String {
        guard let family = draft.family else { return "Use System Font" }
        return "Use \(family)"
    }

    // MARK: - Rows

    private var systemRow: some View {
        row(
            title: "System",
            titleFont: .system(
                size: 19,
                weight: swiftUIWeight(draft.weight),
                design: swiftUIDesign(draft.design)
            ),
            subtitle: "San Francisco · weight and design stay live",
            isSelected: draft.family == nil
        ) {
            draft.family = nil
        }
    }

    private func familyRow(_ family: FontFamily) -> some View {
        row(
            title: family.displayName,
            titleFont: .custom(family.id, size: 19),
            // The name in the system font is the anchor: families like Symbol
            // and Zapf Dingbats draw Latin letters as something else entirely.
            subtitle: "\(family.displayName) · \(family.faceCount) \(family.faceCount == 1 ? "style" : "styles")",
            isSelected: draft.family == family.id
        ) {
            draft.family = family.id
        }
    }

    private func row(
        title: String,
        titleFont: Font,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(FacetUI.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(subtitle)
                        .font(FacetUI.caption)
                        .foregroundStyle(isSelected ? FacetUI.accent : FacetUI.inkTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FacetUI.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(FontRowButton())
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResults: some View {
        let hits = results
        let showSystem = systemMatches
        if hits.isEmpty && !showSystem {
            emptyState
        } else {
            Section {
                if showSystem { systemRow }
                ForEach(hits) { familyRow($0) }
            } header: {
                sectionHeader("Results", count: hits.count + (showSystem ? 1 : 0))
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No font named “\(trimmedQuery)”")
                .font(FacetUI.label)
                .foregroundStyle(FacetUI.ink)
            Text(Self.ceilingText)
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .facetPanel(radius: 11)
        .padding(.top, 18)
    }

    /// Says the quiet part at the bottom of the list rather than letting people
    /// hunt for an import button that cannot exist.
    private var ceilingNote: some View {
        Text(Self.ceilingText)
            .font(FacetUI.caption)
            .foregroundStyle(FacetUI.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .facetPanel(radius: 11)
            .padding(.top, 22)
    }

    private static let ceilingText = """
        These are the fonts iOS installs — \(FontCatalog.families.count) families on this device. \
        Widgets can only draw fonts already on the system, so Facet can't import one.
        """

    // MARK: - Font resolution

    /// Mirrors `FacetWidgetView.font(for:)` exactly. A preview that resolved
    /// fonts differently from the renderer would be a lie — including the part
    /// where a custom family ignores the token's weight and design.
    private func previewFont(size: Double) -> Font {
        if let family = draft.family {
            return .custom(family, size: size)
        }
        return .system(size: size, weight: swiftUIWeight(draft.weight), design: swiftUIDesign(draft.design))
    }

    private func swiftUIWeight(_ weight: FontWeight) -> Font.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }

    private func swiftUIDesign(_ design: FontDesign) -> Font.Design {
        switch design {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

private struct LetterSection: Identifiable {
    let id: String
    let families: [FontFamily]
}

/// Full-bleed row press state; stock `.plain` gives no feedback.
private struct FontRowButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? FacetUI.raised.opacity(0.9) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    FontPickerView(selection: FontToken(size: 28, weight: .semibold, design: .rounded)) { _ in }
}
