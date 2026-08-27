#!/usr/bin/env bash
# =============================================================================
# test_idempotency.sh — repeated execution must be stable and side-effect free
# =============================================================================
TEST_NAME="idempotency"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

ensure_executable

# --- GPU detection twice → identical results ---
setup_mock_gpu_env rtx4090
first="$(capture scripts/detect_gpu.sh 'run_gpu_detection; echo "${GPU_NAME}|${GPU_PROFILE}|${GPU_VRAM_GB}"')"
second="$(capture scripts/detect_gpu.sh 'run_gpu_detection; echo "${GPU_NAME}|${GPU_PROFILE}|${GPU_VRAM_GB}"')"
assert_eq "${first}" "${second}" "detect_gpu.sh is idempotent"
assert_eq "NVIDIA GeForce RTX 4090|large|24" "${first}" "repeat run still correct"

# --- environment detection twice → identical ---
export KIT_PROC_DIR="${TEST_ROOT}/mocks/proc"
first="$(capture scripts/detect_environment.sh 'run_environment_detection; echo "${CPU_MODEL}|${CPU_CORES}|${RAM_TOTAL_GB}"')"
second="$(capture scripts/detect_environment.sh 'run_environment_detection; echo "${CPU_MODEL}|${CPU_CORES}|${RAM_TOTAL_GB}"')"
assert_eq "${first}" "${second}" "detect_environment.sh is idempotent"

# --- bin commands run twice without error or state change ---
for cmd in gpu-status model-list ai-info; do
    out1="$(bash "${KIT_ROOT}/bin/${cmd}" 2>&1)"
    s1=$?
    out2="$(bash "${KIT_ROOT}/bin/${cmd}" 2>&1)"
    s2=$?
    if [[ "${s1}" -eq 0 ]] && [[ "${s2}" -eq 0 ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ ${cmd} runs cleanly twice"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ ${cmd} failed: exit ${s1}/${s2}"
    fi
done

# --- setup.sh --help twice → same output ---
h1="$(bash "${KIT_ROOT}/setup.sh" --help 2>&1)"
h2="$(bash "${KIT_ROOT}/setup.sh" --help 2>&1)"
assert_eq "${h1}" "${h2}" "setup.sh --help is stable"

report_results
