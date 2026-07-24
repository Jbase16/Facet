import SwiftUI
import FacetCore

/// A live workbench for the shape generators, built for the Xcode canvas.
/// This view ships in no screen — its only job is to be opened in Preview
/// so you can drag the sliders and watch each generator respond, and toggle
/// the node overlay to see the anchors and Bézier handles that produce a
/// shape. Open this file, show the canvas (⌥⌘↩), and play.
struct ShapePlayground: View {
    enum Family: String, CaseIterable, Identifiable {
        case cloud = "Cloud"
        case squircle = "Squircle"
        case corners = "Corners"
        case polygon = "Polygon"
        case star = "Star"
        case blob = "Blob"
        var id: String { rawValue }
    }

    @State private var family: Family = .cloud
    @State private var wide = true
    @State private var showNodes = true

    // Cloud
    @State private var cloudPuffs = 5.0
    @State private var cloudPuffiness = 0.28
    @State private var cloudIrregularity = 0.35
    @State private var cloudSeed = 7.0

    // Squircle
    @State private var roundness = 4.0

    // Per-corner radii
    @State private var linked = true
    @State private var tl = 0.3
    @State private var tr = 0.3
    @State private var br = 0.3
    @State private var bl = 0.3

    // Polygon
    @State private var sides = 6.0
    @State private var polyCorner = 0.1
    @State private var polyRotation = 0.0

    // Star
    @State private var points = 5.0
    @State private var innerRatio = 0.45
    @State private var starCorner = 0.06
    @State private var starRotation = 0.0

    // Blob
    @State private var blobPoints = 6.0
    @State private var irregularity = 0.3
    @State private var smoothness = 1.0
    @State private var seed = 0.0

    /// The current shape as a path string — regenerated on every slider
    /// tick, which is exactly what makes the canvas feel live.
    private var pathData: String {
        switch family {
        case .cloud:
            return ShapeGenerator.cloud(
                puffs: Int(cloudPuffs), puffiness: cloudPuffiness,
                irregularity: cloudIrregularity, seed: UInt64(max(0, cloudSeed))
            )
        case .squircle:
            return ShapeGenerator.superellipse(roundness: roundness)
        case .corners:
            return ShapeGenerator.roundedRect(
                topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl
            )
        case .polygon:
            return ShapeGenerator.polygon(
                sides: Int(sides), cornerRadius: polyCorner, rotation: polyRotation
            )
        case .star:
            return ShapeGenerator.star(
                points: Int(points), innerRatio: innerRatio,
                cornerRadius: starCorner, rotation: starRotation
            )
        case .blob:
            return BlobPath.path(BlobParameters(
                points: Int(blobPoints), irregularity: irregularity,
                smoothness: smoothness, seed: UInt64(max(0, seed))
            ))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                stage
                Picker("Family", selection: $family) {
                    ForEach(Family.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 20) {
                    Toggle("Wide layer", isOn: $wide)
                    Toggle("Show nodes", isOn: $showNodes)
                }
                .font(.footnote)
                .tint(Color(red: 0.55, green: 0.47, blue: 1))

                controls

                // The literal output — watching this scroll by as you drag
                // is the fastest way to build intuition for the format.
                Text(pathData)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(20)
        }
        .background(Color(white: 0.05))
        .preferredColorScheme(.dark)
    }

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.10))
            PlaygroundShape(pathData: pathData)
                .fill(Color(red: 0.55, green: 0.47, blue: 1))
                .overlay { if showNodes { NodeOverlay(pathData: pathData) } }
                .padding(28)
        }
        .aspectRatio(wide ? 1.9 : 1, contentMode: .fit)
        .frame(maxHeight: 320)
        .animation(.easeOut(duration: 0.12), value: pathData)
    }

    @ViewBuilder
    private var controls: some View {
        switch family {
        case .cloud:
            slider("Puffs", $cloudPuffs, 3...7, step: 1)
            slider("Puffiness", $cloudPuffiness, 0.05...0.5)
            slider("Irregularity", $cloudIrregularity, 0...1)
            HStack {
                slider("Seed", $cloudSeed, 0...100, step: 1)
                Button("Shuffle") { cloudSeed = Double(Int.random(in: 0...100)) }
                    .buttonStyle(.bordered)
            }
        case .squircle:
            slider("Roundness", $roundness, 1.5...12)
        case .corners:
            Toggle("Link corners", isOn: $linked)
                .font(.footnote)
                .tint(Color(red: 0.55, green: 0.47, blue: 1))
            if linked {
                slider("All corners", $tl, 0...0.5) { tr = tl; br = tl; bl = tl }
            } else {
                slider("Top-left", $tl, 0...0.5)
                slider("Top-right", $tr, 0...0.5)
                slider("Bottom-right", $br, 0...0.5)
                slider("Bottom-left", $bl, 0...0.5)
            }
        case .polygon:
            slider("Sides", $sides, 3...12, step: 1)
            slider("Corner radius", $polyCorner, 0...1)
            slider("Rotation", $polyRotation, 0...360)
        case .star:
            slider("Points", $points, 3...12, step: 1)
            slider("Inner ratio", $innerRatio, 0.2...0.9)
            slider("Corner radius", $starCorner, 0...1)
            slider("Rotation", $starRotation, 0...360)
        case .blob:
            slider("Points", $blobPoints, 3...12, step: 1)
            slider("Irregularity", $irregularity, 0...1)
            slider("Smoothness", $smoothness, 0...1.5)
            HStack {
                slider("Seed", $seed, 0...20, step: 1)
                Button("Shuffle") { seed = Double(Int.random(in: 0...20)) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func slider(
        _ label: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        step: Double? = nil,
        onChange: @escaping () -> Void = {}
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.footnote)
                Spacer()
                Text(step == 1 ? "\(Int(value.wrappedValue))" : String(format: "%.3f", value.wrappedValue))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: value, in: range, step: step) { _ in onChange() }
            } else {
                Slider(value: value, in: range) { _ in onChange() }
            }
        }
        .tint(Color(red: 0.55, green: 0.47, blue: 1))
        .onChange(of: value.wrappedValue) { onChange() }
    }
}

/// Renders a normalized 0...1 path string into whatever frame it's given —
/// a standalone copy because FacetRender's equivalent is module-internal.
struct PlaygroundShape: Shape {
    let pathData: String
    func path(in rect: CGRect) -> Path {
        guard let commands = try? PathData.parse(pathData) else { return Path() }
        var path = Path()
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        for command in commands {
            switch command {
            case .move(let x, let y): path.move(to: point(x, y))
            case .line(let x, let y): path.addLine(to: point(x, y))
            case .quad(let cx, let cy, let x, let y):
                path.addQuadCurve(to: point(x, y), control: point(cx, cy))
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                path.addCurve(to: point(x, y), control1: point(c1x, c1y), control2: point(c2x, c2y))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// Draws the anchors and Bézier handles behind the shape. Seeing that each
/// cloud bump is one arc between two anchors — and that "depth" just pushes
/// that arc's control outward — is the whole point of this overlay.
struct NodeOverlay: View {
    let pathData: String
    var body: some View {
        GeometryReader { geo in
            let nodes = PathEditing.nodes(in: (try? PathData.parse(pathData)) ?? [])
            ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
                if let handle = node.inHandle {
                    handleLine(from: screen(node.point, geo.size), to: screen(handle, geo.size))
                }
                if let handle = node.outHandle {
                    handleLine(from: screen(node.point, geo.size), to: screen(handle, geo.size))
                }
            }
            ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .position(screen(node.point, geo.size))
            }
        }
    }

    private func screen(_ p: PathPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    private func handleLine(from: CGPoint, to: CGPoint) -> some View {
        ZStack {
            Path { $0.move(to: from); $0.addLine(to: to) }
                .stroke(.white.opacity(0.35), lineWidth: 0.75)
            Circle().fill(.white.opacity(0.7)).frame(width: 4, height: 4).position(to)
        }
    }
}

#Preview("Shape Playground") {
    ShapePlayground()
}
