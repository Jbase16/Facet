import Foundation

public enum UnaryOperator: String, Sendable, Equatable {
    case negate = "-"
    case not = "!"
}

public enum BinaryOperator: String, Sendable, Equatable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "%"
    case equal = "=="
    case notEqual = "!="
    case less = "<"
    case lessOrEqual = "<="
    case greater = ">"
    case greaterOrEqual = ">="
    case and = "&&"
    case or = "||"
}

public indirect enum Expression: Sendable, Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)
    /// A dotted variable path resolved against the data snapshot.
    case variable(String)
    case call(String, [Expression])
    case unary(UnaryOperator, Expression)
    case binary(BinaryOperator, Expression, Expression)
    case conditional(Expression, then: Expression, else: Expression)

    /// Parse source text into an expression tree.
    public static func parse(_ source: String) throws -> Expression {
        var lexer = Lexer(source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return try parser.parseExpression()
    }
}

/// Recursive-descent parser. Precedence (low → high):
/// ternary, ||, &&, == !=, < <= > >=, + -, * / %, unary, primary.
struct Parser {
    private let tokens: [Token]
    private var index = 0

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    private var current: Token { tokens[index] }

    private mutating func advance() -> Token {
        let token = current
        if index < tokens.count - 1 { index += 1 }
        return token
    }

    private mutating func expect(_ kind: TokenKind, _ what: String) throws {
        guard current.kind == kind else {
            throw ExpressionError.syntax("Expected \(what)", position: current.position)
        }
        _ = advance()
    }

    mutating func parseExpression() throws -> Expression {
        let expression = try parseTernary()
        guard current.kind == .end else {
            throw ExpressionError.syntax("Unexpected trailing input", position: current.position)
        }
        return expression
    }

    private mutating func parseTernary() throws -> Expression {
        let condition = try parseBinary(minPrecedence: 0)
        guard current.kind == .question else { return condition }
        _ = advance()
        let thenBranch = try parseTernary()
        try expect(.colon, "':' in ternary expression")
        let elseBranch = try parseTernary()
        return .conditional(condition, then: thenBranch, else: elseBranch)
    }

    private static let precedences: [String: Int] = [
        "||": 1, "&&": 2,
        "==": 3, "!=": 3,
        "<": 4, "<=": 4, ">": 4, ">=": 4,
        "+": 5, "-": 5,
        "*": 6, "/": 6, "%": 6,
    ]

    private mutating func parseBinary(minPrecedence: Int) throws -> Expression {
        var left = try parseUnary()
        while case .op(let symbol) = current.kind,
              let precedence = Self.precedences[symbol],
              precedence > minPrecedence {
            _ = advance()
            let right = try parseBinary(minPrecedence: precedence)
            guard let op = BinaryOperator(rawValue: symbol) else {
                throw ExpressionError.syntax("Unknown operator '\(symbol)'", position: current.position)
            }
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func parseUnary() throws -> Expression {
        if case .op(let symbol) = current.kind, symbol == "-" || symbol == "!" {
            let position = current.position
            _ = advance()
            let operand = try parseUnary()
            guard let op = UnaryOperator(rawValue: symbol) else {
                throw ExpressionError.syntax("Unknown operator '\(symbol)'", position: position)
            }
            return .unary(op, operand)
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> Expression {
        switch current.kind {
        case .number(let value):
            _ = advance()
            return .number(value)
        case .string(let value):
            _ = advance()
            return .string(value)
        case .identifier(let name):
            _ = advance()
            if name == "true" { return .bool(true) }
            if name == "false" { return .bool(false) }
            if current.kind == .leftParen {
                _ = advance()
                var arguments: [Expression] = []
                if current.kind != .rightParen {
                    repeat {
                        arguments.append(try parseTernary())
                        if current.kind == .comma {
                            _ = advance()
                        } else {
                            break
                        }
                    } while true
                }
                try expect(.rightParen, "')' to close call to \(name)()")
                return .call(name, arguments)
            }
            return .variable(name)
        case .leftParen:
            _ = advance()
            let inner = try parseTernary()
            try expect(.rightParen, "')'")
            return inner
        default:
            throw ExpressionError.syntax("Expected a value", position: current.position)
        }
    }
}
