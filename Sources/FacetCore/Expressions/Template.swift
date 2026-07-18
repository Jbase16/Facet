import Foundation

/// A parsed template string. Text layers use templates: literal text with
/// `{expression}` spans, e.g. `"⚡ {percent(battery.level)} at {time.short}"`.
/// `{{` and `}}` escape literal braces.
public struct Template: Sendable, Equatable {
    public enum Segment: Sendable, Equatable {
        case literal(String)
        case expression(Expression)
    }

    public var segments: [Segment]

    public init(parsing source: String) throws {
        var segments: [Segment] = []
        var literal = ""
        let characters = Array(source)
        var index = 0

        while index < characters.count {
            let char = characters[index]
            if char == "{" {
                if index + 1 < characters.count, characters[index + 1] == "{" {
                    literal.append("{")
                    index += 2
                    continue
                }
                // Find the matching close brace (expressions cannot nest braces).
                guard let close = characters[(index + 1)...].firstIndex(of: "}") else {
                    throw ExpressionError.syntax("Unclosed '{' in template", position: index)
                }
                let expressionSource = String(characters[(index + 1)..<close])
                if !literal.isEmpty {
                    segments.append(.literal(literal))
                    literal = ""
                }
                segments.append(.expression(try Expression.parse(expressionSource)))
                index = close + 1
            } else if char == "}" {
                if index + 1 < characters.count, characters[index + 1] == "}" {
                    literal.append("}")
                    index += 2
                    continue
                }
                throw ExpressionError.syntax("Unmatched '}' in template", position: index)
            } else {
                literal.append(char)
                index += 1
            }
        }
        if !literal.isEmpty {
            segments.append(.literal(literal))
        }
        self.segments = segments
    }

    public func render(context: EvaluationContext) throws -> String {
        var output = ""
        for segment in segments {
            switch segment {
            case .literal(let text):
                output += text
            case .expression(let expression):
                output += try Evaluator.evaluate(expression, context: context).displayString
            }
        }
        return output
    }

    /// Parse and render in one step.
    public static func render(_ source: String, context: EvaluationContext) throws -> String {
        try Template(parsing: source).render(context: context)
    }
}
