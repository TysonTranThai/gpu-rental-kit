#!/usr/bin/env bash
# =============================================================================
# report_lib.sh — shared helpers for test reports
# =============================================================================
# Provides counters, PASS/FAIL/SKIP/WARN accounting, and per-component result
# files that run_all.sh aggregates into final-report.txt.
#
# When REPORT_FILE is set, every report_* line is teed to that file as well
# as the terminal.
#
# Usage:
#   source test/report_lib.sh
#   report_init "local"
#   REPORT_FILE="test/results/gpu-matrix-report.txt"
#   report_pass "something worked"
#   report_fail "command" "detail"
#   report_skip "needs a GPU"
#   report_warn "shellcheck not installed"
#   report_summary
# =============================================================================
set -Eeuo pipefail

REPORT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${REPORT_ROOT}/results"
mkdir -p "${RESULTS_DIR}"

COMPONENT=""
REPORT_FILE=""
PASS_N=0
FAIL_N=0
SKIP_N=0
WARN_N=0

report_init() {
    COMPONENT="$1"
    PASS_N=0; FAIL_N=0; SKIP_N=0; WARN_N=0
    # Truncate the report file so re-runs never append to stale output.
    if [[ -n "${REPORT_FILE}" ]]; then
        : > "${REPORT_FILE}"
    fi
}

# report_out — print a line to terminal and (if set) append to REPORT_FILE
report_out() {
    if [[ -n "${REPORT_FILE}" ]]; then
        echo "$*" | tee -a "${REPORT_FILE}"
    else
        echo "$*"
    fi
}

report_pass() { PASS_N=$((PASS_N + 1)); report_out "  [PASS] $*"; }
report_fail() { FAIL_N=$((FAIL_N + 1)); report_out "  [FAIL] $*"; }
report_skip() { SKIP_N=$((SKIP_N + 1)); report_out "  [SKIP] $*"; }
report_warn() { WARN_N=$((WARN_N + 1)); report_out "  [WARN] $*"; }

report_section() {
    report_out ""
    report_out "──────────────────────────────────────────────────────────"
    report_out "  $*"
    report_out "──────────────────────────────────────────────────────────"
}

# write_counts <component> — persist counts for final-report aggregation
write_counts() {
    local component="${1:-${COMPONENT}}"
    local counts_file="${RESULTS_DIR}/.counts/${component}.txt"
    mkdir -p "$(dirname "${counts_file}")"
    {
        echo "PASSED ${PASS_N}"
        echo "FAILED ${FAIL_N}"
        echo "SKIPPED ${SKIP_N}"
        echo "WARNINGS ${WARN_N}"
    } > "${counts_file}"
}

# read_counts <component> <field> — read one field from a counts file
read_counts() {
    local component="$1" field="$2"
    local counts_file="${RESULTS_DIR}/.counts/${component}.txt"
    [[ -f "${counts_file}" ]] || { echo 0; return; }
    awk -v f="${field}" '$1 == f { print $2 }' "${counts_file}"
}

report_summary() {
    report_out ""
    report_out "  Summary: ${PASS_N} passed, ${FAIL_N} failed, ${SKIP_N} skipped, ${WARN_N} warnings"
    write_counts "${COMPONENT}"
    [[ "${FAIL_N}" -eq 0 ]]
}
