#!/usr/bin/env bash
# =============================================================================
# local_test.sh — PART 1: full local Mac validation
# =============================================================================
# Runs the complete local suite plus standalone checks and generates
#   test/results/local-test-report.txt
# with TOTAL / PASSED / FAILED / SKIPPED / WARNINGS counts and a failure
# table (test name | command | error | likely cause).
#
# Usage: bash test/local_test.sh
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "${TEST_ROOT}/.." && pwd)"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"

REPORT="${RESULTS_DIR}/local-test-report.txt"
REPORT_FILE="${REPORT}"
FAILURES_LOG="${RESULTS_DIR}/.failures.log"
SUITE_OUTPUT="${RESULTS_DIR}/.local-suite-output.txt"

report_init "local"

# ── 0. Environment ───────────────────────────────────────────────────────────
report_section "Environment"
report_out "  Platform:  $(uname -s) $(uname -m)"
report_out "  Hostname:  $(hostname 2>/dev/null || echo unknown)"
report_out "  Bash:      ${BASH_VERSION}"
report_out "  Date:      $(date '+%Y-%m-%d %H:%M:%S')"
if command -v shellcheck &>/dev/null; then
    report_out "  shellcheck: $(shellcheck --version | head -1)"
else
    report_warn "shellcheck not installed — shellcheck checks SKIPPED (brew install shellcheck)"
fi

# ── 1. Full local suite (via bootstrap.sh --test, which exercises the real path) ──
report_section "Full local test suite (bootstrap.sh --test)"
: > "${FAILURES_LOG}" 2>/dev/null || true

status=0
bash "${KIT_ROOT}/bootstrap.sh" --test > "${SUITE_OUTPUT}" 2>&1 || status=$?
report_out "  bootstrap.sh --test exit code: ${status}"

# Parse per-file results
report_out ""
report_out "  Per-file results:"
per_file="$(grep -E '^  ── .*: [0-9]+ passed, [0-9]+ failed ──$' "${SUITE_OUTPUT}" || true)"
if [[ -n "${per_file}" ]]; then
    echo "${per_file}" | sed 's/^/    /' >> "${REPORT}"
fi

suite_pass=0; suite_fail=0; suite_skip=0
while IFS= read -r line; do
    p="$(echo "${line}" | sed -E 's/.*: ([0-9]+) passed,.*/\1/')"
    f="$(echo "${line}" | sed -E 's/.*passed, ([0-9]+) failed.*/\1/')"
    [[ "${p}" =~ ^[0-9]+$ ]] && suite_pass=$((suite_pass + p))
    [[ "${f}" =~ ^[0-9]+$ ]] && suite_fail=$((suite_fail + f))
done <<< "$(grep -E ': [0-9]+ passed, [0-9]+ failed' "${SUITE_OUTPUT}" || true)"
suite_skip="$(grep -cE 'SKIP' "${SUITE_OUTPUT}" || true)"

if [[ "${status}" -eq 0 ]]; then
    report_pass "local suite: ${suite_pass} passed, ${suite_fail} failed"
else
    report_fail "local suite exited ${status}: ${suite_pass} passed, ${suite_fail} failed"
fi
report_out "  (suite skipped entries: ${suite_skip}; see ${SUITE_OUTPUT} for full output)"

# ── 2. Standalone checks ─────────────────────────────────────────────────────
report_section "Standalone checks"

# 2a. bash -n syntax over every script (independent re-check)
syntax_bad="$(find "${KIT_ROOT}" -type f \( -name '*.sh' -o -path '*/bin/*' \) -print0 2>/dev/null \
    | xargs -0 -n1 bash -n 2>&1 | grep -c 'syntax error' || true)"
if [[ "${syntax_bad}" -eq 0 ]]; then
    report_pass "bash -n over all scripts"
else
    report_fail "bash -n: ${syntax_bad} syntax errors"
fi

# 2b. Secret scan (independent re-check)
secrets="$(grep -rInE '(hf_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)' \
    "${KIT_ROOT}" --exclude-dir=.git --exclude-dir=results 2>/dev/null || true)"
if [[ -z "${secrets}" ]]; then
    report_pass "secret scan (no credentials found)"
else
    report_fail "secret scan found potential secrets:"
    echo "${secrets}" | sed 's/^/    /' >> "${REPORT}"
fi

# 2c. Executable permissions
not_exec=""
for f in bootstrap.sh setup.sh bin/* test/run_tests.sh test/local_test.sh test/run_gpu_matrix.sh; do
    [[ -f "${KIT_ROOT}/${f}" ]] || continue
    [[ -x "${KIT_ROOT}/${f}" ]] || not_exec="${not_exec} ${f}"
done
if [[ -z "${not_exec}" ]]; then
    report_pass "executable permissions OK"
else
    report_fail "not executable:${not_exec}"
fi

# 2d. Clean temporary-copy validation (no modifications to the real repo)
report_section "Clean temporary-copy validation"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/grk-localcopy.XXXXXX")"
cp -R "${KIT_ROOT}" "${tmpdir}/gpu-rental-kit"
rm -rf "${tmpdir}/gpu-rental-kit/.git" "${tmpdir}/gpu-rental-kit/test/results"
(
    cd "${tmpdir}/gpu-rental-kit"
    bash bootstrap.sh --validate >/dev/null 2>&1; echo "validate:$?" > "${tmpdir}/results.txt"
    bash test/run_tests.sh >/dev/null 2>&1; echo "suite:$?" >> "${tmpdir}/results.txt"
    bash test/run_gpu_matrix.sh >/dev/null 2>&1; echo "matrix:$?" >> "${tmpdir}/results.txt"
)
fresh=()
while IFS= read -r line; do fresh+=("${line}"); done < "${tmpdir}/results.txt"
for line in "${fresh[@]}"; do
    name="${line%%:*}"
    code="${line##*:}"
    if [[ "${code}" == "0" ]]; then
        report_pass "fresh copy: ${name} exited 0"
    else
        report_fail "fresh copy: ${name} exited ${code}"
    fi
done
rm -rf "${tmpdir}"

# ── 3. Failure details ───────────────────────────────────────────────────────
report_section "Failure details"
if [[ -s "${FAILURES_LOG}" ]]; then
    while IFS='|' read -r test_name kind detail; do
        case "${kind}" in
            assert_eq|assert_contains)
                cause="Assertion mismatch — mock data, expected values, or the code under test changed" ;;
            command_failed)
                cause="Command exited non-zero — check permissions, missing dependency, or PATH" ;;
            expected_failure)
                cause="Expected a failure but the command succeeded — guard logic may have changed" ;;
            sandbox_side_effect)
                cause="Command wrote files where it must not — macOS guard regression" ;;
            *)
                cause="See test output for details" ;;
        esac
        report_out "  TEST: ${test_name}"
        report_out "    COMMAND: bash test/tests/${test_name}.sh"
        report_out "    ERROR:   ${kind} — ${detail}"
        report_out "    CAUSE:   ${cause}"
    done < "${FAILURES_LOG}"
else
    report_out "  No failures recorded."
fi

# ── 4. Summary ───────────────────────────────────────────────────────────────
# Fold the suite totals into the aggregation counters so the summary and
# final-report.txt reflect the full local run (suite + standalone checks).
PASS_N=$((PASS_N + suite_pass))
FAIL_N=$((FAIL_N + suite_fail))
SKIP_N=$((SKIP_N + suite_skip))

report_section "Summary"
total=$((PASS_N + FAIL_N))
report_out "  TOTAL TESTS:  ${total}"
report_out "  PASSED:       ${PASS_N}"
report_out "  FAILED:       ${FAIL_N}"
report_out "  SKIPPED:      ${SKIP_N}"
report_out "  WARNINGS:     ${WARN_N}"
report_out ""

write_counts "local"
echo ""
echo "  Report: ${REPORT}"
echo ""
exit $([[ "${FAIL_N}" -eq 0 ]] && [[ "${status}" -eq 0 ]])
