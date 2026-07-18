import Foundation

/// File-backed snapshot cache in the App Group container. The main app and
/// background refresh write; the widget extension only reads — it must never
/// fetch, so renders stay fast and inside the extension memory budget.
public struct SnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private func url(for sourceID: String) -> URL {
        // Source IDs are alphanumeric; keep the filename safe regardless.
        let safe = sourceID.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return directory.appendingPathComponent("snapshot-\(String(safe)).json")
    }

    public func save(_ snapshot: DataSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        try data.write(to: url(for: snapshot.sourceID), options: .atomic)
    }

    public func load(sourceID: String) -> DataSnapshot? {
        guard let data = try? Data(contentsOf: url(for: sourceID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(DataSnapshot.self, from: data)
    }

    /// Load everything a document needs. Missing sources are simply absent
    /// from the set; the renderer degrades per-layer rather than failing the
    /// whole widget.
    public func loadSet(sourceIDs: [String]) -> SnapshotSet {
        SnapshotSet(sourceIDs.compactMap { load(sourceID: $0) })
    }

    public func isStale(sourceID: String, cadence: CadenceClass, now: Date = Date()) -> Bool {
        guard let snapshot = load(sourceID: sourceID) else { return true }
        return now.timeIntervalSince(snapshot.fetchedAt) > cadence.staleAfter
    }
}
