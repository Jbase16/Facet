import Foundation
import FacetCore
import FacetData

/// Everything about *where* a widget is rendering, as opposed to *what* it
/// shows (the document) and *with which data* (the snapshot set).
public struct RenderEnvironment: Sendable {
    public var rendition: RenditionKind
    public var colorScheme: ColorScheme
    /// Canvas size in points. Defaults to the rendition's design size; on
    /// device, WidgetKit supplies the actual size.
    public var canvasWidth: Double
    public var canvasHeight: Double

    public init(
        rendition: RenditionKind,
        colorScheme: ColorScheme = .light,
        canvasWidth: Double? = nil,
        canvasHeight: Double? = nil
    ) {
        self.rendition = rendition
        self.colorScheme = colorScheme
        let design = rendition.designSize
        self.canvasWidth = canvasWidth ?? design.width
        self.canvasHeight = canvasHeight ?? design.height
    }
}

/// The evaluation context used during resolution: data snapshot values plus
/// environment variables (`env.rendition`, `env.dark`).
struct ResolutionContext: EvaluationContext {
    let snapshots: SnapshotSet
    let environment: RenderEnvironment

    func value(forVariable path: String) -> Value? {
        switch path {
        case "env.rendition": return .string(environment.rendition.rawValue)
        case "env.dark": return .bool(environment.colorScheme == .dark)
        default: return snapshots.value(forVariable: path)
        }
    }
}
