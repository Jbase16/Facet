import Foundation

enum TokenKind: Equatable {
    case number(Double)
    case string(String)
    /// Identifier or dotted variable path (`steps`, `battery.level`, `items.0.name`).
    case identifier(String)
    case op(String)
    case leftParen
    case rightParen
    case comma
    case question
    case colon
    case end
}

struct Token: Equatable {
    var kind: TokenKind
    /// Offset into the source, for error reporting.
    var position: Int
}

struct Lexer {
    private let scalars: [Character]
    private var index = 0

    init(_ source: String) {
        scalars = Array(source)
    }

    mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        while true {
            let token = try next()
            tokens.append(token)
            if token.kind == .end { break }
        }
        return tokens
    }

    private mutating func next() throws -> Token {
        while index < scalars.count, scalars[index].isWhitespace { index += 1 }
        guard index < scalars.count else { return Token(kind: .end, position: index) }

        let start = index
        let char = scalars[index]

        if char.isNumber || (char == "." && index + 1 < scalars.count && scalars[index + 1].isNumber) {
            return try lexNumber()
        }
        if char == "\"" || char == "'" {
            return try lexString(quote: char)
        }
        if char.isLetter || char == "_" {
            return lexIdentifier()
        }

        index += 1
        switch char {
        case "(": return Token(kind: .leftParen, position: start)
        case ")": return Token(kind: .rightParen, position: start)
        case ",": return Token(kind: .comma, position: start)
        case "?": return Token(kind: .question, position: start)
        case ":": return Token(kind: .colon, position: start)
        case "+", "-", "*", "/", "%": return Token(kind: .op(String(char)), position: start)
        case "=", "!", "<", ">":
            if index < scalars.count, scalars[index] == "=" {
                index += 1
                return Token(kind: .op(String(char) + "="), position: start)
            }
            if char == "=" {
                throw ExpressionError.syntax("Use '==' for comparison", position: start)
            }
            return Token(kind: .op(String(char)), position: start)
        case "&", "|":
            if index < scalars.count, scalars[index] == char {
                index += 1
                return Token(kind: .op(String(char) + String(char)), position: start)
            }
            throw ExpressionError.syntax("Unexpected character '\(char)'", position: start)
        default:
            throw ExpressionError.syntax("Unexpected character '\(char)'", position: start)
        }
    }

    private mutating func lexNumber() throws -> Token {
        let start = index
        var text = ""
        var seenDot = false
        while index < scalars.count {
            let char = scalars[index]
            if char.isNumber {
                text.append(char)
            } else if char == "." && !seenDot && index + 1 < scalars.count && scalars[index + 1].isNumber {
                seenDot = true
                text.append(char)
            } else {
                break
            }
            index += 1
        }
        guard let value = Double(text) else {
            throw ExpressionError.syntax("Invalid number '\(text)'", position: start)
        }
        return Token(kind: .number(value), position: start)
    }

    private mutating func lexString(quote: Character) throws -> Token {
        let start = index
        index += 1
        var text = ""
        while index < scalars.count {
            let char = scalars[index]
            index += 1
            if char == quote {
                return Token(kind: .string(text), position: start)
            }
            if char == "\\", index < scalars.count {
                let escaped = scalars[index]
                index += 1
                switch escaped {
                case "n": text.append("\n")
                case "t": text.append("\t")
                default: text.append(escaped)
                }
            } else {
                text.append(char)
            }
        }
        throw ExpressionError.syntax("Unterminated string", position: start)
    }

    private mutating func lexIdentifier() -> Token {
        let start = index
        var text = ""
        while index < scalars.count {
            let char = scalars[index]
            if char.isLetter || char.isNumber || char == "_" {
                text.append(char)
                index += 1
            } else if char == "." && index + 1 < scalars.count
                        && (scalars[index + 1].isLetter || scalars[index + 1].isNumber || scalars[index + 1] == "_") {
                text.append(char)
                index += 1
            } else {
                break
            }
        }
        return Token(kind: .identifier(text), position: start)
    }
}
