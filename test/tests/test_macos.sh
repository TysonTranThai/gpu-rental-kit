#!/usr/bin/env bash
# =============================================================================
# test_macos.sh — macOS development-environment behavior
# =============================================================================
# These tests only apply when running on macOS. On Linux they are skipped.
# =============================================================================
TEST_NAME="macos"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "  SKIP — not running on macOS"
    PASS_COUNT=1
    report_results
    exit 0
fi

ensure_executable

# --- detect_os reports darwin ---
result="$(capture scripts/detect_environment.sh \
    'detect_os; echo "${OS_ID}|${OS_NAME}"')"
assert_contains "${result}" "darwin" "detect_os → darwin on macOS"

# --- CPU/RAM detection works without /proc (uses sysctl on macOS) ---
result="$(capture scripts/detect_environment.sh \
    'detect_cpu; detect_ram; echo "${CPU_MODEL}|${CPU_CORES}|${RAM_TOTAL_GB}"') "
cpu_model="${result%%|*}"
rest="${result#*|}"
cpu_cores="${rest%%|*}"
ram_gb="${rest#*|}"
if [[ -n "${cpu_model}" ]] && [[ "${cpu_model}" != "unknown" ]] && [[ "${cpu_cores}" != "0" ]] && [[ "${ram_gb}" != "0" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  ✔ system detection uses sysctl on macOS (${cpu_model}, ${cpu_cores} cores, ${ram_gb} GB)"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  ✘ system detection returned nothing useful: ${result}"
fi

# --- full environment detection completes without error ---
assert_ok "run_environment_detection completes on macOS" bash -c \
    'export _GPU_RENTAL_KIT_LOADED=1; source "'"${KIT_ROOT}"'/scripts/detect_environment.sh"; run_environment_detection'

# --- bootstrap.sh shows the dev menu and exits cleanly on choice 5 ---
out="$(echo "5" | bash "${KIT_ROOT}/bootstrap.sh" 2>&1)"
status=$?
assert_eq "0" "${status}" "bootstrap.sh dev menu exits 0 on Exit"
assert_contains "${out}" "macOS development environment detected" "dev menu message printed"
assert_contains "${out}" "NVIDIA GPU setup tests are skipped" "skip message printed"

# --- setup.sh refuses to run on macOS ---
status=0
bash "${KIT_ROOT}/setup.sh" >/dev/null 2>&1 || status=$?
assert_eq "1" "${status}" "setup.sh refuses on macOS"

# --- --remote-gpu on macOS fails with a clear message ---
status=0
out="$(bash "${KIT_ROOT}/bootstrap.sh" --remote-gpu 2>&1)" || status=$?
assert_eq "1" "${status}" "bootstrap.sh --remote-gpu fails on macOS"
assert_contains "${out}" "--remote-gpu requires a Linux machine" "clear error message"

# --- mock GPU tests runnable from dev menu path ---
setup_mock_gpu_env rtx3090
result="$(capture scripts/detect_gpu.sh \
    'run_gpu_detection; echo "${GPU_NAME}|${GPU_VRAM_GB}|${GPU_PROFILE}"')"
assert_eq "NVIDIA GeForce RTX 3090|24|large" "${result}" "mock GPU works on macOS"

report_results
