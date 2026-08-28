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
# test_multi_gpu_detection — verify all GPUs are visible and listed
# =============================================================================
test_multi_gpu_detection() {
    echo -e "${C_BOLD}[test]${C_RESET} Checking multi-GPU detection..."

    if [[ "${GPU_COUNT:-0}" -lt 2 ]]; then
        echo -e "  ${C_YELLOW}[SKIP]${C_RESET} Only ${GPU_COUNT:-0} GPU(s) present — nothing multi-GPU to test."
        return 0
    fi

    if [[ "$(echo "${GPU_NAMES_LIST}" | tr '|' '\n' | grep -c . )" -eq "${GPU_COUNT}" ]] \
       && [[ "${GPU_TOTAL_VRAM_MB}" -gt 0 ]]; then
        echo -e "  ${C_GREEN}[PASS]${C_RESET} ${GPU_COUNT} GPUs detected; aggregate VRAM ${GPU_TOTAL_VRAM_GB} GB"
        return 0
    else
        echo -e "  ${C_RED}[FAIL]${C_RESET} GPU list incomplete (count=${GPU_COUNT}, total=${GPU_TOTAL_VRAM_MB}MB)"
        FAILED_TESTS+=("multi-gpu-detection")
        TEST_RESULT="FAIL"
        return 1
    fi
}

# =============================================================================
# test_multi_gpu_cuda — tiny matmul on EVERY GPU via PyTorch (cheap)
# =============================================================================
test_multi_gpu_cuda() {
    echo -e "${C_BOLD}[test]${C_RESET} Checking CUDA on every GPU..."

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
    n = torch.cuda.device_count()
    if n < 2:
        print(f"SKIP: only {n} CUDA device(s) visible to PyTorch")
        sys.exit(2)
    ok = []
    for i in range(n):
        a = torch.ones(64, 64, device=f"cuda:{i}")
        b = a @ a
        torch.cuda.synchronize(i)
        ok.append(f"cuda:{i}={torch.cuda.get_device_name(i)}")
    print("PASS: " + " | ".join(ok))
    sys.exit(0)
except Exception as e:
    print(f"FAIL: {e}")
    sys.exit(1)
PYEOF
)" 2>/dev/null || true

    case "${result}" in
        PASS*)
            echo -e "  ${C_GREEN}[PASS]${C_RESET} ${result#PASS: }"
            return 0
            ;;
        SKIP*)
            echo -e "  ${C_YELLOW}[SKIP]${C_RESET} ${result#SKIP: }"
            return 0
            ;;
        *)
            echo -e "  ${C_RED}[FAIL]${C_RESET} ${result:-no output}"
            FAILED_TESTS+=("multi-gpu-cuda")
            TEST_RESULT="FAIL"
            return 1
            ;;
    esac
}

# =============================================================================
# test_gpu_to_gpu — check P2P connectivity (report-only, no benchmark)
# =============================================================================
test_gpu_to_gpu() {
    echo -e "${C_BOLD}[test]${C_RESET} Checking GPU-to-GPU communication capability..."

    if [[ "${GPU_COUNT:-0}" -lt 2 ]]; then
        echo -e "  ${C_YELLOW}[SKIP]${C_RESET} Single GPU."
        return 0
    fi

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
    n = torch.cuda.device_count()
    if n < 2:
        print("SKIP: <2 devices")
        sys.exit(2)
    links = []
    for i in range(n):
        for j in range(i + 1, n):
            can = torch.cuda.can_device_access_peer(i, j)
            links.append(f"cuda:{i}<->cuda:{j}={'P2P' if can else 'no-P2P'}")
    print("INFO: " + " | ".join(links))
    sys.exit(0)
except Exception as e:
    print(f"SKIP: {e}")
    sys.exit(2)
PYEOF
)" 2>/dev/null || true

    case "${result}" in
        INFO*)
            echo -e "  ${C_GREEN}[INFO]${C_RESET} ${result#INFO: }"
            echo "        (P2P requires compatible hardware/driver; no-P2P is common on cloud GPUs)"
            return 0
            ;;
        *)
            echo -e "  ${C_YELLOW}[SKIP]${C_RESET} ${result#SKIP: }"
            return 0
            ;;
    esac
}

# =============================================================================
# test_benchmark — OPTIONAL micro-benchmark (single vs multi-GPU).
# Never run by default: gpu-test --bench. Reports honest micro-benchmark
# numbers (matmul GFLOPS, P2P bandwidth); these are NOT LLM tokens/s.
# =============================================================================
test_benchmark() {
    echo -e "${C_BOLD}[bench]${C_RESET} Running optional GPU micro-benchmark..."
    echo "        (micro-benchmark only — NOT a language-model throughput test)"

    local venv_dir="${VENV_DIR:-${AI_HOME:-${HOME}/ai}/venv}"
    if [[ ! -f "${venv_dir}/bin/python" ]]; then
        echo -e "  ${C_YELLOW}[SKIP]${C_RESET} PyTorch not installed — benchmark needs PyTorch."
        return 0
    fi

    local result
    result="$("${venv_dir}/bin/python" - <<'PYEOF'
import sys
try:
    import torch, time
    n = torch.cuda.device_count()
    if n < 1:
        print("SKIP: no CUDA devices")
        sys.exit(2)

    sizes = [2048, 2048, 4096]
    per_gpu = []
    for i in range(n):
        torch.cuda.set_device(i)
        dev = f"cuda:{i}"
        a = torch.randn(2048, 2048, device=dev, dtype=torch.float16)
        b = torch.randn(2048, 2048, device=dev, dtype=torch.float16)
        _ = a @ b  # warmup
        torch.cuda.synchronize(i)
        reps, t0 = 10, time.time()
        for _ in range(reps):
            _ = a @ b
        torch.cuda.synchronize(i)
        dt = (time.time() - t0) / reps
        gflops = (2 * 2048**3) / dt / 1e9
        mem = torch.cuda.max_memory_allocated(i) / (1024**2)
        torch.cuda.reset_peak_memory_stats(i)
        per_gpu.append(f"cuda:{i}={gflops:.0f} GFLOPS fp16 ({mem:.0f}MB peak)")

    lines = ["BENCH|" + " | ".join(per_gpu)]

    # Multi-GPU: P2P copy bandwidth between pairs that support it
    if n >= 2:
        p2p = []
        for i in range(n):
            for j in range(i + 1, n):
                if torch.cuda.can_device_access_peer(i, j):
                    src = torch.randn(64, 1024 * 1024, device=f"cuda:{i}", dtype=torch.float16)  # 128MB
                    dst = torch.empty_like(src, device=f"cuda:{j}")
                    torch.cuda.synchronize(i)
                    reps, t0 = 5, time.time()
                    for _ in range(reps):
                        dst.copy_(src, non_blocking=True)
                    torch.cuda.synchronize(j)
                    dt = (time.time() - t0) / reps
                    gbps = (src.numel() * 2) / dt / 1e9
                    p2p.append(f"cuda:{i}->cuda:{j}={gbps:.1f} GB/s")
                    del src, dst
                else:
                    p2p.append(f"cuda:{i}->cuda:{j}=no-P2P (PCIe path, skip)")
        lines.append("P2P|" + " | ".join(p2p))
    print("\n".join(lines))
    sys.exit(0)
except Exception as e:
    print(f"FAIL: {e}")
    sys.exit(1)
PYEOF
)" 2>/dev/null || true

    local first="$(printf '%s' "${result}" | head -1)"
    case "${first}" in
        BENCH*)
            echo -e "  ${C_GREEN}[BENCH]${C_RESET} ${first#BENCH|}"
            local p2p_line
            p2p_line="$(printf '%s\n' "${result}" | grep '^P2P|' || true)"
            [[ -n "${p2p_line}" ]] && echo -e "  ${C_GREEN}[BENCH]${C_RESET} ${p2p_line#P2P|}"
            echo "        Caveat: raw matmul/P2P numbers say little about end-to-end LLM"
            echo "        speed; multi-GPU scaling depends on backend, model and topology."
            return 0
            ;;
        SKIP*)
            echo -e "  ${C_YELLOW}[SKIP]${C_RESET} ${first#SKIP: }"
            return 0
            ;;
        *)
            echo -e "  ${C_RED}[FAIL]${C_RESET} ${first:-no output}"
            FAILED_TESTS+=("benchmark")
            TEST_RESULT="FAIL"
            return 1
            ;;
    esac
}

# =============================================================================
# run_gpu_tests — run all GPU tests. --multi = deeper multi-GPU checks,
# --bench = optional micro-benchmark (never on by default).
# =============================================================================
run_gpu_tests() {
    local multi="no" bench="no"
    local arg
    for arg in "$@"; do
        case "${arg}" in
            --multi) multi="yes" ;;
            --bench) bench="yes" ;;
        esac
    done
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

    if [[ "${multi}" == "yes" ]]; then
        echo ""
        echo -e "${C_BOLD}Multi-GPU tests:${C_RESET}"
        test_multi_gpu_detection
        test_multi_gpu_cuda
        test_gpu_to_gpu
    fi

    if [[ "${bench}" == "yes" ]]; then
        echo ""
        echo -e "${C_BOLD}Benchmark (optional):${C_RESET}"
        test_benchmark
    fi

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
    run_gpu_tests "$@"
fi