// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Facet",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "FacetCore", targets: ["FacetCore"]),
        .library(name: "FacetData", targets: ["FacetData"]),
        .library(name: "FacetRender", targets: ["FacetRender"]),
        .library(name: "FacetTemplates", targets: ["FacetTemplates"]),
        .executable(name: "facet-preview", targets: ["facet-preview"]),
    ],
    targets: [
        .target(name: "FacetCore"),
        .target(name: "FacetData", dependencies: ["FacetCore"]),
        .target(name: "FacetRender", dependencies: ["FacetCore", "FacetData"]),
        .target(name: "FacetTemplates", dependencies: ["FacetCore"]),
        .executableTarget(
            name: "facet-preview",
            dependencies: ["FacetCore", "FacetData", "FacetRender", "FacetTemplates"]
        ),
        .testTarget(name: "FacetCoreTests", dependencies: ["FacetCore"]),
        .testTarget(name: "FacetDataTests", dependencies: ["FacetData"]),
        .testTarget(name: "FacetRenderTests", dependencies: ["FacetRender", "FacetTemplates"]),
    ]
)
