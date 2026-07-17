# PaedPlot Codebase Reference

> **⚠️ Historical document** — line numbers and structure describe the v1.x build. For the current (v2.x) architecture map see `../../CLAUDE.md`.

**Purpose:** token-efficient lookup for Claude across future edit sessions.
**File:** `paedplot.html` (~184KB, ~2355 lines, single self-contained HTML)
**Current version:** v1.8 (April 2026).
**Previous:** v1.7 (cosmetic paper-chart redesign), v1.6 (0–1y clinical vernacular axis), v1.5.5 (axis gridline/pip restructure), v1.5.4 + API VALIDATION (RCPCH cross-check passed), v1.5.3 (listener/toggle fixes), v1.5.2 (4y boundary fix), v1.5.1 (2-9y weight taller), v1.5 (grid-square geometry migration), v1.4+ (SCALE/pxPerYear aspect-ratio engine).

---

## Version history

- **v1.8** (this file): dedicated preterm range added (6th range button). New `'preterm'` entries in `GRID` (1w × 1cm × 0.1kg squares), `Y_GRID_SPEC` (ht minor 1/major 2, wt minor 0.1/major 0.5), `getRangeLimits` (−17/52.18 to +2/52.18, i.e. 23w→42w gestation), and `getGridSpec` (majors labelled 24, 26, 28, 30, 32, 34, 36, 38, Birth, 42; 1-weekly unlabelled minors). Auto-range in `plotCharts` now picks preterm when earliest measurement corr-age ≤ 2w. Centile-line filtering in `drawSingleChart` — preterm view shows only `uk90_preterm`; 0–1y without toggle hides `uk90_preterm` entirely and clips `who_infant` at ≥2w; 0–1y with toggle shows `uk90_preterm` up to age 0 only. Paper-chart blank region 0–2w on 0–1y view populated with small horizontal birth-centile tick marks at the 9 centile values at age 0. `computeYRange` takes a new `datasetFilter` argument; both callers (drawSingleChart and renderBothCharts) pass a filter matching the view. No calculation changes.
- **v1.7**: pure cosmetic redesign matching RCPCH paper-chart aesthetic. Zero logic/maths changes. Gridlines on canvas now fine dotted light-grey (`#D3D3D3` minor with `setLineDash([1,4])`, `#BFBFBF` major with `[1,3]`). Centile lines render in sex-specific accent colour — `ACCENT_BOYS = #68A1C5` (muted blue), `ACCENT_GIRLS = #C16B86` (muted rose) — via new `getAccentColor(sex)` helper. All 9 lines same colour/weight (1.2px); dash pattern `[4,4]` for 0.4/9/50/91/99.6 and solid for 2/25/75/98. Centile right-edge labels match line colour, 10px, ordinal suffix stripped. CSS palette rebuilt around system-ui font stack with `--accent` variable driven by `body.sex-boys`/`body.sex-girls` classes. New `applySexTheme(sex)` JS helper called on load, on sex-radio change, on state restore, and on every render. Chart title uppercases the gender word with a `.title-sex` span. Results panel restyled as paper-chart "instructional box" (pale yellow `#FFFDF0` with `#E8DFA8` border). Header/footer kept neutral charcoal `#2C3E50`, independent of sex theme. Plotted measurement dot colours (height `#003078`, weight `#8B1A1A`) kept sex-neutral for legibility against centile lines.
- **v1.6**: 0–1y axis labels changed to clinical vernacular. Preterm in weeks-of-gestation (24…36). Early postnatal in weeks-of-age (2…10). Monthly labels from 3m (3m…11m, 1y). Single-row label strip; bottom margin reverted from 54 → 42 px. Gridlines stay at every 2-weekly position; positions at 38w and 12w have gridlines but no labels.
- **v1.5.5**: restructured axis gridlines and pips into three independent tiers. `getGridSpec` now returns `{minorGrid, majorGrid, pipOnly}` instead of `{major, minor, monthMarks}`. New `Y_GRID_SPEC` table at module scope defines minor/major step per range × method. Helpers added: `halfYearLabel`, `weekLabel`, `getYGridSpec`, `getYSnapUnit`, `getBottomPanelMargins`. Y-range snap is now on the major-gridline step (not panel-sizing geometry), so panel edges coincide with major gridlines. 0–1y initially used a two-row label strip (bottom margin 54 px); this was reverted in v1.6. All x-axis and y-axis drawing in `drawSingleChart` rewritten for new model.
- **v1.5.4 validated** (April 2026): calculation engine cross-checked against live RCPCH Digital Growth Charts API using targeted 12-case suite covering all datasets, both boundaries, gestational correction, and centile-band extremes. All 24 SDS measurements agreed to within ±0.001 SDS (target was ±0.05). The embedded UK-WHO LMS reference data is confirmed faithful to the RCPCH reference. Calculation pipeline (interpolation, selectDataset, calcCorrectedAge, sdsFromMeasurement) is confirmed correct. Validation script: `validate_paedplot.sh` (reads `RCPCH_API_KEY` from env, requires curl + jq).
- **v1.5.4** (previous): three pre-existing bugs fixed after code audit. (1) `newPatient` used invalid range literal `"0-4"`; corrected to `"0-1"`. (2) Preterm threshold inconsistent across four sites (`calcCorrectedAge` used `>=40 && days===0`, `renderResults` used `<40 || days>0`, `drawSingleChart` and `updateLegend` used `<37`); unified on `<37` everywhere. Previously post-term babies received spurious backwards correction and early-term babies received inconsistent treatment. (3) `plotCharts` auto-range had a dead branch sending mixed 0–1y/1–4y data to `'0-1'`; now falls through to `'2-18'`.
- **v1.5.3**: fixed two pre-existing bugs. (1) `togglePreterm` referenced an undefined `range` identifier (copy-paste residue from `setChartRange`), causing `showPreterm` to flip back to false immediately on every click — preterm toggle never actually turned preterm on. (2) `setupTooltip` had no listener guard; called twice per render and renders fire on every touchmove during a zoom pan, causing hundreds of duplicate listeners over a session and making mouse/touch events slow. Added `canvas._tooltipListenersAttached` guard and module-level `window._tooltipDocListenerAttached` for the document-level dismiss handler.
- **v1.5.2**: fixed WHO↔UK90 4y boundary overlap. Raw `who_child` data extends to 5.0y, causing 1y of duplicate centile lines where both datasets were drawn. `generateCentileLines` now truncates `who_child` at ≤ 4.0y, producing the paper-chart sharp step at 4y (height ≈ −0.8cm, weight ≈ +0.2kg at 50th). `lookupLMS`/`selectDataset` unchanged — point calculation still uses full data and switches at 4.0y per UK-WHO convention.
- **v1.5.1**: 2–9y weight grid square halved from 5 kg to 2 kg. Panel 2.5× taller with integer gridline labels (2, 4, 6, 8… kg). Departure from paper-chart fidelity on this range is deliberate for on-screen readability. All other ranges unchanged. Single-line edit in `GRID` table.
- **v1.5**: migrated to grid-square geometry. `SCALE`/`pxPerYear`/`MIN_PANEL_PX` replaced by module-scope `GRID` table + `pxPerSquare` clamp (12–32). Panels now size independently on the y-axis. Charts-stack CSS allows horizontal scroll when chart exceeds container. Fixes 0–1y and 1–4y vertical squashing on mobile. Latent bug in old 1–4y `SCALE.wt=12` (implying 1 kg/sq) corrected to true paper-chart 0.5 kg/sq. 2–9y / 9–18y render identically to v1.4+.
- **v1.4+**: SCALE lookup table for all ranges (paper chart ratios), Y_TICK_CANDIDATES per range, preterm toggle, zoom bug fixes.

---

## File anatomy (line numbers — approximate, may drift on edits)

| Lines | Content |
|---|---|
| 1–6 | DOCTYPE, html, head meta |
| 7–523 | `<style>` — all CSS |
| 525–682 | `<body>` — sidebar form + chart container + dev modal |
| 682–684 | `<script id="lms-data" type="application/json">` — **single-line minified LMS JSON, ~105KB** |
| 686–2311 | `<script>` — the full JS application |
| 2311–2320 | end tags |

The LMS JSON line (683) is massive — never `view` without a line range. Everything else is fine to read in chunks.

---

## JS section map (line numbers within the `<script>` block)

### Data / LMS engine (don't touch these)
| Fn | Lines | Purpose |
|---|---|---|
| `LMS_DATA` parse | 692 | One-shot parse of embedded JSON |
| `normalCDF(x)` | 697 | Abramowitz & Stegun 26.2.17 |
| `calcDecimalAge` | 714 | ms → years / 365.25 |
| `calcCorrectedAge` | 720 | Gestational correction. **Preterm = `<37 weeks`** (v1.5.4 unified threshold). If modifying, update threshold consistently at `drawSingleChart` (line ~1234), `updateLegend` (~2056), and `renderResults` (~2069). |
| `selectDataset` | 728 | Age → dataset name |
| `lagrange4` | 736 | Cubic Lagrange interpolator |
| `lookupLMS` | 748 | Get L/M/S at age, cubic if enough points, else linear. **Never crosses 2y or 4y boundaries.** |
| `sdsFromMeasurement` / `measurementFromSDS` | 796 / 804 | LMS method both directions |
| `centileFromSDS` | 812 | Φ(SDS) × 100 |
| `CENTILE_LINES` | 817 | 9 centiles with sds values + labels |
| `CENTILE_DASH` | 828 | Set of dashed labels: 0.4th, 9th, 50th, 91st, 99.6th |
| `centileBandText` | 830 | Produces "on the Nth", "between X and Y centiles" etc |
| `calculateMeasurement` | 847 | Orchestrates: age → dataset → LMS → SDS → centile → band text |
| `generateCentileLines` | 867 | **Cache is `{ds: [{age, vals[9]}, ...]}` — data space, not pixels. No invalidation needed on geometry change.** **v1.5.2:** filters out `who_child` rows with age > 4.0 so centile lines meet at the 4y boundary rather than overlapping. Raw `who_child` data extends to 5.0y but UK-WHO convention uses UK90 from 4y onwards; this filter affects only line drawing, not point calculation. |
| `formatAge` / `formatAgeVerbose` | 886 / 899 | Decimal years → display string |

### Chart state & margins (line 913)
- `chartState` — mutable global: sex, range, showPreterm, zoomMode, panCentre, zoomWindow, htMeasurements, wtMeasurements, gestWeeks, gestDays, htCentileCache, wtCentileCache
- `CHART_MARGINS = { top: 20, right: 52, bottom: 42, left: 46 }` — reference only
- `MARGINS_TOP_PANEL = { top: 20, right: 52, bottom: 4, left: 46 }` — height panel
- `MARGINS_BOTTOM_PANEL = { top: 4, right: 52, bottom: 42, left: 46 }` — weight panel
- Left/right margins identical so panels align on x-axis
- `getCanvasWidth()` — returns `Math.max(300, stack.clientWidth)`; element id = `chartsStack`

### Transform & window (lines 945–995)
- `makeTransform(ageMin, ageMax, valMin, valMax, cw, ch, margins)` — returns `{ x, y, invX, plotW, plotH, m }`. Pure linear mapping.
- `getRangeLimits()` — per-range {ageMin, ageMax}. 0-1 honours `showPreterm` (-0.33 or 0).
- `ZOOM_WINDOWS` (971) — per-range zoom window width in years: 0-1: 4/12, 1-4: 1, 2-9: 2, 9-18: 3, 2-18: 4
- `applyZoomWindow()` — sets `chartState.zoomWindow` from lookup
- `getVisibleWindow()` — returns {ageMin, ageMax} honouring full/zoom + pan centre

### Y-range computation (line 997)
- `computeYRange(centileData, measurements, ageMin, ageMax, isTopPanel)` — tight fit to 0.4th/99.6th centiles across visible age window, expands for plotted measurements in window, outer padding only on non-boundary edge (top pad for height panel, bottom for weight), snaps to nearest of [0.5, 1, 2, 5, 10] where overshoot < 5% of range. **Weight floored at 0 (line 1046).**

### Panel rendering (line 1051)
- `drawSingleChart(canvasId, method, color, title, cw, ch, isTopPanel)` — the big one. Draws:
  - canvas dpr scaling (1065)
  - computes yRange again (cheap recompute — same inputs — line 1076)
  - makeTransform with panel margins (getBottomPanelMargins for bottom)
  - background fill + clip path
  - centile lines — 4 separate segments per dataset
  - 50th centile watermark label
  - panel unit label top-right
  - x-axis grid lines: minorGrid first (lighter), then majorGrid (darker). pipOnly drawn later outside clip (axis strip only)
  - plotted measurements + preterm × / dashed connector
  - axes — y always, x only on bottom panel
  - y-axis: minorGrid (no tick/label) then majorGrid (gridline + tick + label), driven by `Y_GRID_SPEC`
  - y axis "cm"/"kg" label rotated
  - x-axis ticks + labels — bottom panel only, with two-row strip on 0–1y
  - centile labels at right margin
  - sets `canvas._transform`, `_ageMin`, `_ageMax` for pan math

### Helpers (lines 1378–1408)
- `getBestDatasetForAge(age)` — thresholds 0.038, 2.0, 4.0
- `pickStep(vmin, vmax, targetTicks, candidates)` — picks first candidate where `range/c <= targetTicks`
- `ageLabel(age)` — preterm weeks, "Birth", "Nm", "Ny", "NyMm"

### Axis gridlines and pips — v1.5.5 model

Three independent tiers per axis:
- **`minorGrid`** — gridline through plot, no tick, no label
- **`majorGrid`** — gridline + tick + label
- **`pipOnly`** — tick + label, NO gridline (axis-strip only)

Layer order: minor → major → pipOnly (the latter drawn outside the plot clip path so tick + label sit in the margin strip only). Helpers:

- `getGridSpec(range, zoomMode)` — returns `{minorGrid, majorGrid, pipOnly}` for x-axis per range. Each entry is `{age, label?}`.
- `Y_GRID_SPEC` — module-scope lookup: `{range: {height: {minor, major}, weight: {minor, major}}}`. `null` minor = no minor tier.
- `getYGridSpec(range, method)` — returns the `{minor, major}` for the given axis.
- `getYSnapUnit(range, method)` — returns the major-gridline step, used for `computeYRange` snap.
- `halfYearLabel(age)` — `Ny` or `N½y` (Unicode ½). Used on ranges with 6-month majors.
- `weekLabel(weeks)` — terse numeric label for 0–1y weekly axis marks.
- `getBottomPanelMargins(range)` — returns MARGINS_BOTTOM_PANEL with `bottom: 54` on 0–1y (else 42) to fit 0–1y's two-row label strip.

**Per-range x-axis spec:**
- **0–1y** (v1.6): majorGrid at every 2-weekly position (−16w..+52w) with labels on a clinical-vernacular subset — preterm gestational weeks (24, 26, 28, 30, 32, 34, 36), early postnatal weeks (2, 4, 6, 8, 10), and unlabelled gridlines at 38w and 12w and all positions from 14w onward (kept for plotting fidelity). pipOnly provides Birth + monthly labels from 3m (3m, 4m, 5m, 6m, 7m, 8m, 9m, 10m, 11m, 1y). Single-row label strip; bottom margin 42 px.
- **1–4y**: minorGrid every month, majorGrid every 6 months (1y, 1½y, 2y, 2½y, 3y, 3½y, 4y).
- **2–9y**: minorGrid every 2 months, majorGrid every 6 months (2y, 2½y, 3y …).
- **9–18y**: minorGrid every 2 months, majorGrid every 1 year only (no half-year markers).
- **2–18y**: same as 9–18y (minor 2mo, major 1y).

**Per-range y-axis spec (cm / kg):**
| Range | Ht min/maj | Wt min/maj |
|---|---|---|
| 0–1y | — / 2 | — / 0.5 |
| 1–4y | 1 / 4 | — / 1 |
| 2–9y | 1 / 5 | 1 / 5 |
| 9–18y | 1 / 5 | 1 / 5 |
| 2–18y | 1 / 5 | 1 / 5 |

Note: for 2–9y the `GRID.wtKg = 2` geometry (from v1.5.1 panel-sizing) differs from the Y_GRID_SPEC `major = 5`. This is intentional — panel sizing uses GRID, axis drawing uses Y_GRID_SPEC. Snap is now on the major step so panel edges land on 5 kg multiples.

### THE FUNCTION TO REWRITE: `renderBothCharts` (line 1501)
Current logic:
```
cw = getCanvasWidth()
ageRange = ageMax - ageMin
SCALE lookup → {ht, wt} unitsPerYear  (LINES 1527-1534)
MIN_PANEL_PX = 120                    (LINE 1536)
plotW = cw - left - right
pxPerYear = min(plotW/ageRange, 80)   (LINE 1543, THE CAP)
pxPerUnitHt = pxPerYear / scale.ht
pxPerUnitWt = pxPerYear / scale.wt
compute htYRange, wtYRange
htCh = max(MIN, pxPerUnitHt × valueRange + margins)
wtCh = max(MIN, pxPerUnitWt × valueRange + margins)
drawSingleChart(htCanvas...) drawSingleChart(wtCanvas...)
setupPanHandlers + setupTooltip for each
```
**This is where the new GRID-based geometry replaces SCALE/pxPerYear.**

### Controls (lines 1576–1651)
- `togglePreterm`, `setChartRange`, `setZoomMode`, `recenterPan` — all ultimately call `renderBothCharts`

### Pan handlers (line 1653)
- `setupPanHandlers(canvasId)` — uses `canvas._transform.plotW` and `canvas._ageMax/_ageMin`. Safe, no pxPerYear references.
- Direction-aware: 4px threshold, commits to horizontal or vertical, only horizontal pans.
- touchmove passive (no preventDefault anywhere)
- `_panListenersAttached` guard prevents double-attach
- Calls `setupTooltip(canvasId)` unconditionally at end (comment says "Re-setup tooltip on the new node" — vestigial, canvas element is not replaced between renders). After v1.5.3 tooltip guards, this repeated call is a cheap no-op. Could be removed in a future cleanup.

### Tooltip (line 1746)
- Hit testing uses `canvas._hitAreas` which stores pixel coords — populated in drawSingleChart. Rebuilt each render. Safe because the mousemove/touchstart listeners are closures that read `canvas._hitAreas` at call time.
- **v1.5.3**: guarded by `canvas._tooltipListenersAttached` (per canvas) and `window._tooltipDocListenerAttached` (for the single document-level dismiss handler). Previously attached on every render, which added up fast because `renderBothCharts` calls `setupTooltip` twice per canvas (directly + via `setupPanHandlers` at its own line ~1785) and renders fire on every touchmove during zoom pans.

### Form handling (lines 1798–1910)
- `addMeasurementRow`, `removeRow`, `getMeasurements`, `updateGhostValues`, `attachGhostListeners`
- Ghost values show 50th centile in grey italic when DOB + date exist but value empty

### Top-level flows
- `plotCharts()` (1911) — reads form, validates, processes measurements, sets `chartState.htMeasurements/wtMeasurements`, runs `generateCentileLines` if sex changed, auto-selects range from measurement ages, calls `renderBothCharts`
- `updateLegend`, `renderResults`, `formatDisplayDate`, `showError`, `clearAlerts`
- `STORAGE_KEY = "paedplot_session"`
- `saveState` / `loadState` / `clearState` (2056–2165) — localStorage round-trip
- `attachSaveListeners` — debounced save on input/change
- `newPatient()` — clears state, UI, canvases, resets to 0-1 range

### Dev panel (line 2238)
- `TEST_CASES` array with expected centile ranges
- `openDevModal`, `closeDevModal`, `runTests`

### INIT (line 2282 onwards)
- `loadState()` → `applyZoomWindow()` → auto-plot if data exists
- Otherwise: one empty measurement row with today's date

---

## Key HTML IDs

- `chartsStack` — the `<div class="charts-stack">` — container whose width drives `getCanvasWidth`
- `htCanvas`, `wtCanvas` — the two canvases
- `htBlock`, `wtBlock` — their parent divs
- `unifiedTitle` — "Boys/Girls — UK-WHO Growth Chart"
- `sharedLegend`, `resultsBody` — below chart
- `btnFull`, `btnZoom`, `btn01`, `btn14`, `btn29`, `btn918`, `btn218`, `btnPreterm`
- `pretSep`, `pretGroup` — preterm toggle visibility group
- `panIndicator` — shown in zoom mode
- `devModal` — dev testing panel
- `tooltip` — measurement hover tooltip
- Sidebar: `dob`, `gestWeeks`, `gestDays`, `mdate-N`, `mwt-N`, `mht-N`

---

## Key CSS facts

- `.charts-stack` has `touch-action: pan-y` and **`overflow: hidden`** (line 504). The overflow:hidden matters — if canvas becomes wider than container, it gets clipped. When switching to the new grid model, if `pxPerSquare` hits its MIN and chart overflows, this needs changing to `overflow-x: auto` or similar.
- Print CSS: `canvas { width: 100% !important; height: auto !important; }` (line 407) — forces canvas to container width in print.
- Media query at 700px: small tweaks to padding (line 427).

---

## GRID geometry (v2 — IMPLEMENTED April 2026)

### New constants replacing SCALE
```js
const GRID = {
  '0-1':  { xYears: 2/52,    htCm: 1,  wtKg: 0.5 },   // 2-week × 1cm × 0.5kg
  '1-4':  { xYears: 1/12,    htCm: 1,  wtKg: 0.5 },   // 1-month × 1cm × 0.5kg
  '2-9':  { xYears: 0.5,     htCm: 5,  wtKg: 5   },   // 6-month × 5cm × 5kg
  '9-18': { xYears: 0.5,     htCm: 5,  wtKg: 5   },
  '2-18': { xYears: 0.5,     htCm: 5,  wtKg: 5   },
};
const MIN_PX_PER_SQUARE = 12;
const MAX_PX_PER_SQUARE = 32;
```

### Rendering model
- **One scalar** `pxPerSquare` drives everything (both axes). Pixel-square.
- `pxPerSquare = clamp(plotWAvailable / xSquaresInView, MIN, MAX)` where `xSquaresInView = ageRange / GRID[range].xYears`
- `plotW = pxPerSquare × xSquaresInView` (may exceed container → horizontal scroll)
- Height panel height = `pxPerSquare × (htValRange / htCm)` + margins
- Weight panel height = `pxPerSquare × (wtValRange / wtKg)` + margins
- Panels decoupled vertically; only share x.
- `T.x(age)` = `m.left + ((age - ageMin) / GRID[range].xYears) × pxPerSquare`
- `T.y(val)` per panel: `ch - m.bottom - ((val - valMin) / GRID[range].<htCm|wtKg>) × pxPerSquare`
- Grid snap: in `computeYRange`, snap valMin/valMax to nearest multiple of panel's grid unit.

### Settled decisions from design discussion
- Dynamic y-range preserved (fit to visible centiles, not paper chart limits).
- `Y_TICK_CANDIDATES` **replaced in v1.5.5** by `Y_GRID_SPEC` (module scope) — defines minor/major for each range × method. Major step also drives y-range snap (`getYSnapUnit`).
- No range-specific cap on panel height for now.
- Grid-snap panel edges = yes; snap is on major-gridline step (v1.5.5), not on panel-sizing geometry.
- MAX enforces a natural maximum chart width on wide screens; whitespace on either side is fine.
- MIN = 12 chosen to keep chart close to viewport width on the narrowest phones in the worst-case range (1-4y, 36 squares × 12 = 432px vs typical 360px phone = slight horizontal scroll).

### CSS change needed
- `.charts-stack { overflow: hidden }` → `overflow-x: auto` so chart can scroll horizontally when it exceeds container width (primarily 1-4y on narrow phones).

### Touchpoints for edit — COMPLETED
1. ✅ `renderBothCharts` — replaced SCALE/pxPerYear/MIN_PANEL_PX block with GRID/pxPerSquare geometry
2. ✅ `drawSingleChart` — one-line change to pass gridUnit into computeYRange (via new `getGridUnit(range, method)` helper)
3. ✅ `computeYRange` — added optional `gridUnit` parameter; when provided, snaps valMin/valMax to multiples of gridUnit. Legacy snap-candidates path kept for callers that don't pass it.
4. ✅ CSS `.charts-stack` — `overflow: hidden` → `overflow-x: auto; overflow-y: hidden`

### Module-scope constants added (~line 940)
- `GRID` — per-range grid-square definitions (xYears / htCm / wtKg)
- `MIN_PX_PER_SQUARE = 12`
- `MAX_PX_PER_SQUARE = 32`
- `getGridUnit(range, method)` helper

### Predicted vs old behaviour (400px phone, full mode, panel heights in px)
| Range | OLD ht/wt | NEW ht/wt | Notes |
|---|---|---|---|
| 0–1y | 252 / 120 | 468 / 334 | Big fix — was the main user complaint |
| 1–4y | 177 / 153 | 576 / 430 | Also fixes SCALE-table bug: paper chart is 0.5kg/sq not 1kg/sq |
| 2–9y | 369 / 348 | 369 / 348 | Identical (pxPerSquare matches old pxPerYear/unit) |
| 9–18y | 292 / 331 | 292 / 331 | Identical |
| 2–18y | 260 / 254 | 324 / 310 | Slightly taller, marginal |

### Known narrow-phone horizontal overflow (handled by overflow-x:auto)
- 1–4y at 400px container: chart = 530px → 130px horizontal scroll
- 0–1y at 400px: chart = 410px → ~10px scroll, trivial
- All other ranges at 400px: chart fits container, no scroll

### What NOT to change
- LMS engine, centile generation, dataset logic (all pre-1000)
- `getGridSpec` is age-based and independent of `pxPerSquare` — rewritten in v1.5.5 to return `{minorGrid, majorGrid, pipOnly}` but still age-driven only.
- setupPanHandlers — uses plotW and age bounds via canvas._transform, unaffected
- setupTooltip — uses hitAreas, unaffected
- All form / storage / state / results / legend / tests

---

## Risks / edge cases noted during code read

1. **`overflow: hidden` on charts-stack** (CSS line 504) — will clip chart if it exceeds container. Must change to `overflow-x: auto`.
2. **Centile cache in data space** — safe, no invalidation needed on geometry change.
3. **Pan math uses canvas._transform.plotW + _ageMax/_ageMin** — safe, already abstract.
4. **Tooltip hitAreas rebuilt each render** — safe.
5. **Print CSS overrides** (line 407) force `canvas { width:100% !important }`. This might interact oddly with horizontal overflow — needs visual check in print, low priority.
6. **Auto range select in `plotCharts`** (line 1956ish) uses age of measurements — unaffected by geometry change.
7. **Y-axis filtered to visible window** (existing behaviour per v1.3 changelog) — preserved by keeping computeYRange signature and tight-fit logic.
8. **`computeYRange` called twice per panel** (once in renderBothCharts for sizing, once in drawSingleChart for drawing) — kept as-is, described as "cheap recompute, same inputs" in a comment.

---

## Coordinate reference conventions

- `age` = decimal years (negative for preterm)
- `decimal_age` = same, used in LMS tables
- `chronAge` vs `corrAge` = chronological vs gestationally-corrected
- `vals[ci]` in centile cache: ci 0..8 maps to 0.4th, 2nd, 9th, 25th, 50th, 75th, 91st, 98th, 99.6th (per CENTILE_LINES order)
- Canvas coords: (0,0) top-left; y increases downward; `T.y(val)` flips so higher values are higher on screen

---

## Backup location
- `/home/claude/paedplot/paedplot-backup-pre-grid.html` — pristine copy of v1 before GRID rewrite (paedplot-16 as uploaded).
