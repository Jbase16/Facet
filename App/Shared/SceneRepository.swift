import Foundation
import FacetCore

/// Reads and writes `.facetscene` files in the shared container, alongside the
/// widget documents. Scenes live in the App Group rather than the app's own
/// sandbox for the same reason documents do: the widget extension can read
/// them, which is what a future "apply this scene" flow will need.
struct SceneRepository {
    var directory: URL = AppGroup.scenesURL

    func loadAll() -> [FacetScene] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "facetscene" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? SceneFile.decode(data)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func load(id: UUID) -> FacetScene? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? SceneFile.decode(data)
    }

    func save(_ scene: FacetScene) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try SceneFile.encode(scene).write(to: url(for: scene.id), options: .atomic)
    }

    func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).facetscene")
    }
}
