# PaedPlot v2.0 — Phase 1 Plan (Sonnet handoff brief)

**Audience:** Sonnet, with full project context already loaded from `CLAUDE.md`.
**Read first:** `CLAUDE.md` (project rules + v2.0 roadmap), then this document. Do not skim — every numbered "MUST" below is load-bearing. Other docs (`paedplot_explainer.md`, `paedplot_opus_briefing.md`, `CODEBASE_REFERENCE.md`) are reference only; consult them on demand, not up front.
**Working file:** `src/paedplot.html` (v1.9, ~205KB, ~2700 lines).
**Frozen reference:** `versions/paedplot_v1.9.html` is byte-identical to `src/paedplot.html` at the start of Phase 1. Diff against it any time to see what you've changed.
**Validation:** `validation/validate_paedplot.sh` (RCPCH API). The calculation engine MUST still pass after Phase 1 — but Phase 1 should not touch it, so expect zero deltas.

---

## 1. Phase 1 scope (what you are doing, in one paragraph)

Phase 1 delivers a **proof-of-concept Combined view for the 2–9y range only**, alongside a stripped-down Separate view. Both views drop the existing zoom/pan UI and code entirely (the user has shelved this — pinch-to-zoom is being deferred). The Combined view renders height and weight centile lines on a single canvas with two independent y-axes (height left, weight right), aligned so the 50th centile at the midpoint age sits at the canvas vertical centre. **No tooltip, no measurement plotting, no pan, no other ranges, no settings persistence for the new view.** The deliverable is a static, visually-correct Combined 2–9y chart that the user can flip to via a new "Combined / Separate" toggle to compare against the existing Separate rendering.

If anything in this scope is ambiguous, **stop and ask** before implementing. Do not infer.

---

## 2. What MUST NOT change

These are reproduced from `CLAUDE.md` for emphasis. Touching any of them invalidates validation.

1. **Calculation engine** — lines ~733–930 of `src/paedplot.html`. `normalCDF`, `calcDecimalAge`, `calcCorrectedAge`, `selectDataset`, `lagrange4`, `lookupLMS`, `sdsFromMeasurement`, `measurementFromSDS`, `centileFromSDS`, `centileBandText`, `calculateMeasurement`, `generateCentileLines`, `formatAge`, `formatAgeVerbose`. **Read-only.**
2. **Embedded LMS data** (`<script id="lms-data">`).
3. **Centile line set** — 9 lines, specific SDS values, dash pattern from `CENTILE_DASH`.
4. **Dataset boundary rules** — 2y lying→standing, 4y WHO→UK90 truncation in `generateCentileLines`.
5. **Preterm threshold** (`<37` weeks) and the four sites it appears.
6. **Session persistence schema** (localStorage keys in `saveState` / `loadState`) — though new fields may be added (see §6).
7. **GRID table** for 2–9y stays as-is for the Separate view path.

---

## 3. Phase 1 sequence — three independent steps

Do them in order. Commit after each step so they can be reverted independently.

### Step 1A — Remove zoom from the codebase

The zoom feature is being shelved. Remove it cleanly from both UI and JS. Do NOT comment it out — delete it. The v1.9 snapshot in `versions/` preserves the old behaviour if it's ever needed back.

**Specific deletions** (line numbers from current `src/paedplot.html`; verify before editing — they may drift between commits):

| What | Where |
|---|---|
| Full / Zoom buttons + pan indicator HTML | lines ~666–674 (delete the `<div class="ctrl-sep">` + ctrl-group containing `btnFull`/`btnZoom`, the `<div class="ctrl-sep"></div>` after, and the `<div id="panIndicator">`) |
| `chartState.zoomMode`, `chartState.panCentre`, `chartState.zoomWindow` fields | ~lines 987–989 |
| `ZOOM_WINDOWS` table | ~line 1101 |
| `applyZoomWindow()` | ~line 1109 |
| `getVisibleWindow()` body — replace with returning `getRangeLimits()` directly | ~line 1113 |
| `setZoomMode()` | ~line 1963 |
| `recenterPan()` | ~line 1973 |
| Drag-to-pan handlers in `setupPanHandlers` | ~lines 1991–2030 — entire pan logic; keep only what's needed for tooltip dismissal |
| Cursor-style branch on `zoomMode` | ~line 2126 |
| State save/load fields `chartZoom`, `panCentre` | ~lines 2438–2439, 2456–2457 |
| `btnFull`/`btnZoom` class toggling, `panIndicator` show/hide | ~lines 2472–2475 |
| `chartState.zoomMode = "full"` / `panCentre = 1.0` resets | ~lines 2541–2542 |
| `applyZoomWindow()` call in init | ~line 2669 |
| Any `getGridSpec(range, zoomMode)` callers — change signature to drop `zoomMode` | ~lines 1354, 1514, 1569; definition at 1670 |
| Conditional branches inside `setChartRange`, `togglePreterm`, `plotCharts` that reference zoom | ~lines 1922, 1947, 2344 |

After deletion: `getVisibleWindow()` simply becomes a forwarding call to `getRangeLimits()`, or you may inline it everywhere it's used. Pick whichever yields cleaner diff.

**Acceptance for Step 1A:**
- App still loads and renders Separate view in all six ranges (preterm, 0-1, 1-4, 2-9, 9-18, 2-18).
- No "Full"/"Zoom" buttons visible.
- No drag-to-pan behaviour anywhere.
- `node --check` on extracted JS passes (per CLAUDE.md convention).
- No reference to `zoomMode`, `panCentre`, `zoomWindow`, `ZOOM_WINDOWS`, `applyZoomWindow`, `getVisibleWindow`, `setZoomMode`, `recenterPan` remains in the file.
- localStorage state from v1.9 still loads without throwing (the missing keys should be ignored gracefully — verify the `loadState` branches don't crash on `state.chartZoom === undefined`).

### Step 1B — Add `drawCombinedChart` for the 2–9y range only

Implement a new rendering function that draws both height and weight centile bands on a single canvas with two independent y-axes.

**Function signature:**
```javascript
function drawCombinedChart(canvasId, range, cw)
```
Returns nothing. Draws into the canvas. `range` will be `'2-9'` for Phase 1; the function should error or no-op on any other range so Phase 2 can fill in the rest.

**Layout:**
- Canvas height: derive the same way Separate does — `pxPerSquare × ySquaresInView`. Use `GRID['2-9']` for x-axis squares (`xYears: 0.5`). For y-squares total, target a panel that's roughly the sum of the current Separate height + weight panel heights ÷ 2 (i.e., one canvas the size of one of the existing panels, since both data series now share it). Tune visually.
- Margins: top 20, bottom 42, left 50 (height labels), right 50 (weight labels). The right margin must be wider than current `CHART_MARGINS.right = 52` only if labels need it; aim to keep visual width similar.
- X-axis: identical spec to Separate 2–9y (`getGridSpec('2-9')`). 0.5y minors, 1y majors, integer year labels.
- **Two y-axes, SHARED gridline pixel positions:**
  - **Left (height, cm):** ticks/labels every `Y_GRID_SPEC['2-9'].height.major` (5 cm). Minor pips every `Y_GRID_SPEC['2-9'].height.minor` (1 cm).
  - **Right (weight, kg):** ticks/labels every `Y_GRID_SPEC['2-9'].weight.major` (5 kg — confirmed by Nick). Minor pips every 1 kg. Right-aligned labels.
  - Both axes share `pxPerSquare` so every horizontal gridline is simultaneously a height-major AND a weight-major. Minor positions also coincide (1 cm / 1 kg = 1/5 of a square on both axes).
- **Plot-area gridlines: ONE shared set, drawn every `pxPerSquare`** (major) and every `pxPerSquare/5` (minor). Each line is meaningful on both axes.
- **Weight axis is NOT floored at 0** for the alignment algorithm (see below) — but weight labels are NOT drawn for axis values < 0. The bottom of the weight axis strip stays unlabelled below zero.
- Background: same cream `#FFFDF0` as paper-chart current.
- **Sex-accent tint:** apply at two sites — (a) faint full-canvas background tint (`#68A1C5` boys / `#C16B86` girls at ~3% alpha overlaying the cream), and (b) UI chrome (toolbar/range button accent, results-panel border). Centile lines themselves are now measurement-coloured (see below), not sex-coloured.

**Y-axis alignment algorithm (shared-gridline version):**
```
Given range '2-9':
  ageMin = 2.0, ageMax = 9.0
  midAge = (ageMin + ageMax) / 2 = 5.5
  htMajor = Y_GRID_SPEC['2-9'].height.major  // 5 cm
  wtMajor = Y_GRID_SPEC['2-9'].weight.major  // 5 kg

For each measurement type m in {'height','weight'}:
  midVal_m = M parameter at midAge from lookupLMS(m, sex, midAge)
  vMin_m   = min over centileData_m[0.4th] across [ageMin, ageMax]
  vMax_m   = max over centileData_m[99.6th] across [ageMin, ageMax]
  raw_half_m = max(vMax_m - midVal_m, midVal_m - vMin_m)
  half_squares_m = ceil(raw_half_m / Y_GRID_SPEC['2-9'][m].major)

# Shared half-squares: take the larger requirement so both axes encompass their data
half_squares = max(half_squares_height, half_squares_weight)

# Each axis: midVal at canvas centre, half_squares above and below
yMin_height = midVal_height - half_squares × htMajor
yMax_height = midVal_height + half_squares × htMajor
yMin_weight = midVal_weight - half_squares × wtMajor   // may go negative — that's fine
yMax_weight = midVal_weight + half_squares × wtMajor

# Canvas plot height
plotH = 2 × half_squares × pxPerSquare

# Linear maps (one per axis)
height_pixel(val) = top + (yMax_height - val) / (yMax_height - yMin_height) × plotH
weight_pixel(val) = top + (yMax_weight - val) / (yMax_weight - yMin_weight) × plotH

# Verify alignment:
# height_pixel(midVal_height) == top + plotH/2  ✓
# weight_pixel(midVal_weight) == top + plotH/2  ✓
# Same horizontal pixel line at every multiple of pxPerSquare is simultaneously
#   a height major (every 5 cm from yMin_height upward) and
#   a weight major (every 5 kg from yMin_weight upward).
```

**Critical:** weight is NOT floored at 0 in the alignment math. If `yMin_weight < 0`, the gridlines extend full canvas height, but **weight labels are only drawn for values ≥ 0**. The bottom slice of the weight axis strip stays unlabelled. This is the trade-off that lets shared gridlines, 5 kg majors, and 50th-at-centre all coexist at 2–9y.

The two maps are independent. Their value domains differ (cm vs kg) but pixel positions of major and minor gridlines coincide exactly, and both place the 50th centile at midAge at the same pixel — the canvas vertical centre. This is the alignment that produces the shared diagonal envelope.

**Centile lines:**
- All 9 lines for height in **height-curve colour** (placeholder: `#003078`, existing height-dot navy — Nick is finalising palette via Claude Design; expect this to change).
- All 9 lines for weight in **weight-curve colour** (placeholder: `#8B1A1A`, existing weight-dot burgundy — same caveat).
- Dash pattern: same as Separate (`CENTILE_DASH` set). Same line weight (1.2px).
- 50th NOT emphasised (per CLAUDE.md rule).
- **No right-edge ordinal centile labels** in Combined view (deliberate — keeps charts lighter; the diagonal envelope + colour already encodes which line is which centile and which measurement).
- Define palette as constants at the top of the new rendering block — `HEIGHT_CURVE_COLOR`, `WEIGHT_CURVE_COLOR` — so they can be retuned in one place.

**Dataset boundary handling for 2–9y:** Inside this range, `generateCentileLines` already produces separate segments for `who_child` (≤4y) and `uk90_child` (≥4y). Draw each segment independently — never join across the boundary. This already works correctly in Separate; replicate the same logic.

**Acceptance for Step 1B:**
- Function callable from console: `drawCombinedChart('htCanvas','2-9', getCanvasWidth())` produces a sensible chart.
- 50th-centile height line at age 5.5y crosses the canvas vertical centreline.
- 50th-centile weight line at age 5.5y crosses the same vertical centreline.
- All 9 centile lines for both height and weight are visible without clipping.
- 4y dataset boundary visible as the characteristic step in both height and weight (no smooth join).
- No interactivity wired (clicking does nothing, hovering shows nothing). That is by design.

### Step 1C — Add the Combined / Separate view toggle

Add a new toggle to the chart-toolbar (where Full/Zoom used to live). Two buttons: **Combined** (default active) and **Separate**.

**State:**
- New field `chartState.viewMode: 'combined' | 'separate'`, default `'combined'`.
- Persist via existing `saveState` / `loadState`.

**UI:**
- Place where Full/Zoom buttons were removed.
- Same `.ctrl-btn` styling. Same `active` class convention.
- Function `setViewMode(mode)` updates `chartState.viewMode`, toggles button classes, calls render.

**Routing in `renderBothCharts` (or its replacement):**
- `viewMode === 'combined' && range === '2-9'` → call `drawCombinedChart('htCanvas', '2-9', cw)`. Hide the wt canvas (display:none on `wtBlock`).
- Otherwise (any other range, or `viewMode === 'separate'`) → existing Separate path. Show both canvases.
- For ranges other than 2–9y when `viewMode === 'combined'`: **fall back to Separate silently for Phase 1**, but log a console hint ("Combined view not yet implemented for this range — using Separate"). Don't disable the toggle button; this avoids a feature-flag dance later.

**Acceptance for Step 1C:**
- Default load is Combined / 2–9y → renders the new combined chart.
- Click Separate → reverts to current stacked layout.
- Click Combined → returns to single-canvas dual-axis layout.
- Switch to any other range → silently uses Separate layout regardless of toggle.
- View mode persists across page refresh.

---

## 4. Decisions confirmed by Nick

These resolve the open questions from the original draft. Treat them as binding for Phase 1.

1. **Weight gridline density at 2–9y:** keep 5 kg majors. (Reverts v1.5.1's 2-kg-tall-panel choice for the Combined view only — Separate view stays unchanged.)
2. **Plot gridlines:** ONE shared set of horizontal gridlines that serve both axes simultaneously (see §3 Step 1B alignment algorithm). Compatible with 5 kg + 5 cm majors at 2–9y, with the trade-off that the weight axis may go below 0 — handled by suppressing weight labels in that region.
3. **Centile colour palette:** placeholders `#003078` (height) and `#8B1A1A` (weight) for now. Nick is iterating with Claude Design and will provide final values once all charts render. Define as named constants so swapping is a single-line edit.
4. **Sex accent's new home:** apply at two sites — (a) faint full-canvas background tint at ~3% alpha, (b) UI chrome (toolbar/range button accent, results-panel border). Centile lines are NOT sex-coloured in v2.0. Plotted measurement dots stay sex-neutral for Phase 1; revisit in Phase 3 when dots are wired in.
5. **Right-edge centile labels:** drop them in Combined view to keep charts lighter.

---

## 5. Things explicitly out of scope for Phase 1

Do not do these. They belong to later phases.

- Combined view for any range other than 2–9y.
- Tooltip on Combined view.
- Plotting measurement dots on Combined view (height and weight dots).
- Hit detection on Combined view.
- Pinch-to-zoom (no zoom in v2.0 at all per Nick's instruction).
- OFC, BMI, mid-parental-height target band.
- Print layout adjustments.
- Mobile touch gestures specific to Combined view.
- Updating `CLAUDE.md`, `paedplot_explainer.md`, `paedplot_opus_briefing.md`, `CODEBASE_REFERENCE.md` — leave docs at v1.9 state until Phase 1 ships and Nick reviews. (One exception: when Phase 1 lands, snapshot to `versions/paedplot_v2.0-phase1.html` and add a one-line entry to `README.md`'s version table.)

---

## 6. State / persistence changes

Only one new field:

```javascript
// in chartState
viewMode: 'combined',  // 'combined' | 'separate' — v2.0 Phase 1
```

In `saveState`:
```javascript
viewMode: chartState.viewMode,
```

In `loadState`:
```javascript
if (state.viewMode === 'combined' || state.viewMode === 'separate') {
  chartState.viewMode = state.viewMode;
}
```

Existing v1.9 stored state with `chartZoom` and `panCentre` keys must load cleanly — these keys will simply be ignored (no longer referenced anywhere), and `viewMode` will default to `'combined'` on first restore.

---

## 7. Acceptance criteria for "Phase 1 complete"

Phase 1 is done when **all** of the following are true:

1. ✅ Steps 1A, 1B, 1C all complete and committed separately.
2. ✅ App loads cleanly on a fresh session (no localStorage), defaulting to Combined / 2–9y.
3. ✅ Switching ranges still works for all six (preterm, 0-1, 1-4, 2-9, 9-18, 2-18). Combined view only renders for 2-9y; others silently fall back to Separate.
4. ✅ Sex toggle still works (boys↔girls) and updates the sex-accent tint.
5. ✅ Preterm toggle still works on 0-1y view.
6. ✅ Form data entry, "Plot Charts", and the results panel still work in Separate view (untouched). Combined view shows nothing about measurements — that's expected.
7. ✅ `node --check` on extracted JS passes.
8. ✅ `validation/validate_paedplot.sh` passes if re-run (calculation engine untouched).
9. ✅ Visual sanity check: at 2–9y Combined, 50th-centile height and 50th-centile weight both cross the canvas vertical centre at age 5.5y. Lines for each measurement type colour-distinctly. 4y dataset step visible.
10. ✅ No console errors during normal use. localStorage from v1.9 loads without crashing.
11. ✅ `versions/paedplot_v2.0-phase1.html` snapshot created and committed.
12. ✅ One-line entry added to `README.md` version-history table for v2.0-phase1.

---

## 8. After Phase 1

Don't start Phase 2 without Nick's approval. He will eyeball Combined 2–9y and decide whether the visual approach holds. Likely follow-ups:

- **Phase 2 brief** will cover: Combined view for other ranges, the 0-2w blank region in Combined 0-1y, preterm view in Combined mode, and any colour/density tweaks from Nick's feedback.
- **Phase 3 brief** covers interaction (tooltip, plotting, hit detection). Pinch-zoom/pan deliberately omitted unless Nick requests it.
- **Phases 4–6** unchanged from `CLAUDE.md` roadmap.

End of Phase 1 plan.
