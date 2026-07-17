# PaedPlot — Opus Handoff Briefing

> **⚠️ Historical document** — describes the v1.x architecture and is kept for reference. For the current (v2.x) architecture see `../../CLAUDE.md`.

**Current version: v1.8 (paedplot_v1.8.html)**
**Current working file: paedplot.html (~196KB)**
**Date: April 2026**

---

## How to use this briefing

You are being handed a working clinical tool mid-development. Three documents accompany this prompt:
1. **paedplot_opus_briefing.md** (this file) — settled design decisions and current issues
2. **paedplot_explainer.md** — full technical background, reference data, LMS method, architecture
3. **paedplot.html** — the complete single-file application
4. **CODEBASE_REFERENCE.md** — line-number map of the JS for efficient lookup (save tokens by reading this first; only read the HTML file when you need specific code)

Read this briefing and the codebase reference before responding to any task. Do not re-derive decisions already recorded here as settled. Do not alter any lookup table without explicitly flagging it and explaining why.

---

## What PaedPlot is

A fully offline, single-file HTML application for plotting UK-WHO paediatric growth charts. Used by a UK Paediatric SpR (Nick) on locked-down NHS computers and personal phone. No internet required. No patient data transmitted. Distributed as a single `.html` file opened in Edge or any modern browser.

The tool plots height-for-age and weight-for-age on stacked HTML5 Canvas panels that visually replicate the RCPCH paper growth charts. It calculates SDS (z-score) and centile for each measurement using the LMS method with embedded UK-WHO reference data.

---

## Architecture summary

- **Single HTML file**: HTML + CSS + JS + LMS JSON all embedded
- **Two canvas panels**: height (top) + weight (bottom), unified border, shared x-axis
- **Five range toggles**: 0–1y, 1–4y, 2–9y, 9–18y, 2–18y
- **Full / Zoom toggle**: Zoom shows a range-specific time window with horizontal drag-to-pan
- **Grid-square geometry** (v1.5): every square on the chart is a true pixel-square; what a square represents is fixed per range and matches the RCPCH paper chart. Panels have independent vertical rules but share the x-axis.
- **Session persistence**: full form state saved to localStorage, restored on refresh
- **Preterm toggle**: on 0–1y view only, extends chart left to -0.33y (23 wk gestation)

---

## SETTLED DESIGN DECISIONS — do not change without explicit instruction

### 1. Grid-square geometry (GRID lookup) — replaces old SCALE table

Each panel grid square is a true pixel-square of side `pxPerSquare`. What one square represents in age and measurement is fixed per range and matches the RCPCH paper chart grid.

```javascript
const GRID = {
  '0-1':  { xYears: 2/52,  htCm: 1, wtKg: 0.5 },  // 2-week × 1cm × 0.5kg squares
  '1-4':  { xYears: 1/12,  htCm: 1, wtKg: 0.5 },  // 1-month × 1cm × 0.5kg squares
  '2-9':  { xYears: 0.5,   htCm: 5, wtKg: 2   },  // 6-month × 5cm × 2kg — taller weight panel (v1.5.1)
  '9-18': { xYears: 0.5,   htCm: 5, wtKg: 5   },
  '2-18': { xYears: 0.5,   htCm: 5, wtKg: 5   },
};
const MIN_PX_PER_SQUARE = 12;
const MAX_PX_PER_SQUARE = 32;
```

**Rendering model:**
- `xSquaresInView = ageRange / GRID[range].xYears`
- `pxPerSquare = clamp(availablePlotW / xSquaresInView, MIN, MAX)`
- Plot width = `pxPerSquare × xSquaresInView` (shared by both panels)
- Height panel plot height = `pxPerSquare × htValueRange / htCm`
- Weight panel plot height = `pxPerSquare × wtValueRange / wtKg`

**Panels share x-axis only.** Vertical sizing is independent per panel — there is no coupling between height and weight panel heights beyond both using the same `pxPerSquare`. The old constraint that both panels share a single `pxPerYear` was removed in v1.5.

**On narrow phones** `pxPerSquare` bottoms out at MIN=12 and the chart may exceed container width (1–4y most affected: ~530px chart in a 400px container). This is handled by `.charts-stack { overflow-x: auto }` — chart scrolls horizontally inside its container.

**On wide desktops** `pxPerSquare` tops out at MAX=32. The chart stops growing and whitespace fills the remainder of the container.

### 2. Y-axis snap

`computeYRange(centileData, measurements, ageMin, ageMax, isTopPanel, gridUnit)` snaps `valMin` down and `valMax` up to multiples of `gridUnit` (passed by caller: `htCm` for height panel, `wtKg` for weight panel). Panel edges always fall on a gridline — no half-squares at top or bottom. Weight axis floored at 0 (never below).

If `gridUnit` is omitted the function falls back to legacy snap-candidate behaviour ([0.5, 1, 2, 5, 10] with <5% overshoot). Current code always passes it.

### 3. Zoom windows (ZOOM_WINDOWS lookup)

```javascript
const ZOOM_WINDOWS = {
  '0-1':  4/12,   // 4 months
  '1-4':  1.0,    // 12 months
  '2-9':  2.0,    // 2 years
  '9-18': 3.0,    // 3 years
  '2-18': 4.0,    // 4 years
};
```

`applyZoomWindow()` sets `chartState.zoomWindow` from this table. Called in `setZoomMode`, `setChartRange`, `plotCharts` auto-select, and on state restore. In zoom mode, `xSquaresInView` shrinks and `pxPerSquare` recomputes — squares grow to fill the available width, so zoom genuinely increases resolution and panels grow vertically in lockstep.

### 4. Y-axis tick candidates (Y_TICK_CANDIDATES lookup)

Defined inline inside `drawSingleChart`. Kept deliberately separate from the grid-square geometry — expresses clinical label density preference (how often to label the y-axis) which does not derive cleanly from the grid definition alone.

```javascript
const Y_TICK_CANDIDATES = {
  '0-1':  { height: [2, 5],       weight: [1, 2]      },
  '1-4':  { height: [2, 5],       weight: [1, 2, 5]   },
  '2-9':  { height: [5, 10],      weight: [5, 10]      },
  '9-18': { height: [5, 10, 20],  weight: [5, 10, 20]  },
  '2-18': { height: [10, 20, 50], weight: [10, 20, 50] },
};
```

`pickStep` uses max 14 ticks (not 8) to allow 1kg steps on 0–1y weight.

### 5. Range limits

```javascript
'0-1':  ageMin = showPreterm ? -0.33 : 0.0,  ageMax = 1.0
'1-4':  ageMin = 1.0,  ageMax = 4.0
'2-9':  ageMin = 2.0,  ageMax = 9.0
'9-18': ageMin = 9.0,  ageMax = 18.0
'2-18': ageMin = 2.0,  ageMax = 18.0
```

### 6. Axis gridlines and pips (v1.5.5 model)

Three independent tiers on each axis. "Pip" = tick mark + label on axis edge. Each position on an axis is exactly one of:

| Tier | Gridline through plot? | Tick on axis? | Label? | Visual weight |
|---|---|---|---|---|
| `minorGrid` | yes (light) | no | no | `rgba(180,175,165,0.45)`, lineWidth 0.5 |
| `majorGrid` | yes (darker) | yes | yes | `rgba(160,155,145,0.65)`, lineWidth 0.7 |
| `pipOnly` | **no** | yes | yes | tick only |

Layer order: minorGrid (back) → majorGrid (middle) → pipOnly (axis-strip only). Defined per-range by `getGridSpec(range, zoomMode)` for x-axis and by the `Y_GRID_SPEC` lookup table for y-axis (major step also drives y-range snap — see Y-axis snap section below).

**X-axis spec per range:**

| Range | minorGrid | majorGrid | pipOnly | Notes |
|---|---|---|---|---|
| 0–1y | — | every 2 weeks; labels follow clinical vernacular — preterm side in weeks-of-gestation (24, 26, 28, 30, 32, 34, 36), early postnatal in weeks-of-age (2, 4, 6, 8, 10); "Birth" pivot at 40w gestation; positions at 38w, 12w and 14w+ have gridlines but no labels (monthly labels take over from 3m onward) | Birth + monthly labels from 3m: 3m, 4m, 5m, 6m, 7m, 8m, 9m, 10m, 11m, 1y (positions don't align with 2-weekly grid — axis strip only, no gridline) | Single-row label strip; bottom margin 42 px (same as other ranges) |
| 1–4y | every 1 month | every 6 months (1y, 1½y, 2y, 2½y, 3y, 3½y, 4y) | — | |
| 2–9y | every 2 months | every 6 months (2y, 2½y, 3y, …) | — | |
| 9–18y | every 2 months | every 1 year (9y, 10y, …, 18y) | — | |
| 2–18y | every 2 months | every 1 year (2y, 3y, …, 18y) | — | |

**Y-axis spec per range (cm for height, kg for weight):**

| Range | Height minor | Height major | Weight minor | Weight major |
|---|---|---|---|---|
| 0–1y | — | 2 cm | — | 0.5 kg |
| 1–4y | 1 cm | 4 cm | — | 1 kg |
| 2–9y | 1 cm | 5 cm | 1 kg | 5 kg |
| 9–18y | 1 cm | 5 cm | 1 kg | 5 kg |
| 2–18y | 1 cm | 5 cm | 1 kg | 5 kg |

Defined in `Y_GRID_SPEC` at module scope. `null` minor = no minor tier on that axis.

**Y-axis snap:** `computeYRange` snaps valMin/valMax to multiples of the major-gridline step (via `getYSnapUnit(range, method)`). Panel edges therefore always coincide with a major gridline. This is deliberately decoupled from the `GRID` table (which is the panel-sizing geometry used in `pxPerSquare × valueRange / gridUnit`).

**Half-year label helper:** `halfYearLabel(age)` returns `Ny` or `N½y` (Unicode ½). Used where majors are at 6-month intervals.

**0–1y two-row x-axis strip:** bottom panel margin bumped from 42 → 54 px specifically for 0–1y to fit the two-row label strip. Via `getBottomPanelMargins(range)` helper. Week labels sit 6 px below axis, month labels 18 px below. PipOnly ticks descend from weekRowY down to anchor the month label.

### 7. Centile lines

9 lines per panel: 0.4th, 2nd, 9th, 25th, 50th, 75th, 91st, 98th, 99.6th
Dashed: 0.4th, 9th, 50th, 91st, 99.6th
Solid: 2nd, 25th, 75th, 98th
Colour: `#AAAAAA`, lineWidth 0.85
Drawn as **4 separate segments** (one per dataset) — never joined across 2y or 4y boundaries

### 8. Four LMS datasets

| Dataset | Age range (raw data) | Used for | Notes |
|---------|-----------|----------|-------|
| uk90_preterm | -0.33y to 0.038y | Preterm section | UK 1990, Cole |
| who_infant | 0.0y to 2.0y | 0–2y | Lying length |
| who_child | 2.0y to 5.0y | 2–4y (see below) | Standing height |
| uk90_child | 4.0y to 20.0y | 4y+ | UK 1990, Freeman |

**Boundary conventions:**
- **2.0y**: lying→standing transition; both datasets have one point at 2.0, drawn as separate segments (no overlap).
- **4.0y**: WHO→UK90 transition. The raw `who_child` data extends to 5.0y, giving a 1y zone of overlap with `uk90_child`. `selectDataset` uses UK90 from 4.0y onwards for point calculation (UK-WHO convention). For centile-line drawing, `generateCentileLines` truncates `who_child` at ≤ 4.0y (v1.5.2) so the two segments meet exactly at 4y, producing the characteristic sharp step seen on RCPCH paper charts rather than a zone of duplicate lines.

Interpolation: cubic Lagrange (≥2 points each side), else linear. Never across boundaries.

### 9. Panel layout

- Height panel: `MARGINS_TOP_PANEL = { top:20, right:52, bottom:4, left:46 }`
- Weight panel: `MARGINS_BOTTOM_PANEL = { top:4, right:52, bottom:42, left:46 }`
- Both panels share identical `cw` (canvas width) — `T.x()` maps linearly from age to px across the shared plot width
- No minimum panel height — panel height derives from value range ÷ grid unit × pxPerSquare. `MIN_PANEL_PX` was removed in v1.5.

### 10. Preterm toggle

- Default: hidden. Appears only on 0–1y range.
- When active: `getRangeLimits` uses `ageMin = -0.33` instead of `0.0`
- Resets to false when leaving 0–1y range
- Saved/restored in localStorage as `showPreterm`

### 11. Gestational correction (v1.5.4)

Preterm is defined as `gestWeeks < 37` — the standard UK/RCPCH clinical definition. This threshold is applied consistently at four sites: `calcCorrectedAge` (gates whether correction is applied to SDS), `drawSingleChart` (gates whether × at corrected age is drawn), `updateLegend` (gates preterm legend text), and `renderResults` (gates "corrected" age text in result cards). Babies at 37+0 or later receive no gestational correction — SDS is calculated using chronological age, measurements plot only at chronological age on the chart, and no "corrected" text appears in results.

Correction formula (when applied): `correction = (40 − gestWeeks − gestDays/7) / 52.18` years, subtracted from decimal age. Applied throughout the lifespan (not just to 12–24 months as paper charts do).

### 12. Touch/scroll behaviour

- `touch-action: pan-y` on `.charts-stack` — vertical scroll always goes to browser
- `overflow-x: auto` on `.charts-stack` — chart scrolls horizontally inside container if it exceeds container width (new in v1.5)
- Horizontal drag pan (via JS) only active in zoom mode
- Direction detection: gesture commits to horizontal or vertical after 4px movement
- `touchmove` is passive — no `preventDefault` anywhere

---

## Key functions to know

| Function | Purpose |
|----------|---------|
| `renderBothCharts()` | Main render entry point. Computes pxPerSquare, calls drawSingleChart twice |
| `drawSingleChart(canvasId, method, color, title, cw, ch, isTopPanel)` | Draws one panel. No changes in v1.5 — linear mapping via makeTransform works identically with pre-sized ch |
| `computeYRange(centileData, measurements, ageMin, ageMax, isTopPanel, gridUnit)` | Returns {valMin, valMax} snapped to gridUnit |
| `getGridUnit(range, method)` | Helper — returns htCm or wtKg from GRID for given range |
| `getGridSpec(range, zoomMode)` | Returns {major, minor, monthMarks} for x-axis |
| `getVisibleWindow()` | Returns {ageMin, ageMax} for current full/zoom state |
| `getRangeLimits()` | Returns full chart limits for current range |
| `applyZoomWindow()` | Sets chartState.zoomWindow from ZOOM_WINDOWS lookup |
| `generateCentileLines(sex, method)` | Pre-computes centile line coords (data space, not pixel) cached in chartState |
| `calculateMeasurement(...)` | Core LMS calculation → SDS, centile, centile band text |
| `saveState()` / `loadState()` | localStorage persistence |
| `newPatient()` | Full reset of form, chartState, canvases, localStorage |

---

## Known remaining issues (priority order)

1. **X-axis label collisions** — on smaller screens some axis labels overlap, particularly in 1–4y full mode where all months are labelled. Needs a minimum pixel gap check before drawing labels. v1.5 did not address this.

2. **Y-axis label cut-off** — on some views the bottom y-axis label is clipped by the canvas edge. The bottom margin may need a small increase. v1.5 did not address this (though grid-snap may have incidentally reduced its frequency).

3. **SDS verification** — ✅ **RESOLVED April 2026.** Validated against live RCPCH API using 12-case targeted suite (24 measurements spanning every dataset, every boundary, gestational correction, and extreme centiles). All SDS values agreed within ±0.001 SDS — two orders of magnitude tighter than the ±0.05 target. The embedded LMS data is faithful to the RCPCH reference. The calculation pipeline (interpolation, dataset selection, correction, SDS formula) is correct. See validation script `validate_paedplot.sh`.

4. **OFC (head circumference)** — LMS data is embedded but no OFC panel exists. Low priority.

5. **Print layout** — `@media print` CSS is basic. A4 landscape output not optimised. Worth re-checking after v1.5 now that overflow-x behaviour has changed.

6. **Horizontal scroll on narrow phones** (v1.5 introduced) — 1–4y full mode on a ~400px phone produces a chart ~530px wide which scrolls horizontally inside the chart container. Acceptable trade for correct vertical proportions but worth on-device testing. Could be revisited by lowering MIN_PX_PER_SQUARE if it feels awkward.

7. **Panel heights on wide desktop** — at MAX=32 some panels become very tall (e.g. 0–1y at ~1200px, 1–4y at ~1400px on a 1200px container). If this feels excessive we could add a range-specific max on panel height. Skipped in v1.5.

---

## Working conventions

- **Propose before implementing** any non-trivial change
- **One change at a time** — apply, verify with Python checks, ship
- **Never interpolate across dataset boundaries** (2y and 4y)
- **Never join plotted measurement dots with lines**
- **Never emphasise the 50th centile line** (same weight as others)
- **No external dependencies** — everything offline, no CDN
- **No patient-identifiable data stored or transmitted**
- Test cases in the Dev modal should pass before claiming SDS accuracy
- Keep `CODEBASE_REFERENCE.md` updated as edits are made

---

## File structure

```
paedplot.html (~184KB)
├── <style>          CSS (sidebar, chart controls, panels, print)
├── <body>           Two-column layout: sidebar + chart area
│   ├── Sidebar      Sex, DOB, gestation, measurement rows, buttons
│   └── Chart area   Controls row, unified chart container, results panel
├── <script id="lms-data" type="application/json">
│   └── ~105KB minified LMS JSON (4 datasets × 2 sexes × 3 measures)
└── <script>
    ├── LMS_DATA parse
    ├── normalCDF (Abramowitz & Stegun)
    ├── Calculation engine (calcDecimalAge → calculateMeasurement)
    ├── GRID, MIN/MAX_PX_PER_SQUARE, getGridUnit  (v1.5)
    ├── Margins, getCanvasWidth, makeTransform
    ├── getRangeLimits, ZOOM_WINDOWS, applyZoomWindow, getVisibleWindow
    ├── computeYRange (with gridUnit snap)
    ├── Chart rendering (renderBothCharts → drawSingleChart)
    ├── Grid spec (getGridSpec → ageLabel)
    ├── Pan handlers (setupPanHandlers — direction-aware touch)
    ├── Tooltip (setupTooltip)
    ├── Ghost values (updateGhostValues)
    ├── localStorage (saveState, loadState, clearState)
    ├── Measurement rows (addMeasurementRow, removeRow, getMeasurements)
    ├── plotCharts, renderResults, updateLegend
    ├── togglePreterm, setChartRange, setZoomMode, recenterPan
    ├── Dev modal (TEST_CASES, runTests)
    └── INIT (loadState → applyZoomWindow → auto-plot if data present)
```

---

## How to continue development

Start your Opus conversation with:

```
I am attaching four files:
1. paedplot.html — a working offline HTML growth chart tool (v1.5)
2. paedplot_explainer.md — full technical documentation
3. paedplot_opus_briefing.md — handoff briefing with settled decisions
4. CODEBASE_REFERENCE.md — line-number map for efficient code lookup

Please read the briefing and reference doc first. The HTML file is large;
only read specific line ranges from it when you need to see actual code.
Do not alter GRID, ZOOM_WINDOWS, or Y_TICK_CANDIDATES tables without
flagging it explicitly.

[Attach all four files]

First task: [describe what you want]
```

---

## Version history

| Version | Key changes |
|---------|-------------|
| v1.0 | LMS engine, Canvas chart rendering, 9 centile lines, gestational correction, tooltips, Dev modal |
| v1.1 | Unified stacked chart, range toggles 0–4y/2–18y, zoom with touch pan, dynamic y-axis, ghost 50th centile placeholders |
| v1.2 | 4 range toggles, aspect ratio sizing (1yr=10cm=10kg), CSS touch-action:pan-y, direction-aware pan |
| v1.3 | 5 range toggles (0–1y, 1–4y, 2–9y, 9–18y, 2–18y), pxPerYear cap, weight axis floor at 0, y-axis filtered to visible window |
| v1.4 | Grid lines per range spec, x-axis labels per range, range-specific zoom windows, 0–1y weight aspect ratio (1kg=4wks) |
| v1.4+ | SCALE lookup table for all ranges (paper chart ratios), Y_TICK_CANDIDATES per range, preterm toggle, zoom bug fixes |
| **v1.5** | **Grid-square geometry: GRID table + pxPerSquare (12–32) replaces SCALE/pxPerYear/MIN_PANEL_PX. Panels decoupled vertically, share x-axis only. Fixes vertical squashing on 0–1y and 1–4y mobile views. Corrects latent 1–4y `wt:12` bug (paper chart is 0.5kg/square). 2–9y/9–18y render identically to v1.4+. `.charts-stack` CSS now `overflow-x: auto` for narrow-phone scenarios.** |
| **v1.5.1** | **2–9y weight grid square halved from 5kg to 2kg — panel 2.5× taller with integer gridline labels (2, 4, 6, 8… kg). Departs from paper-chart fidelity on this range deliberately, for on-screen readability.** |
| **v1.5.2** | **Fixed WHO↔UK90 4y boundary overlap. Raw `who_child` data extends to 5.0y, which caused 1y of duplicate centile lines where both datasets were drawn. `generateCentileLines` now truncates `who_child` at ≤ 4.0y, producing the paper-chart sharp step at the 4y boundary (height step ≈ −0.8cm, weight step ≈ +0.2kg at 50th centile). Point calculation (`lookupLMS`/`selectDataset`) unchanged — uses full LMS_DATA, switches at 4.0y per UK-WHO convention.** |
| **v1.5.3** | **Two pre-existing bugs fixed: (a) `togglePreterm` referenced an undefined `range` identifier on two lines (copy-paste residue from `setChartRange`), causing the preterm toggle to immediately reset `showPreterm` back to false on every click — the button never actually turned preterm on. (b) `setupTooltip` attached listeners to the canvas (3) and document (1) on every call, but `renderBothCharts()` calls it twice per render (directly and via `setupPanHandlers`), and renders fire on every touchmove during a zoom-pan. Over a session this produced hundreds of duplicate handlers, making any mouse/touch event trigger them all. Added `canvas._tooltipListenersAttached` guard and module-level `window._tooltipDocListenerAttached` guard. Closures over `canvas._hitAreas` still pick up fresh values across re-renders — behaviour unchanged, just no longer stacking.** |
| **v1.5.4** | **Three further pre-existing bugs fixed after code audit. (1) `newPatient()` set `chartState.range = "0-4"` — not a valid range string. All downstream GRID/getRangeLimits/getGridSpec lookups silently fell back to '2-18' default, so after "New Patient" the chart geometry disagreed with the activated `btn01` button. Corrected to `"0-1"`. (2) "Is preterm" threshold was inconsistent across FOUR sites: `calcCorrectedAge` guarded on `>=40 && days==0` (applying backwards correction to post-term babies), `drawSingleChart` used `<37`, `updateLegend` used `<37`, `renderResults` used `<40 \|\| days>0` (marking 40+1 as preterm). Unified on `<37` (standard UK/RCPCH definition) across all sites. Babies 37+0 through 39+6 are no longer corrected — this matches UK clinical convention and aligns with the RCPCH Digital Growth Charts API. SDS for early-term babies will change slightly. (3) `plotCharts` auto-range selection had an unreachable branch that sent data spanning 0–1y and 1–4y to the '0-1' range (truncating older measurements from view); now falls through to '2-18' in that case.** |
| **v1.5.4 API VALIDATION (April 2026)** | **Validated against live RCPCH Digital Growth Charts API (api.rcpch.ac.uk/growth/v1/uk-who/calculation) using a 12-case targeted suite covering every dataset (uk90_preterm, who_infant, who_child, uk90_child), every boundary (2y lying→standing, 4y WHO→UK90), gestational correction (30+0, 36+0, 28+0 preterm cases), and extreme centiles (SDS −2.9 low, +2.3 high). All 24 SDS measurements agreed with the RCPCH API to better than ±0.001 SDS — two orders of magnitude tighter than the ±0.05 pass criterion. This closes the "SDS verification not yet done" item that has been open since v1.0. Script: `validate_paedplot.sh`.** |
| **v1.5.5** | **Restructured axis gridline and pip model. Previously `getGridSpec` returned `{major, minor, monthMarks}` conflating gridline-through-plot with axis-tick-with-label. New model has three independent tiers per axis: `minorGrid` (gridline only, no pip), `majorGrid` (gridline + pip), `pipOnly` (pip on axis, no gridline). New `Y_GRID_SPEC` lookup at module scope defines minor/major for each range × method. New helpers: `halfYearLabel` for 1½y-style labels, `getYSnapUnit` for y-range snap (decoupled from panel-sizing geometry, uses major-gridline step). 0–1y bottom panel margin bumped to 54 px (from 42) to fit a two-row x-axis label strip: weekly labels on top row, monthly labels below. X-axis zoom-dependent minor-label behaviour on 1–4y removed (no longer needed with cleaner model). Visual spec per range: 0–1y (2w gridlines/labels + monthly pips), 1–4y (monthly minor, 6-month major), 2–9y/9–18y/2–18y (2-month minor, 6-month or 1-year major). Weight/height y-axis granularity varies per range, detailed in briefing table.** |
| **v1.6** | **0–1y axis labels redesigned to follow clinical vernacular. Preterm side now labels in weeks-of-gestation (24, 26, 28, 30, 32, 34, 36) rather than weeks-pre-term. Postnatal side shows early weeks-of-age (2, 4, 6, 8, 10) then switches to months from 3m onward (3m, 4m, ..., 11m, 1y). Single-row label strip replaces the two-row weeks/months strip from v1.5.5 — bottom margin reverted to standard 42 px. Labels at −2w (38w gestation) and +12w are suppressed to avoid crowding around the "Birth" and "3m" transition points respectively; gridlines remain at those positions for plotting fidelity. Full visible sequence: "24, 26, 28, 30, 32, 34, 36, Birth, 2, 4, 6, 8, 10, 3m, 4m, 5m, 6m, 7m, 8m, 9m, 10m, 11m, 1y" — matches UK-WHO paper chart convention and how paediatricians/health visitors speak about infants. Calculation engine and all other ranges unchanged from v1.5.5.** |
| **v1.7** | **Pure cosmetic redesign to match RCPCH paper-chart aesthetic. Zero maths/logic changes. (1) Canvas: gridlines now fine dotted light-grey (`#D3D3D3`/`#BFBFBF` with `setLineDash([1,4])` minor, `[1,3]` major) on both x and y axes. (2) Centile lines: sex-specific accent colour replaces monochrome grey — `#68A1C5` muted blue for boys, `#C16B86` muted rose for girls. All 9 lines same colour and weight (1.2px); dash pattern `[4,4]` for 0.4/9/50/91/99.6, solid for 2/25/75/98. 50th NOT emphasised. New helper `getAccentColor(sex)`. (3) Centile labels at right margin match line colour, 10px, ordinal suffix stripped (`50` not `50th`). (4) CSS redesign: system-ui font stack throughout (no more Georgia serif); page background `#F5F5F5`; borders `#E0E0E0`; text `#222`; 2px input/button radii. (5) Sex-theme CSS: `:root --accent` defaults boys; `body.sex-girls` overrides to rose. Applied via `applySexTheme(sex)` helper called on load, on radio change, on state restore, and on render. Accent drives primary buttons, active tabs (now with 3px underline), chart titles, results-panel header, and active range buttons. (6) Chart title: uppercase gender word ("BOYS" / "GIRLS") with bolder weight via `.title-sex` span. (7) Results panel restyled as paper-chart "instructional box": pale yellow `#FFFDF0` background with `#E8DFA8` border. (8) Plotted measurement dots (height navy, weight dark red) kept sex-neutral so they stay distinguishable from centile lines. (9) Header and footer: neutral charcoal `#2C3E50`, independent of sex theme.** |
| **v1.8** | **Preterm view redesigned. (1) New dedicated "Preterm" range button added as a 6th option (before 0–1y). Shows 23w→42w gestation with only `uk90_preterm` centile lines — no `who_infant` data bleed-in. X-axis labelled in gestational weeks (24, 26, 28, 30, 32, 34, 36, 38, Birth, 42) with 1-week minor gridlines and 2-week majors. Tight y-axis granularity matching the preterm scale (weight major every 0.5kg, minor every 0.1kg; height major every 2cm, minor every 1cm). (2) Auto-range now lands on `preterm` when the earliest measurement's corrected age is ≤ 2w post-term (i.e. data in the preterm window). (3) Bug fix on 0–1y view: previously `uk90_preterm` and `who_infant` centile lines both drew in the 0–2w window producing visible duplicate lines. Now `uk90_preterm` is clipped at age ≤ 0 and `who_infant` starts at age ≥ 2w, leaving a paper-chart-style blank 0–2w region. (4) Paper-chart-style birth centile markers: small horizontal ticks at age 0 on the 0–1y view showing each centile's starting value, occupying the 0–2w blank region. (5) Old 0–1y "+ Preterm" toggle retained for users who want the whole preterm-to-1y arc on one chart; on that toggled view `uk90_preterm` draws up to age 0 only (never overlaps `who_infant`). (6) Panel y-range sizing now respects the view's dataset filter (via new `datasetFilter` argument to `computeYRange`), so preterm-view panels size tightly to preterm data.** |
