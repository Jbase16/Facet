import SwiftUI
import FacetCore

/// The scene's shared palette.
///
/// Rather than an empty "add a token" form, this lists the colour tokens the
/// placed widgets *actually* reference, gathered from their own themes. That
/// turns an abstract question ("what should this palette contain?") into a
/// concrete one ("this screen has an accent, a background and a primary — what
/// should they be here?"), and it means you can only override something that
/// will visibly change.
///
/// A token left untouched stays absent from the palette, so `merging` leaves
/// each widget's own value alone. Overriding is opt-in per token.
struct ScenePaletteView: View {
    @Binding var palette: ThemeTokens
    /// The documents placed in this scene, whose tokens define what is
    /// worth offering.
    let documents: [WidgetDocument]

    @Environment(\.dismiss) private var dismiss

    /// Every colour token name used by any placed widget, with the value the
    /// first widget defining it uses — the sensible starting point for an
    /// override, since it is what the screen shows today.
    private var available: [(name: String, fallback: ColorToken)] {
        var seen: [String: ColorToken] = [:]
        for document in documents {
            for (name, token) in document.tokens.colors where seen[name] == nil {
                seen[name] = token
            }
        }
        return seen
            .map { (name: $0.key, fallback: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if available.isEmpty {
                empty
            } else {
                List {
                    Section {
                        ForEach(available, id: \.name) { entry in
                            row(name: entry.name, fallback: entry.fallback)
                        }
                    } footer: {
                        Text("Overridden colours apply to every widget on this scene. Layers using a fixed colour instead of a token are unaffected.")
                            .font(FacetUI.caption)
                            .foregroundStyle(FacetUI.inkTertiary)
                    }
                    .listRowBackground(FacetUI.raised)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(FacetUI.bg)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scene").facetEyebrow()
                Text("Palette")
                    .font(FacetUI.title(20))
                    .foregroundStyle(FacetUI.ink)
            }
            Spacer()
            if !palette.colors.isEmpty {
                Button("Reset all") { palette.colors.removeAll() }
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.accent)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(FacetToolButton())
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "paintpalette")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(FacetUI.inkTertiary)
            Text("Place a widget first")
                .font(FacetUI.label)
                .foregroundStyle(FacetUI.inkSecondary)
            Text("The palette offers the colours your widgets already use, so there is nothing to override yet.")
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(name: String, fallback: ColorToken) -> some View {
        let overridden = palette.colors[name] != nil
        let effective = palette.colors[name] ?? fallback
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.ink)
                Text(overridden ? "Scene override" : "From each widget")
                    .font(FacetUI.caption)
                    .foregroundStyle(overridden ? FacetUI.accent : FacetUI.inkTertiary)
            }
            Spacer(minLength: 0)

            // Editing either well starts an override seeded with what is on
            // screen now, so the first nudge changes one channel rather than
            // snapping the colour to an unrelated default.
            ColorPicker("Light", selection: Binding(
                get: { Color(effective.light) },
                set: { palette.colors[name] = ColorToken(light: ColorValue($0), dark: effective.dark) }
            ))
            .labelsHidden()

            ColorPicker("Dark", selection: Binding(
                get: { Color(effective.dark) },
                set: { palette.colors[name] = ColorToken(light: effective.light, dark: ColorValue($0)) }
            ))
            .labelsHidden()

            if overridden {
                Button {
                    palette.colors.removeValue(forKey: name)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FacetUI.inkTertiary)
                .accessibilityLabel("Reset \(name)")
            }
        }
        .padding(.vertical, 2)
    }
}
