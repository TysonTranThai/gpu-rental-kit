#!/usr/bin/env bash
# =============================================================================
# test_arguments.sh — CLI argument parsing
# =============================================================================
TEST_NAME="arguments"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

ensure_executable

# --- bootstrap.sh --help ---
out="$(bash "${KIT_ROOT}/bootstrap.sh" --help 2>&1)"
status=$?
assert_eq "0" "${status}" "bootstrap.sh --help exits 0"
assert_contains "${out}" "Usage: ./bootstrap.sh" "bootstrap.sh --help shows usage"
assert_contains "${out}" "--remote-gpu" "bootstrap.sh --help mentions --remote-gpu"

# --- bootstrap.sh -h ---
status=0
bash "${KIT_ROOT}/bootstrap.sh" -h >/dev/null 2>&1 || status=$?
assert_eq "0" "${status}" "bootstrap.sh -h exits 0"

# --- bootstrap.sh --validate passes ---
status=0
bash "${KIT_ROOT}/bootstrap.sh" --validate >/dev/null 2>&1 || status=$?
assert_eq "0" "${status}" "bootstrap.sh --validate exits 0"

# --- setup.sh --help ---
out="$(bash "${KIT_ROOT}/setup.sh" --help 2>&1)"
status=$?
assert_eq "0" "${status}" "setup.sh --help exits 0"
assert_contains "${out}" "--remote-gpu" "setup.sh --help mentions --remote-gpu"

# --- remote-gpu flag forces auto-confirm ---
out="$(bash "${KIT_ROOT}/setup.sh" --remote-gpu --help 2>&1)"
assert_eq "0" "$?" "setup.sh --remote-gpu --help exits 0"

# --- unknown args don't crash help ---
out="$(bash "${KIT_ROOT}/bootstrap.sh" --help --bogus-flag 2>&1)"
assert_eq "0" "$?" "bootstrap.sh handles help with extra args"

report_results
