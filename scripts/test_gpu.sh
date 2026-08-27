#!/usr/bin/env bash
# =============================================================================
# test_gpu.sh — Verify GPU compute capability (nvidia-smi, CUDA, PyTorch)
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_CYAN='\033[0;36m'

TEST_RESULT="PASS"
FAILED_TESTS=()

# =============================================================================
# test_nvidia_smi — verify nvidia-smi works
# =============================================================================
test_nvidia_smi() {
    echo -e "${C_BOLD}[test]${C_RESET} Checking nvidia-smi..."
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        local gpu_name vram
        gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
        vram="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -1)"
        echo -e "  ${C_GREEN}[PASS]${C_RESET} nvidia-smi: ${gpu_name} (${vram})"
        return 0
    else
        echo -e "  ${C_RED}[FAIL]${C_RESET} nvidia-smi not working"
        FAILED_TESTS+=("nvidia-smi")
        TEST_RESULT="FAIL"
        return 1
    fi
}

# =============================================================================
# test_cuda_toolkit — verify CUDA availability via nvcc or PyTorch
# =============================================================================
test_cuda_toolkit() {
    echo -e "${C_BOLD}[test]${C_RESET} Checking CUDA..."

    local venv_dir="${VENV_DIR:-${AI_HOME:-${HOME}/ai}/venv}"

    # Check via nvidia-smi CUDA version
    if command -v nvidia-smi &>/dev/null; then
        local cuda_ver
        cuda_ver="$(nvidia-smi | grep 'CUDA Version' | sed 's/.*CUDA Version: //' | sed 's/ .*//' 2>/dev/null || echo "")"
        if [[ -n "${cuda_ver}" ]]; then
            echo -e "  ${C_GREEN}[PASS]${C_RESET} CUDA driver reports: ${cuda_ver}"
        fi
    fi

    # Check PyTorch CUDA
    if [[ -f "${venv_dir}/bin/python" ]]; then
        if "${venv_dir}/bin/python" -c "import torch; print(torch.cuda.is_available())" 2>/dev/null | grep -q "True"; then
            echo -e "  ${C_GREEN}[PASS]${C_RESET} PyTorch CUDA available"
            return 0
        else
            echo -e "  ${C_YELLOW}[WARN]${C_RESET} PyTorch CUDA not available (may be CPU-only build)"
        fi
    else
        echo -e "  ${C_YELLOW}[SKIP]${C_RESET} PyTorch not installed (venv missing)"
    fi

    # If we got here, PyTorch CUDA not confirmed
    if [[ -z "${cuda_ver:-}" ]]; then
        echo -e "  ${C_YELLOW}[WARN]${C_RESET} CUDA not fully confirmed"
        FAILED_TESTS+=("cuda")
        TEST_RESULT="FAIL"
        return 1
    fi
    return 0
}

# =============================================================================
# test_pytorch_gpu — run small matrix multiplication on GPU
# =============================================================================
test_pytorch_gpu() {
    echo -e "${C_BOLD}[test]${C_RESET} Running PyTorch GPU matrix multiplication..."

    local venv_dir="${VENV_DIR:-${AI_HOME:-${HOME}/ai}/venv}"

    if [[ ! -f "${venv_dir}/bin/python" ]]; then
        echo -e "  ${C_YELLOW}[SKIP]${C_RESET} PyTorch not installed."
        return 0
    fi

    local result
    result="$("${venv_dir}/bin/python" - <<'PYEOF'
import sys
try:
    import torch
    if not torch.cuda.is_available():
        print("FAIL: PyTorch CUDA not available")
        sys.exit(1)

    torch.manual_seed(42)
    a = torch.randn(1000, 1000, device="cuda", dtype=torch.float32)
    b = torch.randn(1000, 1000, device="cuda", dtype=torch.float32)

    # Warmup
    _ = a @ b
    torch.cuda.synchronize()

    import time
    start = time.time()
    c = a @ b
    torch.cuda.synchronize()
    elapsed = time.time() - start

    name = torch.cuda.get_device_name(0)
    vram_total = torch.cuda.get_device_properties(0).total_memory / (1024**3)

    print(f"PASS: {name} | {vram_total:.1f}GB VRAM | 1000x1000 matmul in {elapsed*1000:.1f}ms")
    sys.exit(0)
except Exception as e:
    print(f"FAIL: {e}")
    sys.exit(1)
PYEOF
)"

    if [[ "${result}" == PASS* ]]; then
        echo -e "  ${C_GREEN}[PASS]${C_RESET} ${result}"
        return 0
    else
        echo -e "  ${C_RED}[FAIL]${C_RESET} ${result}"
        FAILED_TESTS+=("pytorch-matmul")
        TEST_RESULT="FAIL"
        return 1
    fi
}

# =============================================================================
# test_gpu_memory — verify VRAM is accessible
# =============================================================================
test_gpu_memory() {
    echo -e "${C_BOLD}[test]${C_RESET} Checking GPU memory..."

    if command -v nvidia-smi &>/dev/null; then
        local total used free
        total="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)"
        used="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)"
        free="$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)"
        echo -e "  ${C_GREEN}[PASS]${C_RESET} VRAM: ${total}MB total, ${used}MB used, ${free}MB free"
        return 0
    else
        echo -e "  ${C_RED}[FAIL]${C_RESET} Cannot read GPU memory"
        FAILED_TESTS+=("gpu-memory")
        TEST_RESULT="FAIL"
        return 1
    fi
}

# =============================================================================
# run_gpu_tests — run all GPU tests
# =============================================================================
run_gpu_tests() {
    echo ""
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}  GPU TEST SUITE${C_RESET}"
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""

    if [[ "${HAS_NVIDIA_GPU:-no}" != "yes" ]]; then
        echo -e "${C_RED}[ERROR]${C_RESET} No NVIDIA GPU detected. Cannot run GPU tests."
        echo -e "  Run nvidia-smi to diagnose."
        return 1
    fi

    test_nvidia_smi
    test_cuda_toolkit
    test_gpu_memory
    test_pytorch_gpu

    echo ""
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
    if [[ "${TEST_RESULT}" == "PASS" ]]; then
        echo -e "  ${C_GREEN}${C_BOLD}ALL GPU TESTS PASSED ✓${C_RESET}"
    else
        echo -e "  ${C_RED}${C_BOLD}GPU TESTS FAILED for: ${FAILED_TESTS[*]}${C_RESET}"
    fi
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""

    [[ "${TEST_RESULT}" == "PASS" ]]
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    run_gpu_tests
fi