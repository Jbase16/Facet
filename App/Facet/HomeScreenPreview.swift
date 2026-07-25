import SwiftUI
import FacetCore
import FacetData
import FacetRender

/// The widget shown where it will actually live: true size, in a real grid
/// slot, on the wallpaper, surrounded by icon placeholders. The editor canvas
/// answers "what does this widget look like"; this answers "what does my home
/// screen look like" — the question a Scene is really about.
///
/// Every number here is derived from `RenditionKind.designSize` rather than
/// eyeballed: solving "small is a 2×2 icon block and medium is 4×2" gives a
/// 68pt icon on a 90pt column pitch, and "large is 4×4" gives a 98pt row pitch.
/// Those reproduce all three widget sizes exactly and leave 26pt side margins,
/// within a point of real iOS.
struct HomeScreenPreview: View {
    let document: WidgetDocument
    let rendition: RenditionKind
    let scheme: FacetCore.ColorScheme
    let wallpaper: UIImage?
    @Binding var slot: Int

    /// Reference device: the 390×844 class the schema's design sizes belong to.
    private static let screen = CGSize(width: 390, height: 844)
    private static let iconCell = 68.0
    private static let columnPitch = 90.0
    private static let rowCell = 60.0
    private static let rowPitch = 98.0
    /// The icon glyph itself is 60pt on this device class — the same as the row
    /// cell, which is what makes a widget's top edge line up with the icons
    /// beside it. (The 68pt column cell is pitch minus gutter, not glyph size.)
    private static let iconGlyph = 60.0
    private static let gridOrigin = CGPoint(x: 26, y: 78)
    private static let columns = 4
    private static let rows = 6

    var body: some View {
        GeometryReader { geo in
            // Fit a phone-shaped frame into whatever room the editor gives us.
            let scale = min(
                geo.size.width / Self.screen.width,
                geo.size.height / Self.screen.height
            )
            let width = Self.screen.width * scale
            let height = Self.screen.height * scale

            ZStack(alignment: .topLeading) {
                wallpaperLayer
                if rendition.isAccessory {
                    lockScreenChrome(scale: scale)
                } else {
                    homeScreenChrome(scale: scale)
                }
                widgetLayer(scale: scale)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 44 * scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 44 * scale, style: .continuous)
                    .strokeBorder(FacetUI.hairlineStrong, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Backdrop

    @ViewBuilder
    private var wallpaperLayer: some View {
        if let wallpaper {
            Image(uiImage: wallpaper)
                .resizable()
                .scaledToFill()   // wallpapers fill the screen; never letterbox
        } else {
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.06)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - The widget itself

    /// Rendered through the same resolver and view the extension uses, at its
    /// natural design size, then scaled — so what you see is the real thing
    /// shrunk, not an approximation drawn at preview size.
    private func widgetLayer(scale: Double) -> some View {
        let size = rendition.designSize
        let origin = widgetOrigin(size: size)
        let resolved = DocumentResolver.resolve(
            document: document,
            snapshots: SampleData.snapshotSet(),
            environment: RenderEnvironment(rendition: rendition, colorScheme: scheme)
        )
        return FacetWidgetView(widget: resolved)
            .environment(\.facetImageProvider, FacetImageProviderFactory.make(documentID: document.id))
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .scaleEffect(scale, anchor: .topLeading)
            // `scaleEffect` shrinks the drawing but not the layout box, so this
            // frame holds a box larger than itself — and its default centre
            // alignment would shove the widget up and left by half the
            // difference, hard enough to clip it off the bezel. Pinning to
            // topLeading keeps `origin` meaning the widget's true top-left.
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .offset(x: origin.x * scale, y: origin.y * scale)
            // The slot tap targets live underneath; the widget must never eat
            // a tap meant to move it.
            .allowsHitTesting(false)
    }

    private func widgetOrigin(size: (width: Double, height: Double)) -> CGPoint {
        guard !rendition.isAccessory else {
            // Lock Screen accessories sit under the clock, centred.
            return CGPoint(x: (Self.screen.width - size.width) / 2, y: 250)
        }
        let position = currentSlot
        return CGPoint(
            x: Self.gridOrigin.x + Double(position.col) * Self.columnPitch,
            y: Self.gridOrigin.y + Double(position.row) * Self.rowPitch
        )
    }

    // MARK: - Slots

    /// Where iOS actually allows this size to sit: widgets snap to whole 2-row
    /// bands, and anything wider than two columns starts at the left margin.
    private var slots: [(col: Int, row: Int)] {
        switch rendition {
        case .systemSmall:
            return [(0, 0), (2, 0), (0, 2), (2, 2), (0, 4), (2, 4)]
        case .systemMedium:
            return [(0, 0), (0, 2), (0, 4)]
        case .systemLarge:
            return [(0, 0), (0, 2)]
        default:
            return [(0, 0)]
        }
    }

    private var currentSlot: (col: Int, row: Int) {
        let slots = slots
        return slots[min(max(slot, 0), slots.count - 1)]
    }

    private func covers(column: Int, row: Int) -> Bool {
        let position = currentSlot
        let span = spanInCells
        return column >= position.col && column < position.col + span.cols
            && row >= position.row && row < position.row + span.rows
    }

    private var spanInCells: (cols: Int, rows: Int) {
        switch rendition {
        case .systemSmall: return (2, 2)
        case .systemMedium: return (4, 2)
        case .systemLarge: return (4, 4)
        default: return (0, 0)
        }
    }

    // MARK: - Chrome

    private func homeScreenChrome(scale: Double) -> some View {
        ZStack(alignment: .topLeading) {
            statusBar(scale: scale)

            // Icon placeholders in every cell the widget doesn't occupy. Kept
            // deliberately quiet — they're context, not content.
            ForEach(0..<Self.rows, id: \.self) { row in
                ForEach(0..<Self.columns, id: \.self) { column in
                    if !covers(column: column, row: row) {
                        iconPlaceholder(scale: scale)
                            .offset(
                                x: (Self.gridOrigin.x + Double(column) * Self.columnPitch) * scale,
                                y: (Self.gridOrigin.y + Double(row) * Self.rowPitch) * scale
                            )
                    }
                }
            }

            // Tappable empty slots, so moving the widget is direct manipulation
            // rather than a stepper somewhere else.
            ForEach(Array(slots.enumerated()), id: \.offset) { index, position in
                let size = rendition.designSize
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: size.width * scale, height: size.height * scale)
                    .offset(
                        x: (Self.gridOrigin.x + Double(position.col) * Self.columnPitch) * scale,
                        y: (Self.gridOrigin.y + Double(position.row) * Self.rowPitch) * scale
                    )
                    .onTapGesture { withAnimation(.snappy) { slot = index } }
            }

            pageDots(scale: scale)
            dock(scale: scale)
        }
    }

    private func lockScreenChrome(scale: Double) -> some View {
        VStack(spacing: 2 * scale) {
            Text("Monday, June 14")
                .font(.system(size: 16 * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("9:41")
                .font(.system(size: 92 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .offset(y: 118 * scale)
    }

    private func statusBar(scale: Double) -> some View {
        HStack {
            Text("9:41")
                .font(.system(size: 15 * scale, weight: .semibold))
            Spacer()
            HStack(spacing: 5 * scale) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 15 * scale, height: 10 * scale)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 34 * scale)
        .offset(y: 20 * scale)
    }

    private func iconPlaceholder(scale: Double) -> some View {
        VStack(spacing: 6 * scale) {
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .fill(.white.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
                .frame(width: Self.iconGlyph * scale, height: Self.iconGlyph * scale)
            Capsule()
                .fill(.white.opacity(0.22))
                .frame(width: 34 * scale, height: 4 * scale)
        }
        // Width only: constraining the height too would push the glyph off its
        // row and break the alignment with the widget beside it.
        .frame(width: Self.iconCell * scale, alignment: .top)
    }

    private func pageDots(scale: Double) -> some View {
        HStack(spacing: 7 * scale) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index == 0 ? 0.9 : 0.35))
                    .frame(width: 7 * scale, height: 7 * scale)
            }
        }
        .frame(maxWidth: .infinity)
        .offset(y: 690 * scale)
    }

    private func dock(scale: Double) -> some View {
        RoundedRectangle(cornerRadius: 34 * scale, style: .continuous)
            .fill(.white.opacity(0.14))
            .overlay {
                HStack(spacing: 30 * scale) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                            .fill(.white.opacity(0.2))
                            .frame(width: Self.iconGlyph * scale, height: Self.iconGlyph * scale)
                    }
                }
            }
            .frame(width: 354 * scale, height: 84 * scale)
            .offset(x: 18 * scale, y: 716 * scale)
    }
}
