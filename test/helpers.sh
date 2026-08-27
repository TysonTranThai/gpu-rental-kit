#!/usr/bin/env bash
# =============================================================================
# helpers.sh — shared utilities for GPU Rental Kit tests
# =============================================================================
# Source this from any test_*.sh file. All helpers are Mac-safe: they never
# install packages, never touch system config, and never require a GPU.
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "${TEST_ROOT}/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/grk-test.XXXXXX")"
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-${TEST_ROOT}/results}"
FAILURES_LOG="${TEST_RESULTS_DIR}/.failures.log"
mkdir -p "${TEST_RESULTS_DIR}"

PASS_COUNT=0
FAIL_COUNT=0

# =============================================================================
# record_failure — append a structured failure record for the report generator
# fields (pipe-separated): test_name|kind|detail
# =============================================================================
record_failure() {
    local kind="$1" detail="$2"
    local test_name="${TEST_NAME:-$(basename "${BASH_SOURCE[1]:-unknown}" .sh)}"
    echo "${test_name}|${kind}|${detail}" >> "${FAILURES_LOG}" 2>/dev/null || true
}

# =============================================================================
# Assertions
# =============================================================================
assert_eq() {
    local expected="$1" actual="$2" msg="${3:-assert_eq}"
    if [[ "${expected}" == "${actual}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ ${msg}"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ ${msg} — expected: '${expected}' actual: '${actual}'"
        record_failure "assert_eq" "${msg} — expected: '${expected}' actual: '${actual}'"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-assert_contains}"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ ${msg}"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ ${msg} — '${needle}' not found in output"
        record_failure "assert_contains" "${msg} — '${needle}' not found in output"
    fi
}

# assert_ok <message> <cmd...> — command must exit 0
assert_ok() {
    local msg="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ ${msg}"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ ${msg} — command failed: $*"
        record_failure "command_failed" "${msg} — command: $*"
    fi
}

# assert_fail <message> <cmd...> — command must exit non-zero
assert_fail() {
    local msg="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ ${msg} — expected failure but command succeeded: $*"
        record_failure "expected_failure" "${msg} — command: $*"
    else
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ ${msg}"
    fi
}

# =============================================================================
# Summary — call at end of each test file
# =============================================================================
report_results() {
    echo ""
    echo "  ── ${TEST_NAME:-$(basename "${BASH_SOURCE[1]:-${0}}")}: ${PASS_COUNT} passed, ${FAIL_COUNT} failed ──"
    rm -rf "${TEST_TMP}" 2>/dev/null || true
    [[ "${FAIL_COUNT}" -eq 0 ]]
}

# =============================================================================
# Mock environment setup
# =============================================================================
# setup_mock_gpu_env <profile> — puts mock nvidia-smi on PATH + mock /proc
setup_mock_gpu_env() {
    local profile="${1:-rtx4090}"
    export MOCK_GPU_PROFILE="${profile}"
    export KIT_PROC_DIR="${TEST_ROOT}/mocks/proc"
    export PATH="${TEST_ROOT}/mocks/bin:${PATH}"
}

# setup_mock_docker_env <docker_ok> <nvidia_ctk_ok>
setup_mock_docker_env() {
    export MOCK_DOCKER_OK="${1:-yes}"
    export MOCK_NVIDIA_CTK_OK="${2:-no}"
    export PATH="${TEST_ROOT}/mocks/bin:${PATH}"
}

# =============================================================================
# capture — source a kit script in a subshell with mock env and eval a snippet
# usage: capture <kit-script-path> '<bash-snippet>' [<extra-env-assignments>]
# The snippet should echo the variables you care about.
# =============================================================================
capture() {
    local script="$1" snippet="$2" extra="${3:-}"
    (
        export _GPU_RENTAL_KIT_LOADED="1"
        [[ -n "${extra}" ]] && eval "${extra}"
        # shellcheck source=/dev/null
        source "${KIT_ROOT}/${script}"
        eval "${snippet}"
    )
}

# =============================================================================
# chmod helper — ensure scripts are executable
# =============================================================================
ensure_executable() {
    chmod +x "${KIT_ROOT}/bootstrap.sh" "${KIT_ROOT}/setup.sh" 2>/dev/null || true
    chmod +x "${KIT_ROOT}"/bin/* 2>/dev/null || true
    chmod +x "${TEST_ROOT}"/mocks/bin/* 2>/dev/null || true
}
