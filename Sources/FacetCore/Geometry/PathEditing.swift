import Foundation

/// A point in a layer's normalized 0...1 space. Not CGPoint: FacetCore
/// builds on Linux CI, where CoreGraphics doesn't exist.
public struct PathPoint: Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Editing operations over a parsed outline. Pure functions on
/// `[PathCommand]` so the canvas can drive them from gestures and the
/// result round-trips straight back into `pathData` — generators produce a
/// starting shape, this makes every shape after that reachable.
///
/// Coordinates stay normalized 0...1 in the layer's own space throughout;
/// the canvas converts to and from screen points.
public enum PathEditing {
    /// A draggable anchor plus the two Bézier handles that shape the curve
    /// arriving at and leaving it. Handles are nil where the neighbouring
    /// segment is a straight line.
    public struct Node {
        public var commandIndex: Int
        public var point: PathPoint
        public var inHandle: PathPoint?
        public var outHandle: PathPoint?
    }

    // MARK: - Reading

    public static func endpoint(of command: PathCommand) -> PathPoint? {
        switch command {
        case .move(let x, let y), .line(let x, let y):
            return PathPoint(x: x, y: y)
        case .quad(_, _, let x, let y):
            return PathPoint(x: x, y: y)
        case .cubic(_, _, _, _, let x, let y):
            return PathPoint(x: x, y: y)
        case .close:
            return nil
        }
    }

    public static func nodes(in commands: [PathCommand]) -> [Node] {
        var result: [Node] = []
        for (index, command) in commands.enumerated() {
            guard let point = endpoint(of: command) else { continue }
            var node = Node(commandIndex: index, point: point)
            if case .cubic(_, _, let c2x, let c2y, _, _) = command {
                node.inHandle = PathPoint(x: c2x, y: c2y)
            }
            // The outgoing handle lives on the *next* segment, since that's
            // the curve leaving this anchor.
            if index + 1 < commands.count,
               case .cubic(let c1x, let c1y, _, _, _, _) = commands[index + 1] {
                node.outHandle = PathPoint(x: c1x, y: c1y)
            }
            result.append(node)
        }
        return result
    }

    // MARK: - Mutation

    /// Move an anchor. Attached handles travel with it, which is what makes
    /// dragging a node feel like moving the shape rather than tearing it.
    public static func moveAnchor(_ commands: inout [PathCommand], at index: Int, to point: PathPoint) {
        guard commands.indices.contains(index), let old = endpoint(of: commands[index]) else { return }
        let delta = PathPoint(x: point.x - old.x, y: point.y - old.y)

        switch commands[index] {
        case .move:
            commands[index] = .move(x: point.x, y: point.y)
        case .line:
            commands[index] = .line(x: point.x, y: point.y)
        case .quad(let cx, let cy, _, _):
            commands[index] = .quad(cx: cx + delta.x, cy: cy + delta.y, x: point.x, y: point.y)
        case .cubic(let c1x, let c1y, let c2x, let c2y, _, _):
            commands[index] = .cubic(
                c1x: c1x, c1y: c1y,
                c2x: c2x + delta.x, c2y: c2y + delta.y,
                x: point.x, y: point.y
            )
        case .close:
            return
        }

        if index + 1 < commands.count,
           case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y) = commands[index + 1] {
            commands[index + 1] = .cubic(
                c1x: c1x + delta.x, c1y: c1y + delta.y,
                c2x: c2x, c2y: c2y, x: x, y: y
            )
        }

        // A closed path's first and last anchors are the same point; move
        // both or the outline splits open.
        if index == 0, commands.last == .close, commands.count >= 3,
           let last = endpoint(of: commands[commands.count - 2]),
           abs(last.x - old.x) < 0.0001, abs(last.y - old.y) < 0.0001 {
            moveAnchor(&commands, at: commands.count - 2, to: point)
        }
    }

    public static func setInHandle(_ commands: inout [PathCommand], at index: Int, to point: PathPoint) {
        guard commands.indices.contains(index),
              case .cubic(let c1x, let c1y, _, _, let x, let y) = commands[index] else { return }
        commands[index] = .cubic(c1x: c1x, c1y: c1y, c2x: point.x, c2y: point.y, x: x, y: y)
    }

    public static func setOutHandle(_ commands: inout [PathCommand], at index: Int, to point: PathPoint) {
        let next = index + 1
        guard commands.indices.contains(next),
              case .cubic(_, _, let c2x, let c2y, let x, let y) = commands[next] else { return }
        commands[next] = .cubic(c1x: point.x, c1y: point.y, c2x: c2x, c2y: c2y, x: x, y: y)
    }

    /// Straight segment <-> curve. Converting to a curve seeds handles at
    /// the thirds of the segment, which is the identity curve — the shape
    /// doesn't jump, it just becomes editable.
    public static func toggleCurve(_ commands: inout [PathCommand], at index: Int) {
        guard commands.indices.contains(index), index > 0,
              let start = endpoint(of: commands[index - 1]) else { return }
        switch commands[index] {
        case .line(let x, let y):
            let end = PathPoint(x: x, y: y)
            commands[index] = .cubic(
                c1x: start.x + (end.x - start.x) / 3, c1y: start.y + (end.y - start.y) / 3,
                c2x: start.x + 2 * (end.x - start.x) / 3, c2y: start.y + 2 * (end.y - start.y) / 3,
                x: x, y: y
            )
        case .cubic(_, _, _, _, let x, let y), .quad(_, _, let x, let y):
            commands[index] = .line(x: x, y: y)
        default:
            return
        }
    }

    /// Split the segment ending at `index` at its midpoint. Cubics split by
    /// de Casteljau so the outline is visually unchanged — adding a node
    /// must never deform the shape.
    public static func insertNode(_ commands: inout [PathCommand], onSegmentEndingAt index: Int) {
        guard commands.indices.contains(index), index > 0,
              let start = endpoint(of: commands[index - 1]) else { return }

        switch commands[index] {
        case .line(let x, let y):
            let mid = PathPoint(x: (start.x + x) / 2, y: (start.y + y) / 2)
            commands.insert(.line(x: mid.x, y: mid.y), at: index)
        case .cubic(let c1x, let c1y, let c2x, let c2y, let x, let y):
            let p0 = start
            let p1 = PathPoint(x: c1x, y: c1y)
            let p2 = PathPoint(x: c2x, y: c2y)
            let p3 = PathPoint(x: x, y: y)
            func mid(_ a: PathPoint, _ b: PathPoint) -> PathPoint {
                PathPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            }
            let a = mid(p0, p1), b = mid(p1, p2), c = mid(p2, p3)
            let d = mid(a, b), e = mid(b, c)
            let split = mid(d, e)
            commands[index] = .cubic(c1x: e.x, c1y: e.y, c2x: c.x, c2y: c.y, x: p3.x, y: p3.y)
            commands.insert(
                .cubic(c1x: a.x, c1y: a.y, c2x: d.x, c2y: d.y, x: split.x, y: split.y),
                at: index
            )
        case .quad(let cx, let cy, let x, let y):
            let p0 = start, p1 = PathPoint(x: cx, y: cy), p2 = PathPoint(x: x, y: y)
            let a = PathPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            let b = PathPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            let split = PathPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            commands[index] = .quad(cx: b.x, cy: b.y, x: p2.x, y: p2.y)
            commands.insert(.quad(cx: a.x, cy: a.y, x: split.x, y: split.y), at: index)
        default:
            return
        }
    }

    /// Remove an anchor, keeping the outline closed. Refuses below three
    /// anchors — fewer than that isn't a shape any more.
    public static func deleteNode(_ commands: inout [PathCommand], at index: Int) {
        let anchors = nodes(in: commands)
        guard anchors.count > 3, commands.indices.contains(index) else { return }

        if index == 0 {
            // Promote the next anchor to the subpath's start so the path
            // still begins with a move.
            guard commands.count > 1, let next = endpoint(of: commands[1]) else { return }
            commands[1] = .move(x: next.x, y: next.y)
            commands.remove(at: 0)
        } else {
            commands.remove(at: index)
        }
    }

    // MARK: - Serialization helpers

    public static func commands(from pathData: String?) -> [PathCommand] {
        guard let pathData, !pathData.isEmpty else { return [] }
        return (try? PathData.parse(pathData)) ?? []
    }

    public static func pathData(from commands: [PathCommand]) -> String {
        PathData.string(from: commands)
    }

    /// Clamp into the layer's box. Handles may legitimately sit outside to
    /// bulge a curve, so only anchors are clamped.
    public static func clampAnchor(_ point: PathPoint) -> PathPoint {
        PathPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}
