# CLAUDE.md — PaedPlot Project Context

## What this project is

PaedPlot is a fully offline, single-file HTML tool for plotting UK-WHO paediatric growth charts. It's used by a Paediatric SpR (specialist registrar) at UHBW on locked-down NHS computers and on mobile. Everything — HTML, CSS, JS, and the full UK90/WHO LMS reference dataset (~105KB JSON) — is embedded in one `.html` file with zero external dependencies.

**This is a personal clinical reference tool, not a medical device.**

## Current state

**Version:** v1.9 (April 2026)
**Working file:** `src/paedplot.html` (~205KB, ~2700 lines)
**Validation status:** SDS calculation engine validated against live RCPCH Digital Growth Charts API to ±0.001 SDS across all datasets, boundaries, and extremes (April 2026). See `docs/VALIDATION_RECORD.md`.

## Architecture overview

### Single-file structure

```
paedplot.html
├── <style>           lines 7-530       CSS (~530 lines)
├── <body>            lines 531-730     HTML structure
├── <script id="lms-data">              LMS JSON (~105KB, single line)
└── <script>          lines 732-2692    JavaScript (~1960 lines)
```

### JavaScript organisation (top to bottom)

| Section | Lines | Purpose |
|---|---|---|
| LMS data parsing | 733 | Parse embedded JSON |
| Math engine | 738-930 | normalCDF, calcDecimalAge, calcCorrectedAge, selectDataset, lagrange4, lookupLMS, sdsFromMeasurement, centileFromSDS, centileBandText, calculateMeasurement, generateCentileLines |
| Formatting | 956-980 | formatAge, formatAgeVerbose |
| Chart state | 983-1000 | `chartState` object — all mutable UI state |
| Layout constants | 1003-1035 | Margins, GRID table, MIN/MAX_PX_PER_SQUARE |
| Y-axis spec | 1047-1065 | Y_GRID_SPEC, getYGridSpec, getYSnapUnit |
| Geometry helpers | 1067-1185 | getCanvasWidth, makeTransform, getRangeLimits, computeYRange |
| Drawing engine | 1188-1640 | `drawSingleChart` — the main rendering function (~450 lines) |
| Grid spec | 1644-1805 | ageLabel, halfYearLabel, weekLabel, getGridSpec (x-axis definitions per range) |
| Panel orchestration | 1810-1905 | `renderBothCharts` — computes sizing, calls drawSingleChart twice |
| Range/zoom controls | 1910-1990 | togglePreterm, setChartRange, setZoomMode, recenterPan |
| Interaction handlers | 1991-2150 | setupPanHandlers, setupTooltip |
| Form/data entry | 2152-2260 | addMeasurementRow, getMeasurements, updateGhostValues |
| Plot orchestration | 2264-2405 | plotCharts (main entry point), updateLegend, renderResults |
| State persistence | 2421-2530 | saveState, loadState, clearState, attachSaveListeners |
| Patient management | 2531-2610 | newPatient |
| Dev tools | 2612-2690 | openDevModal, runTests |
| Init | 2692 | IIFE that bootstraps everything |

### Key data structures

**`chartState`** — the single mutable state object:
```javascript
{
  sex: 'male'|'female',
  range: 'preterm'|'0-1'|'1-4'|'2-9'|'9-18'|'2-18',
  zoomMode: 'full'|'zoom',
  showPreterm: boolean,
  htCentileCache: { datasetName: [{age, vals[9]}] },
  wtCentileCache: same structure,
  htMeasurements: [{date, value, chronAge, corrAge, sds, centile, centileText}],
  wtMeasurements: same structure,
  panOffsetX: number,
  zoomCentreAge: number
}
```

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

One grid square = `pxPerSquare × pxPerSquare` pixels, always truly square. Panel width = `xSquares × pxPerSquare`. Panel height = `ySquares × pxPerSquare`. pxPerSquare is clamped to [10, 32] and derived from fitting the chart to container width.

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
- Colour: sex-specific accent — `#68A1C5` (boys), `#C16B86` (girls)

### Axis gridline model (v1.5.5 / v1.6)

Three independent tiers per axis:
- `minorGrid`: gridline through plot only (no tick, no label)
- `majorGrid`: gridline + tick mark + label
- `pipOnly`: tick + label on axis strip only (no gridline through plot)

Defined by `getGridSpec(range, zoomMode)` for x-axis and `Y_GRID_SPEC` for y-axis.

0-1y x-axis uses clinical vernacular: gestational weeks on preterm side (24, 26, 28, 30, 32, 34, 36), postnatal weeks (2, 4, 6, 8, 10), then months from 3m onward (3m, 4m, ..., 11m, 1y). Birth pivot at 40w gestation.

### Preterm handling

- Definition: `gestWeeks < 37` — applied at FOUR sites: `calcCorrectedAge`, `drawSingleChart`, `updateLegend`, `renderResults`. If modifying threshold, update ALL FOUR.
- Correction formula: `correction = (40 - gestWeeks - gestDays/7) / 52.18` years, subtracted from decimal age.
- Dedicated preterm chart (6th range button): 23w-42w gestation, only `uk90_preterm` data.
- 0-1y preterm toggle: extends left to -0.33y; `uk90_preterm` lines drawn up to age 0 only.
- Auto-range: preterm view auto-activates when earliest measurement corrected age ≤ 2w post-term.

### Sex-theme system

CSS custom property `--accent` defaults to boys blue (`#68A1C5`). `body.sex-girls` class overrides to rose (`#C16B86`). JS helper `applySexTheme(sex)` toggles the class. Called on init, sex-radio change, state restore, and every render.

Canvas centile line colour uses `getAccentColor(sex)` (reads JS constants, not CSS vars — canvas has no cascade).

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
│   └── paedplot.html             (v1.9 — the working app)
├── docs/
│   ├── paedplot_opus_briefing.md (handoff briefing — architecture, settled decisions)
│   ├── paedplot_explainer.md     (technical explainer — data, algorithms, version history)
│   ├── CODEBASE_REFERENCE.md     (line-number codebase map for token-efficient lookup)
│   └── VALIDATION_RECORD.md      (RCPCH API validation audit trail)
├── validation/
│   └── validate_paedplot.sh      (Termux script for RCPCH API cross-check)
└── versions/                     (version snapshots — do not modify)
    ├── paedplot_v1.5.html
    ├── paedplot_v1.5.1.html
    ├── paedplot_v1.5.2.html
    ├── paedplot_v1.5.3.html
    ├── paedplot_v1.5.4.html
    ├── paedplot_v1.5.5.html
    ├── paedplot_v1.6.html
    ├── paedplot_v1.7.html
    ├── paedplot_v1.8.html
    └── paedplot_v1.9.html
```

## v2.0 roadmap — unified single-canvas chart

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

- The calculation engine (lines 738-930) — validated, do not touch
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
- Print layout: basic `@media print`, not optimised for A4 landscape
- Horizontal scroll on 1-4y full mode on narrow phones (acceptable trade-off)
- The zoom mode (Full/Zoom toggle) is clunky — planned replacement with pinch-to-zoom in v2.0

## Testing

- Syntax check: `node --check` on extracted JS after every edit
- RCPCH API validation: `validation/validate_paedplot.sh` (requires curl, jq, RCPCH API key in env)
- Manual on-device testing on Pixel 9 Pro Fold (primary test device)
