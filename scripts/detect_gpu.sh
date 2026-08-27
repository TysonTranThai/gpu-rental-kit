#!/usr/bin/env bash
# =============================================================================
# detect_gpu.sh — Detect NVIDIA GPU, driver, CUDA compatibility, VRAM
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'

# --- GPU state ---
HAS_NVIDIA_GPU="no"
GPU_COUNT=0
GPU_NAME=""
GPU_VRAM_MB=0
GPU_VRAM_GB=0
NVIDIA_DRIVER_VERSION=""
NVIDIA_DRIVER_OK="no"
CUDA_DRIVER_VERSION=""
CUDA_MAX_SUPPORTED=""
GPU_PROFILE="unknown"
GPU_ARCHITECTURE=""
GPU_COMPUTE_CAPABILITY=""

# =============================================================================
# detect_nvidia_gpu — detect GPU via nvidia-smi, lspci, or other means
# =============================================================================
detect_nvidia_gpu() {
    # Method 1: nvidia-smi (best)
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi -L &>/dev/null 2>&1; then
            HAS_NVIDIA_GPU="yes"
            GPU_COUNT="$(nvidia-smi -L 2>/dev/null | wc -l | tr -d ' ')"
            GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")"
            GPU_VRAM_MB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1 | sed 's/ MiB//' || echo "0")"
            GPU_VRAM_GB="$(awk "BEGIN {printf \"%.0f\", ${GPU_VRAM_MB}/1024}")"
            NVIDIA_DRIVER_VERSION="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "")"
            NVIDIA_DRIVER_OK="yes"
            export GPU_COUNT GPU_NAME GPU_VRAM_MB GPU_VRAM_GB NVIDIA_DRIVER_VERSION NVIDIA_DRIVER_OK HAS_NVIDIA_GPU
            return 0
        fi
    fi

    # Method 2: lspci
    if command -v lspci &>/dev/null; then
        if lspci 2>/dev/null | grep -qiE '3D|VGA.*NVIDIA'; then
            HAS_NVIDIA_GPU="yes"
            GPU_COUNT="$(lspci 2>/dev/null | grep -ciE '3D.*NVIDIA|VGA.*NVIDIA' || echo 1)"
            GPU_NAME="$(lspci 2>/dev/null | grep -iE '3D.*NVIDIA|VGA.*NVIDIA' | head -1 | sed 's/.*: //' | sed 's/(rev.*//' || echo "unknown")"
            GPU_VRAM_MB=0
            GPU_VRAM_GB=0
            export HAS_NVIDIA_GPU GPU_COUNT GPU_NAME GPU_VRAM_MB GPU_VRAM_GB
            return 0
        fi
    fi

    # Method 3: /dev/nvidia* devices exist
    if ls /dev/nvidia* &>/dev/null 2>&1; then
        HAS_NVIDIA_GPU="yes"
        GPU_COUNT="$(ls -d /dev/nvidia[0-9]* 2>/dev/null | wc -l || echo 1)"
        GPU_NAME="NVIDIA (driver present, nvidia-smi unavailable)"
        export HAS_NVIDIA_GPU GPU_COUNT GPU_NAME
        return 0
    fi

    # No GPU found
    HAS_NVIDIA_GPU="no"
    GPU_COUNT=0
    export HAS_NVIDIA_GPU GPU_COUNT
}

# =============================================================================
# detect_cuda_compat — check CUDA driver API version compatibility
# =============================================================================
detect_cuda_compat() {
    if [[ "${HAS_NVIDIA_GPU}" != "yes" ]]; then
        CUDA_DRIVER_VERSION="N/A"
        CUDA_MAX_SUPPORTED="N/A"
        export CUDA_DRIVER_VERSION CUDA_MAX_SUPPORTED
        return
    fi

    # Check via nvidia-smi
    if command -v nvidia-smi &>/dev/null; then
        CUDA_DRIVER_VERSION="$(nvidia-smi 2>/dev/null | grep "CUDA Version" | sed 's/.*CUDA Version: //' | sed 's/ .*//' || echo "unknown")"
    fi

    # Check via nvcc if installed
    if command -v nvcc &>/dev/null; then
        CUDA_MAX_SUPPORTED="$(nvcc --version 2>/dev/null | grep "release" | sed 's/.*release //' | sed 's/,.*//' || echo "")"
    fi

    # Fallback: use driver version to estimate CUDA compat
    if [[ -z "${CUDA_MAX_SUPPORTED}" ]] && [[ -n "${NVIDIA_DRIVER_VERSION}" ]]; then
        local driver_major
        driver_major="$(echo "${NVIDIA_DRIVER_VERSION}" | cut -d. -f1)"
        # Approximate mapping: driver 550+ → CUDA 12.4, 535+ → 12.2, 525+ → 12.0, 515+ → 11.7, etc.
        if [[ "${driver_major}" -ge 550 ]]; then
            CUDA_MAX_SUPPORTED="12.4"
        elif [[ "${driver_major}" -ge 535 ]]; then
            CUDA_MAX_SUPPORTED="12.2"
        elif [[ "${driver_major}" -ge 525 ]]; then
            CUDA_MAX_SUPPORTED="12.0"
        elif [[ "${driver_major}" -ge 515 ]]; then
            CUDA_MAX_SUPPORTED="11.7"
        elif [[ "${driver_major}" -ge 470 ]]; then
            CUDA_MAX_SUPPORTED="11.4"
        else
            CUDA_MAX_SUPPORTED="unknown"
        fi
    fi

    export CUDA_DRIVER_VERSION CUDA_MAX_SUPPORTED
}

# =============================================================================
# classify_gpu — determine GPU profile based on VRAM
# =============================================================================
classify_gpu() {
    if [[ "${HAS_NVIDIA_GPU}" != "yes" ]]; then
        GPU_PROFILE="no-gpu"
        GPU_ARCHITECTURE="N/A"
        GPU_COMPUTE_CAPABILITY="N/A"
        export GPU_PROFILE GPU_ARCHITECTURE GPU_COMPUTE_CAPABILITY
        return
    fi

    local vram_gb="${GPU_VRAM_GB:-0}"

    if [[ "${vram_gb}" -ge 80 ]]; then
        GPU_PROFILE="extreme"
    elif [[ "${vram_gb}" -ge 48 ]]; then
        GPU_PROFILE="extreme"
    elif [[ "${vram_gb}" -ge 32 ]]; then
        GPU_PROFILE="very-large"
    elif [[ "${vram_gb}" -ge 24 ]]; then
        GPU_PROFILE="large"
    elif [[ "${vram_gb}" -ge 16 ]]; then
        GPU_PROFILE="medium"
    elif [[ "${vram_gb}" -ge 12 ]]; then
        GPU_PROFILE="small-medium"
    elif [[ "${vram_gb}" -gt 0 ]]; then
        GPU_PROFILE="small"
    else
        GPU_PROFILE="unknown-vram"
    fi

    # Detect GPU architecture from name
    local gpu_lower
    gpu_lower="$(echo "${GPU_NAME}" | tr '[:upper:]' '[:lower:]')"

    if echo "${gpu_lower}" | grep -qE 'rtx 50'; then
        GPU_ARCHITECTURE="Blackwell"
        GPU_COMPUTE_CAPABILITY="12.x"
    elif echo "${gpu_lower}" | grep -qE 'rtx 40'; then
        GPU_ARCHITECTURE="Ada Lovelace"
        GPU_COMPUTE_CAPABILITY="8.9"
    elif echo "${gpu_lower}" | grep -qE 'rtx 30'; then
        GPU_ARCHITECTURE="Ampere"
        GPU_COMPUTE_CAPABILITY="8.6"
    elif echo "${gpu_lower}" | grep -qE 'rtx 20'; then
        GPU_ARCHITECTURE="Turing"
        GPU_COMPUTE_CAPABILITY="7.5"
    elif echo "${gpu_lower}" | grep -qiE 'v100'; then
        GPU_ARCHITECTURE="Volta"
        GPU_COMPUTE_CAPABILITY="7.0"
    elif echo "${gpu_lower}" | grep -qiE 'a100'; then
        GPU_ARCHITECTURE="Ampere"
        GPU_COMPUTE_CAPABILITY="8.0"
    elif echo "${gpu_lower}" | grep -qiE 'h100'; then
        GPU_ARCHITECTURE="Hopper"
        GPU_COMPUTE_CAPABILITY="9.0"
    elif echo "${gpu_lower}" | grep -qiE 't4|tesla t4'; then
        GPU_ARCHITECTURE="Turing"
        GPU_COMPUTE_CAPABILITY="7.5"
    elif echo "${gpu_lower}" | grep -qiE 'p100'; then
        GPU_ARCHITECTURE="Pascal"
        GPU_COMPUTE_CAPABILITY="6.0"
    else
        GPU_ARCHITECTURE="unknown"
        GPU_COMPUTE_CAPABILITY="unknown"
    fi

    export GPU_PROFILE GPU_ARCHITECTURE GPU_COMPUTE_CAPABILITY
}

# =============================================================================
# print_gpu_summary
# =============================================================================
print_gpu_summary() {
    echo ""
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}  GPU SUMMARY${C_RESET}"
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    printf "  %-22s %s\n" "NVIDIA GPU:"     "${HAS_NVIDIA_GPU}"
    printf "  %-22s %s\n" "GPU Count:"      "${GPU_COUNT}"
    printf "  %-22s %s\n" "GPU Name:"       "${GPU_NAME}"
    printf "  %-22s %s MB (%s GB)\n" "VRAM:" "${GPU_VRAM_MB}" "${GPU_VRAM_GB}"
    printf "  %-22s %s\n" "Architecture:"   "${GPU_ARCHITECTURE}"
    printf "  %-22s %s\n" "Compute Cap:"    "${GPU_COMPUTE_CAPABILITY}"
    printf "  %-22s %s\n" "Driver:"         "${NVIDIA_DRIVER_VERSION:-not detected}"
    printf "  %-22s %s\n" "Driver OK:"      "${NVIDIA_DRIVER_OK}"
    printf "  %-22s %s\n" "CUDA Driver:"    "${CUDA_DRIVER_VERSION:-N/A}"
    printf "  %-22s %s\n" "CUDA Max:"       "${CUDA_MAX_SUPPORTED:-N/A}"
    printf "  %-22s %s\n" "Profile:"        "${GPU_PROFILE}"
    echo ""

    if [[ "${HAS_NVIDIA_GPU}" != "yes" ]]; then
        echo -e "${C_RED}[ERROR]${C_RESET} No NVIDIA GPU detected."
        echo "This toolkit requires an NVIDIA GPU with working drivers."
        echo "If you believe this is incorrect, check: nvidia-smi"
    elif [[ "${NVIDIA_DRIVER_OK}" != "yes" ]]; then
        echo -e "${C_YELLOW}[WARN]${C_RESET} NVIDIA GPU detected but nvidia-smi is not working."
        echo "Run: sudo apt install -y nvidia-driver-550"
    fi
    echo ""
}

# =============================================================================
# Run all detections
# =============================================================================
run_gpu_detection() {
    detect_nvidia_gpu
    detect_cuda_compat
    classify_gpu
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_gpu_detection
    print_gpu_summary
fi