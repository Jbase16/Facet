# Facet — Product & Architecture Spec

*Working title: **Facet** (naming TBD). A next-generation custom widget builder for iOS.*

## 1. Vision

Widgy proved there's a large audience for deeply customizable iOS widgets, but it did so
with a menu-driven editor designed before SwiftUI, interactive widgets, Live Activities,
or on-device AI existed. Facet's thesis:

> **The widget editor should feel like a design tool, not a settings screen** — and the
> widgets it produces should use every surface modern iOS offers.

Three pillars, in priority order:

1. **A true canvas editor.** Direct manipulation (drag, snap, multi-select, alignment
   guides), live preview at real widget sizes. This alone beats Widgy's biggest weakness.
2. **One design, every surface.** A token/theme layer so a single widget adapts across
   small/medium/large, Lock Screen, StandBy, and Apple Watch — instead of being rebuilt
   per size.
3. **Open data.** User-defined data sources (URL + JSON mapping, with auth and caching),
   alongside first-class built-ins (weather, health, calendar, battery, reminders).

Differentiator on top: **AI-assisted creation** — describe a widget in plain language
(or drop in a screenshot/inspiration image) and get an *editable* layout, not a raster.

## 2. Target users

| Segment | Today they use | What wins them over |
|---|---|---|
| Aesthetic customizers | Widgetsmith, templates | Beautiful presets + easy remixing, no learning curve |
| Power users / tinkerers | Widgy, Scriptable | Canvas editor, custom data sources, formula engine |
| Data-dashboard people | Scriptable, home-grown | JSON API sources, charts, refresh control |

The aesthetic segment is the volume; the power segment is the moat and the community
engine (they make the templates everyone else remixes).

## 3. Competitive landscape (summary)

- **Widgy** — deepest customization; menu-based editor with steep learning curve, no
  canvas, fixed data sources, aging UI, JSON-blob sharing.
- **Widgetsmith** — polished, huge install base, but shallow customization (pick a style,
  not build a design).
- **Scriptable** — ultimate flexibility via JavaScript, near-zero accessibility for
  non-programmers.
- **Widgetable** — social/pet gimmick widgets; different market.

Facet sits in the empty quadrant: **Widgy-level depth with Widgetsmith-level approachability.**

## 4. Core features

### 4.1 Canvas editor (MVP centerpiece)
- SwiftUI-based freeform canvas rendering the actual widget at true size (and zoomed).
- Layers: text, SF Symbols, images, shapes, progress rings/bars, charts (Swift Charts),
  containers (HStack/VStack/ZStack-like groups with padding/spacing).
- Direct manipulation: drag to position, pinch/handles to resize, snapping + alignment
  guides, multi-select, group/ungroup, reorder via layer list.
- Property inspector per layer (font, color, opacity, shadow, corner radius, rotation).
- Undo/redo everywhere; autosave with version history.

### 4.2 Theme & layout tokens
- Named tokens for colors, fonts, spacing; light/dark variants resolved automatically.
- One widget document targets multiple *renditions* (small/medium/large/accessory/
  StandBy/watch). Shared layer tree with per-rendition overrides — edit once, tweak per
  size, never rebuild.

### 4.3 Data engine
- **Built-in sources:** date/time, weather (WeatherKit), calendar, reminders, HealthKit
  (steps, activity rings, sleep), battery (device + connected), photos, RSS, system info.
- **Custom sources:** URL + headers/auth → JSON → field mapping with a small expression
  language (math, string formatting, conditionals, unit conversion). No full scripting
  runtime in v1; expressions cover 90% of Widgy's "math" use cases with less footgun.
- **Refresh budgets as a first-class concept.** iOS gives widgets a limited reload
  budget. Facet surfaces this honestly: each source declares a cadence class
  (realtime-ish / hourly / daily), the app schedules timeline entries accordingly, and
  the editor shows expected freshness. This is where every widget app earns its 1-star
  reviews; we design for it instead of hiding it.

### 4.4 Modern iOS surfaces (post-MVP, but architected from day one)
- **Interactive widgets** (App Intents): buttons/toggles in widgets — e.g., check off a
  reminder, start a timer.
- **Live Activities / Dynamic Island** templates driven by the same layer documents.
- **Lock Screen accessories, StandBy, watchOS complications** as renditions (see 4.2).
- **Controls** (Control Center / Action button) where applicable.

### 4.5 AI-assisted creation
- "Describe your widget" → generates a *document* (layers + tokens + data bindings) the
  user immediately edits on the canvas. Also: import a screenshot for layout inspiration.
- Implementation: server-side LLM call producing Facet's document JSON (schema-validated);
  on-device fallback later if practical. This is a creation accelerant, not the editor.

### 4.6 Community & sharing
- Documents are a single portable file (`.facet`, JSON + assets bundle).
- In-app gallery: browse, search, one-tap install, **remix** (fork with attribution),
  versioned updates from the original author.
- Share links / QR codes that deep-link to install.

## 5. Architecture

### 5.1 App structure
- **Main app** (SwiftUI): editor, gallery, data-source management, settings.
- **Widget extension** (WidgetKit): pure renderer — reads pre-resolved documents +
  cached data snapshots from the shared App Group container. The extension does *no*
  networking or heavy work (extension memory limit is ~30 MB; treat it as a dumb,
  fast renderer).
- **App Intents extension**: interactivity handlers for interactive widgets.
- **Background refresh** (BGAppRefreshTask + timeline policies): fetches data source
  snapshots into the App Group cache on the sources' cadence classes.

### 5.2 Document model
- A widget is a **document**: layer tree + tokens + data bindings + rendition overrides.
- Serialized as versioned JSON (Codable, explicit schema version, forward-migration).
- Rendering is a pure function: `(document, dataSnapshot, environment) → SwiftUI view`,
  shared between editor preview and widget extension so preview is always truthful.

### 5.3 Expression language
- Tiny, sandboxed, deterministic evaluator (no loops, no I/O): arithmetic, comparisons,
  ternaries, string interpolation/format, date math, unit conversion. Parsed to an AST
  at edit time with inline error reporting.

### 5.4 Sync & backend
- iCloud (CloudKit) for the user's own documents — private, free, no accounts needed.
- Lightweight backend only for: gallery/community, share links, AI generation endpoint.
  Sign in with Apple when publishing to the gallery; everything else works signed-out.

### 5.5 Tech baseline
- iOS 17+ minimum (interactive widgets, StandBy; covers the customizer demographic).
- Swift 6 / SwiftUI, Swift Charts, WeatherKit, HealthKit, App Intents, CloudKit.
- Modularized as Swift packages: `FacetCore` (document model + expressions),
  `FacetRender` (pure renderer), `FacetData` (sources + cache), app targets on top.
  Core/Render/Data have no UI-framework-free logic tested on macOS/Linux CI where possible.

## 6. Monetization

- **Free:** full editor, 2 active widgets, built-in data sources, gallery browsing.
- **Pro (subscription, with a fair lifetime option):** unlimited widgets, custom data
  sources, AI generation, watch/Live Activity surfaces, version history.
- No ads, ever. Templates remain free to share/install (community is the growth loop);
  monetize capability, not content.

## 7. MVP scope (v1.0)

**In:** canvas editor (4.1), tokens + small/medium/large + Lock Screen renditions (4.2),
built-in data sources + refresh budgeting (4.3 minus custom URLs), `.facet` import/export,
iCloud sync, a starter template pack.

**Out (v1.x):** custom URL sources, interactive widgets, Live Activities, watchOS,
AI generation, community gallery backend (share via files/links first).

Rationale: v1 must nail the editor and honest data freshness — the two things that
determine reviews. Everything else layers on the same document model.

### Milestones
1. **M1 — Core model:** `FacetCore` document schema + expression engine + tests.
2. **M2 — Renderer:** `FacetRender` pure renderer + snapshot tests; widget extension
   rendering a hardcoded document.
3. **M3 — Editor alpha:** canvas with text/shape/symbol layers, inspector, undo.
4. **M4 — Data:** built-in sources, App Group cache, refresh scheduling, bindings UI.
5. **M5 — Polish:** renditions, templates, iCloud, onboarding → TestFlight.

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| iOS widget refresh limits → "my widget is stale" reviews | Cadence classes, visible freshness expectations, aggressive snapshot caching (4.3) |
| Widget extension memory ceiling | Pure-renderer extension, pre-resolved documents, downsampled assets |
| Canvas editor is genuinely hard to build well | It's the moat; M3 is the longest milestone, prototype early, cut layer types before cutting interaction quality |
| App Store review (user-provided URLs) | Custom sources are v1.x; ship with curated sources first |
| Widgy loyalty / template lock-in | Widgy JSON importer (best-effort converter) as a growth feature, post-MVP |

## 9. Open questions

- Final name + branding.
- Android/interop ambitions (out of scope for now, but document format is portable).
- Whether AI generation runs day-one server-side or waits for on-device viability.
- Pricing specifics (subscription price point, lifetime tier).
