import AppIntents
import WidgetKit
import SwiftUI
import FacetCore
import FacetData
import FacetRender
import FacetTemplates

@main
struct FacetWidgetBundle: WidgetBundle {
    var body: some Widget {
        FacetWidget()
    }
}

/// The widget extension is a dumb renderer by design: it reads a document and
/// cached snapshots from the App Group and draws. No fetching, no decisions —
/// that keeps renders fast and inside the ~30 MB extension memory budget
/// (SPEC §5.1).
///
/// The configuration is per-instance, so each placed widget picks its own
/// design and several can run at once. The kind is unchanged on purpose:
/// widgets already on a home screen keep their identity and pick up a default
/// configuration rather than disappearing.
struct FacetWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "FacetWidget",
            intent: SelectDocumentIntent.self,
            provider: FacetTimelineProvider()
        ) { entry in
            FacetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Facet")
        .description("Your Facet design, live. Long-press to choose which one.")
        .supportedFamilies(Self.families)
    }

    /// Built at runtime rather than as an array literal: the extra-large
    /// families are gated on newer systems, and an unavailable case cannot
    /// appear in a literal compiled against a 17 deployment target.
    private static var families: [WidgetFamily] {
        var families: [WidgetFamily] = [
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ]
        // iPad-only; harmless to declare on iPhone, where the system simply
        // never offers them.
        families.append(.systemExtraLarge)
        if #available(iOS 27.0, *) {
            families.append(.systemExtraLargePortrait)
        }
        return families
    }
}

struct FacetEntry: TimelineEntry {
    let date: Date
    let document: WidgetDocument?
    let snapshots: SnapshotSet
}

struct FacetTimelineProvider: AppIntentTimelineProvider {
    private let repository = SharedDocumentRepository()

    func placeholder(in context: Context) -> FacetEntry {
        FacetEntry(
            date: Date(),
            document: StarterTemplates.batteryRing,
            snapshots: SampleData.snapshotSet()
        )
    }

    func snapshot(for configuration: SelectDocumentIntent, in context: Context) async -> FacetEntry {
        entry(at: Date(), for: configuration)
    }

    func timeline(for configuration: SelectDocumentIntent, in context: Context) async -> Timeline<FacetEntry> {
        // One entry per minute for the next 30 minutes keeps clocks honest;
        // everything else re-renders from the cache each entry for free.
        // After that, WidgetKit re-asks and the planner's floor applies.
        let now = Date()
        let calendar = Calendar.current
        let nextMinute = calendar.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60)

        var entries = [entry(at: now, for: configuration)]
        for offset in 0..<30 {
            entries.append(entry(at: nextMinute.addingTimeInterval(Double(offset) * 60), for: configuration))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// Resolves this instance's configured design, falling back to the old
    /// single-selection key and then to any document — so a widget placed
    /// before per-instance configuration existed still draws something.
    private func entry(at date: Date, for configuration: SelectDocumentIntent) -> FacetEntry {
        let document = configuration.design.flatMap { repository.load(id: $0.id) }
            ?? AppGroup.selectedDocumentID.flatMap { repository.load(id: $0) }
            ?? repository.loadAll().first
        var snapshots = AppGroup.snapshotStore.loadSet(sourceIDs: document?.sources ?? [])
        // Time is computed, not cached — always fresh, pre-dated per entry.
        snapshots.insert(TimeSource().snapshot(at: date))
        return FacetEntry(date: date, document: document, snapshots: snapshots)
    }
}

/// Reads the system's requested level of detail and hands it to the renderer.
///
/// Split into its own view because `\.levelOfDetail` is iOS 26+ and the app's
/// deployment target is 17 — a property wrapper can't be conditionally
/// declared, but a whole view can be conditionally instantiated.
@available(iOS 26.0, *)
private struct DetailAwareEntryView: View {
    @Environment(\.levelOfDetail) private var levelOfDetail
    let entry: FacetEntry

    var body: some View {
        FacetWidgetBody(
            entry: entry,
            detail: levelOfDetail == .simplified ? .simplified : .full
        )
    }
}

struct FacetWidgetEntryView: View {
    let entry: FacetEntry

    var body: some View {
        if #available(iOS 26.0, *) {
            DetailAwareEntryView(entry: entry)
        } else {
            // Before iOS 26 the system never asks for less, so full detail is
            // not a fallback here — it is the only thing that was ever drawn.
            FacetWidgetBody(entry: entry, detail: .full)
        }
    }
}

struct FacetWidgetBody: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: FacetEntry
    let detail: DetailLevel

    var body: some View {
        if let document = entry.document {
            GeometryReader { proxy in
                FacetWidgetView(
                    widget: DocumentResolver.resolve(
                        document: document,
                        snapshots: entry.snapshots,
                        environment: RenderEnvironment(
                            rendition: rendition,
                            colorScheme: colorScheme == .dark ? .dark : .light,
                            canvasWidth: proxy.size.width,
                            canvasHeight: proxy.size.height,
                            detail: detail
                        )
                    ),
                    interactive: true
                )
                .environment(\.facetImageProvider, FacetImageProviderFactory.make(documentID: document.id))
            }
            .containerBackground(.clear, for: .widget)
        } else {
            Text("Open Facet to pick a widget")
                .font(.caption)
                .containerBackground(.background, for: .widget)
        }
    }

    private var rendition: RenditionKind {
        switch family {
        case .systemMedium: return .systemMedium
        case .systemLarge: return .systemLarge
        case .systemExtraLarge: return .systemExtraLarge
        case .accessoryCircular: return .accessoryCircular
        case .accessoryRectangular: return .accessoryRectangular
        case .accessoryInline: return .accessoryInline
        default:
            // `systemExtraLargePortrait` is iOS 27+, so it cannot appear in a
            // switch case compiled against a 17 deployment target.
            if #available(iOS 27.0, *), family == .systemExtraLargePortrait {
                return .systemExtraLargePortrait
            }
            return .systemSmall
        }
    }
}
