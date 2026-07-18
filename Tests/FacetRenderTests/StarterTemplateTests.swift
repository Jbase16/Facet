import XCTest
import FacetCore
import FacetData
import FacetTemplates
@testable import FacetRender

/// Every starter template must resolve with zero diagnostics against sample
/// data, in every rendition and both color schemes — the "no broken presets
/// ever ship" gate.
final class StarterTemplateTests: XCTestCase {
    private func sampleSnapshots() async -> SnapshotSet {
        var set = SnapshotSet()
        for provider in SampleData.all {
            if let snapshot = try? await provider.fetch() {
                set.insert(snapshot)
            }
        }
        return set
    }

    func testAllTemplatesResolveCleanlyEverywhere() async {
        let snapshots = await sampleSnapshots()
        for document in StarterTemplates.all {
            for rendition in RenditionKind.allCases {
                for scheme in [ColorScheme.light, .dark] {
                    let resolved = DocumentResolver.resolve(
                        document: document,
                        snapshots: snapshots,
                        environment: RenderEnvironment(rendition: rendition, colorScheme: scheme)
                    )
                    XCTAssertTrue(
                        resolved.diagnostics.isEmpty,
                        "\(document.name) @ \(rendition.rawValue)/\(scheme.rawValue): \(resolved.diagnostics)"
                    )
                    XCTAssertFalse(SVGRenderer.render(resolved).isEmpty)
                }
            }
        }
    }

    func testTemplatesRoundTripThroughFacetFile() throws {
        for document in StarterTemplates.all {
            let data = try FacetFile.encode(document)
            XCTAssertEqual(try FacetFile.decode(data), document, document.name)
        }
    }

    func testTemplateSourcesAreOnlyKnownSampleSources() {
        let known = Set(SampleData.all.map { $0.descriptor.id })
        for document in StarterTemplates.all {
            for source in document.sources {
                XCTAssertTrue(known.contains(source), "\(document.name) uses unknown source \(source)")
            }
        }
    }

    func testTemplateIDsAreUnique() {
        let ids = StarterTemplates.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
