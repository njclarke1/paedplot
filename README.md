# PaedPlot

Offline single-file HTML tool for plotting UK-WHO paediatric growth charts. Built for mobile-first clinical use on locked-down NHS computers.

**Live preview:** https://njclarke1.github.io/paedplot/ — no install, runs entirely in your browser. Try the Dev modal (bottom of the sidebar) for one-tap sample patients covering every age range.

Embeds the full UK90/WHO LMS reference dataset (~105KB) with zero external dependencies — works entirely offline from a single `.html` file. Open it in any browser, enter patient data, get centile positions and SDS values immediately.

## Features

- **6 age ranges** — Preterm (23–42w gestation), 0–1y, 1–4y, 2–9y, 9–18y, 2–18y
- **9 UK-WHO centile lines** (0.4th to 99.6th) with sex-specific colouring matching RCPCH paper chart aesthetics
- **SDS (z-score) calculation** validated against the RCPCH Digital Growth Charts API to ±0.001 SDS
- **Gestational correction** for preterm infants (<37 weeks) using UK/RCPCH convention
- **Dedicated preterm chart** (23–42w gestation) with auto-selection for preterm patients
- **Clinical vernacular axis labels** — gestational weeks → postnatal weeks → months, matching how paediatricians talk about infant age
- **Paper-chart-style rendering** — solid light-grey gridlines with the printed charts' thick/thin hierarchy and per-range intervals, dashed/solid centile pattern, birth centile markers with blank 0–2w region, grid proportions calibrated against the RCPCH chart PDFs (one grid square is always a true pixel square)
- **Touch-friendly mobile design** — on phones the chart fills the screen width exactly, with a **1×/2×/3× zoom** (sharp re-render at an exact multiple of the grid, never blurry scaling) for interrogating growth trends on a small screen; sticky age and kg/cm axes stay visible while panning, and a floating thumb-reachable zoom control follows you down the chart
- **Fit width / Fit page viewing modes** on desktop — fill the window like a PDF viewer, or shrink the whole chart into one screenful
- **Session persistence** via localStorage — data survives page refresh
- **Zero dependencies, zero network, zero install** — download one HTML file and open it

## Quick start

1. Download `src/paedplot.html`
2. Open in any web browser (Chrome, Safari, Firefox — desktop or mobile)
3. Enter patient details (sex, DOB, gestation)
4. Add measurements (date, height, weight)
5. Tap "Plot Charts"

No server, no internet, no account required.

## Validation

The calculation engine was formally validated against the live RCPCH Digital Growth Charts API in April 2026. A 12-case targeted suite covering every LMS dataset (uk90_preterm, who_infant, who_child, uk90_child), every dataset boundary (2y lying-to-standing, 4y WHO-to-UK90), gestational correction (30+0, 36+0, 28+0), and extreme centile positions — all 24 SDS measurements agreed with the API to better than ±0.001 SDS, two orders of magnitude tighter than the ±0.05 pass criterion.

Full audit trail in `docs/VALIDATION_RECORD.md`. Validation script in `validation/validate_paedplot.mjs` (Node ≥18, no dependencies; requires an RCPCH API key in the `RCPCH_API_KEY` environment variable). A June 2026 audit confirmed the calculation engine and LMS data remain byte-identical to the validated build.

## Architecture

Single HTML file containing embedded CSS, HTML, JavaScript, and LMS reference data (plus the Hind typeface as base64 WOFF2). No build step, no bundler, no framework. The JS calculation engine (~200 lines, unchanged since validation) is cleanly separated from the canvas rendering engine and UI layer.

Key design decisions documented in `docs/archive/paedplot_opus_briefing.md`. Full technical explanation in `docs/archive/paedplot_explainer.md`. Line-by-line codebase map in `docs/archive/CODEBASE_REFERENCE.md`. (These three describe the v1.9 architecture and are archived pending a refresh — the current architecture summary lives in `CLAUDE.md`.)

## Version history

| Version | Summary |
|---|---|
| v2.5 (current) | Mobile-zoom release: solid paper-matched gridlines (thick/thin hierarchy), phones always render flush fit-width, 1×/2×/3× square-preserving zoom with sticky kg/cm axis and floating zoom control, tightened axis gutters with inline unit captions, horizontal touch panning, paper-matched "length"/"height" wording on infant ranges |
| v2.4 | Document-viewer layout: fit-width Paper mode, Combined/Weight/Height selector, sticky age axis, results-panel docking |
| v2.3 | Fit width / Fit page zoom modes; grid proportions recalibrated against the printed RCPCH charts |
| v2.2 | Viewport-fit chart sizing — whole chart visible in one screenful across screen sizes |
| v2.1 | Embedded Hind font, new boys/girls palette, table styling; audit fixes (range persistence, preterm toggle visibility, edge-label filtering) |
| v2.0-phase2 | Combined view for all ranges, tuned scale ratios, sex-specific anchors, girls 2–8y/8–18y split, dual y-axis labels |
| v2.0-phase1 | Combined view (2–9y): single canvas, dual y-axes, shared gridlines, zoom removed |
| v1.9 | MIN_PX_PER_SQUARE trim, crossfade range transitions, top-panel age labels |
| v1.8 | Dedicated preterm chart, 0-2w double-line fix, birth centile markers |
| v1.7 | Paper-chart cosmetic redesign (sex-specific centile colours, dotted gridlines, system fonts) |
| v1.6 | 0-1y clinical vernacular axis labels (gestational weeks, postnatal weeks, months) |
| v1.5.5 | Axis gridline/pip model restructure (three-tier: minorGrid/majorGrid/pipOnly) |
| v1.5.4 | Three bug fixes + RCPCH API validation |
| v1.5 | Grid-square geometry migration (true-square panels, paper-chart aspect ratios) |

Version snapshots preserved in `versions/`.

## Roadmap

The unified single-canvas chart (dual y-axes, height left / weight right) shipped across v2.0–v2.4. Still to come: OFC (head circumference) as a third curve set, BMI, mid-parental height target band, a dedicated print-layout pass, and re-validation against the RCPCH API. See `CLAUDE.md` for the detailed plan.

## Disclaimer

PaedPlot is a personal clinical reference tool. It is **not a medical device** and has not been through any regulatory approval process. It should not be used as the sole basis for clinical decisions. Always verify growth assessments against official charts and clinical judgement.

## Licence

Personal use. Not currently open-source.
