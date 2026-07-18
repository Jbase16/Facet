import SwiftUI
import FacetCore

/// Edit the document's design tokens. Changing a token restyles every layer
/// that references it — this is the "swap the theme" workflow.
struct ThemeEditorView: View {
    let tokens: ThemeTokens
    /// Applies a token mutation with undo recorded by the editor.
    let mutate: ((inout ThemeTokens) -> Void) -> Void

    @State private var renamingToken: String?
    @State private var newName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Colors") {
                    ForEach(tokens.colors.keys.sorted(), id: \.self) { name in
                        colorRow(name: name, token: tokens.colors[name]!)
                    }
                    Button {
                        mutate { theme in
                            var index = 1
                            while theme.colors["color\(index)"] != nil { index += 1 }
                            theme.colors["color\(index)"] = ColorToken(light: .black, dark: .white)
                        }
                    } label: {
                        Label("Add color token", systemImage: "plus")
                    }
                }

                Section("Fonts") {
                    ForEach(tokens.fonts.keys.sorted(), id: \.self) { name in
                        fontRow(name: name, token: tokens.fonts[name]!)
                    }
                }
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Rename token", isPresented: Binding(
                get: { renamingToken != nil },
                set: { if !$0 { renamingToken = nil } }
            )) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let old = renamingToken {
                        rename(from: old, to: newName)
                    }
                    renamingToken = nil
                }
                Button("Cancel", role: .cancel) { renamingToken = nil }
            }
        }
    }

    private func colorRow(name: String, token: ColorToken) -> some View {
        HStack {
            Text(name)
                .font(.callout)
            Spacer()
            ColorPicker("Light", selection: Binding(
                get: { Color(token.light) },
                set: { color in mutate { $0.colors[name]?.light = ColorValue(color) } }
            ))
            .labelsHidden()
            ColorPicker("Dark", selection: Binding(
                get: { Color(token.dark) },
                set: { color in mutate { $0.colors[name]?.dark = ColorValue(color) } }
            ))
            .labelsHidden()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                mutate { $0.colors.removeValue(forKey: name) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                newName = name
                renamingToken = name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
    }

    private func fontRow(name: String, token: FontToken) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.callout)
                Spacer()
                Text("\(Int(token.size)) pt · \(token.weight.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { token.size },
                    set: { size in mutate { $0.fonts[name]?.size = size } }
                ),
                in: 6...72
            )
            Picker("Weight", selection: Binding(
                get: { token.weight },
                set: { weight in mutate { $0.fonts[name]?.weight = weight } }
            )) {
                ForEach([FontWeight.thin, .light, .regular, .medium, .semibold, .bold, .heavy], id: \.self) {
                    Text($0.rawValue.capitalized).tag($0)
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// Renaming rewrites the token table; layers referencing the old name
    /// keep the old reference (and render magenta) until re-pointed — the
    /// honest behavior, made visible rather than silently guessed.
    private func rename(from old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != old else { return }
        mutate { theme in
            guard theme.colors[trimmed] == nil, let token = theme.colors.removeValue(forKey: old) else { return }
            theme.colors[trimmed] = token
        }
    }
}
