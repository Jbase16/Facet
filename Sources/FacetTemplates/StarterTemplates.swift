import Foundation
import FacetCore

/// The built-in starter templates that ship with the app. Each is a plain
/// `WidgetDocument` — users open them in the editor and remix from there.
/// Deterministic UUIDs keep encoded output stable across builds.
public enum StarterTemplates {
    public static var all: [WidgetDocument] {
        [batteryRing, weatherGlance, stepsDashboard, minimalClock]
    }

    public static func template(named name: String) -> WidgetDocument? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func uuid(_ suffix: String) -> UUID {
        UUID(uuidString: "FACE7000-0000-4000-8000-\(suffix)")!
    }

    // MARK: - Battery Ring

    public static var batteryRing: WidgetDocument {
        let ring = Layer(
            id: uuid("000000000001"),
            name: "Ring",
            frame: LayerFrame(width: 0.82, height: 0.82),
            content: .gauge(GaugeContent(
                value: "battery.level",
                tint: .token("accent"),
                track: .token("track"),
                lineWidth: 10
            ))
        )
        let percent = Layer(
            id: uuid("000000000002"),
            name: "Percent",
            frame: LayerFrame(x: 0.5, y: 0.46, width: 0.7, height: 0.24),
            content: .text(TextContent(
                text: "{round(battery.level * 100)}",
                font: .token("display"),
                color: .token("primary")
            ))
        )
        let caption = Layer(
            id: uuid("000000000003"),
            name: "Caption",
            frame: LayerFrame(x: 0.5, y: 0.62, width: 0.7, height: 0.12),
            content: .text(TextContent(
                text: "{battery.state == 'charging' ? '⚡ charging' : 'battery'}",
                font: .token("caption"),
                color: .token("secondary")
            ))
        )
        return WidgetDocument(
            id: uuid("00000000000A"),
            name: "Battery Ring",
            tokens: ThemeTokens(
                colors: [
                    "background": ColorToken(light: ColorValue(hex: "#FFFFFF")!, dark: ColorValue(hex: "#1C1C1E")!),
                    "primary": ColorToken(light: ColorValue(hex: "#000000")!, dark: ColorValue(hex: "#FFFFFF")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#6C6C70")!, dark: ColorValue(hex: "#98989E")!),
                    "accent": ColorToken(light: ColorValue(hex: "#34C759")!, dark: ColorValue(hex: "#30D158")!),
                    "track": ColorToken(light: ColorValue(hex: "#E5E5EA")!, dark: ColorValue(hex: "#3A3A3C")!),
                ],
                fonts: [
                    "display": FontToken(size: 34, weight: .bold, design: .rounded),
                    "caption": FontToken(size: 11, weight: .medium, design: .rounded),
                ]
            ),
            root: Layer(
                id: uuid("00000000000B"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("background"),
                    children: [ring, percent, caption]
                ))
            ),
            sources: ["battery"],
            overrides: [
                .accessoryCircular: [
                    LayerPatch(layerID: caption.id, isHidden: true),
                    LayerPatch(layerID: percent.id, frame: LayerFrame(x: 0.5, y: 0.5, width: 0.7, height: 0.4), fontSize: 18),
                ],
            ]
        )
    }

    // MARK: - Weather Glance

    public static var weatherGlance: WidgetDocument {
        let icon = Layer(
            id: uuid("000000000011"),
            name: "Icon",
            frame: LayerFrame(x: 0.22, y: 0.32, width: 0.32, height: 0.4),
            content: .symbol(SymbolContent(
                systemName: "cloud.sun.fill",
                color: .token("accent"),
                size: 36
            ))
        )
        let temperature = Layer(
            id: uuid("000000000012"),
            name: "Temperature",
            frame: LayerFrame(x: 0.68, y: 0.32, width: 0.5, height: 0.34),
            content: .text(TextContent(
                text: "{round(weather.temperature)}°",
                font: .token("display"),
                color: .token("primary")
            ))
        )
        let condition = Layer(
            id: uuid("000000000013"),
            name: "Condition",
            frame: LayerFrame(x: 0.5, y: 0.66, width: 0.9, height: 0.14),
            content: .text(TextContent(
                text: "{weather.condition}",
                font: .token("body"),
                color: .token("secondary")
            ))
        )
        let range = Layer(
            id: uuid("000000000014"),
            name: "Range",
            frame: LayerFrame(x: 0.5, y: 0.84, width: 0.9, height: 0.12),
            content: .text(TextContent(
                text: "H {round(weather.high)}°  L {round(weather.low)}°",
                font: .token("caption"),
                color: .token("secondary")
            ))
        )
        return WidgetDocument(
            id: uuid("00000000001A"),
            name: "Weather Glance",
            tokens: ThemeTokens(
                colors: [
                    "background": ColorToken(light: ColorValue(hex: "#EAF4FF")!, dark: ColorValue(hex: "#101D2C")!),
                    "primary": ColorToken(light: ColorValue(hex: "#0A2540")!, dark: ColorValue(hex: "#EAF4FF")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#5C7A99")!, dark: ColorValue(hex: "#8FA9C4")!),
                    "accent": ColorToken(light: ColorValue(hex: "#F5A623")!, dark: ColorValue(hex: "#FFC94D")!),
                ],
                fonts: [
                    "display": FontToken(size: 32, weight: .semibold, design: .rounded),
                    "body": FontToken(size: 13, weight: .medium),
                    "caption": FontToken(size: 11, weight: .regular),
                ]
            ),
            root: Layer(
                id: uuid("00000000001B"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("background"),
                    children: [icon, temperature, condition, range]
                ))
            ),
            sources: ["weather"],
            overrides: [
                .accessoryRectangular: [
                    LayerPatch(layerID: range.id, isHidden: true),
                    LayerPatch(layerID: icon.id, frame: LayerFrame(x: 0.14, y: 0.5, width: 0.24, height: 0.7), fontSize: 20),
                    LayerPatch(layerID: temperature.id, frame: LayerFrame(x: 0.6, y: 0.34, width: 0.6, height: 0.5), fontSize: 22),
                    LayerPatch(layerID: condition.id, frame: LayerFrame(x: 0.6, y: 0.74, width: 0.66, height: 0.36), fontSize: 11),
                ],
            ]
        )
    }

    // MARK: - Steps Dashboard

    public static var stepsDashboard: WidgetDocument {
        let progress = Layer(
            id: uuid("000000000021"),
            name: "Progress",
            frame: LayerFrame(x: 0.5, y: 0.78, width: 0.84, height: 0.09),
            content: .gauge(GaugeContent(
                value: "clamp(health.steps / health.stepsGoal, 0, 1)",
                style: .bar,
                tint: .token("accent"),
                track: .token("track")
            ))
        )
        let count = Layer(
            id: uuid("000000000022"),
            name: "Count",
            frame: LayerFrame(x: 0.5, y: 0.34, width: 0.86, height: 0.3),
            content: .text(TextContent(
                text: "{health.steps}",
                font: .token("display"),
                color: .token("primary")
            ))
        )
        let label = Layer(
            id: uuid("000000000023"),
            name: "Label",
            frame: LayerFrame(x: 0.5, y: 0.56, width: 0.86, height: 0.12),
            content: .text(TextContent(
                text: "of {health.stepsGoal} steps · {percent(clamp(health.steps / health.stepsGoal, 0, 1))}",
                font: .token("caption"),
                color: .token("secondary")
            ))
        )
        return WidgetDocument(
            id: uuid("00000000002A"),
            name: "Steps Dashboard",
            tokens: ThemeTokens(
                colors: [
                    "background": ColorToken(light: ColorValue(hex: "#FFF7ED")!, dark: ColorValue(hex: "#221A10")!),
                    "primary": ColorToken(light: ColorValue(hex: "#3D2E1E")!, dark: ColorValue(hex: "#FFF3E3")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#8A7A66")!, dark: ColorValue(hex: "#B3A18B")!),
                    "accent": ColorToken(light: ColorValue(hex: "#FF9500")!, dark: ColorValue(hex: "#FF9F0A")!),
                    "track": ColorToken(light: ColorValue(hex: "#EFE3D3")!, dark: ColorValue(hex: "#3A2F22")!),
                ],
                fonts: [
                    "display": FontToken(size: 30, weight: .bold, design: .rounded),
                    "caption": FontToken(size: 11, weight: .medium, design: .rounded),
                ]
            ),
            root: Layer(
                id: uuid("00000000002B"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("background"),
                    children: [count, label, progress]
                ))
            ),
            sources: ["health"]
        )
    }

    // MARK: - Minimal Clock

    public static var minimalClock: WidgetDocument {
        let time = Layer(
            id: uuid("000000000031"),
            name: "Time",
            frame: LayerFrame(x: 0.5, y: 0.42, width: 0.9, height: 0.34),
            content: .text(TextContent(
                text: "{time.hour12}:{pad(time.minute, 2)}",
                font: .token("display"),
                color: .token("primary")
            ))
        )
        let date = Layer(
            id: uuid("000000000032"),
            name: "Date",
            frame: LayerFrame(x: 0.5, y: 0.66, width: 0.9, height: 0.14),
            content: .text(TextContent(
                text: "{time.weekdayName}, {time.monthName} {time.day}",
                font: .token("caption"),
                color: .token("secondary")
            ))
        )
        return WidgetDocument(
            id: uuid("00000000003A"),
            name: "Minimal Clock",
            tokens: ThemeTokens(
                colors: [
                    "background": ColorToken(light: ColorValue(hex: "#111111")!, dark: ColorValue(hex: "#111111")!),
                    "primary": ColorToken(light: ColorValue(hex: "#FFFFFF")!, dark: ColorValue(hex: "#FFFFFF")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#9A9AA0")!, dark: ColorValue(hex: "#9A9AA0")!),
                ],
                fonts: [
                    "display": FontToken(size: 40, weight: .light, design: .serif),
                    "caption": FontToken(size: 12, weight: .regular),
                ]
            ),
            root: Layer(
                id: uuid("00000000003B"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("background"),
                    children: [time, date]
                ))
            ),
            sources: ["time"]
        )
    }
}
