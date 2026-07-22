import SwiftUI
import FacetCore

/// Per-layer property editing. Every control writes through `apply`, which
/// records undo in the editor. Layout properties respect rendition
/// overrides: the editor decides where a frame/size edit actually lands.
struct InspectorView: View {
    let layer: Layer
    let tokens: ThemeTokens
    let scheme: FacetCore.ColorScheme
    /// True when the current rendition has a patch for this layer.
    let hasOverride: Bool
    let apply: ((inout Layer) -> Void) -> Void
    let clearOverride: () -> Void

    @State private var name: String = ""
    @State private var templateText: String = ""
    @State private var templateValid = true
    @State private var expressionText: String = ""
    @State private var expressionValid = true
    @State private var symbolName: String = ""
    @State private var dataPath: String = ""
    @State private var visibleWhenText: String = ""
    @State private var visibleWhenValid = true
    @State private var tapURLText: String = ""
    @State private var tapURLValid = true
    @State private var showingAppPicker = false
    @State private var showingShapeStudio = false

    var body: some View {
        NavigationStack {
            Form {
                genericSection
                contentSection
                interactionSection
                if hasOverride {
                    Section {
                        Button("Clear override for this size", role: .destructive, action: clearOverride)
                    } footer: {
                        Text("This layer has adjustments specific to the current widget size.")
                    }
                }
            }
            .navigationTitle(layer.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: load)
        .sheet(isPresented: $showingShapeStudio) {
            ShapeStudioView(pathData: currentPathData) { data in
                apply { layer in
                    if case .shape(var shape) = layer.content {
                        shape.kind = .path
                        shape.pathData = data
                        layer.content = .shape(shape)
                    }
                }
                showingShapeStudio = false
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView { app in
                // Picking an app fills the tap link and, for a launcher
                // tile, its glyph and label too — one choice, whole tile.
                tapURLText = app.urlScheme
                tapURLValid = true
                apply { layer in
                    layer.tapAction = TapAction(urlTemplate: app.urlScheme)
                    layer.name = app.displayName
                    if case .symbol(var symbol) = layer.content {
                        symbol.systemName = app.sfSymbol
                        layer.content = .symbol(symbol)
                    }
                    if case .container(var container) = layer.content {
                        for index in container.children.indices {
                            switch container.children[index].content {
                            case .symbol(var symbol):
                                symbol.systemName = app.sfSymbol
                                container.children[index].content = .symbol(symbol)
                            case .text(var text):
                                text.text = app.displayName
                                container.children[index].content = .text(text)
                            default:
                                break
                            }
                        }
                        layer.content = .container(container)
                    }
                }
                showingAppPicker = false
            }
        }
    }

    private var currentPathData: String? {
        if case .shape(let shape) = layer.content { return shape.pathData }
        return nil
    }

    private func load() {
        name = layer.name
        visibleWhenText = layer.visibleWhen ?? ""
        tapURLText = layer.tapAction?.urlTemplate ?? ""
        switch layer.content {
        case .text(let content): templateText = content.text
        case .gauge(let content): expressionText = content.value
        case .symbol(let content): symbolName = content.systemName
        case .chart(let content): dataPath = content.dataPath
        default: break
        }
    }

    // MARK: - Interaction

    private var interactionSection: some View {
        Section {
            TextField("Visible when — e.g. battery.level < 0.2", text: $visibleWhenText, axis: .vertical)
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(visibleWhenValid ? .primary : Color.red)
                .onChange(of: visibleWhenText) {
                    let trimmed = visibleWhenText.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        visibleWhenValid = true
                        apply { $0.visibleWhen = nil }
                    } else {
                        visibleWhenValid = (try? Expression.parse(trimmed)) != nil
                        if visibleWhenValid { apply { $0.visibleWhen = trimmed } }
                    }
                }

            HStack {
                TextField("Tap opens URL — supports {expressions}", text: $tapURLText, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(tapURLValid ? .primary : Color.red)
                    .onChange(of: tapURLText) {
                        let trimmed = tapURLText.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            tapURLValid = true
                            apply { $0.tapAction = nil }
                        } else {
                            tapURLValid = (try? Template(parsing: trimmed)) != nil
                            if tapURLValid { apply { $0.tapAction = TapAction(urlTemplate: trimmed) } }
                        }
                    }
                Button {
                    showingAppPicker = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .buttonStyle(.borderless)
                Menu {
                    Button("Run a Shortcut") { tapURLText = "shortcuts://run-shortcut?name=" }
                    Button("Open today in Calendar") { tapURLText = "calshow:{calendar.nextStart}" }
                    Button("Open Health") { tapURLText = "x-apple-health://" }
                    Button("Open Reminders") { tapURLText = "x-apple-reminderkit://" }
                    Button("Call a number") { tapURLText = "tel:" }
                    Button("Open a website") { tapURLText = "https://" }
                } label: {
                    Image(systemName: "link.badge.plus")
                }
            }
        } header: {
            Text("Interaction")
        } footer: {
            if !visibleWhenValid {
                Text("Visibility expression doesn't parse — the layer stays visible until it does.")
            } else if !tapURLValid {
                Text("Tap URL template doesn't parse.")
            } else {
                Text("Conditions and tap links can use live data: battery, weather, health, calendar, time, env.dark.")
            }
        }
    }

    // MARK: - Generic

    private var genericSection: some View {
        Section("Layer") {
            TextField("Name", text: $name)
                .onSubmit { apply { $0.name = name } }
            sliderRow("Opacity", value: layer.style.opacity, range: 0...1, format: { "\(Int($0 * 100))%" }) { value in
                apply { $0.style.opacity = value }
            }
            sliderRow("Rotation", value: layer.style.rotation, range: -180...180, format: { "\(Int($0))°" }) { value in
                apply { $0.style.rotation = value }
            }
            sliderRow("Corner radius", value: layer.style.cornerRadius, range: 0...60, format: { "\(Int($0))" }) { value in
                apply { $0.style.cornerRadius = value }
            }
            Toggle("Shadow", isOn: Binding(
                get: { layer.style.shadow != nil },
                set: { on in
                    apply {
                        $0.style.shadow = on
                            ? ShadowStyle(color: .literal(ColorValue(red: 0, green: 0, blue: 0, alpha: 0.4)), radius: 6, offsetY: 3)
                            : nil
                    }
                }
            ))
            if let shadow = layer.style.shadow {
                sliderRow("Shadow radius", value: shadow.radius, range: 0...30, format: { "\(Int($0))" }) { value in
                    apply { $0.style.shadow?.radius = value }
                }
            }
        }
    }

    // MARK: - Per-type

    @ViewBuilder
    private var contentSection: some View {
        switch layer.content {
        case .text(let content): textSection(content)
        case .symbol(let content): symbolSection(content)
        case .shape(let content): shapeSection(content)
        case .gauge(let content): gaugeSection(content)
        case .line(let content): lineSection(content)
        case .chart(let content): chartSection(content)
        case .container(let content): containerSection(content)
        case .image(let content): imageSection(content)
        }
    }

    private func textSection(_ content: TextContent) -> some View {
        Section("Text") {
            TextField("Template", text: $templateText, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    templateValid = (try? Template(parsing: templateText)) != nil
                    guard templateValid else { return }
                    apply { layer in
                        if case .text(var text) = layer.content {
                            text.text = templateText
                            layer.content = .text(text)
                        }
                    }
                }
            if !templateValid {
                Label("Invalid template — check the { } expressions", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            fontControls(
                font: fontToken(content.font),
                update: { mutation in
                    apply { layer in
                        if case .text(var text) = layer.content {
                            var font = fontToken(text.font)
                            mutation(&font)
                            text.font = .literal(font)
                            layer.content = .text(text)
                        }
                    }
                }
            )

            Picker("Alignment", selection: contentBinding(get: content.alignment, set: { (value, text: inout TextContent) in text.alignment = value })) {
                Text("Leading").tag(FacetCore.TextAlignment.leading)
                Text("Center").tag(FacetCore.TextAlignment.center)
                Text("Trailing").tag(FacetCore.TextAlignment.trailing)
            }
            Picker("Case", selection: contentBinding(get: content.textCase, set: { (value, text: inout TextContent) in text.textCase = value })) {
                Text("As typed").tag(TextCase?.none)
                Text("UPPER").tag(TextCase?.some(.uppercase))
                Text("lower").tag(TextCase?.some(.lowercase))
            }
            sliderRow("Tracking", value: content.letterSpacing ?? 0, range: 0...8, format: { String(format: "%.1f", $0) }) { value in
                apply { layer in
                    if case .text(var text) = layer.content {
                        text.letterSpacing = value == 0 ? nil : value
                        layer.content = .text(text)
                    }
                }
            }
            ColorRefPicker(
                label: "Color", tokens: tokens.colors, scheme: scheme,
                selection: contentBinding(get: content.color, set: { (value, text: inout TextContent) in text.color = value })
            )
        }
    }

    private static let commonSymbols = [
        "star.fill", "heart.fill", "bolt.fill", "moon.fill", "sun.max.fill", "cloud.fill",
        "cloud.sun.fill", "cloud.rain.fill", "wind", "drop.fill", "flame.fill", "leaf.fill",
        "battery.100", "figure.walk", "figure.run", "calendar", "clock.fill", "bell.fill",
        "music.note", "headphones", "house.fill", "car.fill", "airplane", "sparkles",
    ]

    private func symbolSection(_ content: SymbolContent) -> some View {
        Section("Symbol") {
            TextField("SF Symbol name", text: $symbolName)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { setSymbolName(symbolName) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36))], spacing: 8) {
                ForEach(Self.commonSymbols, id: \.self) { candidate in
                    Button {
                        symbolName = candidate
                        setSymbolName(candidate)
                    } label: {
                        Image(systemName: candidate)
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(candidate == content.systemName ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            sliderRow("Size", value: content.size, range: 8...96, format: { "\(Int($0))" }) { value in
                apply { layer in
                    if case .symbol(var symbol) = layer.content {
                        symbol.size = value
                        layer.content = .symbol(symbol)
                    }
                }
            }
            ColorRefPicker(
                label: "Color", tokens: tokens.colors, scheme: scheme,
                selection: contentBinding(get: content.color, set: { (value, symbol: inout SymbolContent) in symbol.color = value })
            )
        }
    }

    private func setSymbolName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        apply { layer in
            if case .symbol(var symbol) = layer.content {
                symbol.systemName = trimmed
                layer.content = .symbol(symbol)
            }
        }
    }

    private func shapeSection(_ content: ShapeContent) -> some View {
        Section("Shape") {
            Picker("Kind", selection: contentBinding(get: content.kind, set: { (value, shape: inout ShapeContent) in
                shape.kind = value
                // Switching to a path with nothing to draw would resolve as
                // a rectangle; seed a default blob so the choice is visible.
                if value == .path && (shape.pathData?.isEmpty ?? true) {
                    shape.pathData = BlobPath.path(.default)
                }
            })) {
                Text("Rectangle").tag(ShapeKind.rectangle)
                Text("Circle").tag(ShapeKind.circle)
                Text("Capsule").tag(ShapeKind.capsule)
                Text("Blob").tag(ShapeKind.path)
            }
            if content.kind == .path {
                Button {
                    showingShapeStudio = true
                } label: {
                    Label("Open Shape Studio", systemImage: "square.on.circle")
                }
                Text("Edit nodes directly on the canvas with the node button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            FillPicker(
                label: "Fill", tokens: tokens.colors, scheme: scheme,
                selection: contentBinding(get: content.fill, set: { (value, shape: inout ShapeContent) in shape.fill = value })
            )
            sliderRow("Stroke width", value: content.strokeWidth, range: 0...12, format: { String(format: "%.1f", $0) }) { value in
                apply { layer in
                    if case .shape(var shape) = layer.content {
                        shape.strokeWidth = value
                        if value > 0 && shape.strokeColor == nil { shape.strokeColor = .literal(.white) }
                        layer.content = .shape(shape)
                    }
                }
            }
            if content.strokeWidth > 0 {
                ColorRefPicker(
                    label: "Stroke", tokens: tokens.colors, scheme: scheme,
                    selection: contentBinding(get: content.strokeColor ?? .literal(.white), set: { (value, shape: inout ShapeContent) in shape.strokeColor = value })
                )
            }
        }
    }

    private func gaugeSection(_ content: GaugeContent) -> some View {
        Section("Gauge") {
            TextField("Value expression (0–1)", text: $expressionText)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    expressionValid = (try? Expression.parse(expressionText)) != nil
                    guard expressionValid else { return }
                    apply { layer in
                        if case .gauge(var gauge) = layer.content {
                            gauge.value = expressionText
                            layer.content = .gauge(gauge)
                        }
                    }
                }
            if !expressionValid {
                Label("Invalid expression", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Picker("Style", selection: contentBinding(get: content.style, set: { (value, gauge: inout GaugeContent) in gauge.style = value })) {
                Text("Ring").tag(GaugeStyle.ring)
                Text("Bar").tag(GaugeStyle.bar)
            }
            sliderRow("Line width", value: content.lineWidth, range: 2...24, format: { "\(Int($0))" }) { value in
                apply { layer in
                    if case .gauge(var gauge) = layer.content {
                        gauge.lineWidth = value
                        layer.content = .gauge(gauge)
                    }
                }
            }
            ColorRefPicker(
                label: "Tint", tokens: tokens.colors, scheme: scheme,
                selection: contentBinding(get: content.tint, set: { (value, gauge: inout GaugeContent) in gauge.tint = value })
            )
            ColorRefPicker(
                label: "Track", tokens: tokens.colors, scheme: scheme,
                selection: contentBinding(get: content.track, set: { (value, gauge: inout GaugeContent) in gauge.track = value })
            )
        }
    }

    private func lineSection(_ content: LineContent) -> some View {
        Section("Line") {
            sliderRow("Thickness", value: content.thickness, range: 0.5...12, format: { String(format: "%.1f", $0) }) { value in
                apply { layer in
                    if case .line(var line) = layer.content {
                        line.thickness = value
                        layer.content = .line(line)
                    }
                }
            }
            Toggle("Dashed", isOn: Binding(
                get: { content.dash != nil },
                set: { on in
                    apply { layer in
                        if case .line(var line) = layer.content {
                            line.dash = on ? [4, 3] : nil
                            layer.content = .line(line)
                        }
                    }
                }
            ))
            ColorRefPicker(
                label: "Color", tokens: tokens.colors, scheme: scheme,
                selection: contentBinding(get: content.color, set: { (value, line: inout LineContent) in line.color = value })
            )
        }
    }

    private func chartSection(_ content: ChartContent) -> some View {
        Section("Chart") {
            TextField("Data path (a list)", text: $dataPath)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    apply { layer in
                        if case .chart(var chart) = layer.content {
                            chart.dataPath = dataPath.trimmingCharacters(in: .whitespaces)
                            layer.content = .chart(chart)
                        }
                    }
                }
            Text("e.g. weather.hourly or health.weekSteps")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Style", selection: contentBinding(get: content.style, set: { (value, chart: inout ChartContent) in chart.style = value })) {
                Text("Line").tag(ChartStyle.line)
                Text("Area").tag(ChartStyle.area)
                Text("Bars").tag(ChartStyle.bars)
            }
            sliderRow("Line width", value: content.lineWidth, range: 1...8, format: { String(format: "%.1f", $0) }) { value in
                apply { layer in
                    if case .chart(var chart) = layer.content {
                        chart.lineWidth = value
                        layer.content = .chart(chart)
                    }
                }
            }
            ColorRefPicker(
                label: "Color", tokens: tokens.colors, scheme: scheme,
                selection: contentBinding(get: content.color, set: { (value, chart: inout ChartContent) in chart.color = value })
            )
        }
    }

    private func containerSection(_ content: ContainerContent) -> some View {
        Section("Group") {
            Picker("Layout", selection: contentBinding(get: content.layout, set: { (value, container: inout ContainerContent) in container.layout = value })) {
                Text("Free").tag(ContainerLayout.absolute)
                Text("Row").tag(ContainerLayout.horizontal)
                Text("Column").tag(ContainerLayout.vertical)
                Text("Overlay").tag(ContainerLayout.overlay)
            }
            if content.layout == .horizontal || content.layout == .vertical {
                sliderRow("Spacing", value: content.spacing, range: 0...30, format: { "\(Int($0))" }) { value in
                    apply { layer in
                        if case .container(var container) = layer.content {
                            container.spacing = value
                            layer.content = .container(container)
                        }
                    }
                }
                Picker("Align", selection: contentBinding(get: content.alignment ?? .center, set: { (value, container: inout ContainerContent) in container.alignment = value })) {
                    Text("Start").tag(StackAlignment.start)
                    Text("Center").tag(StackAlignment.center)
                    Text("End").tag(StackAlignment.end)
                }
            }
            sliderRow("Padding", value: content.padding, range: 0...30, format: { "\(Int($0))" }) { value in
                apply { layer in
                    if case .container(var container) = layer.content {
                        container.padding = value
                        layer.content = .container(container)
                    }
                }
            }
            Toggle("Background", isOn: Binding(
                get: { content.background != nil },
                set: { on in
                    apply { layer in
                        if case .container(var container) = layer.content {
                            container.background = on ? Fill.literal(ColorValue(hex: "#1C1C1E")!) : nil
                            layer.content = .container(container)
                        }
                    }
                }
            ))
            if let background = content.background {
                FillPicker(
                    label: "Background", tokens: tokens.colors, scheme: scheme,
                    selection: contentBinding(get: background, set: { (value, container: inout ContainerContent) in container.background = value })
                )
            }
        }
    }

    private func imageSection(_ content: ImageContent) -> some View {
        Section("Image") {
            LabeledContent("Asset", value: content.assetName)
            Picker("Mode", selection: contentBinding(get: content.contentMode, set: { (value, image: inout ImageContent) in image.contentMode = value })) {
                Text("Fill").tag(ImageContent.ContentMode.fill)
                Text("Fit").tag(ImageContent.ContentMode.fit)
            }
            Text("Photo import lands with the asset-bundle work.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Plumbing

    private func fontToken(_ ref: FontRef) -> FontToken {
        switch ref {
        case .literal(let font): return font
        case .token(let name): return tokens.fonts[name] ?? FontToken(size: 15)
        }
    }

    @ViewBuilder
    private func fontControls(font: FontToken, update: @escaping ((inout FontToken) -> Void) -> Void) -> some View {
        sliderRow("Size", value: font.size, range: 6...72, format: { "\(Int($0))" }) { value in
            update { $0.size = value }
        }
        Picker("Weight", selection: Binding(get: { font.weight }, set: { value in update { $0.weight = value } })) {
            ForEach([FontWeight.light, .regular, .medium, .semibold, .bold, .heavy, .black], id: \.self) {
                Text($0.rawValue.capitalized).tag($0)
            }
        }
        Picker("Design", selection: Binding(get: { font.design }, set: { value in update { $0.design = value } })) {
            Text("Default").tag(FontDesign.standard)
            Text("Rounded").tag(FontDesign.rounded)
            Text("Serif").tag(FontDesign.serif)
            Text("Mono").tag(FontDesign.monospaced)
        }
    }

    private func sliderRow(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String,
        commit: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title)  \(format(value))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { value }, set: { commit($0) }),
                in: range
            )
        }
    }

    /// A binding that rewrites one field of the layer's content payload.
    private func contentBinding<Payload, Value: Equatable>(
        get current: Value,
        set write: @escaping (Value, inout Payload) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { current },
            set: { newValue in
                apply { layer in
                    layer.rewriteContent(Payload.self) { typed in
                        write(newValue, &typed)
                    }
                }
            }
        )
    }
}

private extension Layer {
    /// Rewrite the content payload when it matches `type`.
    mutating func rewriteContent<Payload>(_ type: Payload.Type, _ mutate: (inout Payload) -> Void) {
        switch content {
        case .text(let value):
            if var typed = value as? Payload { mutate(&typed); content = .text(typed as! TextContent) }
        case .symbol(let value):
            if var typed = value as? Payload { mutate(&typed); content = .symbol(typed as! SymbolContent) }
        case .shape(let value):
            if var typed = value as? Payload { mutate(&typed); content = .shape(typed as! ShapeContent) }
        case .image(let value):
            if var typed = value as? Payload { mutate(&typed); content = .image(typed as! ImageContent) }
        case .gauge(let value):
            if var typed = value as? Payload { mutate(&typed); content = .gauge(typed as! GaugeContent) }
        case .line(let value):
            if var typed = value as? Payload { mutate(&typed); content = .line(typed as! LineContent) }
        case .chart(let value):
            if var typed = value as? Payload { mutate(&typed); content = .chart(typed as! ChartContent) }
        case .container(let value):
            if var typed = value as? Payload { mutate(&typed); content = .container(typed as! ContainerContent) }
        }
    }
}
