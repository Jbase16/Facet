# Facet — project context for Claude Code

Facet is a custom widget builder for iOS (a Widgy competitor). The full
product/architecture spec is docs/SPEC.md — read it before large changes.
README.md has the current status and build instructions.

## Layout

- `Sources/FacetCore` — the `.facet` document model (schema v2) + expression
  language + `Geometry/` (SVG path subset parser, path node editing, shape
  generators). Pure Swift, no UI, builds on Linux — no CoreGraphics, hence
  `PathPoint` rather than CGPoint. Schema changes must keep old documents
  decoding (see the v1-compat pattern: optional fields, string-form fills).
  `Document/Scene.swift` is the *scene* document: a whole home screen
  (wallpaper + widget placements + shared palette). Placements reference
  widgets by id, never copy them, so the two have independent lifetimes —
  and so one design takes on each scene's palette via
  `document.applying(palette:)`, which merges (never replaces) the scene's
  `ThemeTokens` over the widget's own. Layers using literal colours are
  deliberately immune: a literal is the author saying "this exact colour".
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
  `cd App && xcodegen generate`. `App/Shared/` is compiled into BOTH
  targets — anything the widget extension needs (asset store, app group,
  image provider) belongs there, not in `App/Facet/`.
  The `Facet` scheme is declared in project.yml and shared; without it
  XcodeGen emits no scheme and Run has nothing to launch.
- `Templates/` — exported .facet files (regenerate with
  `swift run facet-preview export-templates Templates`).

## Build & test

- Packages: `swift build` / `swift test` (works on macOS and Linux).
- Headless smoke tests: `xcrun simctl launch booted com.JasonPhillips.app
  -facet-show-sources` (or `-facet-open-editor`, `-facet-open-scene`) opens
  a screen directly.
- Simulator: Xcode 27 replaced Simulator.app with DeviceHub.app. The
  physical iPhone and the sim are both named "iPhone 17 Pro" — picking the
  device destination builds fine and launches nothing visible.
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
- The authoritative source for any SDK question is the SDK itself, not a
  search. `xcrun --sdk iphoneos --show-sdk-path`, then read
  `.../Modules/<Framework>.swiftmodule/arm64e-apple-ios.swiftinterface` —
  every public declaration with its exact `@available`. Searching turned up
  iOS 17/18 answers for an iOS 27 question more than once.
- Widget background transparency does not exist on iOS 27 and is not coming
  by API. `containerBackground` is unchanged since iOS 17; `WidgetTexture`
  (`.glass`/`.paper`) is visionOS-only, `@available(iOS, unavailable)`.
  The wallpaper-crop illusion is the only route.
- `DetailLevel` mirrors WidgetKit's `LevelOfDetail` (iOS 26+) but is our own
  type — FacetCore builds on Linux, where WidgetKit doesn't exist. The
  mapping happens once, in `FacetWidgets.swift`, behind the only
  `#available(iOS 26)` in the app.
- Masks (`LayerStyle.mask`) are a shape plus an optional alpha ramp plus
  invert — not a reference to another layer. Masking by a layer's alpha
  (text knockouts) needs cycle detection and a second pass; it is a
  different, bigger feature. `ShapeKind` is reused, so anything the shape
  studio generates works as a mask by pasting its path.
- `LayerStyle.shadows` is a LIST, and each shadow has `inset`. Neumorphism
  (raised/pressed), emboss and deboss are all the same trick: two shadows on
  opposite sides, flipped inside-out. `ShadowPreset` writes ordinary values —
  nothing about it is special-cased in the renderers. The effect only reads
  correctly when the layer is the SAME COLOUR as what's behind it.
  `style.shadow` survives as a first-element accessor. On disk, a lone outer
  shadow still writes the singular `shadow` key so the common case stays
  byte-identical; anything inset or plural writes `shadows`.
- Effect order is `colorAdjust → mask → blur → innerShadows → border →
  transform → glow → outerShadows → opacity → blend`, and BOTH backends must
  match. Inset shadows sit before `transform` because they belong to the
  layer's surface and must rotate with it; outer shadows sit after, cast by
  the transformed silhouette in screen space. SVG puts the mask
  on an inner `<g>` so the outer group's filter runs after it — on the same
  element, SVG would apply the filter first and a shadow would be cast by the
  unclipped silhouette.
- A circle shape or mask is INSCRIBED (`Circle()` / `r = min(w,h)/2`), never
  stretched. `Ellipse()` fills the rect and silently diverges from SVG on any
  non-square layer.
- A radial *gradient* is the opposite: it STRETCHES. SVG's default
  `objectBoundingBox` units map the ramp through the element's own box, so on a
  wide layer it is an ellipse reaching the left/right edge midpoints. The
  SwiftUI side must be `EllipticalGradient(endRadiusFraction: 0.5)`;
  `RadialGradient(endRadius:)` takes points, stays round, and washes out on
  anything non-square. Fractions also let one paint serve a shape filling the
  layer and a line of text occupying a fraction of it — which is how gradient
  text matches across backends. This applies to `MaskModifier.fadeStyle` too —
  a radial mask fade is a vignette, and the round form left it circular in
  SwiftUI and oval in SVG on every non-square layer.
- Text and symbols paint with `Fill`, not `ColorRef` — they take gradients like
  shapes. A solid paint still writes the legacy `color` key as a plain string,
  so existing documents are byte-identical and unmigrated; only a gradient
  writes `fill`. Line, gauge and chart paints are deliberately still
  `ColorRef`: they are STROKES, where the two backends resolve gradient
  geometry against different boxes (SVG the path bbox, SwiftUI the view
  bounds) and a horizontal line's bbox is degenerate in SVG.
- Verify renderer work by rendering and looking, in BOTH backends. Two real
  bugs in the mask pass — the ellipse divergence and a stale simulator
  binary reading as "masks don't work" — were invisible to a green suite.
  `swift run facet-preview render <file> --out x.svg` then
  `qlmanage -t -s 840 -o . x.svg` gives a PNG to actually look at.
- Anything that decides whether a layer renders must go in
  `DocumentResolver.willRender`, not inline. Stack layout sizes its cells
  from that predicate in a pre-pass; when the two disagreed, a hidden layer
  kept its slot and left a hole.
- Home-screen grid constants live in `App/Facet/HomeGrid.swift` and nowhere
  else. `HomeScreenPreview`, `SceneEditorView` and `SceneCell` all draw the
  same grid; when each kept a private copy they agreed only by luck.
- `scaleEffect` scales drawn pixels but *not* layout size. Every widget
  drawn at reduced scale needs `.frame(w*scale, h*scale, alignment:
  .topLeading)` after it, or SwiftUI centres the shrunken render in a
  full-size box and the widget lands offset by half its slack.
- `.facetscene` files store document *ids*, so a scene is not shareable on
  its own yet — it would open elsewhere as a screen of empty slots.
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
