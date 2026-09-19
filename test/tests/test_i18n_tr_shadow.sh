#!/usr/bin/env bash
# =============================================================================
# test_i18n_tr_shadow.sh — regression: i18n tr() must not break coreutils tr
# =============================================================================
# BUG (v1.5.0, remote GPU rentals): i18n.sh defines a shell function `tr`
# that shadows /usr/bin/tr for every module sourced after it (setup.sh,
# bootstrap.sh, ai-doctor). The function ignored stdin and echoed its key,
# so pipelines ending in `| tr ...` lost their last stage: the function
# subshell exited immediately, upstream writers (wc/echo/sort) got SIGPIPE,
# and under `set -Eeuo pipefail` setup.sh died at detect_gpu.sh line 53
# with "exit 141" during stage [4/15] GPU detection on remote GPU rentals.
#
# Fix: non-identifier first args (every real tr usage: -d, -s, char sets)
# are delegated to `command tr`, which reads stdin to EOF.
# =============================================================================

TEST_NAME="i18n_tr_shadow"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

# Isolate i18n state: never read the developer's saved language preference.
export AI_CONFIG_DIR="${TEST_TMP}/cfg"
export GPU_KIT_LANG="en"

# shellcheck source=/dev/null
source "${KIT_ROOT}/scripts/i18n.sh"
i18n_init

# --- 1. Translation path still works -----------------------------------------
assert_eq "Detecting GPU" "$(tr STAGE_GPU)" "tr STAGE_GPU resolves the en catalog"
assert_eq "TOTALLY_UNKNOWN_KEY_XYZ" "$(tr TOTALLY_UNKNOWN_KEY_XYZ)" "tr falls back to the key for unknown keys"

# --- 2. Coreutils delegation (non-identifier first arg) ----------------------
assert_eq "a-b-c" "$(printf 'a b c' | tr ' ' '-')" "tr ' ' '-' delegates to command tr"
assert_eq "abc" "$(printf 'a b c' | tr -d ' ')" "tr -d ' ' delegates to command tr"
assert_eq "a b c" "$(printf 'a  b   c' | tr -s ' ')" "tr -s ' ' delegates to command tr"
assert_eq "abc" "$(printf 'ABC' | tr '[:upper:]' '[:lower:]')" "tr '[:upper:]' '[:lower:]' delegates to command tr"

# --- 3. The exact detect_gpu.sh:53 pipeline shape ----------------------------
# Pre-fix this was the SIGPIPE (exit 141) kill shot: wc writes AFTER the
# tr-function subshell already exited. Guarded so a regression fails this
# assertion instead of aborting the whole test file under set -e.
pipe_out="$(printf 'one\ntwo\n' | wc -l | tr -d ' ' 2>/dev/null)" || pipe_out="PIPELINE-FAILED(exit $?)"
assert_eq "2" "${pipe_out}" "wc -l | tr -d ' ' survives (the detect_gpu.sh:53 shape)"

# --- 4. End-to-end: i18n sourced FIRST (as setup.sh does), then GPU detection
#     under set -Eeuo pipefail — previously exit 141 at line 53.
setup_mock_gpu_env rtx4090
detect_out="$(capture scripts/i18n.sh \
    'i18n_init; source "${KIT_ROOT}/scripts/detect_gpu.sh"; run_gpu_detection; echo "${HAS_NVIDIA_GPU}|${GPU_COUNT}|${GPU_NAME}|${GPU_VRAM_GB}|${GPU_PROFILE}"')" \
    || detect_out="DETECT-FAILED(exit $?)"
assert_eq "yes|1|NVIDIA GeForce RTX 4090|24|large" "${detect_out}" "run_gpu_detection completes in a shell where i18n.sh was sourced first"

report_results
