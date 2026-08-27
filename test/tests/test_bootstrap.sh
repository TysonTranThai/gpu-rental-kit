#!/usr/bin/env bash
# =============================================================================
# test_bootstrap.sh — bootstrap.sh argument combinations + macOS safety
# =============================================================================
# Verifies:
#   --help, --validate, --test (dispatch via sandboxed fake suite)
#   -y, -y --remote-gpu, --remote-gpu combinations
#   --remote-gpu on macOS aborts BEFORE any filesystem/system change
#     (proven by running in a clean sandbox and diffing the directory tree)
# =============================================================================
TEST_NAME="bootstrap"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

ensure_executable

# --- --help ---
status=0
out="$(bash "${KIT_ROOT}/bootstrap.sh" --help 2>&1)" || status=$?
assert_eq "0" "${status}" "bootstrap.sh --help exits 0"
assert_contains "${out}" "--remote-gpu" "--help documents --remote-gpu"
assert_contains "${out}" "--validate" "--help documents --validate"
assert_contains "${out}" "--test" "--help documents --test"

# --- --validate (full run) ---
status=0
bash "${KIT_ROOT}/bootstrap.sh" --validate >/dev/null 2>&1 || status=$?
assert_eq "0" "${status}" "bootstrap.sh --validate exits 0"

# --- --test dispatch: sandboxed fake suite proves it runs test/run_tests.sh ---
sandbox="${TEST_TMP}/bootstrap-test"
mkdir -p "${sandbox}/test"
cp "${KIT_ROOT}/bootstrap.sh" "${sandbox}/"
printf '#!/usr/bin/env bash\necho "FAKE SUITE RAN OK"\nexit 0\n' > "${sandbox}/test/run_tests.sh"
chmod +x "${sandbox}/test/run_tests.sh"
out="$(bash "${sandbox}/bootstrap.sh" --test 2>&1)"
assert_eq "0" "$?" "--test dispatches to test/run_tests.sh"
assert_contains "${out}" "FAKE SUITE RAN OK" "--test executed the suite script"

# --- -y alone on macOS → dev menu; "5" exits cleanly ---
if [[ "$(uname -s)" == "Darwin" ]]; then
    out="$(echo "5" | bash "${KIT_ROOT}/bootstrap.sh" -y 2>&1)"
    assert_eq "0" "$?" "-y on macOS shows dev menu and exits cleanly"
    assert_contains "${out}" "macOS development environment detected" "-y prints dev-environment message"
fi

# --- --remote-gpu on macOS: aborts with exit 1 ---
if [[ "$(uname -s)" == "Darwin" ]]; then
    status=0
    out="$(bash "${KIT_ROOT}/bootstrap.sh" --remote-gpu 2>&1)" || status=$?
    assert_eq "1" "${status}" "--remote-gpu aborts on macOS (exit 1)"
    assert_contains "${out}" "--remote-gpu requires a Linux machine" "--remote-gpu explains why it aborts"

    status=0
    out="$(bash "${KIT_ROOT}/bootstrap.sh" -y --remote-gpu 2>&1)" || status=$?
    assert_eq "1" "${status}" "-y --remote-gpu also aborts on macOS"
fi

# --- SANDBOX PROOF: --remote-gpu on macOS makes NO filesystem changes ---
if [[ "$(uname -s)" == "Darwin" ]]; then
    sandbox_home="${TEST_TMP}/sandbox-home"
    sandbox_kit="${TEST_TMP}/sandbox-kit"
    mkdir -p "${sandbox_home}"
    cp -R "${KIT_ROOT}" "${sandbox_kit}"
    rm -rf "${sandbox_kit}/.git" "${sandbox_kit}/test/results"

    # Snapshot the sandbox before
    before="$(cd "${TEST_TMP}" && find . -mindepth 1 -not -path './sandbox-home/*' | sort)"

    status=0
    HOME="${sandbox_home}" bash "${sandbox_kit}/bootstrap.sh" --remote-gpu >/dev/null 2>&1 || status=$?
    assert_eq "1" "${status}" "sandbox --remote-gpu exits 1 on macOS"

    # Snapshot after
    after="$(cd "${TEST_TMP}" && find . -mindepth 1 -not -path './sandbox-home/*' | sort)"
    assert_eq "${before}" "${after}" "sandbox --remote-gpu created NO new files"
    if [[ -d "${sandbox_home}/ai" ]]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ sandbox --remote-gpu created ~/ai — must not happen on macOS"
        record_failure "sandbox_side_effect" "--remote-gpu created ${sandbox_home}/ai"
    else
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ sandbox --remote-gpu did not create ~/ai"
    fi

    # Home dir must remain empty
    home_files="$(find "${sandbox_home}" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
    assert_eq "0" "${home_files}" "sandbox HOME untouched by --remote-gpu"
fi

report_results
