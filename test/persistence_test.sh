#!/usr/bin/env bash
# =============================================================================
# persistence_test.sh — PART 9: persistence diagnostic (REAL)
# =============================================================================
# Runs the persistence diagnostic locally or on the remote GPU machine.
# Verdict is VERIFIED / NOT VERIFIED / UNKNOWN — never a false claim.
#
# Usage:
#   bash test/persistence_test.sh                 # this machine
#   bash test/persistence_test.sh --host 1.2.3.4  # on the GPU machine
#   env: GPU_HOST GPU_PORT GPU_USER
#
# Output: test/results/persistence-report.txt
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ssh_lib.sh
source "${TEST_ROOT}/ssh_lib.sh"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"

show_help() {
    cat <<'EOF'
persistence_test.sh — PERSISTENCE DIAGNOSTIC (REAL)

  Inspects mounts, Docker volumes, writable paths, disk identifiers and
  environment metadata to classify storage durability. Never claims
  rental-level persistence without provider evidence.

  Usage:
    bash test/persistence_test.sh                    # this machine
    bash test/persistence_test.sh --host 1.2.3.4     # on the GPU machine
    env: GPU_HOST GPU_PORT GPU_USER
EOF
}

parse_status=0
ssh_parse_args "$@" || parse_status=$?
if [[ "${parse_status}" -eq 2 ]]; then show_help; exit 0; fi
if [[ "${parse_status}" -ne 0 ]]; then exit 1; fi

REPORT="${RESULTS_DIR}/persistence-report.txt"
REPORT_FILE="${REPORT}"
report_init "persistence"
tmpout="${RESULTS_DIR}/.persistence-output.txt"

report_section "Persistence diagnostic (REAL)"
report_out "  Mode: $([[ -n "${REMOTE_HOST}" ]] && echo "remote ($(ssh_target))" || echo local)"

if [[ -n "${REMOTE_HOST}" ]]; then
    ssh_run_stdin "${TEST_ROOT}/remote/persistence.sh" > "${tmpout}" 2>&1 || true
else
    bash "${TEST_ROOT}/remote/persistence.sh" > "${tmpout}" 2>&1 || true
fi
cat "${tmpout}" | tee -a "${REPORT}"

# Verdict: the remote script's final [RESULT] line governs
verdict="$(grep '^\[RESULT\]' "${tmpout}" | tail -1 || true)"
if echo "${verdict}" | grep -q "VERIFIED"; then
    report_pass "persistence verdict: VERIFIED"
elif echo "${verdict}" | grep -q "NOT VERIFIED"; then
    report_warn "persistence verdict: NOT VERIFIED"
    report_out "  PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE."
else
    report_warn "persistence verdict: UNKNOWN"
    report_out "  PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE."
fi
report_summary
echo ""
echo "  Report: ${REPORT}"
exit 0
