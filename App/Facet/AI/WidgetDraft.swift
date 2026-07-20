import Foundation
import FoundationModels

// The intermediate schema for on-device generation. Deliberately narrower
// than the real document model: guided generation is reliable in proportion
// to how constrained the schema is, so the model picks from a few layer
// kinds, flat frames, and plain hex strings. DraftMapper turns the result
// into a real WidgetDocument; the draft never leaves the generation path.

@available(iOS 26.0, *)
@Generable(description: "A complete home-screen widget design.")
struct WidgetDraft {
    @Guide(description: "Short widget name, 1-3 words, e.g. 'Battery Ring'.")
    var name: String

    var background: DraftBackground

    @Guide(description: "The widget's layers, back to front. 2-5 well-placed layers beat many cluttered ones.", .count(1...8))
    var layers: [DraftLayer]
}

@available(iOS 26.0, *)
@Generable(description: "The widget background: solid, or a vertical gradient when a second color is given.")
struct DraftBackground {
    @Guide(description: "Main background color as a 6-digit hex like #1C1C2E.", .pattern(/#[0-9A-Fa-f]{6}/))
    var hex: String

    @Guide(description: "Optional second hex; when present the background is a top-to-bottom gradient from hex to this. Omit for a solid background.")
    var bottomHex: String?
}

/// Position and size in the widget's normalized space: 0...1 on both axes,
/// where x/y is the layer's CENTER (0.5, 0.5 is dead center).
@available(iOS 26.0, *)
@Generable(description: "Placement in normalized 0-1 coordinates. x and y are the layer's CENTER; width and height are fractions of the widget.")
struct DraftFrame {
    @Guide(description: "Center x, 0-1.", .range(0.0...1.0))
    var x: Double
    @Guide(description: "Center y, 0-1. Smaller is higher.", .range(0.0...1.0))
    var y: Double
    @Guide(description: "Width as a fraction of the widget.", .range(0.05...1.0))
    var width: Double
    @Guide(description: "Height as a fraction of the widget.", .range(0.05...1.0))
    var height: Double
}

@available(iOS 26.0, *)
@Generable(description: "One layer of the widget.")
enum DraftLayer {
    case text(DraftTextLayer)
    case gauge(DraftGaugeLayer)
    case symbol(DraftSymbolLayer)
    case shape(DraftShapeLayer)
    case chart(DraftChartLayer)
}

@available(iOS 26.0, *)
@Generable(description: "Rough text size: small for captions (~11pt), medium for body (~15pt), large for hero numbers (~28pt).")
enum DraftTextSize {
    case small
    case medium
    case large
}

@available(iOS 26.0, *)
@Generable(description: "Font weight.")
enum DraftTextWeight {
    case light
    case regular
    case medium
    case semibold
    case bold
}

@available(iOS 26.0, *)
@Generable(description: """
A text layer. `template` is literal text where {expression} spans are evaluated live against device data. \
Valid data paths: battery.level (0-1), battery.state ('charging'/'unplugged'), weather.temperature (Celsius), \
weather.condition, weather.high, weather.low, weather.humidity (0-1), health.steps, health.stepsGoal, \
health.activeEnergy, calendar.nextTitle, calendar.todayCount, time.hour (0-23), time.hour12, time.minute, \
time.day, time.weekdayName, time.monthName. \
Functions: round(x), percent(x) formats 0-1 as '82%', pad(x, 2) zero-pads, upper(s), clamp(x, lo, hi). \
Examples: '{percent(battery.level)}', '{round(weather.temperature)}°', '{pad(time.hour, 2)}:{pad(time.minute, 2)}', \
'{health.steps} steps', 'Plain label'.
""")
struct DraftTextLayer {
    @Guide(description: "The template string, e.g. '{percent(battery.level)}' or 'H {round(weather.high)}°  L {round(weather.low)}°'.")
    var template: String
    var size: DraftTextSize
    var weight: DraftTextWeight
    @Guide(description: "Text color as 6-digit hex, contrasting strongly with the background.", .pattern(/#[0-9A-Fa-f]{6}/))
    var hexColor: String
    var frame: DraftFrame
}

@available(iOS 26.0, *)
@Generable(description: "Gauge shape: ring is a circular progress ring, bar is a horizontal progress bar.")
enum DraftGaugeStyle {
    case ring
    case bar
}

@available(iOS 26.0, *)
@Generable(description: """
A progress gauge driven by a bare expression (no braces) that must evaluate to 0-1. \
Good values: 'battery.level', 'weather.humidity', 'clamp(health.steps / health.stepsGoal, 0, 1)'.
""")
struct DraftGaugeLayer {
    @Guide(description: "Bare 0-1 expression, e.g. 'battery.level' or 'clamp(health.steps / health.stepsGoal, 0, 1)'.")
    var valueExpression: String
    var style: DraftGaugeStyle
    @Guide(description: "Gauge fill color as 6-digit hex.", .pattern(/#[0-9A-Fa-f]{6}/))
    var hexTint: String
    var frame: DraftFrame
}

@available(iOS 26.0, *)
@Generable(description: "An SF Symbol icon layer.")
struct DraftSymbolLayer {
    @Guide(description: "An SF Symbols name that really exists, e.g. 'bolt.fill', 'cloud.sun.fill', 'figure.walk', 'calendar', 'battery.75percent', 'heart.fill', 'moon.stars.fill'.")
    var sfSymbolName: String
    @Guide(description: "Symbol color as 6-digit hex.", .pattern(/#[0-9A-Fa-f]{6}/))
    var hexColor: String
    var frame: DraftFrame
}

@available(iOS 26.0, *)
@Generable(description: "Basic shape kind.")
enum DraftShapeKind {
    case rect
    case circle
}

@available(iOS 26.0, *)
@Generable(description: "A filled shape layer — cards, badges, dividers, backdrops behind text.")
struct DraftShapeLayer {
    var kind: DraftShapeKind
    @Guide(description: "Fill color as 6-digit hex.", .pattern(/#[0-9A-Fa-f]{6}/))
    var hexFill: String
    @Guide(description: "Corner radius in points for rects, 0-40. Ignored for circles.", .range(0.0...40.0))
    var cornerRadius: Double
    var frame: DraftFrame
}

@available(iOS 26.0, *)
@Generable(description: "Chart drawing style.")
enum DraftChartStyle {
    case line
    case bar
}

@available(iOS 26.0, *)
@Generable(description: """
A mini-chart over a list from device data. Valid list paths: 'weather.hourly' (hourly temperatures) \
and 'health.weekSteps' (steps per day, last 7 days).
""")
struct DraftChartLayer {
    @Guide(description: "Data path to a list: 'weather.hourly' or 'health.weekSteps'.")
    var dataPath: String
    var style: DraftChartStyle
    @Guide(description: "Chart color as 6-digit hex.", .pattern(/#[0-9A-Fa-f]{6}/))
    var hexColor: String
    var frame: DraftFrame
}
