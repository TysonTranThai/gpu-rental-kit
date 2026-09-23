#!/usr/bin/env bash
# =============================================================================
# test_progress_bar.sh — setup.sh stage progress bar (% remaining)
# =============================================================================
# Covers scripts/progress.sh (show_progress / finish_progress) and its wiring
# in setup.sh: exact ASCII rendering, percentage math, input sanitization
# (malformed/out-of-range args must never crash set -Eeuo pipefail), and the
# tr-shadow safety rule (progress.sh must never define or call tr).
# All assertions capture output via command substitution, so stdout is never a
# TTY inside the test — the ASCII fallback path is exercised deterministically.
# =============================================================================

TEST_NAME="progress_bar"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

# shellcheck source=/dev/null
source "${KIT_ROOT}/scripts/progress.sh"
# A developer shell must never leak a clock into these assertions.
unset PROGRESS_START_EPOCH || true

# --- 1. ASCII rendering (non-TTY fallback) ------------------------------------
out="$(show_progress 0 15)"
assert_eq "  [------------------------]   0%" "${out}" "show_progress 0 15 renders an empty ASCII bar at 0%"

out="$(show_progress 15 15)"
assert_eq "  [########################] 100%" "${out}" "show_progress 15 15 renders a full ASCII bar at 100%"

# --- 2. Percentage math --------------------------------------------------------
out="$(show_progress 5 15)"
assert_eq "  [########----------------]  33%" "${out}" "show_progress 5 15 fills 8/24 cells at 33%"

out="$(show_progress 2 3)"
assert_eq "  [################--------]  66%" "${out}" "show_progress 2 3 fills 16/24 cells at 66%"

# --- 3. No unicode blocks or ANSI colors in non-TTY output ---------------------
assert_fail "no unicode blocks outside TTY" grep -q $'\u2588' <(show_progress 7 15)
assert_fail "no ANSI escapes outside TTY" grep -q $'\033' <(show_progress 7 15)

# --- 4. Sanitization: hostile args never crash set -Eeuo pipefail --------------
assert_ok "octal-ish '08' is treated as decimal" bash -c "source '${KIT_ROOT}/scripts/progress.sh'; show_progress 08 15 >/dev/null"
assert_ok "non-numeric arg falls back to 0" bash -c "source '${KIT_ROOT}/scripts/progress.sh'; show_progress abc 15 >/dev/null"
assert_ok "done > total clamps to 100%" bash -c "source '${KIT_ROOT}/scripts/progress.sh'; show_progress 20 15 >/dev/null"
assert_ok "total 0 does not divide by zero" bash -c "source '${KIT_ROOT}/scripts/progress.sh'; show_progress 5 0 >/dev/null"
out="$(show_progress 20 15)"
assert_eq "  [########################] 100%" "${out}" "clamped done > total renders 100%"
out="$(show_progress 5 0)"
assert_eq "  [########################] 100%" "${out}" "total 0 sanitizes to 1, done clamps to it (100%, no crash)"

# --- 5. finish_progress is the 100% line ---------------------------------------
out="$(finish_progress)"
assert_eq "  [########################] 100%" "${out}" "finish_progress renders the 100% bar"

# --- 5b. Elapsed-time clock (PROGRESS_START_EPOCH) ------------------------------
# No clock set: bars render without any suffix.
out="$(show_progress 5 15)"
assert_ok "unset clock renders no suffix" bash -c '[[ "${1}" != *"("* ]]' _ "${out}"

# Invalid / hostile clock values degrade to no suffix, never a crash.
for bad in banana '' 2026-09-19 "1e9"; do
    out="$(PROGRESS_START_EPOCH="${bad}" show_progress 5 15)"
    assert_ok "clock '${bad}' renders no suffix" bash -c '[[ "${1}" != *"("* ]]' _ "${out}"
done

# Backwards clock step (NTP): no suffix.
out="$(PROGRESS_START_EPOCH="$(($(date +%s) + 500))" show_progress 5 15)"
assert_ok "future epoch (clock stepped back) renders no suffix" bash -c '[[ "${1}" != *"("* ]]' _ "${out}"

# ~130s elapsed renders a (2m NNs) suffix; ±1s second-boundary race tolerated.
out="$(PROGRESS_START_EPOCH="$(($(date +%s) - 130))" show_progress 3 15)"
assert_ok "130s elapsed renders a (2m NNs) suffix" bash -c '[[ "${1}" =~ \ \(2m\ [0-9][0-9]s\)$ ]]' _ "${out}"
assert_contains "${out}" "20% (2m" "elapsed suffix follows the percentage"

# ~3723s elapsed renders (1h 02m NNs).
out="$(PROGRESS_START_EPOCH="$(($(date +%s) - 3723))" show_progress 5 15)"
assert_ok "3723s elapsed renders a (1h 02m NNs) suffix" bash -c '[[ "${1}" =~ \ \(1h\ 02m\ [0-9][0-9]s\)$ ]]' _ "${out}"

# --- 6. setup.sh wiring: bar under every stage header --------------------------
n="$(grep -cE '^show_progress [0-9]+ 15$' "${KIT_ROOT}/setup.sh")"
assert_eq "15" "${n}" "setup.sh calls show_progress under all 15 stage headers"

wiring_ok="yes"
for i in 1 2 3 4 5 6 7 8 9 11 12 13 14 15; do
    want=$(( i - 1 ))
    if ! grep -A1 "\[${i}/15\]" "${KIT_ROOT}/setup.sh" | grep -q "^show_progress ${want} 15$"; then
        wiring_ok="no (stage $i)"
        break
    fi
done
assert_eq "yes" "${wiring_ok}" "each [N/15] header is immediately followed by show_progress N-1 15"

# Stage 10 is the confirm banner (no [10/15] header): bar follows the banner box.
if grep -A3 'tr STAGE_CONFIRM)' "${KIT_ROOT}/setup.sh" | grep -q '^show_progress 9 15$'; then
    assert_ok "stage 10 (confirm banner) is followed by show_progress 9 15" true
else
    assert_fail "stage 10 (confirm banner) is followed by show_progress 9 15" false
fi

assert_ok "setup.sh calls finish_progress after the final stage" grep -q "finish_progress" "${KIT_ROOT}/setup.sh"
assert_ok "setup.sh sources scripts/progress.sh" grep -q 'scripts/progress.sh' "${KIT_ROOT}/setup.sh"
assert_ok "setup.sh starts the elapsed clock (PROGRESS_START_EPOCH)" grep -q 'PROGRESS_START_EPOCH="\$(date +%s)"' "${KIT_ROOT}/setup.sh"

# --- 7. tr-shadow safety: progress.sh must not define or call tr ---------------
assert_fail "progress.sh contains no tr call (tr-shadow rule)" grep -E '(^|[^a-zA-Z_])tr[[:space:]]' "${KIT_ROOT}/scripts/progress.sh"
declare -F tr >/dev/null 2>&1 && had_tr_fn="yes" || had_tr_fn="no"
source "${KIT_ROOT}/scripts/progress.sh"
declare -F tr >/dev/null 2>&1 && has_tr_fn="yes" || has_tr_fn="no"
assert_eq "${had_tr_fn}" "${has_tr_fn}" "sourcing progress.sh never defines a tr function"

report_results
