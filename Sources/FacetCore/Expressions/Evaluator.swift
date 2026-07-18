import Foundation

/// Supplies variable values (dotted paths like `battery.level`) to the evaluator.
public protocol EvaluationContext: Sendable {
    func value(forVariable path: String) -> Value?
}

/// A simple dictionary-backed context, used by tests and previews.
public struct DictionaryContext: EvaluationContext {
    private let values: [String: Value]

    public init(_ values: [String: Value]) {
        self.values = values
    }

    public func value(forVariable path: String) -> Value? {
        values[path]
    }
}

public struct EmptyContext: EvaluationContext {
    public init() {}
    public func value(forVariable path: String) -> Value? { nil }
}

public enum Evaluator {
    public static func evaluate(_ expression: Expression, context: EvaluationContext) throws -> Value {
        switch expression {
        case .number(let value):
            return .number(value)
        case .string(let value):
            return .string(value)
        case .bool(let value):
            return .bool(value)
        case .variable(let path):
            guard let value = context.value(forVariable: path) else {
                throw ExpressionError.unknownVariable(path)
            }
            return value
        case .unary(let op, let operand):
            return try evaluateUnary(op, operand, context: context)
        case .binary(let op, let lhs, let rhs):
            return try evaluateBinary(op, lhs, rhs, context: context)
        case .conditional(let condition, let thenBranch, let elseBranch):
            let flag = try evaluate(condition, context: context).asBool()
            return try evaluate(flag ? thenBranch : elseBranch, context: context)
        case .call(let name, let arguments):
            guard let function = Builtins.all[name] else {
                throw ExpressionError.unknownFunction(name)
            }
            let values = try arguments.map { try evaluate($0, context: context) }
            return try function.invoke(values, context)
        }
    }

    /// Convenience: parse and evaluate in one step.
    public static func evaluate(_ source: String, context: EvaluationContext) throws -> Value {
        try evaluate(Expression.parse(source), context: context)
    }

    private static func evaluateUnary(
        _ op: UnaryOperator,
        _ operand: Expression,
        context: EvaluationContext
    ) throws -> Value {
        let value = try evaluate(operand, context: context)
        switch op {
        case .negate: return .number(-(try value.asNumber()))
        case .not: return .bool(!(try value.asBool()))
        }
    }

    private static func evaluateBinary(
        _ op: BinaryOperator,
        _ lhs: Expression,
        _ rhs: Expression,
        context: EvaluationContext
    ) throws -> Value {
        // Short-circuit logical operators before evaluating the right side.
        if op == .and || op == .or {
            let left = try evaluate(lhs, context: context).asBool()
            if op == .and && !left { return .bool(false) }
            if op == .or && left { return .bool(true) }
            return .bool(try evaluate(rhs, context: context).asBool())
        }

        let left = try evaluate(lhs, context: context)
        let right = try evaluate(rhs, context: context)

        switch op {
        case .add:
            // `+` concatenates when either side is a string — the common case
            // in text bindings ("Steps: " + str(health.steps)).
            if case .string = left {
                return .string(try left.asString() + right.displayString)
            }
            if case .string = right {
                return .string(left.displayString + (try right.asString()))
            }
            return .number(try left.asNumber() + right.asNumber())
        case .subtract:
            return .number(try left.asNumber() - right.asNumber())
        case .multiply:
            return .number(try left.asNumber() * right.asNumber())
        case .divide:
            let divisor = try right.asNumber()
            guard divisor != 0 else { throw ExpressionError.divisionByZero }
            return .number(try left.asNumber() / divisor)
        case .modulo:
            let divisor = try right.asNumber()
            guard divisor != 0 else { throw ExpressionError.divisionByZero }
            return .number(try left.asNumber().truncatingRemainder(dividingBy: divisor))
        case .equal:
            return .bool(left == right)
        case .notEqual:
            return .bool(left != right)
        case .less, .lessOrEqual, .greater, .greaterOrEqual:
            return try compare(op, left, right)
        case .and, .or:
            fatalError("Handled above")
        }
    }

    private static func compare(_ op: BinaryOperator, _ left: Value, _ right: Value) throws -> Value {
        if case .string(let l) = left, case .string(let r) = right {
            switch op {
            case .less: return .bool(l < r)
            case .lessOrEqual: return .bool(l <= r)
            case .greater: return .bool(l > r)
            default: return .bool(l >= r)
            }
        }
        let l = try left.asNumber()
        let r = try right.asNumber()
        switch op {
        case .less: return .bool(l < r)
        case .lessOrEqual: return .bool(l <= r)
        case .greater: return .bool(l > r)
        default: return .bool(l >= r)
        }
    }
}
