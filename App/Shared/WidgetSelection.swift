import AppIntents
import FacetCore

/// Which design a *single placed widget* shows.
///
/// This is what makes several Facet widgets able to coexist. Before, the
/// extension read one `selectedDocumentID` out of the App Group, so every
/// widget on the home screen drew the same document and the app could only
/// ever occupy one slot no matter how many designs you had.
struct SelectDocumentIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Design"
    static let description = IntentDescription("Pick which Facet design this widget shows.")

    @Parameter(title: "Design")
    var design: DocumentEntity?

    init() {}

    init(design: DocumentEntity?) {
        self.design = design
    }
}

/// A document as the widget configuration UI sees it. Deliberately just an id
/// and a name: the entity is a *reference*, and the extension loads the real
/// document from the App Group at render time, so editing a design updates
/// every widget showing it without reconfiguring anything.
struct DocumentEntity: AppEntity, Identifiable, Hashable {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Facet Design")
    }

    static let defaultQuery = DocumentQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct DocumentQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [DocumentEntity] {
        let documents = SharedDocumentRepository().loadAll()
        // Preserve the order the caller asked in; a lookup that reorders makes
        // the configuration UI show the wrong current value.
        return identifiers.compactMap { id in
            documents.first(where: { $0.id == id }).map { DocumentEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [DocumentEntity] {
        SharedDocumentRepository().loadAll().map { DocumentEntity(id: $0.id, name: $0.name) }
    }

    /// What a freshly placed widget shows before anyone configures it. Falls
    /// back to the document the old single-selection model had chosen, so
    /// widgets already on a home screen keep showing what they showed.
    func defaultResult() async -> DocumentEntity? {
        let documents = SharedDocumentRepository().loadAll()
        if let selected = AppGroup.selectedDocumentID,
           let match = documents.first(where: { $0.id == selected }) {
            return DocumentEntity(id: match.id, name: match.name)
        }
        return documents.first.map { DocumentEntity(id: $0.id, name: $0.name) }
    }
}
