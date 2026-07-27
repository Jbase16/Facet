import CoreGraphics

/// The iOS home-screen icon grid, in points on the reference device.
///
/// Three surfaces draw this grid — the single-widget preview, the scene editor,
/// and the scene thumbnails in the gallery — and they must agree exactly. When
/// each kept its own copy of these numbers, "where does a medium widget sit"
/// had three answers that only happened to match.
///
/// Every value is solved from `RenditionKind.designSize` on a 390×844 screen:
/// a small widget is 158pt across, which is two 68pt icon cells plus the 22pt
/// gutter between them, so `columnPitch` is 90 and the widget spans two columns.
enum HomeGrid {
    /// Reference device: the 390×844 class the schema's design sizes belong to.
    static let screen = CGSize(width: 390, height: 844)
    static let iconCell = 68.0
    static let columnPitch = 90.0
    static let rowCell = 60.0
    static let rowPitch = 98.0
    /// The icon glyph itself is 60pt on this device class — the same as the row
    /// cell, which is what makes a widget's top edge line up with the icons
    /// beside it. (The 68pt column cell is pitch minus gutter, not glyph size.)
    static let iconGlyph = 60.0
    static let gridOrigin = CGPoint(x: 26, y: 78)
    static let columns = 4
    static let rows = 6

    /// Top-left corner of the given cell, in reference-screen points.
    static func origin(column: Int, row: Int) -> CGPoint {
        CGPoint(
            x: gridOrigin.x + Double(column) * columnPitch,
            y: gridOrigin.y + Double(row) * rowPitch
        )
    }
}
