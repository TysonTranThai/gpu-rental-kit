#!/usr/bin/env bash
# =============================================================================
# run_all.sh — PART 12/14: ONE-COMMAND test runner
# =============================================================================
#   ./test/run_all.sh local    Mac-safe tests: full suite, bootstrap logic,
#                              mock matrix, persistence+network diagnostics,
#                              cleanup
#   ./test/run_all.sh mock     GPU/provider mocks only (matrix + mock tests)
#   ./test/run_all.sh remote   REAL tests against a rented GPU machine
#                              (needs GPU_HOST/GPU_PORT/GPU_USER or flags)
#   ./test/run_all.sh all      everything currently possible; remote parts are
#                              skipped (honestly labeled SKIP) when no SSH
#                              target is configured
#
# Output: test/results/final-report.txt  (plus per-component reports)
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"
RESULTS_DIR="${TEST_ROOT}/results"
mkdir -p "${RESULTS_DIR}"

MODE="${1:-all}"
START="$(date '+%Y-%m-%d %H:%M:%S')"
COUNTS_DIR="${RESULTS_DIR}/.counts"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  GPU RENTAL KIT — Test Runner (mode: ${MODE})"
echo "  Started: ${START}"
echo "══════════════════════════════════════════════════════════════"

run_component() {
    local name="$1"; shift
    echo ""
    echo "── ${name} ──"
    bash "$@"
    local code=$?
    echo "  (${name} exit: ${code})"
    return "${code}"
}

# ── mode: mock ──────────────────────────────────────────────────────────────
run_mock() {
    run_component "gpu-matrix" "${TEST_ROOT}/run_gpu_matrix.sh" || true
    run_component "mock-gpu-tests" "${TEST_ROOT}/run_tests.sh" gpu || true
    run_component "mock-docker-tests" "${TEST_ROOT}/run_tests.sh" docker || true
    run_component "mock-storage-tests" "${TEST_ROOT}/run_tests.sh" storage || true
}

# ── mode: local ─────────────────────────────────────────────────────────────
run_local() {
    run_component "local-suite" "${TEST_ROOT}/local_test.sh" || true
    run_mock
    run_component "persistence-diagnostic" "${TEST_ROOT}/persistence_test.sh" || true
    run_component "network-diagnostic" "${TEST_ROOT}/network_test.sh" || true
    run_component "cleanup" "${TEST_ROOT}/cleanup_test.sh" || true
}

# ── mode: remote ────────────────────────────────────────────────────────────
run_remote() {
    run_component "remote-diagnostics" "${TEST_ROOT}/remote_gpu_test.sh" || true
    run_component "remote-install" "${TEST_ROOT}/remote_install_test.sh" || true
    run_component "llamacpp-test" "${TEST_ROOT}/llamacpp_test.sh" || true
    if [[ -n "${GPU_HOST:-}" ]]; then
        run_component "api-test" "${TEST_ROOT}/api_test.sh" || true
        run_component "benchmark" "${TEST_ROOT}/benchmark.sh" || true
    else
        echo "  [SKIP] api/benchmark — no GPU_HOST (remote diagnostics already noted)"
    fi
    run_component "remote-persistence" "${TEST_ROOT}/persistence_test.sh" || true
    run_component "remote-network" "${TEST_ROOT}/network_test.sh" || true
    run_component "remote-cleanup" "${TEST_ROOT}/cleanup_test.sh" || true
}

case "${MODE}" in
    local)  run_local ;;
    mock)   run_mock ;;
    remote) run_remote ;;
    all|*)
        echo "  (mode '${MODE}' → running everything possible)"
        run_local
        if [[ -n "${GPU_HOST:-}" ]]; then
            run_remote
        else
            echo ""
            echo "  [SKIP] remote tests — no GPU_HOST set (set GPU_HOST/GPU_PORT/GPU_USER"
            echo "         or pass --host to individual remote scripts)"
            # Record honest SKIP counts so final-report.txt shows the remote
            # components were skipped, never counted as passed or failed.
            for comp in remote_diagnostics remote_install llamacpp api benchmark; do
                printf 'PASSED 0\nFAILED 0\nSKIPPED 1\nWARNINGS 0\n' \
                    > "${COUNTS_DIR}/${comp}.txt"
            done
        fi
        ;;
esac

# ── final report ────────────────────────────────────────────────────────────
FINAL="${RESULTS_DIR}/final-report.txt"

count_of() { # count_of <component> <field>
    read_counts "$1" "$2" 2>/dev/null || echo 0
}

# derived counts from remote reports (CUDA, DOCKER GPU)
grep_count() { # grep_count <file> <pattern>
    local f="${RESULTS_DIR}/$1"
    [[ -f "${f}" ]] || { echo "0"; return; }
    grep -cE "$2" "${f}" 2>/dev/null || echo "0"
}

{
    echo "# GPU Rental Kit — FINAL TEST REPORT"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')  Mode: ${MODE}"
    echo ""
    echo "LOCAL TESTS"
    echo "  PASS: $(count_of local PASSED)"
    echo "  FAIL: $(count_of local FAILED)"
    echo "  SKIP: $(count_of local SKIPPED)"
    echo ""
    echo "MOCK GPU TESTS"
    echo "  PASS: $(count_of mock_gpu_matrix PASSED)"
    echo "  FAIL: $(count_of mock_gpu_matrix FAILED)"
    echo "  SKIP: $(count_of mock_gpu_matrix SKIPPED)"
    echo ""
    echo "REMOTE TESTS"
    echo "  PASS: $(($(count_of remote_diagnostics PASSED) + $(count_of remote_install PASSED)))"
    echo "  FAIL: $(($(count_of remote_diagnostics FAILED) + $(count_of remote_install FAILED)))"
    echo "  SKIP: $(($(count_of remote_diagnostics SKIPPED) + $(count_of remote_install SKIPPED)))"
    echo ""
    echo "LLAMA.CPP"
    echo "  PASS: $(count_of llamacpp PASSED)"
    echo "  FAIL: $(count_of llamacpp FAILED)"
    echo "  SKIP: $(count_of llamacpp SKIPPED)"
    echo ""
    echo "CUDA"
    echo "  PASS: $(( $(grep_count remote-diagnostics-report.txt '^\[PASS\].*cuda') + $(grep_count remote-install-report.txt '^\[PASS\].*cuda') ))"
    echo "  FAIL: $(( $(grep_count remote-diagnostics-report.txt '^\[FAIL\].*cuda') + $(grep_count remote-install-report.txt '^\[FAIL\].*cuda') ))"
    echo "  SKIP: $(count_of remote_diagnostics SKIPPED)"
    echo ""
    echo "DOCKER GPU"
    echo "  PASS: $(( $(grep_count remote-diagnostics-report.txt '^\[PASS\].*docker') + $(grep_count remote-install-report.txt '^\[PASS\].*docker') ))"
    echo "  FAIL: $(( $(grep_count remote-diagnostics-report.txt '^\[FAIL\].*docker') + $(grep_count remote-install-report.txt '^\[FAIL\].*docker') ))"
    echo "  SKIP: $(count_of remote_diagnostics SKIPPED)"
    echo ""
    echo "API"
    echo "  PASS: $(count_of api PASSED)"
    echo "  FAIL: $(count_of api FAILED)"
    echo "  SKIP: $(count_of api SKIPPED)"
    echo ""
    echo "PERSISTENCE"
    if grep -q 'PERSISTENCE: VERIFIED' "${RESULTS_DIR}/persistence-report.txt" 2>/dev/null; then
        echo "  VERIFIED: yes"
        echo "  UNKNOWN: no"
    elif [[ -f "${RESULTS_DIR}/persistence-report.txt" ]]; then
        echo "  VERIFIED: no"
        echo "  UNKNOWN: yes  (PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE)"
    else
        echo "  VERIFIED: no"
        echo "  UNKNOWN: yes  (no persistence report generated)"
    fi
    echo ""
    echo "NETWORK"
    if grep -q 'EXPOSURE: LOCALHOST-ONLY' "${RESULTS_DIR}/network-report.txt" 2>/dev/null; then
        echo "  VERIFIED: yes (localhost-only — no public exposure)"
        echo "  UNKNOWN: no"
    elif [[ -f "${RESULTS_DIR}/network-report.txt" ]]; then
        echo "  VERIFIED: yes (verdict: publicly bound services detected)"
        echo "  UNKNOWN: no"
    else
        echo "  VERIFIED: no"
        echo "  UNKNOWN: yes (no network report generated)"
    fi
    echo ""
    echo "WARNINGS: $(($(count_of local WARNINGS) + $(count_of mock_gpu_matrix WARNINGS)))"
} > "${FINAL}"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  FINAL REPORT: ${FINAL}"
echo "══════════════════════════════════════════════════════════════"
cat "${FINAL}"
echo ""
echo "  Per-component reports:"
ls -1 "${RESULTS_DIR}"/*-report.txt 2>/dev/null | sed 's/^/    /'
echo ""
echo "  Done. (Skipped components are labeled SKIP — never counted as passed.)"
