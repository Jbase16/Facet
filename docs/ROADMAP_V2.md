# Facet — the Scene thesis

Rewritten 2026-07-22, replacing a first draft that was a Widgy parity
checklist wearing a "2.0" label. The correction came from two places: a
capability audit of Widgy 26.1.1 (which already ships photos, a community
gallery with search, iCloud backup, watch support, now-playing, and
Control Center widgets), and a target design that made the real gap
obvious.

## What the target design revealed

The reference is a molten-volcano home screen: an organic blob-framed hero
widget with clock, date, quote, weather and a five-chip status row; themed
app icons flanking a mountain-path wallpaper; a matching dock.

The insight is that **every element knows about every other element.** The
widget's dark fill *is* the wallpaper's sky. The orange path winding
through the mountains rhymes with the orange glow inside the widget. The
icons speak the same visual language. It is one composition.

Widgy cannot express that, and not because of a missing feature: Widgy is
architecturally a widget editor. You build a widget in a vacuum and hope
it sits well on your wallpaper. **Every app in this category works that
way.** That is the gap.

## The thesis

**Facet designs Scenes, not widgets.**

A Scene is one portable document holding the wallpaper, the widgets placed
where they will actually live, the launcher tiles, and one shared token
palette. You edit against the real backdrop. Sharing a Scene reproduces an
entire home screen from a single file — which is what people actually
trade, not lone widgets.

It also makes the AI story something Widgy structurally cannot answer: one
prompt produces a coherent wallpaper, matching widgets, and a matching
icon set, because they are all views of the same token set.

## Shipped toward it

- **Path shapes** — `ShapeKind.path` with an SVG-subset parser resolved
  once in `DocumentResolver`, drawn by both the SwiftUI and SVG backends.
  Organic silhouettes are now expressible.
- **Blob generator** — procedural, deterministic, seed-driven; the editor
  exposes sliders instead of asking anyone to author Béziers on a phone.
- **Launcher tiles** — themed app tiles composed from ordinary layers
  (container + glyph + label + `tapAction`), so they inherit theming,
  shapes, glow, and per-rendition overrides for free. See "Why not
  Web Clips" below.
- **User images** — content-addressed, downsampled into the App Group so
  the extension stays inside its ~30 MB budget; assets travel with the
  document.
- **Layer interactivity** — `tapAction` deep links and `visibleWhen`
  expression gating, through the whole pipeline.
- **On-device AI generation** — plain-language prompt to editable layers.
- **Data breadth** — battery, weather (now unit-aware), health, calendar,
  reminders, astronomy, focus, and arbitrary user JSON APIs.

## Why not Web Clips for icons

A configuration-profile approach (base64 icons in a `.mobileconfig`,
served over local loopback) installs a whole icon set in one confirmation
and removes it in one action. It is genuinely clever, and it is the wrong
default:

- **App Review risk is severe.** Consumer theming is far outside the
  intended use of profile installation, and an embedded HTTP server
  compounds it.
- **Fidelity is out of our hands.** iOS renders Web Clip icons with its
  own masking. The whole point of a Scene is that the tile matches the
  design exactly.
- **Guideline 4.1c** — shipping other developers' brand names and icons is
  its own legal exposure, independent of delivery mechanism.
- **Web Clip + custom URL scheme is unverified** and may silently fail.

Launcher tiles avoid all four: we render them, so they are pixel-exact;
they are ordinary widget layers, so there is no platform risk; and there
is no install step at all. The trade is that they live inside a widget's
grid area rather than replacing springboard icons.

If real springboard icons are wanted later, the defensible version is a
`.mobileconfig` **exported through the share sheet** as a document — not
an in-app installer with a loopback server — shipped as an explicitly
experimental feature.

## Next

1. **Wallpaper-aware canvas** — import the wallpaper, position widgets in
   their real slots, sample colors from behind them. The enabling feature
   for everything above.
2. **Scene document** — wallpaper + widget set + launcher set + palette in
   one file, with export/import and an apply checklist.
3. **Widget slots** — `AppIntentConfiguration` so several Facet widgets
   run at once, each bound to a different document.
4. **Scene AI** — one prompt, whole coherent set; restyle-in-place;
   natural-language edits as undoable mutations.
5. **Motion** — timeline-entry choreography inside the real refresh budget.
6. **Widgy importer** — the migration wedge against their gallery moat.

## Known platform limits (documented honestly)

- **Focus mode names are unavailable.** `INFocusStatus` exposes exactly
  one property, `isFocused: Bool?`. There is no API for "Deep Work" — a
  widget can show On/Off, or the user types their own label. Sharing must
  also be enabled per Focus in Settings, or the value reads nil forever.
- **Springboard icons cannot be replaced programmatically.** See above.
- **Wallpaper cannot be set programmatically** — a Scene export ends in a
  user-performed apply step.

## Standing gates

Buildable after every pass. Template gate green in every rendition ×
scheme. Package tests pass on Linux. Every capability reachable from the
UI — no dead code. Push to main after each pass.
