# PaedPlot

Offline single-file HTML tool for plotting UK-WHO paediatric growth charts. Built for mobile-first clinical use on locked-down NHS computers.

Embeds the full UK90/WHO LMS reference dataset (~105KB) with zero external dependencies — works entirely offline from a single `.html` file. Open it in any browser, enter patient data, get centile positions and SDS values immediately.

## Features

- **6 age ranges** — Preterm (23–42w gestation), 0–1y, 1–4y, 2–9y, 9–18y, 2–18y
- **9 UK-WHO centile lines** (0.4th to 99.6th) with sex-specific colouring matching RCPCH paper chart aesthetics
- **SDS (z-score) calculation** validated against the RCPCH Digital Growth Charts API to ±0.001 SDS
- **Gestational correction** for preterm infants (<37 weeks) using UK/RCPCH convention
- **Dedicated preterm chart** (23–42w gestation) with auto-selection for preterm patients
- **Clinical vernacular axis labels** — gestational weeks → postnatal weeks → months, matching how paediatricians talk about infant age
- **Paper-chart-style rendering** — dotted gridlines, dashed/solid centile pattern, cream background, birth centile markers with blank 0–2w region
- **Touch-friendly mobile design** — built for use between clinic appointments on a phone
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

Full audit trail in `docs/VALIDATION_RECORD.md`. Validation script in `validation/validate_paedplot.sh`.

## Architecture

Single HTML file containing embedded CSS, HTML, JavaScript, and LMS reference data. No build step, no bundler, no framework. The JS calculation engine (~200 lines) is cleanly separated from the rendering engine (~500 lines) and UI layer (~800 lines).

Key design decisions documented in `docs/paedplot_opus_briefing.md`. Full technical explanation in `docs/paedplot_explainer.md`. Line-by-line codebase map in `docs/CODEBASE_REFERENCE.md`.

For Claude Code integration, see `CLAUDE.md`.

## Version history

| Version | Summary |
|---|---|
| v1.9 | MIN_PX_PER_SQUARE trim, crossfade range transitions, top-panel age labels |
| v1.8 | Dedicated preterm chart, 0-2w double-line fix, birth centile markers |
| v1.7 | Paper-chart cosmetic redesign (sex-specific centile colours, dotted gridlines, system fonts) |
| v1.6 | 0-1y clinical vernacular axis labels (gestational weeks, postnatal weeks, months) |
| v1.5.5 | Axis gridline/pip model restructure (three-tier: minorGrid/majorGrid/pipOnly) |
| v1.5.4 | Three bug fixes + RCPCH API validation |
| v1.5 | Grid-square geometry migration (true-square panels, paper-chart aspect ratios) |

Version snapshots preserved in `versions/`.

## Roadmap

**v2.0** — Unified single-canvas chart with dual y-axes (height left, weight right). Eliminates triangular dead space by overlaying both measurement types on one chart. Pinch-to-zoom replacing the current binary zoom toggle. OFC, BMI, and mid-parental height as clinical add-ons. See `CLAUDE.md` for the detailed phased plan.

## Disclaimer

PaedPlot is a personal clinical reference tool. It is **not a medical device** and has not been through any regulatory approval process. It should not be used as the sole basis for clinical decisions. Always verify growth assessments against official charts and clinical judgement.

## Licence

Personal use. Not currently open-source.
