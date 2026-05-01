# PaedPlot — Editing Guide

Practical how-tos for common code changes. For full architecture context see
`paedplot_explainer.md`; for a line-by-line codebase map see `CODEBASE_REFERENCE.md`;
for Claude Code–specific instructions see `../CLAUDE.md`.

---

## Adjusting the combined chart scale ratios

The combined chart (height + weight on a single canvas) has a fixed visual ratio
between the age axis (x) and each measurement axis (y). This controls how "zoomed
in" the chart looks and how tall it grows as screen width increases.

### Where to find it

`src/paedplot.html` — `COMBINED_CHART_CONFIG` object, roughly 50 lines above
`function drawCombinedChart`.

```javascript
const COMBINED_CHART_CONFIG = {
  '0-1':  { ..., STEP_HT: 1, WT_MAJOR: 0.375, ... },
  '1-4':  { ..., STEP_HT: 1, WT_MAJOR: 0.5,   ... },
  '2-9':  { ..., STEP_HT: 3, WT_MAJOR: 3,      ... },
  '9-18': { ..., STEP_HT: 3, WT_MAJOR: 3,      ... },
};
```

### The formula

Each range has a fixed number of grid squares per year, determined by
`GRID[range].xYears` (the age width of one square):

| Range  | xYears | Squares per year (S) |
|--------|--------|----------------------|
| 0-1y   | 2/52   | 26                   |
| 1-4y   | 1/12   | 12                   |
| 2-9y   | 0.5    | 2                    |
| 9-18y  | 0.5    | 2                    |

To set a target ratio of **"1y = A cm = B kg"** in pixel-space:

```
STEP_HT  = A / S      (cm per grid square)
WT_MAJOR = B / S      (kg per grid square)
```

**Example — 2-9y, target 1y = 6cm = 6kg, S = 2:**
```
STEP_HT  = 6 / 2 = 3
WT_MAJOR = 6 / 2 = 3
```

**Example — 0-1y, target 4w = 2cm = 0.75kg:**

4 weeks = 4/52 years = (4/52) × 26 squares = 2 squares. So S_effective = 2.
```
STEP_HT  = 2 / 2 = 1
WT_MAJOR = 0.75 / 2 = 0.375
```

### What each field does

| Field       | Effect |
|-------------|--------|
| `STEP_HT`   | Cm per grid square → drives `pxPerCm = pxSq / STEP_HT`. Also sets the major height gridline interval and the number of minor gridlines per square (`STEP_HT - 1` minors). Height axis labels appear every `STEP_HT` cm. |
| `WT_MAJOR`  | Kg per grid square → drives `pxPerKg = pxSq / WT_MAJOR`. Controls the weight pixel scale independently of `STEP_HT`. If omitted, falls back to `Y_GRID_SPEC[range].weight.major`. |
| `STEP_WT`   | Weight axis label interval in kg. For labels to land on gridlines this should be an integer multiple of `WT_MAJOR`; otherwise labels sit cleanly between gridlines. |
| `HT_ANCHOR` | The cm value that sits at the shared anchor y-pixel. Moving it shifts the height band up or down relative to the weight band. Should be a multiple of `STEP_HT`. |
| `WT_ANCHOR` | The kg value that sits at the same anchor y-pixel as `HT_ANCHOR`. Moving it shifts the weight band. Should be a multiple of `WT_MAJOR`. |
| `drawMinors`| `true` = draw minor gridlines within each square at 1cm intervals. `false` = major gridlines only (used for 0-1y where the squares are already small). |

### Current tuned ratios (May 2026)

| Range  | Ratio            | STEP_HT | WT_MAJOR |
|--------|------------------|---------|----------|
| 0-1y   | 4w = 2cm = 0.75kg | 1      | 0.375    |
| 1-4y   | 1y ≈ 9cm = 3.5kg  | 1      | 0.5      |
| 2-9y   | 1y = 6cm = 6kg    | 3      | 3        |
| 9-18y  | 1y = 6cm = 6kg    | 3      | 3        |

### Sizing behaviour

The combined chart has **no `MAX_PX_PER_SQUARE` cap** (unlike the separate panels).
`pxSq` scales freely to fill the available container width:

```
pxSq = availableWidth / xSquares   (minimum floor of MIN_PX_PER_SQUARE = 10)
```

As the screen widens, `pxSq` grows → the chart grows taller. Vertical panning is
expected. This is intentional: the scale ratio stays constant across all screen sizes.

### Planned future feature

Nick would like an **in-app ratio slider** so the user can adjust `STEP_HT` /
`WT_MAJOR` at runtime without redeploying. Candidate implementation:

1. Add a `<input type="range">` per range (or a single global zoom slider)
2. On `input` event: update `COMBINED_CHART_CONFIG[range].STEP_HT` and `.WT_MAJOR`
3. Re-call `drawCombinedChart()`
4. Persist the chosen value to `localStorage` (same pattern as other state in `saveState`)

---

## Changing the anchor (where height and weight bands overlap)

`HT_ANCHOR` and `WT_ANCHOR` define the single y-pixel row where both axes meet.
The anchor was chosen so the centile bands overlap in a clinically meaningful zone —
matching the convention on the RCPCH 0-1y paper chart.

To shift the weight band **up** relative to height: decrease `WT_ANCHOR`.
To shift the weight band **down**: increase `WT_ANCHOR`.

Both values must be multiples of their respective step sizes so they fall on a
major gridline. After changing an anchor, visually verify the centile bands still
occupy a sensible shared region.

Current anchors:

| Range  | HT_ANCHOR | WT_ANCHOR |
|--------|-----------|-----------|
| 0-1y   | 60 cm     | 13 kg     |
| 1-4y   | 84 cm     | 23 kg     |
| 2-9y   | 100 cm    | 50 kg     |
| 9-18y  | 125 cm    | 105 kg    |

---

## Adding a new age range to the combined chart

1. Add an entry to `COMBINED_CHART_CONFIG` with the six required fields.
2. Ensure `GRID[range]` has a matching entry (for `xYears`).
3. Ensure `Y_GRID_SPEC[range]` exists (for minor gridline spec and the `WT_MAJOR`
   fallback).
4. The `getGridSpec(range)` x-axis function must handle the new range — add a
   `case` if needed.
5. Test in both Combined and Separate view modes.

The `preterm` range deliberately stays in Separate view only — the dual-axis
combined layout does not suit the preterm gestational-age x-axis.

---

## Syntax checking after edits

After any JS edit, extract and check with Node:

```bash
node -e "
const fs = require('fs');
const html = fs.readFileSync('src/paedplot.html', 'utf8');
const m = html.match(/<script(?! id)[^>]*>([\s\S]*?)<\/script>/g);
if (m) {
  const js = m.map(s => s.replace(/<\/?script[^>]*>/g, '')).join('\n');
  require('vm').compileFunction(js);
  console.log('OK');
}
"
```

Run from the `paedplot/` root directory.
