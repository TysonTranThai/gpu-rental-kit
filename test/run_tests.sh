#!/usr/bin/env bash
# =============================================================================
# run_tests.sh — GPU Rental Kit local test suite (Mac-safe)
# =============================================================================
# Runs every test/tests/test_*.sh. Safe on macOS: no package installs, no
# system changes, no GPU required. Mock nvidia-smi/docker drive GPU logic.
#
# Usage:
#   ./test/run_tests.sh            # run everything
#   ./test/run_tests.sh gpu        # only tests matching "gpu"
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

chmod +x "${TEST_ROOT}"/mocks/bin/* 2>/dev/null || true
chmod +x "${KIT_ROOT:-${TEST_ROOT}/..}"/bin/* 2>/dev/null || true

echo "══════════════════════════════════════════════════════════════"
echo "  GPU RENTAL KIT — Local Test Suite (macOS-safe)"
echo "══════════════════════════════════════════════════════════════"
echo ""

GLOBAL_PASS=0
GLOBAL_FAIL=0
declare -a RESULTS=()

for test_file in "${TEST_ROOT}"/tests/test_*.sh; do
    [[ -f "${test_file}" ]] || continue
    name="$(basename "${test_file}" .sh)"
    if [[ -n "${FILTER}" ]] && [[ "${name}" != *"${FILTER}"* ]]; then
        continue
    fi

    echo "── ${name} ──"
    # Run each test file in a fresh subshell so state never leaks.
    # A failing test file exits non-zero — capture without tripping set -e.
    status=0
    output="$(bash "${test_file}" 2>&1)" || status=$?
    echo "${output}" | sed 's/^/  /'
    echo ""

    pass_line="$(echo "${output}" | grep -oE '[0-9]+ passed' | head -1 | grep -oE '[0-9]+' || echo 0)"
    fail_line="$(echo "${output}" | grep -oE '[0-9]+ failed' | head -1 | grep -oE '[0-9]+' || echo 0)"
    GLOBAL_PASS=$((GLOBAL_PASS + pass_line))
    GLOBAL_FAIL=$((GLOBAL_FAIL + fail_line))

    if [[ "${status}" -eq 0 ]]; then
        RESULTS+=("✔ ${name}")
    else
        RESULTS+=("✘ ${name}")
    fi
done

echo "══════════════════════════════════════════════════════════════"
echo "  RESULTS"
echo "══════════════════════════════════════════════════════════════"
for r in "${RESULTS[@]}"; do
    echo "  ${r}"
done
echo ""
echo "  Total: ${GLOBAL_PASS} passed, ${GLOBAL_FAIL} failed"
echo ""

if [[ "${GLOBAL_FAIL}" -gt 0 ]]; then
    echo -e "\033[0;31mFAILURES PRESENT — fix before shipping.\033[0m"
    exit 1
fi
echo -e "\033[0;32mAll local tests passed.\033[0m"
exit 0
