import Foundation

/// One step of a resolved outline. Coordinates are normalized 0...1 in the
/// layer's own space, so a path scales to any rendition without rework —
/// the same reason `LayerFrame` is fractional.
public enum PathCommand: Sendable, Equatable, Hashable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case quad(cx: Double, cy: Double, x: Double, y: Double)
    case cubic(c1x: Double, c1y: Double, c2x: Double, c2y: Double, x: Double, y: Double)
    case close
}

public enum PathError: Error, Equatable, Sendable {
    case unexpectedCharacter(Character, at: Int)
    case missingNumber(after: Character)
    case leadingCommand(Character)
}

/// Parser for the subset of SVG path syntax Facet documents use:
/// `M m L l H h V v C c Q q Z z`. Arcs and smooth shorthands are
/// deliberately unsupported — every shape Facet generates or imports is
/// expressible with lines and Béziers, and a smaller grammar means fewer
/// ways for a hand-edited document to render wrong.
///
/// Parsing happens once in the resolver, not per frame in a renderer, so
/// both the SwiftUI and SVG backends draw from identical commands and a
/// malformed path surfaces as a render diagnostic instead of silence.
public enum PathData {
    public static func parse(_ source: String) throws -> [PathCommand] {
        var scanner = Scanner(source)
        var commands: [PathCommand] = []

        // Absolute cursor and subpath origin, both needed to resolve
        // relative commands and to give `Z` somewhere to return to.
        var current = (x: 0.0, y: 0.0)
        var origin = (x: 0.0, y: 0.0)
        var previousCommand: Character?

        while let command = try scanner.nextCommand(previous: previousCommand) {
            let relative = command.isLowercase
            switch Character(command.uppercased()) {
            case "M":
                let x = try scanner.number(after: command)
                let y = try scanner.number(after: command)
                current = relative ? (current.x + x, current.y + y) : (x, y)
                origin = current
                commands.append(.move(x: current.x, y: current.y))
            case "L":
                let x = try scanner.number(after: command)
                let y = try scanner.number(after: command)
                current = relative ? (current.x + x, current.y + y) : (x, y)
                commands.append(.line(x: current.x, y: current.y))
            case "H":
                let x = try scanner.number(after: command)
                current.x = relative ? current.x + x : x
                commands.append(.line(x: current.x, y: current.y))
            case "V":
                let y = try scanner.number(after: command)
                current.y = relative ? current.y + y : y
                commands.append(.line(x: current.x, y: current.y))
            case "Q":
                let cx = try scanner.number(after: command)
                let cy = try scanner.number(after: command)
                let x = try scanner.number(after: command)
                let y = try scanner.number(after: command)
                let control = relative ? (current.x + cx, current.y + cy) : (cx, cy)
                current = relative ? (current.x + x, current.y + y) : (x, y)
                commands.append(.quad(cx: control.0, cy: control.1, x: current.x, y: current.y))
            case "C":
                let c1x = try scanner.number(after: command)
                let c1y = try scanner.number(after: command)
                let c2x = try scanner.number(after: command)
                let c2y = try scanner.number(after: command)
                let x = try scanner.number(after: command)
                let y = try scanner.number(after: command)
                let c1 = relative ? (current.x + c1x, current.y + c1y) : (c1x, c1y)
                let c2 = relative ? (current.x + c2x, current.y + c2y) : (c2x, c2y)
                current = relative ? (current.x + x, current.y + y) : (x, y)
                commands.append(.cubic(
                    c1x: c1.0, c1y: c1.1, c2x: c2.0, c2y: c2.1, x: current.x, y: current.y
                ))
            case "Z":
                current = origin
                commands.append(.close)
            default:
                throw PathError.unexpectedCharacter(command, at: scanner.offset)
            }
            previousCommand = command
        }
        return commands
    }

    /// Serialize back to SVG syntax. Round-tripping keeps generated shapes
    /// (blobs, imports) storable as plain strings in the document.
    public static func string(from commands: [PathCommand], precision: Int = 4) -> String {
        func f(_ value: Double) -> String {
            let rounded = (value * pow(10, Double(precision))).rounded() / pow(10, Double(precision))
            // Trim the trailing ".0" that Double's description always adds.
            return rounded == rounded.rounded()
                ? String(Int(rounded.rounded()))
                : String(rounded)
        }
        return commands.map { command in
            switch command {
            case .move(let x, let y): return "M\(f(x)),\(f(y))"
            case .line(let x, let y): return "L\(f(x)),\(f(y))"
            case .quad(let cx, let cy, let x, let y):
                return "Q\(f(cx)),\(f(cy)) \(f(x)),\(f(y))"
            case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
                return "C\(f(c1x)),\(f(c1y)) \(f(c2x)),\(f(c2y)) \(f(x)),\(f(y))"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }

    /// Tokenizer over the path string. SVG allows commas, whitespace, or
    /// nothing at all between numbers ("M.5.5"), and repeats the previous
    /// command when a coordinate pair follows without a new letter.
    private struct Scanner {
        private let characters: [Character]
        private(set) var offset = 0

        init(_ source: String) {
            characters = Array(source)
        }

        mutating func skipSeparators() {
            while offset < characters.count {
                let character = characters[offset]
                guard character == "," || character.isWhitespace else { break }
                offset += 1
            }
        }

        /// The next command letter, or an implicit repeat of `previous`
        /// when the next token is a number. `M` implicitly repeats as `L`,
        /// per the SVG spec.
        mutating func nextCommand(previous: Character?) throws -> Character? {
            skipSeparators()
            guard offset < characters.count else { return nil }
            let character = characters[offset]
            if character.isLetter {
                offset += 1
                return character
            }
            guard character.isNumber || character == "-" || character == "+" || character == "." else {
                throw PathError.unexpectedCharacter(character, at: offset)
            }
            guard let previous else { throw PathError.leadingCommand(character) }
            switch previous {
            case "M": return "L"
            case "m": return "l"
            default: return previous
            }
        }

        mutating func number(after command: Character) throws -> Double {
            skipSeparators()
            let start = offset
            if offset < characters.count, characters[offset] == "-" || characters[offset] == "+" {
                offset += 1
            }
            var sawDot = false
            while offset < characters.count {
                let character = characters[offset]
                if character.isNumber {
                    offset += 1
                } else if character == "." && !sawDot {
                    sawDot = true
                    offset += 1
                } else if character == "e" || character == "E" {
                    offset += 1
                    if offset < characters.count, characters[offset] == "-" || characters[offset] == "+" {
                        offset += 1
                    }
                } else {
                    break
                }
            }
            guard offset > start, let value = Double(String(characters[start..<offset])) else {
                throw PathError.missingNumber(after: command)
            }
            return value
        }
    }
}
