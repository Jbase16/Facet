import Foundation
import FacetCore

extension StarterTemplates {
    private static func makeID(_ suffix: String) -> UUID {
        UUID(uuidString: "FACE7000-0000-4000-8000-\(suffix)")!
    }

    // MARK: - Step Week

    public static var stepWeek: WidgetDocument {
        let count = Layer(
            id: makeID("000000000061"),
            name: "Count",
            frame: LayerFrame(x: 0.5, y: 0.2, width: 0.88, height: 0.24),
            content: .text(TextContent(
                text: "{health.steps}",
                font: .token("display"),
                color: .token("primary")
            ))
        )
        let caption = Layer(
            id: makeID("000000000062"),
            name: "Caption",
            frame: LayerFrame(x: 0.5, y: 0.38, width: 0.88, height: 0.1),
            content: .text(TextContent(
                text: "steps this week",
                font: .token("caption"),
                color: .token("secondary"),
                letterSpacing: 1.5,
                textCase: .uppercase
            ))
        )
        let bars = Layer(
            id: makeID("000000000063"),
            name: "Week",
            frame: LayerFrame(x: 0.5, y: 0.72, width: 0.84, height: 0.36),
            content: .chart(ChartContent(
                dataPath: "health.weekSteps",
                style: .bars,
                color: .token("accent")
            ))
        )
        let goal = Layer(
            id: makeID("000000000064"),
            name: "Goal",
            frame: LayerFrame(x: 0.5, y: 0.55, width: 0.84, height: 0.02),
            content: .line(LineContent(color: .token("secondary"), thickness: 1, dash: [3, 3]))
        )
        return WidgetDocument(
            id: makeID("00000000006A"),
            name: "Step Week",
            tokens: ThemeTokens(
                colors: [
                    "background": ColorToken(light: ColorValue(hex: "#FFFFFF")!, dark: ColorValue(hex: "#161616")!),
                    "primary": ColorToken(light: ColorValue(hex: "#101010")!, dark: ColorValue(hex: "#F5F5F5")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#8E8E93")!, dark: ColorValue(hex: "#98989E")!),
                    "accent": ColorToken(light: ColorValue(hex: "#FF3B30")!, dark: ColorValue(hex: "#FF453A")!),
                ],
                fonts: [
                    "display": FontToken(size: 30, weight: .heavy, design: .rounded),
                    "caption": FontToken(size: 9, weight: .semibold),
                ]
            ),
            root: Layer(
                id: makeID("00000000006B"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("background"),
                    children: [count, caption, goal, bars]
                ))
            ),
            sources: ["health"],
            overrides: [
                .accessoryRectangular: [
                    LayerPatch(layerID: caption.id, isHidden: true),
                    LayerPatch(layerID: goal.id, isHidden: true),
                    LayerPatch(layerID: count.id, frame: LayerFrame(x: 0.26, y: 0.5, width: 0.44, height: 0.6), fontSize: 20),
                    LayerPatch(layerID: bars.id, frame: LayerFrame(x: 0.72, y: 0.5, width: 0.5, height: 0.7)),
                ],
            ]
        )
    }

    // MARK: - Focus Dashboard

    public static var focusDashboard: WidgetDocument {
        func column(idSuffix: String, value: String, label: String) -> Layer {
            Layer(
                id: makeID("0000000000\(idSuffix)1"),
                name: "\(label) column",
                frame: LayerFrame(width: 0.3, height: 1.0),
                content: .container(ContainerContent(
                    layout: .absolute,
                    children: [
                        Layer(
                            id: makeID("0000000000\(idSuffix)2"),
                            name: "\(label) value",
                            frame: LayerFrame(x: 0.5, y: 0.4, width: 1, height: 0.4),
                            content: .text(TextContent(
                                text: value,
                                font: .token("value"),
                                color: .token("primary")
                            ))
                        ),
                        Layer(
                            id: makeID("0000000000\(idSuffix)3"),
                            name: "\(label) label",
                            frame: LayerFrame(x: 0.5, y: 0.72, width: 1, height: 0.2),
                            content: .text(TextContent(
                                text: label,
                                font: .token("label"),
                                color: .token("secondary"),
                                letterSpacing: 1.2,
                                textCase: .uppercase
                            ))
                        ),
                    ]
                ))
            )
        }
        func divider(idSuffix: String) -> Layer {
            Layer(
                id: makeID("0000000000\(idSuffix)"),
                name: "Divider",
                frame: LayerFrame(width: 0.01, height: 0.5),
                style: LayerStyle(rotation: 90),
                content: .line(LineContent(color: .token("secondary"), thickness: 0.5))
            )
        }
        let row = Layer(
            id: makeID("00000000007B"),
            name: "Row",
            content: .container(ContainerContent(
                layout: .horizontal,
                spacing: 4,
                padding: 10,
                background: .token("background"),
                children: [
                    column(idSuffix: "7", value: "{health.steps}", label: "steps"),
                    divider(idSuffix: "78"),
                    column(idSuffix: "8", value: "{round(health.activeEnergy)}", label: "kcal"),
                    divider(idSuffix: "89"),
                    column(idSuffix: "9", value: "{health.standHours}", label: "stand"),
                ]
            ))
        )
        return WidgetDocument(
            id: makeID("00000000007A"),
            name: "Focus Dashboard",
            tokens: ThemeTokens(
                colors: [
                    "background": ColorToken(light: ColorValue(hex: "#F7F7F9")!, dark: ColorValue(hex: "#141416")!),
                    "primary": ColorToken(light: ColorValue(hex: "#111114")!, dark: ColorValue(hex: "#F2F2F5")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#9999A0")!, dark: ColorValue(hex: "#8A8A90")!),
                ],
                fonts: [
                    "value": FontToken(size: 24, weight: .bold, design: .rounded),
                    "label": FontToken(size: 9, weight: .semibold),
                ]
            ),
            root: row,
            sources: ["health"]
        )
    }

    // MARK: - Big Minimal Time

    public static var bigMinimalTime: WidgetDocument {
        let time = Layer(
            id: makeID("000000000081"),
            name: "Time",
            frame: LayerFrame(x: 0.5, y: 0.5, width: 0.96, height: 0.5),
            content: .text(TextContent(
                text: "{time.hour12}:{pad(time.minute, 2)}",
                font: .token("display"),
                color: .token("primary")
            ))
        )
        return WidgetDocument(
            id: makeID("00000000008A"),
            name: "Big Minimal Time",
            tokens: ThemeTokens(
                colors: [
                    "background": ColorToken(light: ColorValue(hex: "#0A0A0A")!, dark: ColorValue(hex: "#0A0A0A")!),
                    "primary": ColorToken(light: ColorValue(hex: "#F5F5F0")!, dark: ColorValue(hex: "#F5F5F0")!),
                ],
                fonts: ["display": FontToken(size: 52, weight: .heavy, design: .rounded)]
            ),
            root: Layer(
                id: makeID("00000000008B"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("background"),
                    children: [time]
                ))
            ),
            sources: ["time"],
            overrides: [
                .accessoryRectangular: [LayerPatch(layerID: time.id, fontSize: 26)],
                .accessoryCircular: [LayerPatch(layerID: time.id, fontSize: 16)],
                .accessoryInline: [LayerPatch(layerID: time.id, fontSize: 14)],
            ]
        )
    }

    // MARK: - Battery Bar

    public static var batteryBar: WidgetDocument {
        let percent = Layer(
            id: makeID("000000000091"),
            name: "Percent",
            frame: LayerFrame(x: 0.5, y: 0.32, width: 0.86, height: 0.28),
            content: .text(TextContent(
                text: "{percent(battery.level)}",
                font: .token("display"),
                color: .token("primary")
            ))
        )
        let state = Layer(
            id: makeID("000000000092"),
            name: "State",
            frame: LayerFrame(x: 0.5, y: 0.52, width: 0.86, height: 0.1),
            content: .text(TextContent(
                text: "{battery.state}",
                font: .token("caption"),
                color: .token("secondary"),
                letterSpacing: 1.5,
                textCase: .uppercase
            ))
        )
        let bar = Layer(
            id: makeID("000000000093"),
            name: "Bar",
            frame: LayerFrame(x: 0.5, y: 0.72, width: 0.82, height: 0.1),
            content: .gauge(GaugeContent(
                value: "battery.level",
                style: .bar,
                tint: .token("accent"),
                track: .token("track")
            ))
        )
        return WidgetDocument(
            id: makeID("00000000009A"),
            name: "Battery Bar",
            tokens: ThemeTokens(
                colors: [
                    "card1": ColorToken(light: ColorValue(hex: "#EAFBF1")!, dark: ColorValue(hex: "#0D1F16")!),
                    "card2": ColorToken(light: ColorValue(hex: "#D3F2E0")!, dark: ColorValue(hex: "#132A1E")!),
                    "primary": ColorToken(light: ColorValue(hex: "#0B3D24")!, dark: ColorValue(hex: "#D9F5E6")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#4E8B6B")!, dark: ColorValue(hex: "#7FBF9E")!),
                    "accent": ColorToken(light: ColorValue(hex: "#28A05C")!, dark: ColorValue(hex: "#30D158")!),
                    "track": ColorToken(light: ColorValue(hex: "#C4E5D2")!, dark: ColorValue(hex: "#24382E")!),
                ],
                fonts: [
                    "display": FontToken(size: 30, weight: .bold, design: .rounded),
                    "caption": FontToken(size: 9, weight: .semibold),
                ]
            ),
            root: Layer(
                id: makeID("00000000009B"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .linearGradient(GradientFill(
                        stops: [
                            GradientStop(position: 0, color: .token("card1")),
                            GradientStop(position: 1, color: .token("card2")),
                        ],
                        angle: 135
                    )),
                    children: [percent, state, bar]
                ))
            ),
            sources: ["battery"],
            overrides: [
                .accessoryRectangular: [
                    LayerPatch(layerID: state.id, isHidden: true),
                    LayerPatch(layerID: percent.id, frame: LayerFrame(x: 0.5, y: 0.32, width: 0.9, height: 0.5), fontSize: 20),
                    LayerPatch(layerID: bar.id, frame: LayerFrame(x: 0.5, y: 0.74, width: 0.9, height: 0.16)),
                ],
            ]
        )
    }

    // MARK: - Next Up

    public static var nextUp: WidgetDocument {
        let icon = Layer(
            id: makeID("0000000000A1"),
            name: "Icon",
            frame: LayerFrame(x: 0.16, y: 0.2, width: 0.2, height: 0.2),
            content: .symbol(SymbolContent(systemName: "calendar", color: .token("accent"), size: 18))
        )
        let title = Layer(
            id: makeID("0000000000A2"),
            name: "Title",
            frame: LayerFrame(x: 0.55, y: 0.42, width: 0.86, height: 0.3),
            content: .text(TextContent(
                text: "{calendar.nextTitle}",
                font: .token("title"),
                color: .token("primary"),
                alignment: .leading,
                maxLines: 2
            ))
        )
        let countdown = Layer(
            id: makeID("0000000000A3"),
            name: "Countdown",
            frame: LayerFrame(x: 0.55, y: 0.64, width: 0.86, height: 0.12),
            content: .text(TextContent(
                text: "in {round((calendar.nextStart - time.timestamp) / 60)} min",
                font: .token("caption"),
                color: .token("accent"),
                alignment: .leading
            ))
        )
        let today = Layer(
            id: makeID("0000000000A4"),
            name: "Today",
            frame: LayerFrame(x: 0.55, y: 0.84, width: 0.86, height: 0.1),
            content: .text(TextContent(
                text: "{calendar.todayCount} events today",
                font: .token("caption"),
                color: .token("secondary"),
                alignment: .leading
            ))
        )
        return WidgetDocument(
            id: makeID("0000000000AA"),
            name: "Next Up",
            tokens: ThemeTokens(
                colors: [
                    "background": ColorToken(light: ColorValue(hex: "#FFFFFF")!, dark: ColorValue(hex: "#17171A")!),
                    "primary": ColorToken(light: ColorValue(hex: "#141418")!, dark: ColorValue(hex: "#F2F2F6")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#95959C")!, dark: ColorValue(hex: "#8A8A92")!),
                    "accent": ColorToken(light: ColorValue(hex: "#E4572E")!, dark: ColorValue(hex: "#FF7A50")!),
                ],
                fonts: [
                    "title": FontToken(size: 16, weight: .semibold),
                    "caption": FontToken(size: 11, weight: .medium),
                ]
            ),
            root: Layer(
                id: makeID("0000000000AB"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("background"),
                    children: [icon, title, countdown, today]
                ))
            ),
            sources: ["calendar", "time"],
            overrides: [
                .accessoryRectangular: [
                    LayerPatch(layerID: icon.id, isHidden: true),
                    LayerPatch(layerID: today.id, isHidden: true),
                    LayerPatch(layerID: title.id, frame: LayerFrame(x: 0.5, y: 0.32, width: 0.96, height: 0.5)),
                    LayerPatch(layerID: countdown.id, frame: LayerFrame(x: 0.5, y: 0.76, width: 0.96, height: 0.3)),
                ],
            ]
        )
    }

    // MARK: - Humidity Ring

    public static var humidityRing: WidgetDocument {
        let ring = Layer(
            id: makeID("0000000000B1"),
            name: "Ring",
            frame: LayerFrame(width: 0.78, height: 0.78),
            content: .gauge(GaugeContent(
                value: "weather.humidity",
                tint: .token("accent"),
                track: .token("track"),
                lineWidth: 9
            ))
        )
        let percent = Layer(
            id: makeID("0000000000B2"),
            name: "Percent",
            frame: LayerFrame(x: 0.5, y: 0.46, width: 0.6, height: 0.2),
            content: .text(TextContent(
                text: "{percent(weather.humidity)}",
                font: .token("display"),
                color: .token("primary")
            ))
        )
        let caption = Layer(
            id: makeID("0000000000B3"),
            name: "Caption",
            frame: LayerFrame(x: 0.5, y: 0.6, width: 0.6, height: 0.1),
            content: .text(TextContent(
                text: "humidity",
                font: .token("caption"),
                color: .token("secondary"),
                letterSpacing: 1.8,
                textCase: .uppercase
            ))
        )
        return WidgetDocument(
            id: makeID("0000000000BA"),
            name: "Humidity Ring",
            tokens: ThemeTokens(
                colors: [
                    "deep": ColorToken(light: ColorValue(hex: "#E8F4FD")!, dark: ColorValue(hex: "#0A1B28")!),
                    "edge": ColorToken(light: ColorValue(hex: "#C9E4F8")!, dark: ColorValue(hex: "#132C40")!),
                    "primary": ColorToken(light: ColorValue(hex: "#0E2A40")!, dark: ColorValue(hex: "#E4F1FB")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#5E86A6")!, dark: ColorValue(hex: "#7FA6C4")!),
                    "accent": ColorToken(light: ColorValue(hex: "#0A84FF")!, dark: ColorValue(hex: "#409CFF")!),
                    "track": ColorToken(light: ColorValue(hex: "#CFE3F2")!, dark: ColorValue(hex: "#1C3A52")!),
                ],
                fonts: [
                    "display": FontToken(size: 22, weight: .bold, design: .rounded),
                    "caption": FontToken(size: 8, weight: .semibold),
                ]
            ),
            root: Layer(
                id: makeID("0000000000BB"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .radialGradient(GradientFill(stops: [
                        GradientStop(position: 0, color: .token("deep")),
                        GradientStop(position: 1, color: .token("edge")),
                    ])),
                    children: [ring, percent, caption]
                ))
            ),
            sources: ["weather"],
            overrides: [
                .accessoryCircular: [
                    LayerPatch(layerID: caption.id, isHidden: true),
                    LayerPatch(layerID: percent.id, frame: LayerFrame(x: 0.5, y: 0.5, width: 0.7, height: 0.36), fontSize: 15),
                    LayerPatch(layerID: ring.id, frame: LayerFrame(width: 0.94, height: 0.94)),
                ],
            ]
        )
    }
}
