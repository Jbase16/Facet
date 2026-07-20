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

/// The widget extension is a dumb renderer by design: it reads the selected
/// document and cached snapshots from the App Group and draws. No fetching,
/// no decisions — that keeps renders fast and inside the ~30 MB extension
/// memory budget (SPEC §5.1).
struct FacetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FacetWidget", provider: FacetTimelineProvider()) { entry in
            FacetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Facet")
        .description("Your Facet design, live.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct FacetEntry: TimelineEntry {
    let date: Date
    let document: WidgetDocument?
    let snapshots: SnapshotSet
}

struct FacetTimelineProvider: TimelineProvider {
    private let repository = SharedDocumentRepository()

    func placeholder(in context: Context) -> FacetEntry {
        FacetEntry(
            date: Date(),
            document: StarterTemplates.batteryRing,
            snapshots: SampleData.snapshotSet()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FacetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FacetEntry>) -> Void) {
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

        var entries = [entry(at: now)]
        for offset in 0..<30 {
            entries.append(entry(at: nextMinute.addingTimeInterval(Double(offset) * 60)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> FacetEntry {
        let document = AppGroup.selectedDocumentID.flatMap { repository.load(id: $0) }
            ?? repository.loadAll().first
        var snapshots = AppGroup.snapshotStore.loadSet(sourceIDs: document?.sources ?? [])
        // Time is computed, not cached — always fresh, pre-dated per entry.
        snapshots.insert(TimeSource().snapshot(at: date))
        return FacetEntry(date: date, document: document, snapshots: snapshots)
    }
}

struct FacetWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: FacetEntry

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
                            canvasHeight: proxy.size.height
                        )
                    ),
                    interactive: true
                )
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
        case .accessoryCircular: return .accessoryCircular
        case .accessoryRectangular: return .accessoryRectangular
        case .accessoryInline: return .accessoryInline
        default: return .systemSmall
        }
    }
}
