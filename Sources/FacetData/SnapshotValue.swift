import Foundation
import FacetCore

/// A JSON-shaped value captured from a data source. Serializes as plain JSON.
public indirect enum SnapshotValue: Sendable, Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case list([SnapshotValue])
    case object([String: SnapshotValue])

    /// Look up a dotted path (`"forecast.0.high"`). List elements are
    /// addressed by integer segments.
    public func value(atPath path: String) -> SnapshotValue? {
        guard !path.isEmpty else { return self }
        var current = self
        for segment in path.split(separator: ".") {
            switch current {
            case .object(let dictionary):
                guard let next = dictionary[String(segment)] else { return nil }
                current = next
            case .list(let items):
                guard let index = Int(segment), items.indices.contains(index) else { return nil }
                current = items[index]
            default:
                return nil
            }
        }
        return current
    }

    /// The expression-language value for leaf nodes; nil for lists/objects,
    /// which cannot appear in expressions directly.
    public var scalar: Value? {
        switch self {
        case .number(let value): return .number(value)
        case .string(let value): return .string(value)
        case .bool(let value): return .bool(value)
        case .list, .object: return nil
        }
    }
}

extension SnapshotValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SnapshotValue].self) {
            self = .list(value)
        } else if let value = try? container.decode([String: SnapshotValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .list(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// One captured fetch from one data source.
public struct DataSnapshot: Codable, Sendable, Equatable {
    public var sourceID: String
    public var fetchedAt: Date
    public var values: SnapshotValue

    public init(sourceID: String, fetchedAt: Date = Date(), values: SnapshotValue) {
        self.sourceID = sourceID
        self.fetchedAt = fetchedAt
        self.values = values
    }
}

/// The merged snapshots a widget renders from, keyed by source ID. Acts as the
/// expression evaluation context: `battery.level` reads path `level` from the
/// snapshot of source `battery`.
public struct SnapshotSet: EvaluationContext, Sendable, Equatable {
    public private(set) var snapshots: [String: DataSnapshot]

    public init(_ snapshots: [DataSnapshot] = []) {
        self.snapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.sourceID, $0) })
    }

    public mutating func insert(_ snapshot: DataSnapshot) {
        snapshots[snapshot.sourceID] = snapshot
    }

    public func snapshot(for sourceID: String) -> DataSnapshot? {
        snapshots[sourceID]
    }

    public func value(forVariable path: String) -> Value? {
        snapshotValue(forVariable: path)?.scalar
    }

    /// The raw snapshot value at a dotted path — lists and objects included.
    /// Chart layers read lists through this.
    public func snapshotValue(forVariable path: String) -> SnapshotValue? {
        let segments = path.split(separator: ".", maxSplits: 1)
        guard let first = segments.first, let snapshot = snapshots[String(first)] else { return nil }
        let rest = segments.count > 1 ? String(segments[1]) : ""
        return snapshot.values.value(atPath: rest)
    }

    /// The numbers in the list at `path`; nil when the path isn't a list.
    /// Non-numeric elements are skipped.
    public func numberList(forVariable path: String) -> [Double]? {
        guard case .list(let items)? = snapshotValue(forVariable: path) else { return nil }
        return items.compactMap {
            if case .number(let value) = $0 { return value }
            return nil
        }
    }
}
