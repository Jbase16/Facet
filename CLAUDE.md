# Facet — project context for Claude Code

Facet is a custom widget builder for iOS (a Widgy competitor). The full
product/architecture spec is docs/SPEC.md — read it before large changes.
README.md has the current status and build instructions.

## Layout

- `Sources/FacetCore` — the `.facet` document model (schema v2) + expression
  language. Pure Swift, no UI. Schema changes must keep old documents
  decoding (see the v1-compat pattern: optional fields, string-form fills).
- `Sources/FacetData` — data sources, snapshot cache, refresh planner,
  URLJSONSource (custom APIs), AstronomySource (computed sun/moon).
- `Sources/FacetRender` — DocumentResolver (pure: document + data + env →
  render tree), SVGRenderer (Linux/CI debug backend), SwiftUI renderer.
  The editor preview, SVG output, and the widget extension all share the
  resolver — never fork rendering logic per surface.
- `Sources/FacetTemplates` — 12 starter templates, deterministic UUIDs.
- `Sources/facet-preview` — CLI: render templates/.facet files to SVG.
- `App/` — the iOS app + widget extension. Xcode project is generated from
  `App/project.yml` by XcodeGen; the generated `Facet.xcodeproj` is
  committed. After adding/removing files under App/, run
  `cd App && xcodegen generate`.
- `Templates/` — exported .facet files (regenerate with
  `swift run facet-preview export-templates Templates`).

## Build & test

- Packages: `swift build` / `swift test` (works on macOS and Linux; 96 tests).
- App: build the `Facet` scheme in Xcode or
  `xcodebuild -project App/Facet.xcodeproj -scheme Facet -destination 'generic/platform=iOS Simulator' build`.
- Template gate: every starter template must resolve with zero diagnostics
  in every rendition × both color schemes (StarterTemplateTests enforces).
- Regenerate preview SVGs after template/render changes:
  `swift run facet-preview render "<name>" --scheme dark --out docs/previews/<file>.svg`.

## Conventions & gotchas

- Value types + Sendable everywhere; comments explain *why*, sparingly.
- The widget extension must stay a dumb renderer: no networking, reads only
  the App Group snapshot cache (extension memory budget is ~30 MB).
- Refresh discipline: sources declare CadenceClass; RefreshPlanner enforces
  a 15-minute floor. Don't add code that asks WidgetKit for faster reloads.
- Bundle IDs: app `com.JasonPhillips.app`, widgets
  `com.JasonPhillips.app.widgets` (extension ID must prefix-match the app).
- App Group: `group.com.facet.app` in AppGroupStore.swift and both
  .entitlements files — rename all three together or not at all.
- Editor: `systemSmall` is the base design; geometry edits in any other
  rendition record `LayerPatch` overrides instead of mutating the base.
- Xcode 27 quirk: don't store bare closures via @Entry (comparability
  diagnostic) — see FacetImageProvider for the wrapper pattern.

## Roadmap (from docs/SPEC.md; not yet built)

Interactive button layers (App Intents), Live Activities, Widgy JSON
importer, photo/image asset bundles, AI widget generation, community
gallery. Custom URL sources exist in FacetData but have no editor UI yet.
Device providers (battery/weather/health/calendar) are real as of M4 —
they live in App/Facet/DataSources/, throw `.unavailable` until their
permission is granted, and the cache keeps stale-seeded sample data so
templates always render. WeatherKit additionally needs the WeatherKit
service enabled on the App ID in the developer portal; without it the
weather fetch fails (by design, non-fatally).
