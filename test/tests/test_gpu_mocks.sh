#!/usr/bin/env bash
# =============================================================================
# test_gpu_mocks.sh — GPU detection/classification against mock nvidia-smi
# =============================================================================
# Uses mock nvidia-smi outputs for the five representative rented GPUs.
# Real GPU tests only ever run on a Linux machine with an actual GPU.
# =============================================================================
TEST_NAME="gpu_mocks"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

check_profile() {
    local profile="$1" expected="$2"
    setup_mock_gpu_env "${profile}"
    local result
    result="$(capture scripts/detect_gpu.sh \
        'run_gpu_detection; echo "${HAS_NVIDIA_GPU}|${GPU_NAME}|${GPU_VRAM_GB}|${GPU_PROFILE}|${GPU_ARCHITECTURE}|${GPU_COMPUTE_CAPABILITY}|${NVIDIA_DRIVER_OK}|${CUDA_DRIVER_VERSION}|${CUDA_MAX_SUPPORTED}"')"
    assert_eq "${expected}" "${result}" "${profile} detection+classification"
}

# Profile expectations: HAS_GPU|NAME|VRAM_GB|PROFILE|ARCH|COMPUTE|DRIVER_OK|CUDA_DRIVER|CUDA_MAX
check_profile "rtx3090"   "yes|NVIDIA GeForce RTX 3090|24|large|Ampere|8.6|yes|12.4|12.4"
check_profile "rtx4090"   "yes|NVIDIA GeForce RTX 4090|24|large|Ada Lovelace|8.9|yes|12.4|12.4"
check_profile "rtx5090"   "yes|NVIDIA GeForce RTX 5090|32|very-large|Blackwell|12.x|yes|13.0|12.4"
check_profile "rtx5060ti" "yes|NVIDIA GeForce RTX 5060 Ti|16|medium|Blackwell|12.x|yes|13.0|12.4"
check_profile "v100"      "yes|NVIDIA Tesla V100-SXM2-32GB|32|very-large|Volta|7.0|yes|12.2|12.2"

# --- no-GPU environment (macOS-like: no nvidia-smi, no lspci, no /dev/nvidia*) ---
result="$(PATH="/usr/bin:/bin" KIT_PROC_DIR="${TEST_ROOT}/mocks/proc" capture scripts/detect_gpu.sh \
    'run_gpu_detection; echo "${HAS_NVIDIA_GPU}|${GPU_PROFILE}|${GPU_VRAM_GB}|${GPU_COUNT}"')"
assert_eq "no|no-gpu|0|0" "${result}" "no-GPU environment classified safely"# --- GPU_COUNT with two GPUs ---
result="$(setup_mock_gpu_env rtx3090; export MOCK_EXTRA_GPU_COUNT=2; capture scripts/detect_gpu.sh \
    'run_gpu_detection; echo "${GPU_COUNT}"') "
assert_eq "2" "$(echo "${result}" | tr -d ' ')" "multi-GPU count detected"

report_results
