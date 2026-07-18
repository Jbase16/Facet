import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// User configuration for a custom URL source — the "any API becomes widget
/// data" feature. Stored as part of the user's source catalog, so it is plain
/// Codable JSON with no behavior of its own.
public struct URLSourceConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var url: URL
    /// Extra HTTP header fields sent with every fetch. This is how users
    /// attach API keys and bearer tokens without Facet knowing the scheme.
    public var headers: [String: String]
    public var cadence: CadenceClass
    /// Optional dotted path applied to the fetched JSON before storing, so a
    /// deeply nested API response (`"data.current"`) becomes the snapshot
    /// root and bindings stay short.
    public var rootPath: String?

    public init(
        id: String,
        displayName: String,
        url: URL,
        headers: [String: String] = [:],
        cadence: CadenceClass = .hourly,
        rootPath: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.url = url
        self.headers = headers
        self.cadence = cadence
        self.rootPath = rootPath
    }
}

/// Fetches a user-configured URL and stores the JSON body as a snapshot.
///
/// The transport is injectable so tests never touch the network; the default
/// wraps `URLSession`. Responses are capped at 1 MB — snapshots live in the
/// App Group cache read by the memory-limited widget extension, so a runaway
/// API must fail the fetch (keeping the last good snapshot) rather than
/// balloon the cache.
public struct URLJSONSource: DataSourceProvider {
    /// Performs one HTTP exchange: returns the body and the status code.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    /// Bodies larger than this are rejected with `fetchFailed`.
    public static let maxResponseBytes = 1_048_576

    public let config: URLSourceConfig
    private let transport: Transport

    public init(config: URLSourceConfig, transport: Transport? = nil) {
        self.config = config
        self.transport = transport ?? Self.urlSessionTransport
    }

    /// Custom sources can't declare paths up front — they depend on whatever
    /// the API returns. The editor fills autocomplete from
    /// `discoveredPaths(in:)` after the first successful fetch.
    public var descriptor: DataSourceDescriptor {
        DataSourceDescriptor(
            id: config.id,
            displayName: config.displayName,
            cadence: config.cadence,
            providedPaths: []
        )
    }

    public func fetch() async throws -> DataSnapshot {
        var request = URLRequest(url: config.url)
        request.timeoutInterval = 15
        for (field, value) in config.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, statusCode) = try await transport(request)
        guard (200..<300).contains(statusCode) else {
            throw DataSourceError.fetchFailed("HTTP \(statusCode) from \(config.url.absoluteString)")
        }
        guard data.count <= Self.maxResponseBytes else {
            throw DataSourceError.fetchFailed(
                "Response is \(data.count) bytes; limit is \(Self.maxResponseBytes)"
            )
        }

        let decoded: SnapshotValue
        do {
            decoded = try JSONDecoder().decode(SnapshotValue.self, from: data)
        } catch {
            throw DataSourceError.fetchFailed("Body is not valid JSON")
        }

        let values: SnapshotValue
        if let rootPath = config.rootPath, !rootPath.isEmpty {
            guard let subtree = decoded.value(atPath: rootPath) else {
                throw DataSourceError.fetchFailed("rootPath \"\(rootPath)\" not found in response")
            }
            values = subtree
        } else {
            values = decoded
        }
        return DataSnapshot(sourceID: config.id, values: values)
    }

    /// The dotted variable paths present in a fetched snapshot, prefixed with
    /// the source ID (`myapi.data.temp`). The editor calls this after the
    /// first fetch to populate autocomplete for custom sources. Lists
    /// contribute their own path (chart layers read lists whole) plus the
    /// paths of their first element as an `.0` sample.
    public static func discoveredPaths(in snapshot: DataSnapshot) -> [String] {
        var paths: [String] = []
        collectPaths(of: snapshot.values, prefix: snapshot.sourceID, into: &paths)
        return paths.sorted()
    }

    private static func collectPaths(
        of value: SnapshotValue,
        prefix: String,
        into paths: inout [String]
    ) {
        switch value {
        case .number, .string, .bool:
            paths.append(prefix)
        case .object(let dictionary):
            for (key, child) in dictionary {
                collectPaths(of: child, prefix: "\(prefix).\(key)", into: &paths)
            }
        case .list(let items):
            paths.append(prefix)
            if let first = items.first {
                collectPaths(of: first, prefix: "\(prefix).0", into: &paths)
            }
        }
    }

    /// Default transport. Wraps `dataTask` in a continuation rather than
    /// using the async `data(for:)` overload so behavior is identical across
    /// Darwin and corelibs-foundation on Linux.
    private static let urlSessionTransport: Transport = { request in
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: DataSourceError.fetchFailed(error.localizedDescription))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: DataSourceError.fetchFailed("Non-HTTP response"))
                    return
                }
                continuation.resume(returning: (data ?? Data(), http.statusCode))
            }
            task.resume()
        }
    }
}
