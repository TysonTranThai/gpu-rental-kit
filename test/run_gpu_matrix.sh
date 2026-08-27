#!/usr/bin/env bash
# =============================================================================
# run_gpu_matrix.sh — Mock GPU test matrix (MOCK tests, macOS-safe)
# =============================================================================
# Runs the REAL detection/classification logic (scripts/detect_gpu.sh) against
# mocked nvidia-smi outputs for every representative rented GPU, and verifies:
#   GPU name, VRAM, GPU count, driver parsing, CUDA parsing, architecture,
#   compute capability, VRAM classification, model profile selection.
#
# Output: test/results/gpu-matrix-report.txt
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "${TEST_ROOT}/.." && pwd)"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"
# shellcheck source=helpers.sh
source "${TEST_ROOT}/helpers.sh"

REPORT="${RESULTS_DIR}/gpu-matrix-report.txt"
REPORT_FILE="${REPORT}"

report_init "mock_gpu_matrix"

{
    echo "# GPU Rental Kit — Mock GPU Test Matrix"
    echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# Label: MOCK — mocked nvidia-smi outputs; no real GPU was used."
    echo ""
} > "${REPORT}"

# ── GPU matrix definition ────────────────────────────────────────────────────
# profile|name|VRAM_GB|profile|arch|compute|driver|cuda_driver|cuda_max
MATRIX=(
    "rtx3090|NVIDIA GeForce RTX 3090|24|large|Ampere|8.6|550.54.15|12.4|12.4"
    "rtx4090|NVIDIA GeForce RTX 4090|24|large|Ada Lovelace|8.9|550.54.15|12.4|12.4"
    "rtx5090|NVIDIA GeForce RTX 5090|32|very-large|Blackwell|12.x|570.124.06|13.0|12.4"
    "rtx5060ti|NVIDIA GeForce RTX 5060 Ti|16|medium|Blackwell|12.x|570.124.06|13.0|12.4"
    "rtx4070tisuper|NVIDIA GeForce RTX 4070 Ti Super|16|medium|Ada Lovelace|8.9|550.54.15|12.4|12.4"
    "v100|NVIDIA Tesla V100-SXM2-32GB|32|very-large|Volta|7.0|535.183.01|12.2|12.2"
    "v100pcie|NVIDIA Tesla V100-PCIE-16GB|16|medium|Volta|7.0|535.183.01|12.2|12.2"
)

# ── model registry fit helper ────────────────────────────────────────────────
model_fit_summary() {
    local vram_gb="$1"
    local yaml="${KIT_ROOT}/config/models.yaml"
    [[ -f "${yaml}" ]] || { echo "models.yaml missing"; return; }
    local alias="" name="" minv="" total=0 fitting=0 line
    while IFS= read -r line; do
        if [[ "${line}" =~ ^[a-zA-Z0-9_.-]+:$ ]]; then
            alias="${line%:}"; name=""; minv=""
        elif [[ "${line}" =~ ^[[:space:]]+name:[[:space:]]*(.*)$ ]]; then
            name="${BASH_REMATCH[1]}"
        elif [[ "${line}" =~ ^[[:space:]]+min_vram_gb:[[:space:]]*([0-9]+) ]]; then
            minv="${BASH_REMATCH[1]}"
            total=$((total + 1))
            [[ -n "${minv}" ]] && [[ "${vram_gb}" -ge "${minv}" ]] && fitting=$((fitting + 1))
        fi
    done < "${yaml}"
    echo "${fitting}/${total} registered models fit in ${vram_gb}GB VRAM"
}

# ── run the matrix ───────────────────────────────────────────────────────────
report_section "Per-GPU verification (MOCK)"

for entry in "${MATRIX[@]}"; do
    IFS='|' read -r profile exp_name exp_vram exp_profile exp_arch exp_cc exp_driver exp_cuda exp_max <<<"${entry}"

    setup_mock_gpu_env "${profile}"
    result="$(capture scripts/detect_gpu.sh \
        'run_gpu_detection; echo "${HAS_NVIDIA_GPU}|${GPU_NAME}|${GPU_VRAM_MB}|${GPU_VRAM_GB}|${GPU_COUNT}|${GPU_PROFILE}|${GPU_ARCHITECTURE}|${GPU_COMPUTE_CAPABILITY}|${NVIDIA_DRIVER_VERSION}|${NVIDIA_DRIVER_OK}|${CUDA_DRIVER_VERSION}|${CUDA_MAX_SUPPORTED}"')"
    IFS='|' read -r has_gpu name vram_mb vram_gb gpu_count gpu_profile arch cc driver driver_ok cuda_driver cuda_max <<<"${result}"

    report_out ""
    report_out "GPU: ${profile}  (${exp_name})"
    report_out "  LABEL: MOCK"
    report_out "  GPU NAME:        ${name}"
    report_out "  VRAM:            ${vram_mb} MiB (${vram_gb} GB)   [expect ${exp_vram} GB]"
    report_out "  GPU COUNT:       ${gpu_count}"
    report_out "  DRIVER:          ${driver}   (parsed OK: ${driver_ok})   [expect ${exp_driver}]"
    report_out "  CUDA (driver):   ${cuda_driver}   [expect ${exp_cuda}]"
    report_out "  CUDA max:        ${cuda_max}   [expect ${exp_max}]"
    report_out "  ARCHITECTURE:    ${arch}   [expect ${exp_arch}]"
    report_out "  COMPUTE CAP:     ${cc}   [expect ${exp_cc}]"
    report_out "  PROFILE:         ${gpu_profile}   [expect ${exp_profile}]"
    report_out "  MODEL FIT:       $(model_fit_summary "${vram_gb}")"

    ok=1
    [[ "${has_gpu}" == "yes" ]] || { report_fail "${profile}: GPU not detected"; ok=0; }
    [[ "${name}" == "${exp_name}" ]] || { report_fail "${profile}: name '${name}' != '${exp_name}'"; ok=0; }
    [[ "${vram_gb}" == "${exp_vram}" ]] || { report_fail "${profile}: VRAM ${vram_gb}GB != ${exp_vram}GB"; ok=0; }
    [[ "${gpu_count}" == "1" ]] || { report_fail "${profile}: GPU count '${gpu_count}' != 1"; ok=0; }
    [[ "${driver}" == "${exp_driver}" ]] || { report_fail "${profile}: driver '${driver}' != '${exp_driver}'"; ok=0; }
    [[ "${driver_ok}" == "yes" ]] || { report_fail "${profile}: driver not OK"; ok=0; }
    [[ "${cuda_driver}" == "${exp_cuda}" ]] || { report_fail "${profile}: CUDA '${cuda_driver}' != '${exp_cuda}'"; ok=0; }
    [[ "${cuda_max}" == "${exp_max}" ]] || { report_fail "${profile}: CUDA max '${cuda_max}' != '${exp_max}'"; ok=0; }
    [[ "${arch}" == "${exp_arch}" ]] || { report_fail "${profile}: arch '${arch}' != '${exp_arch}'"; ok=0; }
    [[ "${cc}" == "${exp_cc}" ]] || { report_fail "${profile}: compute cap '${cc}' != '${exp_cc}'"; ok=0; }
    [[ "${gpu_profile}" == "${exp_profile}" ]] || { report_fail "${profile}: profile '${gpu_profile}' != '${exp_profile}'"; ok=0; }
    [[ "${ok}" -eq 1 ]] && report_pass "${profile}: all checks passed"
done

# ── multi-GPU + no-GPU cases ─────────────────────────────────────────────────
report_section "Edge cases (MOCK)"

setup_mock_gpu_env rtx3090
export MOCK_EXTRA_GPU_COUNT=2
multi="$(capture scripts/detect_gpu.sh 'run_gpu_detection; echo "${GPU_COUNT}"')"
multi_trim="$(echo "${multi}" | tr -d ' ')"
report_out "  GPU COUNT (2x rtx3090, MOCK): ${multi_trim}"
if [[ "${multi_trim}" == "2" ]]; then
    report_pass "multi-GPU count = 2"
else
    report_fail "multi-GPU count = '${multi_trim}' (expected 2)"
fi

no_gpu="$(PATH="/usr/bin:/bin" KIT_PROC_DIR="${TEST_ROOT}/mocks/proc" capture scripts/detect_gpu.sh 'run_gpu_detection; echo "${HAS_NVIDIA_GPU}|${GPU_PROFILE}"')"
report_out "  No GPU (macOS-like, MOCK): ${no_gpu}"
if [[ "${no_gpu}" == "no|no-gpu" ]]; then
    report_pass "no-GPU classified safely"
else
    report_fail "no-GPU classification = '${no_gpu}' (expected 'no|no-gpu')"
fi

report_section "Summary"
report_summary

echo ""
echo "  Report: ${REPORT}"
echo ""
exit $([[ "${FAIL_N}" -eq 0 ]])
