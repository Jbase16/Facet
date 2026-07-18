import Foundation
import FacetCore
import FacetData

/// The bridge between the app and the widget extension: documents, data
/// snapshots, and the widget's selected document all live in the shared
/// App Group container. The extension only ever reads.
enum AppGroup {
    /// Must match the App Group capability in both targets' entitlements.
    static let identifier = "group.com.facet.app"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            // Missing entitlement is a build misconfiguration; fall back so
            // previews and simulators without the capability still run.
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        return url
    }

    static var documentsURL: URL {
        containerURL.appendingPathComponent("Documents", isDirectory: true)
    }

    static var snapshotStore: SnapshotStore {
        SnapshotStore(directory: containerURL.appendingPathComponent("Snapshots", isDirectory: true))
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    private static let selectedDocumentKey = "selectedDocumentID"

    /// Which document the home-screen widget displays.
    static var selectedDocumentID: UUID? {
        get { defaults.string(forKey: selectedDocumentKey).flatMap(UUID.init) }
        set { defaults.set(newValue?.uuidString, forKey: selectedDocumentKey) }
    }
}

/// Reads and writes `.facet` files in the shared container.
struct SharedDocumentRepository {
    var directory: URL = AppGroup.documentsURL

    func loadAll() -> [WidgetDocument] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "facet" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? FacetFile.decode(data)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func load(id: UUID) -> WidgetDocument? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? FacetFile.decode(data)
    }

    func save(_ document: WidgetDocument) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FacetFile.encode(document).write(to: url(for: document.id), options: .atomic)
    }

    func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).facet")
    }
}
