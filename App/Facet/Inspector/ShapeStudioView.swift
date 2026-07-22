import SwiftUI
import FacetCore

/// Picks and tunes the outline for a `.path` shape layer.
///
/// Two ways in: a preset gallery for people who want a shape now, and six
/// generator families for people who want *their* shape. Both end in the same
/// place — an SVG-subset string in normalized 0...1 coordinates — because that
/// is all the document stores.
///
/// Which means the trip is one-way: given a path we cannot recover the sliders
/// that made it. The sheet says so rather than showing invented values (see
/// `stageCaption`).
struct ShapeStudioView: View {
    @Environment(\.dismiss) private var dismiss

    /// The layer's existing outline, if it has one.
    let pathData: String?
    let onApply: (String) -> Void

    @State private var source: Source

    // One state bag per family, kept alive across tab switches so flipping
    // back to a family finds it exactly as it was left.
    @State private var squircle: Double = 4
    @State private var corners = CornerRadii()
    @State private var linkCorners = true
    @State private var cloud = CloudParameters()
    @State private var polygon = PolygonParameters()
    @State private var star = StarParameters()
    @State private var blob = BlobParameters(points: 6, irregularity: 0.3, smoothness: 1.0, seed: 7)

    init(pathData: String?, onApply: @escaping (String) -> Void) {
        let existing = pathData.flatMap { $0.isEmpty ? nil : $0 }
        self.pathData = existing
        self.onApply = onApply
        // Nothing to preserve means nothing to warn about: start on a family
        // so the first thing on screen is a shape, not an empty stage.
        _source = State(initialValue: existing == nil ? .family(.squircle) : .existing)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    stage
                    familyPicker
                    if case .family(let family) = source {
                        section(family.title) { controls(for: family) }
                    }
                    presetGallery
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
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: apply) {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(FacetToolButton(prominent: true))
                    .disabled(!isDrawable)
                    .opacity(isDrawable ? 1 : 0.4)
                    .accessibilityLabel("Apply")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func apply() {
        let outline = currentPathData
        guard !outline.isEmpty else { return }
        onApply(outline)
        dismiss()
    }

    // MARK: - Current outline

    /// The path the sheet would apply right now. Regenerated on every read —
    /// the generators are pure string math, cheap enough to run per frame.
    private var currentPathData: String {
        switch source {
        case .existing:
            return pathData ?? ""
        case .preset(let name):
            return ShapeGenerator.presets.first { $0.name == name }?.pathData ?? ""
        case .family(let family):
            return path(for: family)
        }
    }

    private func path(for family: ShapeFamily) -> String {
        switch family {
        case .squircle:
            return ShapeGenerator.superellipse(roundness: squircle)
        case .corners:
            return ShapeGenerator.roundedRect(
                topLeft: corners.topLeft,
                topRight: corners.topRight,
                bottomRight: corners.bottomRight,
                bottomLeft: corners.bottomLeft
            )
        case .cloud:
            return ShapeGenerator.scallop(
                bumpsX: cloud.bumpsX,
                bumpsY: cloud.bumpsY,
                depth: cloud.depth,
                cornerRadius: cloud.cornerRadius
            )
        case .polygon:
            return ShapeGenerator.polygon(
                sides: polygon.sides,
                cornerRadius: polygon.cornerRadius,
                rotation: polygon.rotation
            )
        case .star:
            return ShapeGenerator.star(
                points: star.points,
                innerRatio: star.innerRatio,
                cornerRadius: star.cornerRadius,
                rotation: star.rotation
            )
        case .blob:
            return BlobPath.path(blob)
        }
    }

    /// Guards Apply. A generator that emits something the parser rejects would
    /// otherwise write a shape into the document that renders as nothing.
    private var isDrawable: Bool {
        guard let commands = try? PathData.parse(currentPathData) else { return false }
        return !commands.isEmpty
    }

    // MARK: - Header & stage

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shape").facetEyebrow()
            Text("Studio")
                .font(FacetUI.title(26))
                .kerning(-0.3)
                .foregroundStyle(FacetUI.ink)
        }
        .padding(.top, 8)
    }

    /// 4:3 rather than square: a layer usually lives in a wide widget, and a
    /// squircle judged inside a square is a different shape than the one that
    /// ships. The dot grid gives the outline something to sit on.
    private var stage: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                DotGrid(spacing: 16)
                if isDrawable {
                    PathPreview(pathData: currentPathData, fill: FacetUI.ink)
                        .padding(18)
                } else {
                    Text("This path didn't parse.")
                        .font(FacetUI.caption)
                        .foregroundStyle(FacetUI.sample)
                }
            }
            .overlay(alignment: .topLeading) {
                FacetPill(text: sourceLabel, color: FacetUI.accent)
                    .padding(8)
            }
            .frame(height: 180)
            .frame(maxWidth: 240)
            .facetPanel()
            .frame(maxWidth: .infinity)

            Text(stageCaption)
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceLabel: String {
        switch source {
        case .existing: return "Current"
        case .preset(let name): return name
        case .family(let family): return family.title
        }
    }

    /// The honest bit. Path data has no parameters to read back, so the sheet
    /// promises nothing it cannot do.
    private var stageCaption: String {
        switch source {
        case .existing:
            return "The outline this layer already has. Facet stores shapes as path data, not as the settings that produced them, so the controls below start from their own defaults — touching any of them replaces this shape."
        case .preset, .family:
            return pathData == nil
                ? "Shown at widget proportions, so the outline reads the way it will in a wide widget."
                : "This replaces the layer's previous shape. Cancel keeps it."
        }
    }

    // MARK: - Families

    private var familyPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Family").facetEyebrow()
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ShapeFamily.allCases) { family in
                        familyChip(family)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func familyChip(_ family: ShapeFamily) -> some View {
        let isSelected = source == .family(family)
        return Button {
            source = .family(family)
        } label: {
            Text(family.title)
                .font(FacetUI.caption)
                .foregroundStyle(isSelected ? FacetUI.accent : FacetUI.inkSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isSelected ? FacetUI.accentDim : FacetUI.raised)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        isSelected ? FacetUI.accent.opacity(0.4) : FacetUI.hairline,
                        lineWidth: 1
                    )
                }
                // Visual capsule stays chip-sized; the tap target is 44.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func controls(for family: ShapeFamily) -> some View {
        switch family {
        case .squircle:
            sliderRow("Roundness", value: $squircle, range: 1.5...12) {
                String(format: "%.1f", $0)
            }
            note("The superellipse exponent. 2 is an ellipse, 4 is the iOS corner, 12 is nearly a rectangle.")

        case .corners:
            toggleRow("Link corners", isOn: $linkCorners)
                .onChange(of: linkCorners) { _, linked in
                    // Linking has to make the four agree, or the single
                    // slider would show a value the shape does not have.
                    if linked { corners = CornerRadii(all: corners.topLeft) }
                }
            if linkCorners {
                sliderRow("All corners", value: linkedCornerBinding, range: 0...0.5, format: percent)
            } else {
                sliderRow("Top left", value: $corners.topLeft, range: 0...0.5, format: percent)
                sliderRow("Top right", value: $corners.topRight, range: 0...0.5, format: percent)
                sliderRow("Bottom right", value: $corners.bottomRight, range: 0...0.5, format: percent)
                sliderRow("Bottom left", value: $corners.bottomLeft, range: 0...0.5, format: percent)
            }
            note("Radii are fractions of the layer's shorter side, so they hold their look at any widget size.")

        case .cloud:
            stepperRow("Bumps across", value: $cloud.bumpsX, range: 0...8)
            stepperRow("Bumps down", value: $cloud.bumpsY, range: 0...8)
            sliderRow("Depth", value: $cloud.depth, range: 0...0.12) {
                String(format: "%.1f%%", $0 * 100)
            }
            sliderRow("Corner radius", value: $cloud.cornerRadius, range: 0...0.3, format: percent)

        case .polygon:
            stepperRow("Sides", value: $polygon.sides, range: 3...12)
            sliderRow("Corner radius", value: $polygon.cornerRadius, range: 0...1, format: percent)
            sliderRow("Rotation", value: $polygon.rotation, range: 0...360, format: degrees)

        case .star:
            stepperRow("Points", value: $star.points, range: 3...12)
            sliderRow("Inner ratio", value: $star.innerRatio, range: 0.2...0.9, format: percent)
            sliderRow("Corner radius", value: $star.cornerRadius, range: 0...1, format: percent)
            sliderRow("Rotation", value: $star.rotation, range: 0...360, format: degrees)

        case .blob:
            stepperRow("Points", value: $blob.points, range: 3...12)
            sliderRow("Irregularity", value: $blob.irregularity, range: 0...1, format: percent)
            sliderRow("Smoothness", value: $blob.smoothness, range: 0...1.5) {
                String(format: "%.2f", $0)
            }
            shuffleRow
        }
    }

    /// Drives all four radii from one slider. Reads the top-left corner, which
    /// `linkCorners` keeps authoritative while the link is on.
    private var linkedCornerBinding: Binding<Double> {
        Binding(
            get: { corners.topLeft },
            set: { corners = CornerRadii(all: $0) }
        )
    }

    private var shuffleRow: some View {
        HStack(spacing: 12) {
            Text("Seed")
                .font(FacetUI.label)
                .foregroundStyle(FacetUI.inkSecondary)
            Text("#\(blob.seed % 10_000)")
                .font(FacetUI.caption.monospacedDigit())
                .foregroundStyle(FacetUI.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(FacetUI.raised, in: Capsule())
            Spacer()
            Button {
                blob.seed = UInt64.random(in: 0..<UInt64.max)
            } label: {
                Label("Shuffle", systemImage: "dice")
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(FacetUI.accentDim)
                    .clipShape(Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 44)
    }

    // MARK: - Presets

    @ViewBuilder
    private var presetGallery: some View {
        let presets = ShapeGenerator.presets
        if !presets.isEmpty {
            section("Presets") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 88), spacing: 12)],
                    spacing: 14
                ) {
                    ForEach(presets, id: \.name) { preset in
                        presetTile(preset)
                    }
                }
                note("Presets are finished outlines — picking one replaces whatever the family controls were making, and hides them until you pick a family again.")
            }
        }
    }

    private func presetTile(_ preset: ShapePreset) -> some View {
        let isSelected = source == .preset(preset.name)
        return Button {
            source = .preset(preset.name)
        } label: {
            VStack(spacing: 8) {
                PathPreview(
                    pathData: preset.pathData,
                    fill: isSelected ? FacetUI.accent : FacetUI.inkSecondary
                )
                .padding(12)
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .background(FacetUI.raised)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            isSelected ? FacetUI.accent : FacetUI.hairline,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }

                Text(preset.name)
                    .font(FacetUI.caption)
                    .foregroundStyle(isSelected ? FacetUI.ink : FacetUI.inkTertiary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chrome

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).facetEyebrow()
            content()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(FacetUI.caption)
            .foregroundStyle(FacetUI.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.inkSecondary)
                Spacer()
                readout(format(value.wrappedValue))
            }
            Slider(value: value, in: range)
                .tint(FacetUI.accent)
        }
        .frame(minHeight: 44)
    }

    private func stepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(FacetUI.label)
                .foregroundStyle(FacetUI.inkSecondary)
            Spacer()
            stepButton("minus", enabled: value.wrappedValue > range.lowerBound) {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            }
            readout("\(value.wrappedValue)")
                .frame(minWidth: 34)
            stepButton("plus", enabled: value.wrappedValue < range.upperBound) {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            }
        }
        .frame(minHeight: 44)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(FacetUI.label)
                .foregroundStyle(FacetUI.inkSecondary)
        }
        .tint(FacetUI.accent)
        .frame(minHeight: 44)
    }

    private func readout(_ text: String) -> some View {
        Text(text)
            .font(FacetUI.caption.monospacedDigit())
            .foregroundStyle(FacetUI.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(FacetUI.raised, in: Capsule())
    }

    /// A 32pt dot inside a 44pt target — FacetToolButton's look, but the hit
    /// area has to clear the minimum on a control users tap repeatedly.
    private func stepButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? FacetUI.ink : FacetUI.inkTertiary)
                .frame(width: 32, height: 32)
                .background(FacetUI.raised, in: Circle())
                .overlay { Circle().strokeBorder(FacetUI.hairline, lineWidth: 1) }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}

// MARK: - Path preview

/// Draws normalized path data at whatever size it is handed.
///
/// Parsing can fail — the string may come from a hand-edited document or a
/// generator that is still being written — so a bad path draws nothing rather
/// than taking the sheet with it. Parsed once in `init`, not per frame.
struct PathPreview: View {
    let pathData: String
    let fill: Color
    let stroke: Color?
    let strokeWidth: Double

    private let commands: [PathCommand]

    init(
        pathData: String,
        fill: Color = FacetUI.ink,
        stroke: Color? = nil,
        strokeWidth: Double = 1
    ) {
        self.pathData = pathData
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.commands = (try? PathData.parse(pathData)) ?? []
    }

    var body: some View {
        if commands.isEmpty {
            EmptyView()
        } else {
            let outline = NormalizedOutline(commands: commands)
            outline
                .fill(fill)
                .overlay {
                    if let stroke {
                        outline.stroke(stroke, lineWidth: strokeWidth)
                    }
                }
        }
    }
}

/// Local copy of FacetRender's shape of the same job: 0...1 coordinates
/// stretched across the given rect. FacetRender's is internal, and this sheet
/// is the only other place that draws raw path data.
private struct NormalizedOutline: Shape {
    let commands: [PathCommand]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        for command in commands {
            switch command {
            case .move(let x, let y):
                path.move(to: point(x, y))
            case .line(let x, let y):
                path.addLine(to: point(x, y))
            case .quad(let cx, let cy, let x, let y):
                path.addQuadCurve(to: point(x, y), control: point(cx, cy))
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                path.addCurve(to: point(x, y), control1: point(c1x, c1y), control2: point(c2x, c2y))
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }
}

// MARK: - Local models

/// What the stage is currently showing. Presets key on name rather than index
/// so the selection survives the generator list growing.
private enum Source: Equatable {
    case existing
    case preset(String)
    case family(ShapeFamily)
}

private enum ShapeFamily: String, CaseIterable, Identifiable {
    case squircle
    case corners
    case cloud
    case polygon
    case star
    case blob

    var id: String { rawValue }

    var title: String {
        switch self {
        case .squircle: return "Squircle"
        case .corners: return "Corners"
        case .cloud: return "Cloud"
        case .polygon: return "Polygon"
        case .star: return "Star"
        case .blob: return "Blob"
        }
    }
}

private struct CornerRadii {
    var topLeft: Double = 0.25
    var topRight: Double = 0.25
    var bottomRight: Double = 0.25
    var bottomLeft: Double = 0.25

    init() {}

    init(all radius: Double) {
        topLeft = radius
        topRight = radius
        bottomRight = radius
        bottomLeft = radius
    }
}

private struct CloudParameters {
    var bumpsX: Int = 4
    var bumpsY: Int = 3
    var depth: Double = 0.06
    var cornerRadius: Double = 0.12
}

private struct PolygonParameters {
    var sides: Int = 6
    var cornerRadius: Double = 0.08
    var rotation: Double = 0
}

private struct StarParameters {
    var points: Int = 5
    var innerRatio: Double = 0.45
    var cornerRadius: Double = 0.06
    var rotation: Double = 0
}
