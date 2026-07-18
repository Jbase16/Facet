import Foundation

/// A runtime value in the expression language.
public enum Value: Sendable, Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)

    public var typeName: String {
        switch self {
        case .number: return "number"
        case .string: return "string"
        case .bool: return "bool"
        }
    }

    /// Human-facing rendering, used by templates. Whole numbers drop the
    /// trailing ".0" so `{battery.level * 100}` reads "80", not "80.0".
    public var displayString: String {
        switch self {
        case .string(let string):
            return string
        case .bool(let bool):
            return bool ? "true" : "false"
        case .number(let number):
            if number.isNaN { return "NaN" }
            if number == number.rounded() && abs(number) < 1e15 {
                return String(Int64(number))
            }
            return String(number)
        }
    }

    public func asNumber() throws -> Double {
        guard case .number(let value) = self else {
            throw ExpressionError.typeMismatch(expected: "number", got: typeName)
        }
        return value
    }

    public func asString() throws -> String {
        guard case .string(let value) = self else {
            throw ExpressionError.typeMismatch(expected: "string", got: typeName)
        }
        return value
    }

    public func asBool() throws -> Bool {
        guard case .bool(let value) = self else {
            throw ExpressionError.typeMismatch(expected: "bool", got: typeName)
        }
        return value
    }
}

public enum ExpressionError: Error, Equatable, Sendable, CustomStringConvertible {
    case syntax(String, position: Int)
    case unknownVariable(String)
    case unknownFunction(String)
    case typeMismatch(expected: String, got: String)
    case arity(function: String, expected: String, got: Int)
    case divisionByZero
    case invalidArgument(String)

    public var description: String {
        switch self {
        case .syntax(let message, let position):
            return "Syntax error at \(position): \(message)"
        case .unknownVariable(let name):
            return "Unknown variable '\(name)'"
        case .unknownFunction(let name):
            return "Unknown function '\(name)'"
        case .typeMismatch(let expected, let got):
            return "Type mismatch: expected \(expected), got \(got)"
        case .arity(let function, let expected, let got):
            return "\(function)() expects \(expected) arguments, got \(got)"
        case .divisionByZero:
            return "Division by zero"
        case .invalidArgument(let message):
            return "Invalid argument: \(message)"
        }
    }
}
