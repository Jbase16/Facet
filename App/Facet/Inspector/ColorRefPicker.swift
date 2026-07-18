import SwiftUI
import UIKit
import FacetCore

extension ColorValue {
    init(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }
}

/// Pick a color for a layer: the document's tokens as swatches (the
/// encouraged path — token colors restyle with the theme and adapt to dark
/// mode) or a custom literal.
struct ColorRefPicker: View {
    let label: String
    let tokens: [String: ColorToken]
    let scheme: FacetCore.ColorScheme
    @Binding var selection: ColorRef

    private var customBinding: Binding<Color> {
        Binding(
            get: {
                if case .literal(let value) = selection { return Color(value) }
                return .white
            },
            set: { selection = .literal(ColorValue($0)) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(tokens.keys.sorted(), id: \.self) { name in
                        swatch(name: name, token: tokens[name]!)
                    }
                    ColorPicker("", selection: customBinding, supportsOpacity: true)
                        .labelsHidden()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func swatch(name: String, token: ColorToken) -> some View {
        let isSelected = selection == .token(name)
        return Button {
            selection = .token(name)
        } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(Color(token.resolved(for: scheme)))
                    .frame(width: 26, height: 26)
                    .overlay {
                        Circle().strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                    }
                Text(name)
                    .font(.system(size: 8))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A Fill (solid / linear / radial gradient) editor built on ColorRefPicker.
/// Gradients edit as two stops plus an angle — covers the common cases
/// without turning the inspector into a gradient workstation.
struct FillPicker: View {
    let label: String
    let tokens: [String: ColorToken]
    let scheme: FacetCore.ColorScheme
    @Binding var selection: Fill

    private enum Mode: String, CaseIterable {
        case solid = "Solid"
        case linear = "Linear"
        case radial = "Radial"
    }

    private var mode: Mode {
        switch selection {
        case .color: return .solid
        case .linearGradient: return .linear
        case .radialGradient: return .radial
        }
    }

    private var gradient: GradientFill {
        switch selection {
        case .color(let ref):
            return GradientFill(stops: [
                GradientStop(position: 0, color: ref),
                GradientStop(position: 1, color: ref),
            ])
        case .linearGradient(let value), .radialGradient(let value):
            return value
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(label, selection: Binding(get: { mode }, set: { setMode($0) })) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch selection {
            case .color:
                ColorRefPicker(
                    label: label,
                    tokens: tokens,
                    scheme: scheme,
                    selection: Binding(
                        get: {
                            if case .color(let ref) = selection { return ref }
                            return .literal(.white)
                        },
                        set: { selection = .color($0) }
                    )
                )
            case .linearGradient, .radialGradient:
                ColorRefPicker(label: "Start", tokens: tokens, scheme: scheme, selection: stopBinding(0))
                ColorRefPicker(label: "End", tokens: tokens, scheme: scheme, selection: stopBinding(1))
                if case .linearGradient(let value) = selection {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Angle  \(Int(value.angle))°")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { value.angle },
                                set: { angle in
                                    var updated = value
                                    updated.angle = angle
                                    selection = .linearGradient(updated)
                                }
                            ),
                            in: 0...360, step: 15
                        )
                    }
                }
            }
        }
    }

    private func setMode(_ newMode: Mode) {
        let current = gradient
        switch newMode {
        case .solid: selection = .color(current.stops.first?.color ?? .literal(.white))
        case .linear: selection = .linearGradient(current)
        case .radial: selection = .radialGradient(current)
        }
    }

    private func stopBinding(_ index: Int) -> Binding<ColorRef> {
        Binding(
            get: {
                let stops = gradient.stops
                return index < stops.count ? stops[index].color : .literal(.white)
            },
            set: { color in
                var value = gradient
                while value.stops.count < 2 {
                    value.stops.append(GradientStop(position: 1, color: color))
                }
                value.stops[index].color = color
                if case .radialGradient = selection {
                    selection = .radialGradient(value)
                } else {
                    selection = .linearGradient(value)
                }
            }
        )
    }
}
