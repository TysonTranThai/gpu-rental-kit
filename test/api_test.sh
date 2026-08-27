#!/usr/bin/env bash
# =============================================================================
# api_test.sh — PART 7: API endpoint test (REAL)
# =============================================================================
# Runs the OpenAI-compatible API checks against an inference server.
# Defaults to localhost — never exposes anything publicly.
#
# Usage:
#   bash test/api_test.sh [--base-url http://127.0.0.1:8080] [--model NAME]
#                         [--auth TOKEN]
#   bash test/api_test.sh --host 1.2.3.4 [--api-port 8080]   # run ON the remote
#
# Output: test/results/api-report.txt
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ssh_lib.sh
source "${TEST_ROOT}/ssh_lib.sh"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"

BASE_URL="http://127.0.0.1:8080"
API_PORT="8080"
MODEL=""
AUTH=""
TARGET_MODE="local"

show_help() {
    cat <<'EOF'
api_test.sh — API ENDPOINT TEST (REAL, localhost by default)

  Tests GET /health (if present) and POST /v1/chat/completions on an
  OpenAI-compatible inference server (llama.cpp / vLLM / Ollama).

  Usage:
    bash test/api_test.sh [--base-url http://127.0.0.1:8080]
                          [--model NAME] [--auth TOKEN]
    bash test/api_test.sh --host 1.2.3.4 [--api-port 8080] [--user root]

  --host  runs the checks ON the remote machine via SSH, against its own
          127.0.0.1 — the request never leaves the server, so nothing is
          exposed to the network.
  Never binds or opens ports; never exposes the API publicly.
EOF
}

# --- parse args ---
clean_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url) BASE_URL="$2"; shift 2 ;;
        --api-port) API_PORT="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --auth) AUTH="$2"; shift 2 ;;
        *) clean_args+=("$1"); shift ;;
    esac
done
set -- "${clean_args[@]}"
parse_status=0
ssh_parse_args "$@" || parse_status=$?
if [[ "${parse_status}" -eq 2 ]]; then show_help; exit 0; fi
if [[ "${parse_status}" -ne 0 ]]; then exit 1; fi

if ssh_target_ok; then
    TARGET_MODE="remote"
fi

REPORT="${RESULTS_DIR}/api-report.txt"
REPORT_FILE="${REPORT}"
report_init "api"
tmpout="${RESULTS_DIR}/.api-check-output.txt"

report_section "API test (REAL)"
report_out "  Mode: ${TARGET_MODE}"

if [[ "${TARGET_MODE}" == "remote" ]]; then
    report_out "  Target: $(ssh_target) — checks run ON the server against 127.0.0.1:${API_PORT}"
    if ! ssh_run_stdin "${TEST_ROOT}/remote/api_check.sh" \
        --base-url "http://127.0.0.1:${API_PORT}" \
        ${MODEL:+--model "${MODEL}"} \
        ${AUTH:+--auth "${AUTH}"} > "${tmpout}" 2>&1; then
        report_fail "remote api check failed to execute"
        report_summary
        exit 1
    fi
else
    report_out "  Base URL: ${BASE_URL} (localhost-safe)"
    bash "${TEST_ROOT}/remote/api_check.sh" --base-url "${BASE_URL}" \
        ${MODEL:+--model "${MODEL}"} \
        ${AUTH:+--auth "${AUTH}"} > "${tmpout}" 2>&1
fi

cat "${tmpout}" | tee -a "${REPORT}"

a_pass="$(grep -c '^\[PASS\]' "${tmpout}" || true)"
a_fail="$(grep -c '^\[FAIL\]' "${tmpout}" || true)"
a_unk="$(grep -c '^\[UNKNOWN\]' "${tmpout}" || true)"
a_warn="$(grep -c '^\[WARN\]' "${tmpout}" || true)"

report_out ""
report_out "  API results: ${a_pass} PASS, ${a_fail} FAIL, ${a_unk} UNKNOWN, ${a_warn} WARN"
if [[ "${a_fail}" -eq 0 ]]; then
    report_pass "API checks clean"
else
    report_fail "${a_fail} API check failures"
fi
report_summary
echo ""
echo "  Report: ${REPORT}"
exit $([[ "${a_fail}" -eq 0 ]])
