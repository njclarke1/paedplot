# PaedPlot — Technical Explainer

> **⚠️ Historical document** — describes the v1.x architecture and is kept for reference. For the current (v2.x) architecture see `../CLAUDE.md`.

**Current version: v1.8**
**Author: Nick (Paediatric SpR, UHBW)**
**Last updated: April 2026**

---

## What PaedPlot Is

PaedPlot is a fully offline, single-file HTML clinical reference tool for plotting paediatric growth measurements against UK-standard centile charts. It is intended for use by paediatricians and trainees at the point of care — in clinic, on the ward, or during ward rounds — on any device including locked-down NHS computers (Microsoft Edge, no admin rights) and personal phones.

A child's sex, date of birth, gestational age, and one or more dated measurements (height and/or weight) are entered into the form. PaedPlot calculates the child's decimal age, applies gestational correction if needed, looks up the appropriate UK-WHO reference data, computes an SDS (standard deviation score) and centile for each measurement, and renders the results on growth charts that closely replicate the familiar RCPCH paper growth charts used in clinical practice throughout the UK.

**PaedPlot is not a medical device.** It is a personal clinical reference aid. It does not write to any clinical record. No patient-identifiable data is stored beyond the current browser session.

---

## The UK-WHO Growth Reference

### The four datasets

| Dataset | Source | Raw data range | Used for |
|---------|--------|----------------|----------|
| **uk90_preterm** | UK 1990 (Cole et al.) | 23 weeks gestation to ~2 weeks postnatal | Preterm section (negative decimal ages) |
| **who_infant** | WHO 2006 | 2 weeks to 2 years | 0–2y (length, lying) |
| **who_child** | WHO 2006 | 2 years to 5 years | 2–4y (height, standing) — see boundary note |
| **uk90_child** | UK 1990 (Freeman et al.) | 4 years to 20 years | 4y onwards (UK population data) |

**Boundary steps are intentional and must be preserved:**
- At 2 years: lying→standing transition (~0.7cm step down). Centile lines drawn as separate segments, never joined.
- At 4 years: WHO→UK90 transition. Height steps down by ~0.6–1.1 cm (50th: −0.8 cm), weight steps up by ~0.02–0.65 kg (50th: +0.2 kg) at the boundary. The raw `who_child` data extends to 5.0y, giving a one-year zone of overlap with `uk90_child`. `selectDataset` uses UK90 from 4.0y onwards for point calculation (UK-WHO convention); `generateCentileLines` truncates `who_child` at ≤ 4.0y for line drawing (v1.5.2), so the two segments meet exactly at 4y and produce the characteristic sharp step seen on RCPCH paper charts rather than a zone of duplicate centile lines.

### The LMS method

All centile calculations use the LMS method (Cole & Green, 1992). Reference data provides L (lambda), M (mu), S (sigma) at specific ages.

**Measurement → SDS:**
```
L ≠ 0:  SDS = ((measurement/M)^L − 1) / (L × S)
L = 0:  SDS = ln(measurement/M) / S
```

**SDS → Measurement** (for drawing centile lines):
```
L ≠ 0:  measurement = M × (1 + L × S × SDS)^(1/L)
L = 0:  measurement = M × exp(S × SDS)
```

**SDS → Centile:** `Φ(SDS) × 100` using Abramowitz & Stegun 26.2.17 (~1.5×10⁻⁷ accuracy)

### The nine UK centile lines

| Centile | SDS | Style |
|---------|-----|-------|
| 0.4th | −2.67 | Dashed |
| 2nd | −2.00 | Solid |
| 9th | −1.33 | Dashed |
| 25th | −0.67 | Solid |
| 50th | 0.00 | Dashed |
| 75th | +0.67 | Solid |
| 91st | +1.33 | Dashed |
| 98th | +2.00 | Solid |
| 99.6th | +2.67 | Dashed |

Each centile is 2/3 SDS apart ("Cole nine-centile" format). A measurement crossing two centile lines (one "centile space") = 4/3 SDS shift, which is clinically significant.

### Decimal age and gestational correction

`decimal_age = days_between_dates / 365.25`

For preterm babies (gestation < 37+0 weeks — the UK/RCPCH clinical definition):
`corrected_age = decimal_age − ((40 − gestWeeks − gestDays/7) / 52.18)`

Babies at 37+0 weeks or later ("early term", "term", "late term", "post-term") receive no gestational correction — SDS is calculated from chronological age. Prior to v1.5.4 the threshold was inconsistent across four code sites; it is now uniformly `<37` everywhere (calcCorrectedAge, drawSingleChart, updateLegend, renderResults).

Gestational correction is applied throughout the lifespan (unlike paper charts which correct only to 12–24 months). Preterm measurements are plotted at both chronological (●) and corrected (×) age, connected by a dashed line.

### Interpolation

Cubic Lagrange interpolation where ≥2 data points exist on each side of target age; linear at dataset edges. **Never interpolated across the 2y or 4y dataset boundaries.**

---

## The Reference Data

### Source

Extracted from the RCPCH `growth-references` GitHub repository — the same data used by the official RCPCH Digital Growth Charts API. Covers height, weight, and OFC for both sexes across all four datasets.

### Embedding

The minified JSON (~105KB) is embedded in a `<script type="application/json">` tag and parsed once on load:

```javascript
const LMS_DATA = JSON.parse(document.getElementById('lms-data').textContent);
```

### Data counts

| Dataset | Weight | Height | OFC |
|---------|--------|--------|-----|
| uk90_preterm (each sex) | 20 pts | 18 pts | 20 pts |
| who_infant (each sex) | 38 pts | 38 pts | 38 pts |
| who_child (each sex) | 37 pts | 37 pts | 37 pts |
| uk90_child (male) | 193 pts | 193 pts | 169 pts |
| uk90_child (female) | 193 pts | 193 pts | 157 pts |

---

## How the Application Works

### Architecture

Single HTML file (~184KB). No external dependencies, no CDN, no network requests. Everything — HTML, CSS, JavaScript, reference data — in one file.

### User interface

**Sidebar (data entry):**
- Sex, Date of birth, Gestational age (23–42 weeks, 0–6 days)
- Repeatable measurement rows (date, weight kg, height cm)
- Ghost placeholders: once DOB is entered, each row's date defaults to today and weight/height fields show the 50th centile for that age in light grey
- Plot Charts, New Patient, Print, Dev buttons

**Chart area:**
- Five range toggle buttons: **0–1y, 1–4y, 2–9y, 9–18y, 2–18y**
- Full / Zoom toggle. Zoom shows a range-specific time window with horizontal drag-to-pan (touch-action: pan-y ensures vertical scroll always works)
- Unified stacked chart: height above weight, single border, shared x-axis
- Preterm toggle (0–1y only): extends chart left to 23 weeks gestation
- Results summary panel below

### Chart rendering

HTML5 Canvas API, no external charting library.

**Panel sizing — grid-square geometry (v1.5):**

Every grid square on either panel is rendered as a true pixel-square of side `pxPerSquare`. What one grid square represents is fixed per range by the GRID lookup and matches the RCPCH paper chart:

```javascript
const GRID = {
  '0-1':  { xYears: 2/52,  htCm: 1, wtKg: 0.5 },  // 2wk × 1cm × 0.5kg
  '1-4':  { xYears: 1/12,  htCm: 1, wtKg: 0.5 },  // 1mo × 1cm × 0.5kg
  '2-9':  { xYears: 0.5,   htCm: 5, wtKg: 2   },  // 6mo × 5cm × 2kg (v1.5.1 — see note)
  '9-18': { xYears: 0.5,   htCm: 5, wtKg: 5   },  // 6mo × 5cm × 5kg
  '2-18': { xYears: 0.5,   htCm: 5, wtKg: 5   },  // 6mo × 5cm × 5kg
};
const MIN_PX_PER_SQUARE = 12;
const MAX_PX_PER_SQUARE = 32;
```

**Note on 2–9y weight:** the RCPCH paper chart uses 5 kg/square throughout the 2–9y range. v1.5.1 departed from this deliberately, halving the weight grid to 2 kg/square to produce a panel 2.5× taller on screen. This improves on-screen readability — there is no clinical or calculation consequence, only a visual one. All other ranges retain paper-chart fidelity.

`pxPerSquare = clamp(availablePlotW / xSquaresInView, MIN, MAX)`, where `xSquaresInView = ageRange / GRID[range].xYears`.

Panels share the x-axis (both use the same `pxPerSquare × xSquaresInView` plot width) but have **independent** vertical sizing: height panel plot height = `pxPerSquare × htValueRange / htCm`, weight panel plot height = `pxPerSquare × wtValueRange / wtKg`. The y-axis range for each panel is computed tightly from the visible centile data (see Y-range below) and snapped to multiples of the panel's grid unit so panel edges always fall on a gridline.

On **narrow phones** `pxPerSquare` bottoms out at MIN=12; the chart may exceed container width and scrolls horizontally inside the `.charts-stack` container (which has `overflow-x: auto`). On **wide desktops** `pxPerSquare` tops out at MAX=32; whitespace fills the remainder.

In **zoom mode**, `xSquaresInView` shrinks and `pxPerSquare` recomputes — squares grow to fill the available width, so zoom genuinely increases resolution. Panels grow vertically in lockstep.

**Prior model (v1.0–v1.4+):** used a `SCALE` table of `unitsPerYear` values and a single `pxPerYear = min(plotW/ageRange, 80)` shared by both panels. Panel height = `(pxPerYear / unitsPerYear) × valueRange`. This coupled the vertical sizes of the two panels and, combined with the 80px/year cap, produced severely squashed weight panels on 0–1y and 1–4y on mobile. v1.5 replaced it entirely. The grid-square model also fixed a latent bug in the v1.4+ SCALE table where 1–4y weight was defined as `wt: 12` (implying 1 kg per grid square) but the RCPCH paper chart is actually 0.5 kg per square.

**Zoom windows:**

```javascript
const ZOOM_WINDOWS = {
  '0-1':  4/12,   // 4 months — one infant surveillance interval
  '1-4':  1.0,    // 12 months — one year of growth
  '2-9':  2.0,    // 2 years — school year either side
  '9-18': 3.0,    // 3 years — pubertal assessment window
  '2-18': 4.0,    // 4 years — broad overview
};
```

**Y-axis ticks** use per-range candidates to match paper chart label density (max 14 labels). The tick lookup is kept deliberately separate from the grid geometry — it expresses how often to *label* the y-axis, not what the gridlines represent:

```javascript
const Y_TICK_CANDIDATES = {
  '0-1':  { height: [2, 5],       weight: [1, 2]       },
  '1-4':  { height: [2, 5],       weight: [1, 2, 5]    },
  '2-9':  { height: [5, 10],      weight: [5, 10]       },
  '9-18': { height: [5, 10, 20],  weight: [5, 10, 20]   },
  '2-18': { height: [10, 20, 50], weight: [10, 20, 50]  },
};
```

**Axis gridlines and pips (v1.5.5 model)** — three independent tiers per axis. Layer order: minor gridlines (back) → major gridlines (middle) → "pip-only" ticks (front, axis strip only).

| Tier | Gridline through plot | Tick on axis edge | Label | Use |
|---|---|---|---|---|
| `minorGrid` | yes, light | — | — | fine reference at small intervals |
| `majorGrid` | yes, darker | yes | yes | primary reference lines with numeric labels |
| `pipOnly` | — | yes | yes | axis-only anchors (used for 0–1y month markers) |

**X-axis spec per range:**

| Range | `minorGrid` | `majorGrid` (→ label) | `pipOnly` (→ label) |
|---|---|---|---|
| 0–1y | — | every 2 weeks; labels in clinical vernacular — weeks-of-gestation on preterm side (24, 26, 28, 30, 32, 34, 36) and weeks-of-age on early postnatal side (2, 4, 6, 8, 10); unlabelled gridlines at 38w and 12w keep plotting granularity without label crowding | Birth + 3m, 4m, …, 11m, 1y (monthly labels from 3 months onward — sit between 2-weekly gridlines, hence pipOnly) |
| 1–4y | every month | every 6 months (1y, 1½y, 2y, 2½y, 3y, 3½y, 4y) | — |
| 2–9y | every 2 months | every 6 months (2y, 2½y, 3y … 9y) | — |
| 9–18y | every 2 months | every 1 year (9y, 10y … 18y) | — |
| 2–18y | every 2 months | every 1 year (2y, 3y … 18y) | — |

All ranges use a single-row x-axis label strip; bottom panel margin is 42 px across the board. (Historical note: v1.5.5 briefly used a 54 px bottom margin and two-row strip on 0–1y to accommodate both weekly and monthly labels; v1.6 collapsed this into a single row with mixed weeks-then-months labels to match clinical vernacular.)

**Y-axis spec (cm for height, kg for weight):**

| Range | Ht minor | Ht major | Wt minor | Wt major |
|---|---|---|---|---|
| 0–1y | — | 2 | — | 0.5 |
| 1–4y | 1 | 4 | — | 1 |
| 2–9y | 1 | 5 | 1 | 5 |
| 9–18y | 1 | 5 | 1 | 5 |
| 2–18y | 1 | 5 | 1 | 5 |

Defined in `Y_GRID_SPEC` at module scope. `null` minor = no minor tier. Major step also drives y-range snap (see below).

**Y-axis range** — `computeYRange(centileData, measurements, ageMin, ageMax, isTopPanel, snapUnit)` fits tightly to centile data visible in the current age window, plus any plotted measurements in that window. Outer padding = 3% of range on the non-boundary edge only; zero padding at the inter-panel boundary. Weight axis floored at 0. The result is snapped to multiples of `snapUnit` — since v1.5.5 this is the major-gridline step from `Y_GRID_SPEC` (via `getYSnapUnit(range, method)`), NOT the panel-sizing geometry from `GRID`. This makes panel top/bottom edges coincide with a major gridline.

**Centile lines** — pre-computed in `generateCentileLines`, cached in `chartState` in **data space** (decimal age + measurement values). Drawn as 4 separate segments per centile (one per dataset). `setLineDash` for dashed centiles. All `#AAAAAA`, 0.85px. Because the cache is in data space (not pixel coordinates), it is unaffected by geometry changes and needs no invalidation.

### Session persistence

Full form state (sex, DOB, gestation, all rows, range, zoom mode, pan position, showPreterm) saved to localStorage on every change. Auto-restored and auto-plotted on page load. New Patient clears everything.

### Calculation verification

Dev panel (🔧 button) runs built-in test cases. All SDS values should be within ±0.05 of RCPCH API output before clinical use.

---

## Version History

| Version | Key changes |
|---------|-------------|
| v1.0 | LMS engine, Canvas chart rendering, 9 centile lines, gestational correction, tooltips, Dev modal |
| v1.1 | Unified stacked chart, range toggles 0–4y/2–18y, zoom with touch pan, dynamic y-axis, ghost 50th centile placeholders |
| v1.2 | 4 range toggles, aspect ratio sizing (1yr=10cm=10kg), CSS touch-action:pan-y, direction-aware pan |
| v1.3 | 5 range toggles (0–1y, 1–4y, 2–9y, 9–18y, 2–18y), pxPerYear cap, weight axis floor at 0, y-axis filtered to visible window |
| v1.4 | Grid lines per range spec, x-axis labels per range, range-specific zoom windows, 0–1y weight aspect ratio (1kg=4wks) |
| v1.4+ | SCALE lookup table for all ranges (paper chart ratios), Y_TICK_CANDIDATES per range, preterm toggle, zoom bug fixes |
| **v1.5** | **Grid-square geometry: GRID table + pxPerSquare (12–32) replaces SCALE/pxPerYear/MIN_PANEL_PX. Panels decoupled vertically, share x-axis only. Fixes vertical squashing on 0–1y and 1–4y mobile views. Corrects latent 1–4y weight scale bug. 2–9y/9–18y render identically. `.charts-stack` now `overflow-x: auto`.** |
| **v1.5.1** | **2–9y weight grid square halved from 5kg to 2kg — panel 2.5× taller with integer gridline labels. Departs from paper-chart fidelity on this range deliberately, for on-screen readability.** |
| **v1.5.2** | **Fixed WHO↔UK90 4y boundary overlap. `generateCentileLines` now truncates `who_child` at ≤ 4.0y, eliminating 1y of duplicate centile lines. Paper-chart-style sharp step at 4y restored. Point calculation unchanged.** |
| **v1.5.3** | **Fixed two pre-existing bugs: (a) preterm toggle was broken — `togglePreterm` referenced an undefined `range` identifier that immediately reset `showPreterm` to false after each click; (b) tooltip listener accumulation — `setupTooltip` re-attached handlers on every render including during zoom pans, causing hundreds of duplicate listeners to pile up and making the UI feel slow. Added listener guards.** |
| **v1.5.4** | **Three more pre-existing bugs found in code audit: (1) `newPatient` set an invalid `chartState.range = "0-4"` causing the chart to silently use the `2-18` fallback after "New Patient"; corrected to `0-1`. (2) "Is preterm" threshold was inconsistent across four sites (`calcCorrectedAge`, `drawSingleChart`, `updateLegend`, `renderResults`) with three different definitions; unified on `<37 weeks` matching UK/RCPCH convention. Post-term babies no longer receive backwards-correction; early-term babies (37+0 to 39+6) no longer receive a small correction — this will slightly change SDS for those babies. (3) Auto-range selection in `plotCharts` had a dead branch that hid older measurements when data spanned 0–1y and 1–4y; now falls through to `2-18`.** |
| **v1.5.4 validated** | **Calculation engine formally validated against live RCPCH Digital Growth Charts API. 12-case targeted suite (24 SDS measurements) covering every dataset, every boundary, gestational correction, and extreme centiles — all agreed with the API to better than ±0.001 SDS. The embedded UK-WHO LMS reference data is confirmed faithful; interpolation, dataset selection, correction, and SDS formulas all match RCPCH's reference implementation. Resolves the "SDS verification required before clinical use" open item.** |
| **v1.5.5** | **Restructured axis gridline and pip model into three independent tiers (minorGrid / majorGrid / pipOnly). New `Y_GRID_SPEC` table drives y-axis gridlines and range snap (decoupled from panel-sizing geometry). 0–1y initially gained a two-row label strip (weeks above, months below) with bottom margin bumped 42→54 px; this was reverted in v1.6. Visual density per range: 0–1y 2w gridlines + monthly pips, 1–4y monthly minor + 6-month major, 2–9y/9–18y/2–18y 2-month minor + 6-month or 1-year major. Removed old zoom-dependent minor-label hack on 1–4y.** |
| **v1.6** | **0–1y axis labels redesigned for clinical vernacular. Preterm side in weeks-of-gestation (24, 26, 28, 30, 32, 34, 36). Early postnatal in weeks-of-age (2, 4, 6, 8, 10). Monthly labels take over from 3m (3m, 4m, …, 11m, 1y). Full sequence: "24, 26, 28, 30, 32, 34, 36, Birth, 2, 4, 6, 8, 10, 3m, 4m, 5m, 6m, 7m, 8m, 9m, 10m, 11m, 1y". Gridlines remain at every 2-weekly position for plotting fidelity. Single-row strip (bottom margin back to 42 px). Unlabelled gridlines at 38w and 12w avoid crowding near Birth and the weeks→months transition.** |
| **v1.7** | **Cosmetic-only redesign to match RCPCH paper-chart aesthetic. Gridlines now fine dotted light-grey on both axes. Centile lines switch to sex-specific colour (muted blue `#68A1C5` for boys, muted rose `#C16B86` for girls) — all 9 lines same colour/weight; 50th NOT emphasised; dashes `[4,4]` for 0.4/9/50/91/99.6, solid for 2/25/75/98. Centile right-edge labels match line colour at 10px. CSS palette reworked: system sans stack throughout (no Georgia serif), page `#F5F5F5`, borders `#E0E0E0`, text `#222`. Sex-accent via `body.sex-girls`/`sex-boys` classes and `--accent` CSS variable; JS `applySexTheme(sex)` helper syncs on load, sex-radio change, state restore, and render. Chart title uppercases gender word. Results panel styled as paper-chart "instructional box" (pale yellow with border). No maths/logic changes.** |
| **v1.8** | **Dedicated preterm view + 0–1y double-line bug fix. Preterm is now its own range (6th button) showing 23w→42w gestation with only `uk90_preterm` data. Auto-activates when the earliest measurement falls in the preterm window. 0–1y view previously drew duplicate centile lines in 0–2w (both `uk90_preterm` and `who_infant` had data there); now `uk90_preterm` is clipped at age ≤ 0 and `who_infant` starts at age ≥ 2w, producing the paper-chart-style blank 0–2w region. Birth centile markers (small horizontal ticks at age 0) occupy that region to anchor the 9 centiles at term-newborn values. Old 0–1y "+ Preterm" toggle retained. `computeYRange` gained a `datasetFilter` argument so panel y-range matches what's drawn. No maths/logic changes to calculation pipeline — calculations remain as validated in v1.5.4.** |

---

## Known Limitations and Pending Work

- **X-axis label collisions** — labels can overlap on small screens, particularly 1–4y full mode where all months are labelled. Minimum pixel gap check needed before drawing.
- **Y-axis label cut-off** — bottom label sometimes clipped; may need margin increase. Grid-snap in v1.5 may have reduced frequency.
- **SDS verification** — ✅ **resolved April 2026**. Validated against live RCPCH Digital Growth Charts API via 12-case suite (24 SDS measurements). All agreed to within ±0.001 SDS — two orders of magnitude tighter than the ±0.05 target. Embedded LMS data confirmed faithful; calculation pipeline confirmed correct.
- **OFC panel** — data embedded but no head circumference chart panel.
- **Print layout** — `@media print` basic; A4 landscape not optimised. Worth re-checking after v1.5 CSS changes.
- **Horizontal scroll on narrow phones** — introduced by v1.5 for 1–4y full mode on devices ~400px wide. Acceptable trade for correct vertical proportions; revisit if on-device UX feels awkward.

---

## Disclaimer

PaedPlot — Offline growth chart reference tool
Calculations use the LMS method (Cole & Green, 1992) with UK-WHO reference data.
Reference data sourced from the RCPCH growth-references repository (github.com/rcpch/growth-references).
This is a personal clinical reference tool, not a medical device.
It does not replace clinical judgement or the formal clinical record.
Session data is stored locally in this browser only and never transmitted.
