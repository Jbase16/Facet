import UIKit

/// One installed font family and the faces it ships.
struct FontFamily: Identifiable, Hashable, Sendable {
    /// The family name exactly as `UIFont` reports it — this is the string
    /// that goes into `FontToken.family`. Every stock iOS family name also
    /// resolves through `UIFont(name:)`, so `Font.custom(family, size:)` in
    /// the renderer finds it without any PostScript translation.
    let id: String
    /// What the picker shows. Identical to `id` for every stock family; it
    /// exists so a private, dot-prefixed name could never reach the UI raw.
    let displayName: String
    /// PostScript names of the faces in this family ("AvenirNext-DemiBold").
    /// Facet stores a family, not a face — these are here so a row can say how
    /// much range a family has.
    let faceNames: [String]

    var faceCount: Int { faceNames.count }
}

/// The font families actually installed on this device.
///
/// iOS ships a fixed font set and Facet cannot extend it: a widget draws only
/// fonts already on the device, and adding one requires a font-provider
/// extension the user installs and enables in Settings. There is no bundled
/// -font path that reaches the widget extension either. So this enumeration is
/// the honest ceiling — roughly 87 families on current iOS — and the picker
/// should not imply otherwise.
///
/// Concurrency: `UIFont.familyNames` and `UIFont.fontNames(forFamilyName:)`
/// are *not* main-actor isolated in the iOS SDK (verified under Swift 6
/// language mode), so the catalog is a plain immutable global rather than
/// main-actor state and can be read from anywhere. Enumeration walks every
/// registered font, so it runs exactly once, lazily, on first touch — the
/// picker re-reads these on every keystroke.
enum FontCatalog {
    /// Every usable family, de-duplicated and sorted.
    static let families: [FontFamily] = {
        var seen = Set<String>()
        return UIFont.familyNames
            // Dot-prefixed families are the private system faces; they are not
            // ours to hand out and their names are not user-facing.
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .compactMap { name -> FontFamily? in
                guard seen.insert(name).inserted else { return nil }
                let faces = UIFont.fontNames(forFamilyName: name).sorted()
                guard !faces.isEmpty else { return nil }
                return FontFamily(id: name, displayName: name, faceNames: faces)
            }
    }()

    /// A shortlist surfaced above the full run: families with the presence,
    /// numerals, or character a widget actually wants. Ordered by how often
    /// they earn their place, not alphabetically.
    ///
    /// Verified against the live enumeration rather than trusted — iOS drops
    /// and renames families between releases, and a hardcoded name that no
    /// longer exists would render as the system font with no explanation.
    static let curated: [FontFamily] = curatedNames.compactMap { byID[$0] }

    static let curatedIDs: Set<String> = Set(curated.map(\.id))

    /// Case- and diacritic-insensitive. Matches face names too, so "condensed"
    /// finds American Typewriter as well as Avenir Next Condensed.
    static func search(_ query: String) -> [FontFamily] {
        let needle = fold(query)
        guard !needle.isEmpty else { return families }
        return index.compactMap { $0.key.contains(needle) ? $0.family : nil }
    }

    static func family(named name: String) -> FontFamily? { byID[name] }

    /// Alphabetical sections for the long tail. Families that start with
    /// anything but a letter collect under "#".
    static func grouped(_ list: [FontFamily]) -> [(String, [FontFamily])] {
        Dictionary(grouping: list) { family -> String in
            let initial = family.displayName.prefix(1).uppercased()
            return initial.rangeOfCharacter(from: .letters) == nil ? "#" : initial
        }
        .sorted { $0.key < $1.key }
        .map { ($0.key, $0.value) }
    }

    // MARK: - Internals

    private static let byID: [String: FontFamily] =
        Dictionary(families.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// Folded search keys, built once. The picker searches on every keystroke
    /// and folding 87 strings per character would be visible.
    private static let index: [(key: String, family: FontFamily)] = families.map {
        (fold($0.displayName + " " + $0.faceNames.joined(separator: " ")), $0)
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static let curatedNames = [
        // Geometric and grotesque workhorses — the default good answer.
        "Avenir Next",
        "Avenir Next Condensed",
        "Futura",
        "Helvetica Neue",
        "Gill Sans",
        "Optima",
        "Trebuchet MS",
        // Built for numerals; the reason clock and gauge widgets look sharp.
        "DIN Condensed",
        "DIN Alternate",
        // Serifs, from workaday to high-contrast display.
        "Georgia",
        "Charter",
        "Baskerville",
        "Hoefler Text",
        "Didot",
        "Bodoni 72",
        // Slab and engraved — weight without shouting.
        "American Typewriter",
        "Rockwell",
        "Copperplate",
        "Impact",
        // Mono, for terminal-flavored layouts.
        "Menlo",
        // Hand and script, where most "aesthetic" widgets end up.
        "Snell Roundhand",
        "Savoye LET",
        "Zapfino",
        "Noteworthy",
        "Marker Felt",
        "Chalkboard SE",
    ]
}
