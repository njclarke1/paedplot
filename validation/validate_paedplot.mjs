#!/usr/bin/env node
// PaedPlot validation against RCPCH Digital Growth Charts API — Node version
// ===========================================================================
// Same 12-case set as validate_paedplot.sh, but with two improvements:
//   1. No jq dependency — plain Node (>= 18, for built-in fetch).
//   2. PaedPlot SDS values are computed LIVE from the engine embedded in
//      ../src/paedplot.html, not hardcoded — so this validates whatever
//      build is currently in src/, automatically.
//
// USAGE:
//   export RCPCH_API_KEY="your-key-here"     (PowerShell: $env:RCPCH_API_KEY="...")
//   node validation/validate_paedplot.mjs
//
// Your API key never leaves this script — it goes only to api.rcpch.ac.uk.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const API_URL = 'https://api.rcpch.ac.uk/growth/v1/uk-who/calculation';
const TOLERANCE = 0.05;

const API_KEY = process.env.RCPCH_API_KEY;
if (!API_KEY) {
  console.error('ERROR: RCPCH_API_KEY env var not set.');
  console.error('  bash:       export RCPCH_API_KEY="your-key-here"');
  console.error('  PowerShell: $env:RCPCH_API_KEY="your-key-here"');
  process.exit(1);
}

// ── Load the PaedPlot calculation engine from the live HTML ────────────────
const htmlPath = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'paedplot.html');
const html = readFileSync(htmlPath, 'utf8');
const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)];
const lmsJson = scripts[0][1];                       // <script id="lms-data">
let engineJs = scripts[scripts.length - 1][1];        // main <script>
engineJs = engineJs.slice(0, engineJs.indexOf('(function init()')); // drop DOM bootstrap

const sandbox = new Function(
  'document',
  '"use strict";' + engineJs + '\nreturn { calculateMeasurement };'
);
const { calculateMeasurement } = sandbox({
  getElementById: () => ({ textContent: lmsJson }),
  // applySexTheme guards on document.body being falsy
  body: null,
});

// ── Test cases (identical to validate_paedplot.sh) ─────────────────────────
// Dates pinned to reference date 2026-04-21 so corrected ages match the
// documented audit cases in docs/VALIDATION_RECORD.md.
const CASES = [
  // name,               sex,      gw, gd, birth,        obs,          wt,   ht
  ['C01 30+0 corr -8w',  'male',   30, 0, '2026-04-07', '2026-04-21', 1.4,  40],
  ['C02 36+0 corr -2w',  'male',   36, 0, '2026-04-07', '2026-04-21', 2.5,  47],
  ['C03 28+0 corr -4w',  'male',   28, 0, '2026-02-24', '2026-04-21', 1.9,  43],
  ['C04 term 0d',        'male',   40, 0, '2026-04-21', '2026-04-21', 3.5,  50],
  ['C05 6m',             'male',   40, 0, '2025-10-21', '2026-04-21', 7.8,  67],
  ['C06 3y',             'male',   40, 0, '2023-04-21', '2026-04-21', 14.5, 96],
  ['C07 2y boundary',    'male',   40, 0, '2024-04-21', '2026-04-21', 12.5, 88],
  ['C08 4y boundary',    'male',   40, 0, '2022-04-21', '2026-04-21', 16.5, 102],
  ['C09 8y',             'male',   40, 0, '2018-04-21', '2026-04-21', 26,   128],
  ['C10 14y',            'male',   40, 0, '2012-04-21', '2026-04-21', 55,   165],
  ['C11 8y low wt',      'male',   40, 0, '2018-04-21', '2026-04-21', 18,   125],
  ['C12 8y high wt',     'female', 40, 0, '2018-04-21', '2026-04-21', 40,   130],
];

async function callApi(birth, obs, value, sex, gw, gd, method) {
  const res = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'Subscription-Key': API_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      birth_date: birth,
      observation_date: obs,
      observation_value: value,
      sex,
      gestation_weeks: gw,
      gestation_days: gd,
      measurement_method: method,
    }),
  });
  if (!res.ok) return { error: `HTTP ${res.status}: ${(await res.text()).slice(0, 200)}` };
  const json = await res.json();
  const v = json?.measurement_calculated_values;
  const sds = v?.corrected_sds ?? v?.chronological_sds;
  if (sds == null) return { error: 'no sds in response: ' + JSON.stringify(json).slice(0, 200) };
  return { sds };
}

function fmt(x, w = 9) { return String(x).padStart(w); }

console.log('PaedPlot → RCPCH API validation (engine read live from src/paedplot.html)');
console.log(`Tolerance: ±${TOLERANCE} SDS`);
console.log(`API: ${API_URL}\n`);
console.log(
  'case'.padEnd(22) + ' |' + fmt('wt PP', 8) + ' |' + fmt('wt RCPCH', 9) + ' |' + fmt('wt Δ', 7) +
  ' |' + fmt('ht PP', 8) + ' |' + fmt('ht RCPCH', 9) + ' |' + fmt('ht Δ', 7) + ' | result'
);
console.log('─'.repeat(100));

let pass = 0, fail = 0;
const failedCases = [];

for (const [name, sex, gw, gd, birth, obs, wt, ht] of CASES) {
  const ppWt = calculateMeasurement(birth, obs, gw, gd, sex, 'weight', wt);
  const ppHt = calculateMeasurement(birth, obs, gw, gd, sex, 'height', ht);
  const rcWt = await callApi(birth, obs, wt, sex, gw, gd, 'weight');
  const rcHt = await callApi(birth, obs, ht, sex, gw, gd, 'height');

  function check(pp, rc) {
    if (!pp || rc.error) return { ok: false, delta: '--', rcS: rc.error ? 'ERR' : '?' };
    const delta = pp.sds - rc.sds;
    return { ok: Math.abs(delta) <= TOLERANCE, delta: delta.toFixed(3), rcS: rc.sds.toFixed(3) };
  }
  const w = check(ppWt, rcWt);
  const h = check(ppHt, rcHt);
  const ok = w.ok && h.ok;
  ok ? pass++ : (fail++, failedCases.push(`${name} (wt:${w.ok ? 'PASS' : 'FAIL'} ht:${h.ok ? 'PASS' : 'FAIL'})`));

  console.log(
    name.padEnd(22) + ' |' + fmt(ppWt ? ppWt.sds.toFixed(3) : 'NULL', 8) + ' |' + fmt(w.rcS, 9) +
    ' |' + fmt(w.delta, 7) + ' |' + fmt(ppHt ? ppHt.sds.toFixed(3) : 'NULL', 8) + ' |' + fmt(h.rcS, 9) +
    ' |' + fmt(h.delta, 7) + ' | ' + (ok ? 'OK' : 'FAIL')
  );
  if (rcWt.error) console.log(`    wt error: ${rcWt.error}`);
  if (rcHt.error) console.log(`    ht error: ${rcHt.error}`);
}

console.log(`\nSummary: ${pass} passed, ${fail} failed (of ${CASES.length} cases)`);
if (failedCases.length) {
  console.log('\nFailed cases:');
  for (const c of failedCases) console.log('  - ' + c);
  process.exit(1);
}
