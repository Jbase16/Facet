import SwiftUI
import WidgetKit
import FacetCore
import FacetData
import FacetTemplates

@main
struct FacetApp: App {
    @State private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .environment(store)
                .task {
                    store.seedStarterTemplatesIfNeeded()
                    await store.refreshData()
                }
        }
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
        documents.removeAll { $0.id == document.id }
    }

    func duplicate(_ document: WidgetDocument) {
        var copy = document
        copy.id = UUID()
        copy.name += " Copy"
        save(copy)
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
