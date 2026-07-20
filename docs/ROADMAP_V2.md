# Facet — Widgy 2.0 Roadmap

Written 2026-07-20, after the capability audit that found the app functionally
far behind Widgy despite a solid architecture. This roadmap is ordered by
"capability per week", and every pass ends with a push to main.

## Where we honestly stand

**Have:** 8 layer kinds (text/symbol/shape/image/gauge/line/chart/container),
expression engine (arithmetic, comparisons, ternary conditionals, 31
functions, `{template}` spans), canvas editor (drag/snap/resize/undo,
per-rendition overrides), 6 live data sources + custom URL sources, theme
tokens, 12 templates, .facet import/export, layer interactivity
(tapAction deep links + visibleWhen conditions), on-device AI generation
(iOS 26 Foundation Models).

**Missing vs Widgy:** user photos/images, music/now-playing, stocks, RSS,
network/storage/device stats, countdowns as first-class, per-layer blend
modes/masks, animations-between-entries, timeline sequences, Widgy JSON
import, community gallery, iCloud sync, watch faces, StandBy layouts,
tap-to-configure per-widget-instance, multiple simultaneous widget slots.

## Pass 1 — Photos & assets (the #1 aesthetic gap)
Image layers that load user photos: PhotosPicker in the editor, assets
copied into the App Group (downsampled, budget-aware), per-document asset
bundle that travels inside .facet export (base64 chunk), asset-aware
ImageAssetProvider on both app and extension sides. Adds photo frames,
masked shapes (circle/rounded/capsule), and opacity/blend of images.

## Pass 2 — Widget slots & instance configuration
Today one document is "the widget". Ship N configurable slots
(AppIntentConfiguration with a document picker parameter), so users run
many Facet widgets at once — table stakes vs Widgy. Includes per-slot
rendition preview in the gallery ("Small · Medium · Lock").

## Pass 3 — Data breadth
- Now Playing (MPNowPlayingInfoCenter via app refresh; artwork to cache)
- Device stats source: storage free/used, uptime, thermal state
- Countdown source: user-defined target dates (UI in Data Sources)
- Stocks/crypto via the custom-URL rails with curated presets
  (no keys server-side; user pastes their endpoint)
- RSS/JSON headlines preset on the same rails

## Pass 4 — Sequences & motion
Timeline choreography inside the widget budget: a `sequence` container
whose children rotate across timeline entries (minute/hour cadence),
plus entry-relative time text (Widgy's "animated" clocks are this).
Transitions rendered as WidgetKit timeline entries, honestly documented.

## Pass 5 — Widgy importer
Best-effort `.widgy` JSON converter mapping their layer/formula model
onto FacetCore (text, images, shapes, progress, battery/weather/health
bindings, common formulas → expression rewrites). Import report listing
what converted cleanly and what needs touch-up. Growth feature: bring
your library with you.

## Pass 6 — Gallery & sync
- iCloud Drive document sync (documents are already portable JSON)
- Shared gallery v0: publish/import via .facet files + a curated feed
  (static JSON index to start — no backend commitment yet)
- Template remixing flow ("Duplicate & edit" from any imported design)

## Pass 7 — AI deepening (the moat Widgy can't copy quickly)
- "Restyle this widget" (keep layers, regenerate theme)
- Image-to-widget: screenshot/inspiration photo → layout draft
  (Foundation Models multimodal when available)
- Natural-language edits in the inspector: "make the ring thicker and
  orange" → targeted mutations, undoable

## Standing quality gates
Buildable after every pass; template gate green in every rendition ×
scheme; package tests on Linux stay green; every new capability reachable
from the UI (no more dead code); push to main after each pass.
