# CLAUDE.md — PaedPlot Project Context

## What this project is

PaedPlot is a fully offline, single-file HTML tool for plotting UK-WHO paediatric growth charts. It's used by a Paediatric SpR (specialist registrar) at UHBW on locked-down NHS computers and on mobile. Everything — HTML, CSS, JS, and the full UK90/WHO LMS reference dataset (~105KB JSON) — is embedded in one `.html` file with zero external dependencies.

**This is a personal clinical reference tool, not a medical device.**

## Current state

**Version:** v2.1 (June 2026)
**Working file:** `src/paedplot.html` (~298KB, ~3270 lines — includes ~90KB embedded Hind WOFF2 font)
**Validation status:** SDS calculation engine validated against live RCPCH Digital Growth Charts API to ±0.001 SDS across all datasets, boundaries, and extremes (April 2026). See `docs/VALIDATION_RECORD.md`. June 2026 audit confirmed the engine and LMS data are byte-identical to the validated v1.9 build.

## Architecture overview

### Single-file structure

```
paedplot.html
├── <style>           lines 7-604       CSS incl. 3 @font-face Hind embeds (w300/400/600)
├── <body>            lines 606-775     HTML structure
├── <script id="lms-data">  line 776    LMS JSON (~105KB, single line)
└── <script>          lines 780-3265    JavaScript (~2480 lines)
```

### JavaScript organisation (top to bottom; line numbers as of v2.1)

| Section | Lines | Purpose |
|---|---|---|
| LMS data parsing | 786 | Parse embedded JSON |
| Math engine | 791-1009 | normalCDF, calcDecimalAge, calcCorrectedAge, selectDataset, lagrange4, lookupLMS, sdsFromMeasurement, measurementFromSDS, centileFromSDS, centileBandText, calculateMeasurement, generateCentileLines (+ getAccentColor/applySexTheme at 933-950) |
| Formatting | 1014-1038 | formatAge, formatAgeVerbose |
| Chart state | 1041 | `chartState` object — all mutable UI state |
| Layout constants | 1059-1110 | Margins, GRID table, MIN/MAX_PX_PER_SQUARE, Y_GRID_SPEC |
| Geometry helpers | 1112-1218 | getYSnapUnit, getCanvasWidth, makeTransform, getRangeLimits, computeYRange |
| Separate-view renderer | 1220-1693 | `drawSingleChart` — stacked-panel rendering (~470 lines) |
| Grid spec | 1696-1859 | ageLabel, halfYearLabel, weekLabel, getGridSpec (x-axis definitions per range) |
| View mode | 1861 | setViewMode (Combined/Separate toggle) |
| Combined-view renderer | 1935-2400 | COMBINED_CHART_CONFIG + `drawCombinedChart` — single canvas, dual y-axes |
| Panel orchestration | 2402-2515 | `renderBothCharts` — sizing, routes to combined or separate renderer |
| Range controls | 2517-2575 | updatePretermToggleVisibility, togglePreterm, setChartRange |
| Tooltip | 2577-2643 | setupTooltip (once-attached listeners, `canvas._hitAreas`) |
| Form/data entry | 2645-2757 | addMeasurementRow, getMeasurements, updateGhostValues |
| Plot orchestration | 2759-2894 | plotCharts (main entry; `preserveRange` arg skips auto-range on session restore), updateLegend, renderResults |
| State persistence | 2911-3001 | saveState, loadState, clearState, attachSaveListeners |
| Patient management | 3017+ | newPatient |
| Dev tools | ~3090-3240 | TEST_CASES, loadSamplePatient (sample presets), openDevModal, runTests |
| Init | ~3230 | IIFE bootstrap + debounced resize handler |

### Key data structures

**`chartState`** — the single mutable state object:
```javascript
{
  sex: 'male'|'female',
  range: 'preterm'|'0-1'|'1-4'|'2-9'|'9-18'|'2-18',
  showPreterm: boolean,
  viewMode: 'combined'|'separate',   // v2.0 — default 'combined'
  gestWeeks: number, gestDays: number,
  htCentileCache: { datasetName: [{age, vals[9]}] },
  wtCentileCache: same structure,
  htMeasurements: [{date, value, chronAge, corrAge, htResult, wtResult, ...}],
  wtMeasurements: same structure
}
```
(zoomMode/panOffsetX/zoomCentreAge were removed with the zoom/pan system in v2.0 step 1A.)

**`GRID`** — panel sizing geometry per range:
```javascript
{
  'preterm': { xYears: 1/52,  htCm: 1, wtKg: 0.1 },
  '0-1':    { xYears: 2/52,  htCm: 1, wtKg: 0.5 },
  '1-4':    { xYears: 1/12,  htCm: 1, wtKg: 0.5 },
  '2-9':    { xYears: 0.5,   htCm: 5, wtKg: 2   },
  '9-18':   { xYears: 0.5,   htCm: 5, wtKg: 5   },
  '2-18':   { xYears: 0.5,   htCm: 5, wtKg: 5   },
}
```

One grid square = `pxPerSquare × pxPerSquare` pixels, always truly square. Panel width = `xSquares × pxPerSquare`. Panel height = `ySquares × pxPerSquare`. pxPerSquare is clamped to [10, 32] in the separate view and derived from fitting the chart to container width. (The combined view has no MAX cap — it fills the width and grows taller.)

**`COMBINED_CHART_CONFIG`** — per-range geometry for the combined (dual-axis) view: `ageMin/ageMax` (with `_F` girl overrides: girls 2–8y / 8–18y), `HT_ANCHOR`/`WT_ANCHOR` (this cm == this kg at the same y-pixel), `STEP_HT`/`WT_MAJOR` (cm and kg per grid square → independent y-scales `pxPerCm = pxSq/STEP_HT`, `pxPerKg = pxSq/WT_MAJOR`), `STEP_WT`/`LABEL_HT_STEP` (label intervals), and `LEFT/RIGHT_WT_MAX` / `LEFT/RIGHT_HT_MIN` dual-axis label cutoffs. Preterm and 2–18y ranges have no config → always render in separate view. Full field reference lives in the combined-chart comment block in the source (~line 1880).

**`Y_GRID_SPEC`** — y-axis gridline intervals (independent from GRID):
```javascript
{
  'preterm': { height: {minor:1, major:2}, weight: {minor:0.1, major:0.5} },
  '0-1':    { height: {minor:null, major:2}, weight: {minor:null, major:0.5} },
  '1-4':    { height: {minor:1, major:4}, weight: {minor:null, major:1} },
  '2-9':    { height: {minor:1, major:5}, weight: {minor:1, major:5} },
  '9-18':   { height: {minor:1, major:5}, weight: {minor:1, major:5} },
  '2-18':   { height: {minor:1, major:5}, weight: {minor:1, major:5} },
}
```

### LMS datasets embedded

| Dataset | Source | Age range (decimal years) | Used for |
|---|---|---|---|
| `uk90_preterm` | UK 1990 (Cole et al.) | -0.326 to +0.038 (23w to 42w gestation) | Preterm chart + preterm toggle on 0-1y |
| `who_infant` | WHO 2006 | 0 to 2.0 | 0-1y and 1-4y (birth to 2 years) |
| `who_child` | WHO 2006 | 2.0 to 4.0 (truncated from raw 2-5y in v1.5.2) | 1-4y and 2-9y (2 to 4 years) |
| `uk90_child` | UK 1990 (Cole et al.) | 4.0 to 20.0 | 2-9y, 9-18y, 2-18y (4 years onward) |

**Critical boundary rules:**
- `who_child` centile lines truncated at `decimal_age ≤ 4.0` in `generateCentileLines` (v1.5.2 fix — prevents duplicate lines from 4-5y overlap with `uk90_child`)
- On 0-1y view: `uk90_preterm` clipped at `age ≤ 0`, `who_infant` clipped at `age ≥ 2 weeks` — creates paper-chart-style blank 0-2w region with birth centile markers (v1.8)
- On preterm view: only `uk90_preterm` data drawn (v1.8)
- `selectDataset` (for point calculation): `< 0.038 → uk90_preterm`, `< 2.0 → who_infant`, `< 4.0 → who_child`, else `uk90_child`

### Centile lines

9 lines: 0.4th (SDS -2.67), 2nd (-2), 9th (-1.33), 25th (-0.67), 50th (0), 75th (+0.67), 91st (+1.33), 98th (+2), 99.6th (+2.67).

- Dashed `[4,4]`: 0.4th, 9th, 50th, 91st, 99.6th
- Solid: 2nd, 25th, 75th, 98th
- All same colour and weight (1.2px). 50th is NOT emphasised.
- Colour: sex-specific accent — `#0081c7` (boys), `#e7459a` (girls) — v2.1 palette; both height and weight centile sets use the accent in the combined view too
- Centile labels (suffix-stripped, e.g. "50") drawn on the line at both left and right plot edges with a white halo; 'height'/'weight' watermark at 25% alpha on the 50th centile

### Axis gridline model (v1.5.5 / v1.6)

Three independent tiers per axis:
- `minorGrid`: gridline through plot only (no tick, no label)
- `majorGrid`: gridline + tick mark + label
- `pipOnly`: tick + label on axis strip only (no gridline through plot)

Defined by `getGridSpec(range)` for x-axis and `Y_GRID_SPEC` for y-axis.

0-1y x-axis uses clinical vernacular: gestational weeks on preterm side (24, 26, 28, 30, 32, 34, 36), postnatal weeks (2, 4, 6, 8, 10), then months from 3m onward (3m, 4m, ..., 11m, 1y). Birth pivot at 40w gestation.

### Preterm handling

- Definition: `gestWeeks < 37` — applied at FOUR sites: `calcCorrectedAge`, `drawSingleChart`, `updateLegend`, `renderResults`. If modifying threshold, update ALL FOUR.
- Correction formula: `correction = (40 - gestWeeks - gestDays/7) / 52.18` years, subtracted from decimal age.
- Dedicated preterm chart (6th range button): 23w-42w gestation, only `uk90_preterm` data. **Separate view only** — no COMBINED_CHART_CONFIG entry.
- 0-1y preterm toggle: extends left to -0.33y; `uk90_preterm` lines drawn up to age 0 only. **Only works in separate view** — combined 0-1y pins ageMin at 0, so the toggle is hidden in combined view (`updatePretermToggleVisibility`).
- Auto-range: preterm view auto-activates when earliest measurement corrected age ≤ 2w post-term.
- Dot semantics differ between views: separate view plots ● at chronological age + ✕ at corrected age (joined by a dashed line) for preterm patients; combined view plots a single dot at corrected age.
- UK90 has no length/height reference below 25w gestation — `lookupLMS` correctly returns null for length of a 23-24w baby (weight works from 23w).

### Sex-theme system

CSS custom property `--accent` defaults to boys blue (`#0081c7`). `body.sex-girls` class overrides to pink (`#e7459a`). JS helper `applySexTheme(sex)` toggles the class AND updates the 2–9y/9–18y button labels (girls: "2–8y"/"8–18y"). Called on init, sex-radio change, state restore, newPatient, and every render.

Canvas centile line colour uses `getAccentColor(sex)` (reads JS constants `ACCENT_BOYS`/`ACCENT_GIRLS`, not CSS vars — canvas has no cascade). Measurement dot colours: height `#81c320` boys / `#9dc955` girls, weight `#c32081` boys / `#559dc9` girls (matched in the legend).

Typography: Hind, embedded as three base64 WOFF2 @font-face blocks (weights 300/400/600) — fully offline. Note canvas code requests `bold` (700), which the browser resolves to the 600 face.

## Coding conventions

- **Propose before implementing** non-trivial changes
- **One change at a time** — verify syntax between edits
- **Never interpolate across dataset boundaries** (2y, 4y)
- **Never join plotted measurement dots with lines**
- **Never emphasise the 50th centile**
- **No external dependencies** (offline-only requirement)
- **Keep docs updated** as edits are made (briefing, explainer, codebase reference)
- **Paper-chart fidelity** preferred when choosing between design options
- Syntax check after every edit: extract JS → `node --check`

## Files in this repository

```
paedplot/
├── CLAUDE.md                     (this file)
├── README.md                     (project README)
├── .gitignore
├── src/
│   └── paedplot.html             (v2.1 — the working app)
├── docs/
│   ├── paedplot_opus_briefing.md (handoff briefing — STALE, describes v1.x)
│   ├── paedplot_explainer.md     (technical explainer — STALE, describes v1.x)
│   ├── CODEBASE_REFERENCE.md     (line-number codebase map — STALE, v1.9 line numbers)
│   └── VALIDATION_RECORD.md      (RCPCH API validation audit trail)
├── validation/
│   ├── validate_paedplot.sh      (Termux/bash script — needs curl+jq, hardcoded v1.5.4 values)
│   └── validate_paedplot.mjs     (Node ≥18 — no deps, computes PaedPlot SDS live from src; preferred)
└── versions/                     (version snapshots — do not modify)
    ├── paedplot_v1.5.html … paedplot_v1.9.html   (v1.5, v1.5.1-v1.5.5, v1.6-v1.9)
    ├── paedplot_v2.0-phase1.html
    ├── paedplot_v2.0-phase2.html
    ├── paedplot_v2.0-design.html
    └── paedplot_v2.1.html
```

## v2.0 roadmap — unified single-canvas chart

### Status (June 2026)

Phases 1-2 **done** (combined renderer for 0-1y/1-4y/2-9y/9-18y; preterm and 2-18y stay separate-only). Phase 3 **partial** (tooltip + measurement dots work in combined view; no pinch-to-zoom — zoom/pan was removed entirely in step 1A). Phase 4 **mostly done** (Combined/Separate toggle, persistence, sex theme; print layout still stale). Phases 5-6 not started. Next planned UI change: replace Combined/Separate with a three-way Combined | Weight | Height selector.

### Goal

Replace the current two-stacked-canvas model (height panel above, weight panel below) with a single canvas per range showing both measurement types. Two independent y-axes: height (cm) on the left, weight (kg) on the right. Centile bands from both measurements share the same diagonal visual envelope, eliminating the large triangular dead zones that currently waste ~30-50% of vertical screen space.

### Key architectural decisions (confirmed with user)

1. **Height (cm) on LEFT y-axis, Weight (kg) on RIGHT y-axis** — matches RCPCH 0-1y paper chart convention.
2. **Curves colour-coded to their axis** — height curves in one colour, weight in another. Sex-accent moves to background tint, plotted dots, and UI chrome (departing from v1.7 where all centile lines were sex-coloured).
3. **Both views available** — toggle between "Combined" (v2.0 unified) and "Separate" (v1.9 stacked panels). Default to combined.
4. **Y-axis alignment algorithm**: map each axis so the 50th centile at the midpoint age lands at the vertical centre of the canvas. This makes the two centile bands occupy the same visual region.

### Phased implementation

**Phase 1 — Proof of concept.** Single canvas renderer for 2-9y only. Both height and weight centile curves, dual y-axes, no interactivity. Compare side-by-side with current 2-9y. Validates the visual approach.

**Phase 2 — Core rendering engine.** Generalise to all six ranges. Handle y-axis alignment for each range's data. Handle dataset boundaries and 0-2w blank region.

**Phase 3 — Interaction layer.** Tooltip, measurement plotting, hit detection, pinch-to-zoom (replacing current binary zoom toggle), pan.

**Phase 4 — UI integration.** Combined/Separate toggle, range buttons, preterm toggle, state persistence, results panel, print layout, sex theme.

**Phase 5 — Clinical features.** OFC (head circumference) as optional third curve set. BMI calculation and display. Mid-parental height target band.

**Phase 6 — Validation.** Re-run RCPCH API validation. On-device testing across all ranges.

### What MUST NOT change in v2.0

- The calculation engine (lines 791-1009) — validated, do not touch
- The embedded LMS data — validated, do not touch
- The centile line set (9 lines, specific SDS values, specific dash patterns)
- Dataset boundary rules (2y, 4y truncation)
- Preterm threshold (<37 weeks) and the four sites where it's applied
- The SDS formula and interpolation method
- Session persistence format (localStorage keys)

## Known limitations

- X-axis label collisions on very small screens (not addressed)
- Y-axis labels occasionally cut off at extremes
- OFC: LMS data embedded but no chart panel built
- Print layout: STALE — `@media print` rules target classes removed in v2.0 (`.chart-panel`, `.chart-tabs`, `.chart-title`, `.print-header`), hides the results panel, and does not hide `.chart-controls`. Needs a dedicated pass.
- Horizontal scroll on 1-4y separate view on narrow phones (acceptable trade-off)
- Combined view can grow very tall on wide screens (no MAX pxPerSquare cap — by design, vertical scrolling expected)
- Combined view plots preterm measurements at corrected age only (no ✕/chronological-dot pair as in separate view) — but the legend still shows "✕ Corrected age" for preterm patients
- `docs/` briefing, explainer, and CODEBASE_REFERENCE still describe v1.9 — pending a refresh

## Testing

- Syntax check: `node --check` on extracted JS after every edit
- RCPCH API validation: `node validation/validate_paedplot.mjs` (Node ≥18, RCPCH_API_KEY in env; computes PaedPlot SDS live from src). Legacy: `validation/validate_paedplot.sh` (Termux, curl+jq, hardcoded v1.5.4 expected values).
- In-app: Dev modal → runTests (7 sanity cases) + sample patient presets for every range/sex + preterm
- Manual on-device testing on Pixel 9 Pro Fold (primary test device)
