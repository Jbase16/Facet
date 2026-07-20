import SwiftUI

/// Facet's visual language. One place, used everywhere — the app is a design
/// tool, so its own chrome holds to a designed system: near-black surfaces,
/// hairline separation, a single accent, and tight typographic hierarchy.
/// Stock system styling is the enemy here.
enum FacetUI {
    // MARK: Surfaces (dark-first; the canvas is the star, chrome recedes)

    /// App background — near-black with a whisper of blue so pure-black
    /// widget previews still separate from it.
    static let bg = Color(red: 0.043, green: 0.043, blue: 0.059)
    /// Cards, bars, sheets.
    static let surface = Color(red: 0.078, green: 0.078, blue: 0.098)
    /// Elements raised above a surface (tiles, fields, chips).
    static let raised = Color(red: 0.11, green: 0.11, blue: 0.141)
    /// Hairline borders — separation by line, not by shadow.
    static let hairline = Color.white.opacity(0.08)
    /// Stronger border for focused/selected states.
    static let hairlineStrong = Color.white.opacity(0.16)

    // MARK: Ink

    static let ink = Color(red: 0.957, green: 0.957, blue: 0.965)
    static let inkSecondary = Color.white.opacity(0.55)
    static let inkTertiary = Color.white.opacity(0.32)

    /// The one accent: Facet violet. Selection, primary actions, focus.
    static let accent = Color(red: 0.545, green: 0.475, blue: 1.0)
    static let accentDim = Color(red: 0.545, green: 0.475, blue: 1.0).opacity(0.16)

    static let live = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let sample = Color(red: 1.0, green: 0.70, blue: 0.35)

    // MARK: Type

    static func title(_ size: Double = 24) -> Font {
        .system(size: size, weight: .semibold)
    }
    static let label = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11, weight: .medium)
    /// Small-caps section eyebrow, the quiet backbone of the hierarchy.
    static let eyebrow = Font.system(size: 11, weight: .semibold)

    static let cornerRadius: Double = 14
}

// MARK: - Reusable chrome

/// A raised tile: the standard container for anything sitting on `bg`.
struct FacetPanel: ViewModifier {
    var radius: Double = FacetUI.cornerRadius
    func body(content: Content) -> some View {
        content
            .background(FacetUI.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(FacetUI.hairline, lineWidth: 1)
            }
    }
}

extension View {
    func facetPanel(radius: Double = FacetUI.cornerRadius) -> some View {
        modifier(FacetPanel(radius: radius))
    }

    /// Section eyebrow text treatment (VS "Section Header" caps noise).
    func facetEyebrow() -> some View {
        font(FacetUI.eyebrow)
            .textCase(.uppercase)
            .kerning(1.1)
            .foregroundStyle(FacetUI.inkTertiary)
    }
}

/// Circular chrome button for toolbars — consistent hit target, quiet until
/// pressed, never a bare blue SF symbol floating in space.
struct FacetToolButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(prominent ? FacetUI.bg : FacetUI.ink)
            .frame(width: 34, height: 34)
            .background(prominent ? FacetUI.accent : FacetUI.raised)
            .clipShape(Circle())
            .overlay {
                if !prominent {
                    Circle().strokeBorder(FacetUI.hairline, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}

/// Status pill — Live / Sample / counts. Color-coded but quiet.
struct FacetPill: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(FacetUI.caption)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }
}

/// The design-tool signature: a dot-grid canvas backdrop. Subtle, endless,
/// instantly reads as "workspace" rather than "screen".
struct DotGrid: View {
    var spacing: Double = 22
    var body: some View {
        Canvas { context, size in
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.6, height: 1.6))
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    context.fill(
                        dot.offsetBy(dx: x, dy: y),
                        with: .color(.white.opacity(0.055))
                    )
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
