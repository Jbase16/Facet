import Foundation
import FacetCore

/// Wave 2: templates exercising schema v2 — gradients, charts, lines,
/// letter-spaced typography, and stack layouts.
extension StarterTemplates {
    static var wave2: [WidgetDocument] {
        [
            sunsetGradientClock, hourlyTemps, stepWeek, focusDashboard,
            bigMinimalTime, batteryBar, nextUp, humidityRing,
        ]
    }

    private static func makeID(_ suffix: String) -> UUID {
        UUID(uuidString: "FACE7000-0000-4000-8000-\(suffix)")!
    }

    // MARK: - Sunset Gradient Clock

    public static var sunsetGradientClock: WidgetDocument {
        let time = Layer(
            id: makeID("000000000041"),
            name: "Time",
            frame: LayerFrame(x: 0.5, y: 0.44, width: 0.94, height: 0.34),
            content: .text(TextContent(
                text: "{time.hour12}:{pad(time.minute, 2)}",
                font: .token("display"),
                color: .token("primary")
            ))
        )
        let date = Layer(
            id: makeID("000000000042"),
            name: "Date",
            frame: LayerFrame(x: 0.5, y: 0.68, width: 0.94, height: 0.12),
            content: .text(TextContent(
                text: "{time.weekdayName} {time.monthName} {time.day}",
                font: .token("caption"),
                color: .token("secondary"),
                letterSpacing: 2.5,
                textCase: .uppercase
            ))
        )
        return WidgetDocument(
            id: makeID("00000000004A"),
            name: "Sunset Gradient Clock",
            tokens: ThemeTokens(
                colors: [
                    "sky1": ColorToken(light: ColorValue(hex: "#FF9A5A")!, dark: ColorValue(hex: "#B34700")!),
                    "sky2": ColorToken(light: ColorValue(hex: "#C0397F")!, dark: ColorValue(hex: "#5A1140")!),
                    "sky3": ColorToken(light: ColorValue(hex: "#4A1E6E")!, dark: ColorValue(hex: "#1E0A30")!),
                    "primary": ColorToken(light: ColorValue(hex: "#FFF8F0")!, dark: ColorValue(hex: "#FFF0E0")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#FFE0C8")!, dark: ColorValue(hex: "#E8C0A0")!),
                ],
                fonts: [
                    "display": FontToken(size: 42, weight: .thin, design: .rounded),
                    "caption": FontToken(size: 10, weight: .semibold),
                ]
            ),
            root: Layer(
                id: makeID("00000000004B"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .linearGradient(GradientFill(
                        stops: [
                            GradientStop(position: 0, color: .token("sky1")),
                            GradientStop(position: 0.55, color: .token("sky2")),
                            GradientStop(position: 1, color: .token("sky3")),
                        ],
                        angle: 105
                    )),
                    children: [time, date]
                ))
            ),
            sources: ["time"],
            overrides: [
                .accessoryRectangular: [
                    LayerPatch(layerID: time.id, frame: LayerFrame(x: 0.5, y: 0.5, width: 0.94, height: 0.7), fontSize: 26),
                    LayerPatch(layerID: date.id, isHidden: true),
                ],
            ]
        )
    }

    // MARK: - Hourly Temps

    public static var hourlyTemps: WidgetDocument {
        let temperature = Layer(
            id: makeID("000000000051"),
            name: "Temperature",
            frame: LayerFrame(x: 0.24, y: 0.26, width: 0.4, height: 0.3),
            content: .text(TextContent(
                text: "{round(weather.temperature)}°",
                font: .token("display"),
                color: .token("primary"),
                alignment: .leading
            ))
        )
        let range = Layer(
            id: makeID("000000000052"),
            name: "Range",
            frame: LayerFrame(x: 0.76, y: 0.22, width: 0.4, height: 0.14),
            content: .text(TextContent(
                text: "H {round(weather.high)}°  L {round(weather.low)}°",
                font: .token("caption"),
                color: .token("secondary"),
                alignment: .trailing
            ))
        )
        let condition = Layer(
            id: makeID("000000000053"),
            name: "Condition",
            frame: LayerFrame(x: 0.76, y: 0.36, width: 0.4, height: 0.12),
            content: .text(TextContent(
                text: "{weather.condition}",
                font: .token("caption"),
                color: .token("secondary"),
                alignment: .trailing
            ))
        )
        let spark = Layer(
            id: makeID("000000000054"),
            name: "Hourly",
            frame: LayerFrame(x: 0.5, y: 0.72, width: 0.88, height: 0.34),
            content: .chart(ChartContent(
                dataPath: "weather.hourly",
                style: .area,
                color: .token("accent"),
                lineWidth: 2.5
            ))
        )
        return WidgetDocument(
            id: makeID("00000000005A"),
            name: "Hourly Temps",
            tokens: ThemeTokens(
                colors: [
                    "background": ColorToken(light: ColorValue(hex: "#F2F7FC")!, dark: ColorValue(hex: "#0E1722")!),
                    "primary": ColorToken(light: ColorValue(hex: "#12263A")!, dark: ColorValue(hex: "#EAF2FA")!),
                    "secondary": ColorToken(light: ColorValue(hex: "#5C7A99")!, dark: ColorValue(hex: "#8FA9C4")!),
                    "accent": ColorToken(light: ColorValue(hex: "#1E88E5")!, dark: ColorValue(hex: "#64B5F6")!),
                ],
                fonts: [
                    "display": FontToken(size: 34, weight: .semibold, design: .rounded),
                    "caption": FontToken(size: 11, weight: .medium),
                ]
            ),
            root: Layer(
                id: makeID("00000000005B"),
                name: "Canvas",
                content: .container(ContainerContent(
                    layout: .absolute,
                    background: .token("background"),
                    children: [temperature, range, condition, spark]
                ))
            ),
            sources: ["weather"],
            overrides: [
                .accessoryRectangular: [
                    LayerPatch(layerID: range.id, isHidden: true),
                    LayerPatch(layerID: condition.id, isHidden: true),
                    LayerPatch(layerID: temperature.id, frame: LayerFrame(x: 0.2, y: 0.5, width: 0.34, height: 0.7), fontSize: 22),
                    LayerPatch(layerID: spark.id, frame: LayerFrame(x: 0.68, y: 0.5, width: 0.58, height: 0.72)),
                ],
            ]
        )
    }
}
