import XCTest
@testable import FacetData

final class URLJSONSourceTests: XCTestCase {
    private func config(rootPath: String? = nil) -> URLSourceConfig {
        URLSourceConfig(
            id: "crypto",
            displayName: "Crypto Prices",
            url: URL(string: "https://api.example.com/v1/prices")!,
            headers: ["Authorization": "Bearer token-123"],
            cadence: .hourly,
            rootPath: rootPath
        )
    }

    func testHappyPathDecodesJSONIntoSnapshot() async throws {
        let json = """
        {"bitcoin": {"usd": 64250.5, "symbol": "BTC"}, "stale": false,
         "history": [1, 2, 3]}
        """
        let source = URLJSONSource(config: config()) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/prices")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
            return (Data(json.utf8), 200)
        }
        let snapshot = try await source.fetch()

        XCTAssertEqual(snapshot.sourceID, "crypto")
        XCTAssertEqual(snapshot.values.value(atPath: "bitcoin.usd"), .number(64250.5))
        XCTAssertEqual(snapshot.values.value(atPath: "bitcoin.symbol"), .string("BTC"))
        XCTAssertEqual(snapshot.values.value(atPath: "stale"), .bool(false))
        XCTAssertEqual(snapshot.values.value(atPath: "history.2"), .number(3))
    }

    func testRootPathSelectsSubtree() async throws {
        let json = """
        {"data": {"current": {"temp": 21.5, "wind": 12}}, "meta": {"page": 1}}
        """
        let source = URLJSONSource(config: config(rootPath: "data.current")) { _ in
            (Data(json.utf8), 200)
        }
        let snapshot = try await source.fetch()

        XCTAssertEqual(snapshot.values.value(atPath: "temp"), .number(21.5))
        XCTAssertEqual(snapshot.values.value(atPath: "wind"), .number(12))
        XCTAssertNil(snapshot.values.value(atPath: "meta.page"), "Content outside rootPath is dropped")
    }

    func testMissingRootPathFails() async {
        let source = URLJSONSource(config: config(rootPath: "data.nope")) { _ in
            (Data("{\"data\": {}}".utf8), 200)
        }
        await assertFetchFails(source, messageContains: "data.nope")
    }

    func testNon2xxStatusIsRejectedWithCode() async {
        let source = URLJSONSource(config: config()) { _ in
            (Data("{\"error\": \"nope\"}".utf8), 403)
        }
        await assertFetchFails(source, messageContains: "403")
    }

    func testOversizedResponseIsRejected() async {
        let big = Data(repeating: UInt8(ascii: "x"), count: URLJSONSource.maxResponseBytes + 1)
        let source = URLJSONSource(config: config()) { _ in (big, 200) }
        await assertFetchFails(source, messageContains: "bytes")
    }

    func testInvalidJSONBodyIsRejected() async {
        let source = URLJSONSource(config: config()) { _ in
            (Data("not json at all".utf8), 200)
        }
        await assertFetchFails(source, messageContains: "JSON")
    }

    func testConfigCodableRoundTrip() throws {
        let original = config(rootPath: "data.current")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(URLSourceConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDescriptorReflectsConfig() {
        let descriptor = URLJSONSource(config: config()).descriptor
        XCTAssertEqual(descriptor.id, "crypto")
        XCTAssertEqual(descriptor.displayName, "Crypto Prices")
        XCTAssertEqual(descriptor.cadence, .hourly)
    }

    func testDiscoveredPathsWalkTheSnapshot() {
        let snapshot = DataSnapshot(
            sourceID: "crypto",
            values: .object([
                "bitcoin": .object(["usd": .number(64250.5)]),
                "history": .list([.number(1), .number(2)]),
                "stale": .bool(false),
            ])
        )
        XCTAssertEqual(
            URLJSONSource.discoveredPaths(in: snapshot),
            ["crypto.bitcoin.usd", "crypto.history", "crypto.history.0", "crypto.stale"]
        )
    }

    private func assertFetchFails(
        _ source: URLJSONSource,
        messageContains fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await source.fetch()
            XCTFail("Expected fetch to throw", file: file, line: line)
        } catch let DataSourceError.fetchFailed(message) {
            XCTAssertTrue(
                message.contains(fragment),
                "\"\(message)\" should mention \"\(fragment)\"",
                file: file,
                line: line
            )
        } catch {
            XCTFail("Expected DataSourceError.fetchFailed, got \(error)", file: file, line: line)
        }
    }
}
