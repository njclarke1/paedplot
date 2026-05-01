#!/data/data/com.termux/files/usr/bin/bash
#
# PaedPlot validation against RCPCH API
# ======================================
# Targeted 12-case set covering audit concerns:
#   - Preterm dataset boundary (cases 1, 2, 3)
#   - Term newborn at uk90_preterm/who_infant boundary (case 4)
#   - WHO infant (case 5)
#   - WHO child (case 6)
#   - 2y boundary lying→standing (case 7)
#   - 4y WHO→UK90 boundary (case 8)
#   - UK90 child interior (case 9)
#   - Adolescent uk90_child (case 10)
#   - Extreme low SDS (case 11)
#   - Extreme high SDS (case 12)
#
# USAGE:
#   1. Install jq:   pkg install curl jq
#   2. Set your key: export RCPCH_API_KEY="your-key-here"
#   3. Run:          bash validate_paedplot.sh
#
# The script prints, for each case:
#   - PaedPlot SDS (height + weight) — what our app computes
#   - RCPCH SDS   (height + weight) — what the official API returns
#   - Delta       — should be within ±0.05 to pass
#
# At the end, a summary tells you how many passed / failed.
# Your API key never leaves the script — it goes only to api.rcpch.ac.uk.

set -e

# ──────────────────────────────────────────────────────────────────────────────
# Pre-flight checks
# ──────────────────────────────────────────────────────────────────────────────

if [ -z "$RCPCH_API_KEY" ]; then
  echo "ERROR: RCPCH_API_KEY env var not set."
  echo "Run:  export RCPCH_API_KEY=\"your-key-here\""
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl not found.  Run:  pkg install curl"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found.  Run:  pkg install jq"
  exit 1
fi

API_URL="https://api.rcpch.ac.uk/growth/v1/uk-who/calculation"
TOLERANCE=0.05

# ──────────────────────────────────────────────────────────────────────────────
# Test cases
# Format: name|sex|gw|gd|birth_date|obs_date|wt|ht|paedplot_wt_sds|paedplot_ht_sds
# Dates picked so that on obs_date the corrected age matches the audit case.
# Reference date = 2026-04-21.
# paedplot_wt_sds and paedplot_ht_sds are what our app v1.5.4 currently outputs.
# ──────────────────────────────────────────────────────────────────────────────

CASES=(
  # ── Preterm — these test the uk90_preterm dataset ──
  # 30+0 baby born 2026-04-07, observed 2026-04-21 → chronological 2w, corrected -8w → preterm dataset
  "C01 30+0 corr -8w|male|30|0|2026-04-07|2026-04-21|1.4|40|-1.241|-1.046"
  # 36+0 baby born 2026-04-07, observed 2026-04-21 → chronological 2w, corrected -2w → preterm dataset (just inside)
  "C02 36+0 corr -2w|male|36|0|2026-04-07|2026-04-21|2.5|47|-1.527|-1.034"
  # 28+0 baby born 2026-02-24, observed 2026-04-21 → chronological 8w, corrected -4w → preterm dataset
  "C03 28+0 corr -4w|male|28|0|2026-02-24|2026-04-21|1.9|43|-1.944|-1.831"

  # ── Term newborn at uk90_preterm/who_infant boundary ──
  "C04 term 0d|male|40|0|2026-04-21|2026-04-21|3.5|50|-0.121|-0.442"

  # ── WHO infant interior (6m) ──
  "C05 6m|male|40|0|2025-10-21|2026-04-21|7.8|67|-0.146|-0.276"

  # ── WHO child interior (3y) ──
  "C06 3y|male|40|0|2023-04-21|2026-04-21|14.5|96|0.089|-0.024"

  # ── 2y boundary (lying→standing) ──
  "C07 2y boundary|male|40|0|2024-04-21|2026-04-21|12.5|88|0.250|0.065"

  # ── 4y boundary (WHO→UK90) ──
  "C08 4y boundary|male|40|0|2022-04-21|2026-04-21|16.5|102|-0.027|-0.119"

  # ── UK90 child interior (8y) ──
  "C09 8y|male|40|0|2018-04-21|2026-04-21|26|128|0.098|0.027"

  # ── Adolescent (14y) ──
  "C10 14y|male|40|0|2012-04-21|2026-04-21|55|165|0.599|0.319"

  # ── Extreme low SDS (8y boy, 18kg) ──
  "C11 8y low wt|male|40|0|2018-04-21|2026-04-21|18|125|-2.922|-0.520"

  # ── Extreme high SDS (8y girl, 40kg) ──
  "C12 8y high wt|female|40|0|2018-04-21|2026-04-21|40|130|2.262|0.486"
)

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

# Make one API call and extract the SDS for the result.
# Args: birth_date observation_date observation_value sex gw gd method
# Echoes the SDS as a decimal number (or "ERROR: ..." string)
call_api() {
  local birth="$1" obs="$2" val="$3" sex="$4" gw="$5" gd="$6" method="$7"
  local payload
  payload=$(cat <<EOF
{
  "birth_date": "$birth",
  "observation_date": "$obs",
  "observation_value": $val,
  "sex": "$sex",
  "gestation_weeks": $gw,
  "gestation_days": $gd,
  "measurement_method": "$method"
}
EOF
)
  local response
  response=$(curl -s -X POST "$API_URL" \
    -H "Subscription-Key: $RCPCH_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload")

  # If response empty or contains an error, surface it.
  if [ -z "$response" ]; then
    echo "ERROR: empty response"
    return
  fi

  # The RCPCH response structure: measurement_calculated_values.corrected_sds (or chronological_sds)
  # We use corrected_sds — that's what PaedPlot uses too.
  local sds
  sds=$(echo "$response" | jq -r '.measurement_calculated_values.corrected_sds // empty' 2>/dev/null)

  if [ -z "$sds" ] || [ "$sds" = "null" ]; then
    # Fallback: try chronological_sds if corrected isn't present
    sds=$(echo "$response" | jq -r '.measurement_calculated_values.chronological_sds // empty' 2>/dev/null)
  fi

  if [ -z "$sds" ] || [ "$sds" = "null" ]; then
    # Surface the error message if structure differs
    local err
    err=$(echo "$response" | jq -r '. | tostring' 2>/dev/null | head -c 200)
    echo "ERROR: no sds in response — first 200 chars: $err"
    return
  fi

  echo "$sds"
}

# Compare two floats within a tolerance. Returns "PASS" or "FAIL".
# Args: paedplot_sds rcpch_sds
compare() {
  local a="$1" b="$2"
  if [[ "$b" == ERROR* ]]; then
    echo "FAIL"
    return
  fi
  local result
  result=$(awk -v a="$a" -v b="$b" -v t="$TOLERANCE" 'BEGIN {
    diff = a - b; if (diff < 0) diff = -diff;
    print (diff <= t) ? "PASS" : "FAIL"
  }')
  echo "$result"
}

# ──────────────────────────────────────────────────────────────────────────────
# Run cases
# ──────────────────────────────────────────────────────────────────────────────

echo "PaedPlot v1.5.4 → RCPCH API validation"
echo "Tolerance: ±$TOLERANCE SDS"
echo "API: $API_URL"
echo ""
printf "%-22s | %-9s | %-9s | %-9s | %-9s | %-9s | %-9s | %s\n" \
  "case" "wt PaedPlot" "wt RCPCH" "wt Δ" "ht PaedPlot" "ht RCPCH" "ht Δ" "result"
echo "──────────────────────────────────────────────────────────────────────────────────────────────────────────────"

pass=0; fail=0
failed_cases=()

for spec in "${CASES[@]}"; do
  IFS='|' read -r name sex gw gd birth obs wt ht pp_wt pp_ht <<< "$spec"

  rcpch_wt=$(call_api "$birth" "$obs" "$wt" "$sex" "$gw" "$gd" "weight")
  rcpch_ht=$(call_api "$birth" "$obs" "$ht" "$sex" "$gw" "$gd" "height")

  wt_result=$(compare "$pp_wt" "$rcpch_wt")
  ht_result=$(compare "$pp_ht" "$rcpch_ht")

  # Compute deltas if numeric
  wt_delta="--"
  ht_delta="--"
  if [[ "$rcpch_wt" != ERROR* ]]; then
    wt_delta=$(awk -v a="$pp_wt" -v b="$rcpch_wt" 'BEGIN { printf "%.3f", a - b }')
  fi
  if [[ "$rcpch_ht" != ERROR* ]]; then
    ht_delta=$(awk -v a="$pp_ht" -v b="$rcpch_ht" 'BEGIN { printf "%.3f", a - b }')
  fi

  # Truncate ERROR messages for display
  display_rcpch_wt="$rcpch_wt"
  display_rcpch_ht="$rcpch_ht"
  if [[ "$rcpch_wt" == ERROR* ]]; then display_rcpch_wt="ERR"; fi
  if [[ "$rcpch_ht" == ERROR* ]]; then display_rcpch_ht="ERR"; fi

  combined="OK"
  if [ "$wt_result" = "FAIL" ] || [ "$ht_result" = "FAIL" ]; then
    combined="FAIL"
    fail=$((fail+1))
    failed_cases+=("$name (wt:$wt_result ht:$ht_result)")
  else
    pass=$((pass+1))
  fi

  printf "%-22s | %9s | %9s | %9s | %9s | %9s | %9s | %s\n" \
    "$name" "$pp_wt" "$display_rcpch_wt" "$wt_delta" "$pp_ht" "$display_rcpch_ht" "$ht_delta" "$combined"
done

echo ""
echo "Summary: $pass passed, $fail failed (of ${#CASES[@]} cases)"

if [ "$fail" -gt 0 ]; then
  echo ""
  echo "Failed cases:"
  for c in "${failed_cases[@]}"; do
    echo "  - $c"
  done
fi

# Also dump full JSON of any failure for debugging — saved to file for inspection
if [ "$fail" -gt 0 ]; then
  echo ""
  echo "For deeper investigation of failures, you can re-run a single case manually with:"
  echo ""
  echo '  curl -s -X POST "https://api.rcpch.ac.uk/growth/v1/uk-who/calculation" \'
  echo '    -H "Subscription-Key: $RCPCH_API_KEY" \'
  echo '    -H "Content-Type: application/json" \'
  echo "    -d '<payload>' | jq"
  echo ""
fi
