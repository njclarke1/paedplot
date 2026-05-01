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
- **Two y-axes:**
  - **Left (height, cm):** ticks/labels every `Y_GRID_SPEC['2-9'].height.major` (5 cm). Minor gridlines every `Y_GRID_SPEC['2-9'].height.minor` (1 cm) — but only if `pxPerSquare ≥ 14`, else minors are pip-only on the axis strip.
  - **Right (weight, kg):** ticks/labels every `Y_GRID_SPEC['2-9'].weight.major` (5 kg with current setting, 2 kg if you want to keep the v1.5.1 readability bias — flag this to Nick before deciding). Right-aligned labels.
- **Plot-area gridlines: HEIGHT axis only.** (Single set of horizontal gridlines for clarity. Weight ticks live as labels and a short tick mark on the right axis strip but DO NOT draw across the plot.) Mark this as a Phase-1 design decision — Nick will eyeball and may ask for both sets.
- Background: same cream `#FFFDF0` as paper-chart current.
- Sex-accent tint (`#68A1C5` boys, `#C16B86` girls) reduces to ~3% alpha as a faint full-canvas background tint, replacing its previous role on centile lines.

**Y-axis alignment algorithm:**
```
Given range '2-9':
  ageMin = 2.0, ageMax = 9.0
  midAge = (ageMin + ageMax) / 2 = 5.5

For each measurement type m in {'height','weight'}:
  centileData_m = centile cache for m (from generateCentileLines)
  Find LMS at midAge using lookupLMS(m, sex, midAge)
  midVal_m = M (the M parameter at midAge)

  Compute data envelope across the visible age range:
    vMin_m = min over centileData[0.4th] across ages
    vMax_m = max over centileData[99.6th] across ages
    Optionally pad by 0.5 × Y_GRID_SPEC.major

  half_m = max(vMax_m - midVal_m, midVal_m - vMin_m)
  Round half_m UP to the nearest multiple of Y_GRID_SPEC[range][m].major.
  yMin_m = midVal_m - half_m
  yMax_m = midVal_m + half_m
  (For weight, floor yMin at 0 — never negative.)

  Build linear map: pixel_y = top + (yMax_m - val) / (yMax_m - yMin_m) * plotH
  At val = midVal_m, pixel_y = top + plotH/2 ✓ (canvas vertical centre)
```

The two maps are independent. Their domains differ (cm vs kg), but both place the 50th centile at midAge at the same pixel — the canvas vertical centre. This is the alignment that produces the shared diagonal envelope.

**Centile lines:**
- All 9 lines for height in **height-curve colour** (suggest `#003078` — the existing height-dot navy).
- All 9 lines for weight in **weight-curve colour** (suggest `#8B1A1A` — the existing weight-dot burgundy).
- Dash pattern: same as Separate (`CENTILE_DASH` set). Same line weight (1.2px).
- 50th NOT emphasised (per CLAUDE.md rule).
- Right-edge labels: small ordinal centile labels at the right end of each line, in matching colour. Height labels live just inside the right margin's left edge; weight labels sit in the right margin proper. Don't let them collide — if they would, drop the weight labels for this Phase.

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

## 4. Things to flag to Nick before implementing

Open questions worth a short message before you start, even if you have an opinion:

1. **Weight gridline density at 2–9y in Combined view.** Y_GRID_SPEC currently says major 5 kg, but v1.5.1 deliberately made the Separate weight panel taller with 2 kg squares for readability. In Combined view, do we want 5 kg or 2 kg majors on the right axis?
2. **Height-only vs both-y-axes plot gridlines.** The plan says height-axis gridlines only run across the plot. If Nick wants paper-chart-faithful both-axis horizontal gridlines, that's a small change but visually busier.
3. **Centile colour palette.** Suggested `#003078` (height) and `#8B1A1A` (weight) — these are the existing measurement-dot colours. Worth confirming, since this is the v2.0 visual identity.
4. **Sex accent at 3% alpha as background tint** — confirm or veto. The v1.7 spec moved sex accent OUT of centile lines; v2.0 needs to give it a new home.
5. **Right-edge centile labels** — keep them in Combined view, or drop entirely (the diagonal envelope already encodes which line is which centile, and the colour says which measurement). Lighter charts may be preferable.

If Nick has not answered, default to the values stated in §3 Step 1B.

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
