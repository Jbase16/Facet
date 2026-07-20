import SwiftUI
import FacetData

/// Create/edit sheet for one custom URL source. The "Test Fetch" panel runs
/// the real URLJSONSource fetch and shows exactly what came back — the
/// discovered variable paths users will bind to, or the actual error. No
/// fake success: if the API is down or the rootPath is wrong, they see it
/// here rather than in a silently stale widget.
struct CustomSourceEditorView: View {
    @Environment(\.dismiss) private var dismiss

    /// nil when creating a new source.
    let existing: URLSourceConfig?
    let onSave: (URLSourceConfig) -> Void

    @State private var name: String
    @State private var urlText: String
    @State private var cadence: CadenceClass
    @State private var rootPath: String
    @State private var headers: [HeaderField]
    @State private var testState: TestState = .idle

    init(existing: URLSourceConfig?, onSave: @escaping (URLSourceConfig) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.displayName ?? "")
        _urlText = State(initialValue: existing?.url.absoluteString ?? "")
        _cadence = State(initialValue: existing?.cadence ?? .hourly)
        _rootPath = State(initialValue: existing?.rootPath ?? "")
        _headers = State(initialValue: (existing?.headers ?? [:])
            .sorted { $0.key < $1.key }
            .map { HeaderField(name: $0.key, value: $0.value) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(existing == nil ? "New Source" : "Edit Source").facetEyebrow()
                        Text(name.isEmpty ? "Custom Source" : name)
                            .font(FacetUI.title(26))
                            .kerning(-0.3)
                            .foregroundStyle(FacetUI.ink)
                    }
                    .padding(.top, 8)

                    section("Details") {
                        field("Name", text: $name)
                        field("https://api.example.com/data.json", text: $urlText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    section("Refresh") {
                        cadencePicker
                        Text("How often Facet asks for fresh data. Faster than the API changes just burns the widget budget.")
                            .font(FacetUI.caption)
                            .foregroundStyle(FacetUI.inkTertiary)
                    }

                    section("Mapping") {
                        field("Root path (optional, e.g. data.current)", text: $rootPath)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text("A dotted path applied to the response before storing, so bindings stay short.")
                            .font(FacetUI.caption)
                            .foregroundStyle(FacetUI.inkTertiary)
                    }

                    section("Headers") {
                        ForEach($headers) { $header in
                            HStack(spacing: 8) {
                                field("Header", text: $header.name)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                field("Value", text: $header.value)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                Button {
                                    headers.removeAll { $0.id == header.id }
                                } label: {
                                    Image(systemName: "minus")
                                }
                                .buttonStyle(FacetToolButton())
                            }
                        }
                        Button {
                            headers.append(HeaderField())
                        } label: {
                            Label("Add Header", systemImage: "plus")
                                .font(FacetUI.label)
                                .foregroundStyle(FacetUI.accent)
                        }
                        .buttonStyle(.plain)
                        Text("Sent with every fetch — API keys and bearer tokens go here.")
                            .font(FacetUI.caption)
                            .foregroundStyle(FacetUI.inkTertiary)
                    }

                    section("Test Fetch") {
                        Button(action: runTest) {
                            HStack(spacing: 6) {
                                if case .running = testState {
                                    ProgressView().tint(FacetUI.accent)
                                } else {
                                    Image(systemName: "bolt.fill").font(FacetUI.caption)
                                }
                                Text("Test Fetch")
                            }
                            .font(FacetUI.label)
                            .foregroundStyle(FacetUI.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FacetUI.accentDim)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunningTest)

                        testResultPanel
                    }
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
                    Button(action: save) {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(FacetToolButton(prominent: true))
                    .disabled(draftConfig() == nil)
                    .opacity(draftConfig() == nil ? 0.4 : 1)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Draft config

    /// The config the current fields describe; nil until name and URL are
    /// usable. New sources get their slug here — makeID only reads, so
    /// calling it per-draft is harmless.
    private func draftConfig() -> URLSourceConfig? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty,
              let url = URL(string: trimmedURL),
              url.scheme == "https" || url.scheme == "http",
              url.host() != nil
        else { return nil }

        // Last-wins on duplicate header names; crashing on user input is
        // never the right answer.
        var headerMap: [String: String] = [:]
        for header in headers {
            let key = header.name.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { headerMap[key] = header.value }
        }

        let trimmedRoot = rootPath.trimmingCharacters(in: .whitespaces)
        return URLSourceConfig(
            id: existing?.id ?? CustomSourceStore().makeID(for: trimmedName),
            displayName: trimmedName,
            url: url,
            headers: headerMap,
            cadence: cadence,
            rootPath: trimmedRoot.isEmpty ? nil : trimmedRoot
        )
    }

    private func save() {
        guard let config = draftConfig() else { return }
        onSave(config)
        dismiss()
    }

    // MARK: - Test fetch

    private var isRunningTest: Bool {
        if case .running = testState { return true }
        return false
    }

    private func runTest() {
        guard let config = draftConfig() else {
            testState = .failure("Enter a name and a valid http(s) URL first.")
            return
        }
        testState = .running
        Task {
            do {
                let snapshot = try await URLJSONSource(config: config).fetch()
                testState = .success(Self.rows(from: snapshot))
            } catch let error as DataSourceError {
                switch error {
                case .fetchFailed(let message), .unavailable(let message):
                    testState = .failure(message)
                }
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }

    /// One row per discovered path, with the leaf value rendered the way
    /// the expression language will see it.
    private static func rows(from snapshot: DataSnapshot) -> [TestRow] {
        URLJSONSource.discoveredPaths(in: snapshot).map { path in
            // Discovered paths are prefixed with the source ID; strip it to
            // look the value up within the snapshot.
            let localPath = path.split(separator: ".").dropFirst().joined(separator: ".")
            return TestRow(path: path, value: display(snapshot.values.value(atPath: localPath)))
        }
    }

    private static func display(_ value: SnapshotValue?) -> String {
        switch value {
        case .number(let number):
            return number == number.rounded() && abs(number) < 1e15
                ? String(Int(number)) : String(number)
        case .string(let string): return "\"\(string)\""
        case .bool(let bool): return bool ? "true" : "false"
        case .list(let items): return "list · \(items.count) items"
        case .object, .none: return "—"
        }
    }

    @ViewBuilder
    private var testResultPanel: some View {
        switch testState {
        case .idle, .running:
            EmptyView()
        case .failure(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.sample)
                Text(message)
                    .font(FacetUI.caption)
                    .foregroundStyle(FacetUI.sample)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .facetPanel(radius: 11)
        case .success(let rows):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    FacetPill(text: "OK", color: FacetUI.live, icon: "checkmark")
                    Text("\(rows.count) variable\(rows.count == 1 ? "" : "s") found")
                        .font(FacetUI.caption)
                        .foregroundStyle(FacetUI.inkTertiary)
                    Spacer()
                }
                .padding(12)
                Divider().overlay(FacetUI.hairline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            HStack(alignment: .top) {
                                Text(row.path)
                                    .font(FacetUI.caption)
                                    .foregroundStyle(FacetUI.ink)
                                Spacer(minLength: 12)
                                Text(row.value)
                                    .font(FacetUI.caption)
                                    .foregroundStyle(FacetUI.inkSecondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 220)
            }
            .facetPanel(radius: 11)
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).facetEyebrow()
            content()
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(FacetUI.label)
            .foregroundStyle(FacetUI.ink)
            .padding(12)
            .background(FacetUI.raised)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(FacetUI.hairline, lineWidth: 1)
            }
    }

    private var cadencePicker: some View {
        HStack(spacing: 8) {
            ForEach(CadenceClass.allCases, id: \.self) { candidate in
                Button {
                    cadence = candidate
                } label: {
                    Text(candidate.displayName)
                        .font(FacetUI.caption)
                        .foregroundStyle(cadence == candidate ? FacetUI.accent : FacetUI.inkSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(cadence == candidate ? FacetUI.accentDim : FacetUI.raised)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(
                                cadence == candidate ? FacetUI.accent.opacity(0.4) : FacetUI.hairline,
                                lineWidth: 1
                            )
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Local models

private struct HeaderField: Identifiable {
    let id = UUID()
    var name = ""
    var value = ""
}

private struct TestRow: Identifiable {
    var path: String
    var value: String
    var id: String { path }
}

private enum TestState {
    case idle
    case running
    case success([TestRow])
    case failure(String)
}
