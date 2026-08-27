#!/usr/bin/env bash
# =============================================================================
# cleanup_test.sh — PART 11: cleanup test
# =============================================================================
# Stops ONLY inference servers started by the test harness and removes
# temporary artifacts. Preserves logs and test reports. Runs no destructive
# disk cleanup. Safe on macOS and Linux; can also run on the remote machine.
#
# Usage:
#   bash test/cleanup_test.sh                # this machine
#   bash test/cleanup_test.sh --host 1.2.3.4 # on the GPU machine
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ssh_lib.sh
source "${TEST_ROOT}/ssh_lib.sh"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"

show_help() {
    cat <<'EOF'
cleanup_test.sh — CLEANUP (stops test servers, keeps logs and reports)

  Usage:
    bash test/cleanup_test.sh                # this machine
    bash test/cleanup_test.sh --host 1.2.3.4 # on the GPU machine
EOF
}

parse_status=0
ssh_parse_args "$@" || parse_status=$?
if [[ "${parse_status}" -eq 2 ]]; then show_help; exit 0; fi
if [[ "${parse_status}" -ne 0 ]]; then exit 1; fi

REPORT="${RESULTS_DIR}/cleanup-report.txt"
REPORT_FILE="${REPORT}"
report_init "cleanup"

report_section "Cleanup test"
report_out "  Mode: $([[ -n "${REMOTE_HOST}" ]] && echo "remote ($(ssh_target))" || echo local)"

BODY_FILE="${RESULTS_DIR}/.cleanup-body.sh"
cat > "${BODY_FILE}" <<'CLEAN_EOF'
#!/usr/bin/env bash
set -uo pipefail
info() { echo "[INFO] $*"; }
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; }

# Stop ONLY inference servers started by the test harness. The harness always
# launches llama.cpp with a model path under ~/ai/models/test-grun, so the
# command line contains "test-grun" or "grk". User processes are never killed.
if [[ -f /tmp/grk-llamacpp.pid ]]; then
    pid="$(cat /tmp/grk-llamacpp.pid 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill "${pid}" 2>/dev/null; then
        pass "stopped llama.cpp server (pid ${pid})"
    else
        info "llama.cpp already stopped"
    fi
    rm -f /tmp/grk-llamacpp.pid
fi
for pid in $(pgrep -f "llama_cpp.server|llamacpp-serve" 2>/dev/null || true); do
    cmdline="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
    case "${cmdline}" in
        *test-grun*|*grk*)
            kill "${pid}" 2>/dev/null && pass "stopped harness server (pid ${pid})" || true
            ;;
        *)
            info "keeping process (pid ${pid}) — not a harness process"
            ;;
    esac
done

# Remove temporary test containers (only grk-prefixed ones)
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    for c in $(docker ps -aq --filter "name=grk-" 2>/dev/null || true); do
        docker rm -f "${c}" >/dev/null 2>&1 && pass "removed test container ${c}" || true
    done
fi

# Remove temporary test files (preserve logs + reports)
rm -f /tmp/grk-*.txt /tmp/grk-*.json /tmp/grk-*.log /tmp/grk-*.pid 2>/dev/null || true
rm -rf "${HOME}/ai/models/test-grun" 2>/dev/null || true
info "temporary test files removed; logs and reports preserved"

pass "cleanup complete"
CLEAN_EOF

tmpout="${RESULTS_DIR}/.cleanup-output.txt"
if [[ -n "${REMOTE_HOST}" ]]; then
    ssh_run_stdin "${BODY_FILE}" > "${tmpout}" 2>&1 || true
else
    bash "${BODY_FILE}" > "${tmpout}" 2>&1 || true
fi
cat "${tmpout}" | tee -a "${REPORT}"
rm -f "${BODY_FILE}"

c_fail="$(grep -c '^\[FAIL\]' "${tmpout}" || true)"
if [[ "${c_fail}" -eq 0 ]]; then
    report_pass "cleanup ran without failures"
else
    report_fail "${c_fail} cleanup failures"
fi
report_summary
echo ""
echo "  Report: ${REPORT}"
exit $([[ "${c_fail}" -eq 0 ]])
