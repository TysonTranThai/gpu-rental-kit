#!/usr/bin/env bash
# =============================================================================
# network_test.sh — PART 10: network / API exposure test (REAL, read-only)
# =============================================================================
# Determines whether an external client could reach an inference API.
# Never opens firewall ports, never binds, never exposes anything.
#
# Usage:
#   bash test/network_test.sh                 # this machine
#   bash test/network_test.sh --host 1.2.3.4  # on the GPU machine
#   env: GPU_HOST GPU_PORT GPU_USER
#
# Output: test/results/network-report.txt
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ssh_lib.sh
source "${TEST_ROOT}/ssh_lib.sh"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"

show_help() {
    cat <<'EOF'
network_test.sh — NETWORK / API EXPOSURE TEST (REAL, read-only)

  Checks localhost endpoints first, then inspects listening ports, Docker
  port mappings, public IP and tunnel interfaces to determine whether an
  external client could reach the API. Opens NO firewall ports.

  Usage:
    bash test/network_test.sh                    # this machine
    bash test/network_test.sh --host 1.2.3.4     # on the GPU machine
    env: GPU_HOST GPU_PORT GPU_USER
EOF
}

parse_status=0
ssh_parse_args "$@" || parse_status=$?
if [[ "${parse_status}" -eq 2 ]]; then show_help; exit 0; fi
if [[ "${parse_status}" -ne 0 ]]; then exit 1; fi

REPORT="${RESULTS_DIR}/network-report.txt"
REPORT_FILE="${REPORT}"
report_init "network"
tmpout="${RESULTS_DIR}/.network-output.txt"

report_section "Network / API exposure test (REAL)"
report_out "  Mode: $([[ -n "${REMOTE_HOST}" ]] && echo "remote ($(ssh_target))" || echo local)"

if [[ -n "${REMOTE_HOST}" ]]; then
    ssh_run_stdin "${TEST_ROOT}/remote/network.sh" > "${tmpout}" 2>&1 || true
else
    bash "${TEST_ROOT}/remote/network.sh" > "${tmpout}" 2>&1 || true
fi
cat "${tmpout}" | tee -a "${REPORT}"

if grep -q 'EXPOSURE: PUBLICLY BOUND' "${tmpout}"; then
    report_warn "network verdict: publicly bound services detected"
else
    report_pass "network verdict: localhost-only (no public exposure detected)"
fi
report_summary
echo ""
echo "  Report: ${REPORT}"
exit 0
