#!/usr/bin/env bash
# =============================================================================
# llamacpp_test.sh — PART 6: llama.cpp test (REAL)
# =============================================================================
# llama.cpp is the PRIMARY inference runtime. Runs a full real test on the
# rented GPU machine (or locally with --local if a llama-cpp venv exists):
#   download small GGUF → start server → wait for API → real chat completion
#   → verify content → metrics (speeds, GPU util, VRAM) → stop → cleanup.
#
# Usage:
#   bash test/llamacpp_test.sh --host 1.2.3.4 [--user root]
#   bash test/llamacpp_test.sh --local          # run on this machine
#   env: GPU_HOST GPU_PORT GPU_USER
#
# Output: test/results/llamacpp-report.txt
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ssh_lib.sh
source "${TEST_ROOT}/ssh_lib.sh"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"

LOCAL_MODE="no"

show_help() {
    cat <<'EOF'
llamacpp_test.sh — LLAMA.CPP TEST (REAL, primary runtime)

  Full llama.cpp validation with a SMALL test GGUF (~100MB):
    download → start server (127.0.0.1:8080) → wait for API → real chat
    completion → verify content → measure speeds/GPU/VRAM → stop → cleanup.

  Usage:
    bash test/llamacpp_test.sh --host 1.2.3.4 [--user root] [--port 22]
    bash test/llamacpp_test.sh --local     # run on this machine instead
    env: GPU_HOST GPU_PORT GPU_USER

  Model override (default: SmolLM2-135M Q4_K_M, ~100MB):
    GRK_TEST_MODEL_REPO=... GRK_TEST_MODEL_PATTERN='*Q4_K_M.gguf'
    GRK_TEST_PORT=8080

  Report: test/results/llamacpp-report.txt
EOF
}

# --- parse args ---
clean_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --local) LOCAL_MODE="yes"; shift ;;
        *) clean_args+=("$1"); shift ;;
    esac
done
set -- "${clean_args[@]}"
parse_status=0
ssh_parse_args "$@" || parse_status=$?
if [[ "${parse_status}" -eq 2 ]]; then show_help; exit 0; fi
if [[ "${parse_status}" -ne 0 ]]; then exit 1; fi

REPORT="${RESULTS_DIR}/llamacpp-report.txt"
REPORT_FILE="${REPORT}"
report_init "llamacpp"
tmpout="${RESULTS_DIR}/.llamacpp-output.txt"

report_section "llama.cpp test (REAL)"

if [[ "${LOCAL_MODE}" == "yes" ]]; then
    if ! bash "${TEST_ROOT}/remote/llamacpp_run.sh" > "${tmpout}" 2>&1; then
        report_fail "local llama.cpp test failed to run"
    fi
elif ssh_target_ok; then
    report_out "  Target: $(ssh_target) — running full llama.cpp test on the server"
    if ! ssh_run_stdin "${TEST_ROOT}/remote/llamacpp_run.sh" > "${tmpout}" 2>&1; then
        report_fail "remote llama.cpp test failed to run"
    fi
else
    echo "  [SKIP] No GPU_HOST set and no --local — llama.cpp test skipped."
    report_skip "llamacpp test skipped — no SSH target (set GPU_HOST or use --local)"
    report_summary
    exit 0
fi

cat "${tmpout}" | tee -a "${REPORT}"

l_pass="$(grep -c '^\[PASS\]' "${tmpout}" || true)"
l_fail="$(grep -c '^\[FAIL\]' "${tmpout}" || true)"
l_unk="$(grep -c '^\[UNKNOWN\]' "${tmpout}" || true)"
l_warn="$(grep -c '^\[WARN\]' "${tmpout}" || true)"

report_out ""
report_out "  llama.cpp results: ${l_pass} PASS, ${l_fail} FAIL, ${l_unk} UNKNOWN, ${l_warn} WARN"
if [[ "${l_fail}" -eq 0 ]] && [[ "${l_pass}" -gt 0 ]]; then
    report_pass "llama.cpp real generation verified"
else
    report_fail "${l_fail} llama.cpp failures"
fi
report_summary
echo ""
echo "  Report: ${REPORT}"
exit $([[ "${l_fail}" -eq 0 ]])
