import Foundation
import FacetCore
import FacetData
import FacetRender
import FacetTemplates

// facet-preview — render .facet documents (or built-in starter templates) to
// SVG with sample data. This is the Linux-friendly window into the exact
// resolution pipeline the iOS widget extension runs.
//
//   facet-preview list
//   facet-preview render "Battery Ring" [--rendition systemSmall] [--scheme light] [--out file.svg]
//   facet-preview render path/to/widget.facet [...]
//   facet-preview export-templates <directory>

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

func loadDocument(_ nameOrPath: String) -> WidgetDocument {
    if let template = StarterTemplates.template(named: nameOrPath) {
        return template
    }
    let url = URL(fileURLWithPath: nameOrPath)
    guard let data = try? Data(contentsOf: url) else {
        let names = StarterTemplates.all.map(\.name).joined(separator: ", ")
        fail("no template or file named '\(nameOrPath)'. Templates: \(names)")
    }
    do {
        return try FacetFile.decode(data)
    } catch {
        fail("could not decode \(nameOrPath): \(error)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print("""
    usage:
      facet-preview list
      facet-preview render <template-name|file.facet> [--rendition systemSmall] [--scheme light|dark] [--out file.svg]
      facet-preview export-templates <directory>
    """)
    exit(0)
}

switch command {
case "list":
    for document in StarterTemplates.all {
        print("\(document.name)  (sources: \(document.sources.joined(separator: ", ")))")
    }

case "render":
    guard arguments.count >= 2 else { fail("render needs a template name or .facet path") }
    let document = loadDocument(arguments[1])

    var rendition = RenditionKind.systemSmall
    var scheme = ColorScheme.light
    var outPath: String?
    var index = 2
    while index < arguments.count - 1 {
        switch arguments[index] {
        case "--rendition":
            guard let parsed = RenditionKind(rawValue: arguments[index + 1]) else {
                fail("unknown rendition '\(arguments[index + 1])'. One of: \(RenditionKind.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            rendition = parsed
        case "--scheme":
            guard let parsed = ColorScheme(rawValue: arguments[index + 1]) else {
                fail("scheme must be light or dark")
            }
            scheme = parsed
        case "--out":
            outPath = arguments[index + 1]
        default:
            fail("unknown option '\(arguments[index])'")
        }
        index += 2
    }

    let snapshots = SampleData.snapshotSet()
    let resolved = DocumentResolver.resolve(
        document: document,
        snapshots: snapshots,
        environment: RenderEnvironment(rendition: rendition, colorScheme: scheme)
    )
    for diagnostic in resolved.diagnostics {
        FileHandle.standardError.write(
            Data("warning: \(diagnostic.layerName): \(diagnostic.message)\n".utf8)
        )
    }
    let svg = SVGRenderer.render(resolved)
    if let outPath {
        try svg.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("wrote \(outPath)")
    } else {
        print(svg)
    }

case "export-templates":
    guard arguments.count >= 2 else { fail("export-templates needs a target directory") }
    let directory = URL(fileURLWithPath: arguments[1])
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for document in StarterTemplates.all {
        let slug = document.name.lowercased().replacingOccurrences(of: " ", with: "-")
        let url = directory.appendingPathComponent("\(slug).facet")
        try FacetFile.encode(document).write(to: url)
        print("wrote \(url.path)")
    }

default:
    fail("unknown command '\(command)'")
}
