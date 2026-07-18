import Foundation

struct BuiltinFunction: Sendable {
    let name: String
    /// Accepted argument counts; nil upper bound means variadic.
    let minArity: Int
    let maxArity: Int?
    private let body: @Sendable ([Value], EvaluationContext) throws -> Value

    init(
        _ name: String,
        arity: ClosedRange<Int>,
        _ body: @escaping @Sendable ([Value], EvaluationContext) throws -> Value
    ) {
        self.name = name
        self.minArity = arity.lowerBound
        self.maxArity = arity.upperBound
        self.body = body
    }

    init(
        _ name: String,
        minArity: Int,
        _ body: @escaping @Sendable ([Value], EvaluationContext) throws -> Value
    ) {
        self.name = name
        self.minArity = minArity
        self.maxArity = nil
        self.body = body
    }

    func invoke(_ arguments: [Value], _ context: EvaluationContext) throws -> Value {
        if arguments.count < minArity || (maxArity.map { arguments.count > $0 } ?? false) {
            let expected = maxArity.map { max in
                minArity == max ? "\(minArity)" : "\(minArity)–\(max)"
            } ?? "at least \(minArity)"
            throw ExpressionError.arity(function: name, expected: expected, got: arguments.count)
        }
        return try body(arguments, context)
    }
}

enum Builtins {
    static let all: [String: BuiltinFunction] = {
        var table: [String: BuiltinFunction] = [:]
        for function in functions { table[function.name] = function }
        return table
    }()

    private static let functions: [BuiltinFunction] = [
        // Math
        BuiltinFunction("abs", arity: 1...1) { args, _ in .number(abs(try args[0].asNumber())) },
        BuiltinFunction("floor", arity: 1...1) { args, _ in .number(try args[0].asNumber().rounded(.down)) },
        BuiltinFunction("ceil", arity: 1...1) { args, _ in .number(try args[0].asNumber().rounded(.up)) },
        BuiltinFunction("sqrt", arity: 1...1) { args, _ in
            let x = try args[0].asNumber()
            guard x >= 0 else { throw ExpressionError.invalidArgument("sqrt of negative number") }
            return .number(x.squareRoot())
        },
        BuiltinFunction("pow", arity: 2...2) { args, _ in
            .number(Foundation.pow(try args[0].asNumber(), try args[1].asNumber()))
        },
        BuiltinFunction("round", arity: 1...2) { args, _ in
            let x = try args[0].asNumber()
            if args.count == 1 { return .number(x.rounded()) }
            let digits = try args[1].asNumber()
            let factor = Foundation.pow(10.0, digits.rounded())
            return .number((x * factor).rounded() / factor)
        },
        BuiltinFunction("min", minArity: 1) { args, _ in
            .number(try args.map { try $0.asNumber() }.min()!)
        },
        BuiltinFunction("max", minArity: 1) { args, _ in
            .number(try args.map { try $0.asNumber() }.max()!)
        },
        BuiltinFunction("clamp", arity: 3...3) { args, _ in
            let x = try args[0].asNumber()
            let lo = try args[1].asNumber()
            let hi = try args[2].asNumber()
            guard lo <= hi else { throw ExpressionError.invalidArgument("clamp bounds reversed") }
            return .number(Swift.min(Swift.max(x, lo), hi))
        },

        // Formatting & conversion
        BuiltinFunction("format", arity: 2...2) { args, _ in
            let digits = Int(try args[1].asNumber().rounded())
            guard (0...10).contains(digits) else {
                throw ExpressionError.invalidArgument("format digits must be 0–10")
            }
            return .string(String(format: "%.\(digits)f", try args[0].asNumber()))
        },
        BuiltinFunction("percent", arity: 1...2) { args, _ in
            let fraction = try args[0].asNumber()
            let digits = args.count > 1 ? Int(try args[1].asNumber().rounded()) : 0
            guard (0...10).contains(digits) else {
                throw ExpressionError.invalidArgument("percent digits must be 0–10")
            }
            return .string(String(format: "%.\(digits)f%%", fraction * 100))
        },
        BuiltinFunction("str", arity: 1...1) { args, _ in .string(args[0].displayString) },
        BuiltinFunction("num", arity: 1...1) { args, _ in
            switch args[0] {
            case .number(let x): return .number(x)
            case .bool(let flag): return .number(flag ? 1 : 0)
            case .string(let text):
                guard let x = Double(text.trimmingCharacters(in: .whitespaces)) else {
                    throw ExpressionError.invalidArgument("'\(text)' is not a number")
                }
                return .number(x)
            }
        },
        BuiltinFunction("pad", arity: 2...2) { args, _ in
            let text = args[0].displayString
            let width = Int(try args[1].asNumber().rounded())
            guard (0...40).contains(width) else {
                throw ExpressionError.invalidArgument("pad width must be 0–40")
            }
            return .string(text.count >= width ? text : String(repeating: "0", count: width - text.count) + text)
        },

        // Strings
        BuiltinFunction("upper", arity: 1...1) { args, _ in .string(try args[0].asString().uppercased()) },
        BuiltinFunction("lower", arity: 1...1) { args, _ in .string(try args[0].asString().lowercased()) },
        BuiltinFunction("trim", arity: 1...1) { args, _ in
            .string(try args[0].asString().trimmingCharacters(in: .whitespacesAndNewlines))
        },
        BuiltinFunction("len", arity: 1...1) { args, _ in .number(Double(try args[0].asString().count)) },
        BuiltinFunction("contains", arity: 2...2) { args, _ in
            .bool(try args[0].asString().contains(try args[1].asString()))
        },
        BuiltinFunction("replace", arity: 3...3) { args, _ in
            .string(try args[0].asString().replacingOccurrences(
                of: try args[1].asString(),
                with: try args[2].asString()
            ))
        },

        // Units
        BuiltinFunction("cToF", arity: 1...1) { args, _ in .number(try args[0].asNumber() * 9 / 5 + 32) },
        BuiltinFunction("fToC", arity: 1...1) { args, _ in .number((try args[0].asNumber() - 32) * 5 / 9) },
        BuiltinFunction("kmToMi", arity: 1...1) { args, _ in .number(try args[0].asNumber() * 0.621371) },
        BuiltinFunction("miToKm", arity: 1...1) { args, _ in .number(try args[0].asNumber() / 0.621371) },

        // Dates. Timestamps are seconds since 1970, as produced by the time source.
        BuiltinFunction("dateFormat", arity: 2...2) { args, _ in
            let timestamp = try args[0].asNumber()
            let pattern = try args[1].asString()
            guard pattern.count <= 64 else {
                throw ExpressionError.invalidArgument("date pattern too long")
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return .string(formatter.string(from: Date(timeIntervalSince1970: timestamp)))
        },

        // Data presence
        BuiltinFunction("has", arity: 1...1) { args, context in
            .bool(context.value(forVariable: try args[0].asString()) != nil)
        },
    ]
}
