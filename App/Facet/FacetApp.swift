import SwiftUI
import WidgetKit
import FacetCore
import FacetData
import FacetTemplates

@main
struct FacetApp: App {
    @State private var store = DocumentStore()
    @State private var scenes = SceneStore()

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .environment(store)
                .environment(scenes)
                // A design tool lives on a dark workspace; the widgets being
                // edited are the only things that get to be loud.
                .preferredColorScheme(.dark)
                .tint(FacetUI.accent)
                .task {
                    store.seedStarterTemplatesIfNeeded()
                    await store.refreshData()
                }
        }
    }
}

/// App-side scene state. Deliberately separate from `DocumentStore`: a scene
/// only references documents by id, so the two have independent lifetimes and
/// deleting either must not disturb the other.
///
/// No `WidgetCenter` reload here — a scene is a design-time composition, not
/// something the home screen renders. Saving one changes nothing on the device.
@Observable
@MainActor
final class SceneStore {
    private let repository = SceneRepository()
    private(set) var scenes: [FacetScene] = []

    init() {
        scenes = repository.loadAll()
    }

    func save(_ scene: FacetScene) {
        do {
            try repository.save(scene)
            if let index = scenes.firstIndex(where: { $0.id == scene.id }) {
                scenes[index] = scene
            } else {
                scenes.append(scene)
            }
            scenes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            assertionFailure("Failed to save scene: \(error)")
        }
    }

    func delete(_ scene: FacetScene) {
        try? repository.delete(id: scene.id)
        // The wallpaper is stored under the scene's own id, so it has to go
        // with it — otherwise every deleted scene leaves a full-res photo
        // behind in the App Group container.
        try? AssetStore().deleteAll(for: scene.id)
        scenes.removeAll { $0.id == scene.id }
    }

    func duplicate(_ scene: FacetScene) {
        var copy = scene
        copy.id = UUID()
        copy.name += " Copy"
        // Placements are references, so they copy for free. The wallpaper does
        // not: it is keyed by scene id and would dangle.
        if let name = scene.backdrop,
           let data = AssetStore().data(for: name, in: scene.id) {
            try? AssetStore().write(data, named: name, for: copy.id)
        }
        // Fresh identities for the placements too, so editing the copy's
        // layout cannot collide with the original's drag targets.
        copy.placements = copy.placements.map {
            ScenePlacement(documentID: $0.documentID, rendition: $0.rendition, column: $0.column, row: $0.row)
        }
        save(copy)
    }
}

/// App-side document state. Every save also nudges WidgetKit so home-screen
/// widgets pick up edits immediately.
@Observable
@MainActor
final class DocumentStore {
    private let repository = SharedDocumentRepository()
    private(set) var documents: [WidgetDocument] = []

    var selectedForWidget: UUID? {
        get { AppGroup.selectedDocumentID }
        set {
            AppGroup.selectedDocumentID = newValue
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    init() {
        documents = repository.loadAll()
    }

    func seedStarterTemplatesIfNeeded() {
        guard documents.isEmpty else { return }
        for template in StarterTemplates.all {
            try? repository.save(template)
        }
        documents = repository.loadAll()
        if selectedForWidget == nil {
            selectedForWidget = documents.first?.id
        }
    }

    func save(_ document: WidgetDocument) {
        do {
            try repository.save(document)
            if let index = documents.firstIndex(where: { $0.id == document.id }) {
                documents[index] = document
            } else {
                documents.append(document)
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            assertionFailure("Failed to save document: \(error)")
        }
    }

    func delete(_ document: WidgetDocument) {
        try? repository.delete(id: document.id)
        // Assets are stored per document ID; without this the photos
        // outlive the widget forever in the App Group container.
        try? AssetStore().deleteAll(for: document.id)
        documents.removeAll { $0.id == document.id }
    }

    func duplicate(_ document: WidgetDocument) {
        var copy = document
        copy.id = UUID()
        copy.name += " Copy"
        // Asset names are scoped by document ID, so a copy needs its own
        // set or every image layer in it would dangle.
        copyAssets(from: document.id, to: copy.id)
        save(copy)
    }

    private func copyAssets(from source: UUID, to destination: UUID) {
        let store = AssetStore()
        for name in store.list(for: source) {
            if let data = store.data(for: name, in: source) {
                try? store.write(data, named: name, for: destination)
            }
        }
    }

    /// Fetch every source any document uses, respecting the refresh planner,
    /// then let widgets re-render from the shared cache.
    func refreshData() async {
        let store = AppGroup.snapshotStore
        DeviceDataSources.seedSampleSnapshotsIfNeeded(store: store)
        let providers = DeviceDataSources.providers
        let descriptors = providers.map { $0.descriptor }
        let planner = RefreshPlanner(store: store)
        let plan = planner.plan(for: descriptors)
        await planner.executePlan(plan, providers: providers)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
