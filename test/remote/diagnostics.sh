#!/usr/bin/env bash
# =============================================================================
# diagnostics.sh — REMOTE GPU diagnostics (REAL, read-only)
# =============================================================================
# Runs on the rented Linux NVIDIA machine. Performs NO installations and
# makes NO filesystem changes. Every line is labeled PASS / FAIL / UNKNOWN /
# WARN so the caller can count results.
#
# Usage (from your Mac): bash test/remote_gpu_test.sh --host <IP>
# =============================================================================
set -uo pipefail

# --- helpers ----------------------------------------------------------------
PASS=0; FAIL=0; UNKNOWN=0; WARN=0
pass()   { PASS=$((PASS+1));   echo "[PASS] $*"; }
fail()   { FAIL=$((FAIL+1));   echo "[FAIL] $*"; }
unknown(){ UNKNOWN=$((UNKNOWN+1)); echo "[UNKNOWN] $*"; }
warn()   { WARN=$((WARN+1));   echo "[WARN] $*"; }
info()   { echo "[INFO] $*"; }

try() { # try <name> <cmd...> — PASS on exit 0, FAIL otherwise
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "${name}"; else fail "${name}"; fi
}

echo "════════════════════════════════════════════════════════"
echo "  GPU RENTAL KIT — Remote Diagnostics (REAL, read-only)"
echo "════════════════════════════════════════════════════════"
echo "  Host: $(hostname)  Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

# --- 1-5. System ------------------------------------------------------------
info "SYSTEM"
info "  OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo unknown)"
info "  Kernel: $(uname -r 2>/dev/null || echo unknown)"
info "  Arch: $(uname -m 2>/dev/null || echo unknown)"
if grep -qE 'Ubuntu|Debian' /etc/os-release 2>/dev/null; then pass "linux: supported distro"; else warn "linux: unsupported distro"; fi
info "  CPU: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ ]*//' || echo unknown) ($(nproc 2>/dev/null || echo 0) cores)"
info "  RAM: $(free -h 2>/dev/null | awk '/Mem:/{print $2" total, "$7" available"}' || echo unknown)"
info "  Disk: $(df -h / 2>/dev/null | tail -1 | awk '{print $2" total, "$4" free"}' || echo unknown)"
if curl -sI --connect-timeout 5 --max-time 8 https://huggingface.co >/dev/null 2>&1; then pass "network: internet reachable"; else fail "network: no internet"; fi

# --- 6-11. GPU / driver / CUDA ---------------------------------------------
info ""
info "GPU"
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    pass "nvidia-smi: works"
    info "  GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | tr '\n' ';')"
    info "  GPU COUNT: $(nvidia-smi -L 2>/dev/null | wc -l | tr -d ' ')"
    info "  VRAM TOTAL: $(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | tr '\n' ';')"
    info "  DRIVER: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
    info "  CUDA (driver): $(nvidia-smi 2>/dev/null | grep 'CUDA Version' | sed 's/.*CUDA Version: //' | sed 's/ .*//' || echo unknown)"
    try "gpu: nvidia-smi query" nvidia-smi --query-gpu=name --format=csv,noheader
else
    fail "nvidia-smi: not working"
    if command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -qi nvidia; then
        warn "gpu: NVIDIA device present via lspci but driver not loaded"
    else
        warn "gpu: no NVIDIA device detected"
    fi
fi

# --- 12. PyTorch CUDA -------------------------------------------------------
info ""
info "PYTORCH"
PY=""
for cand in "${HOME}/ai/venv/bin/python" python3; do
    if command -v "${cand}" >/dev/null 2>&1 || [[ -x "${cand}" ]]; then PY="${cand}"; break; fi
done
if [[ -n "${PY}" ]] && "${PY}" -c "import torch" >/dev/null 2>&1; then
    if "${PY}" -c "print(torch.cuda.is_available())" 2>/dev/null | grep -q True; then
        pass "pytorch: CUDA available"
        info "  torch $( "${PY}" -c 'import torch; print(torch.__version__)' 2>/dev/null )"
    else
        fail "pytorch: installed but CUDA NOT available"
    fi
else
    unknown "pytorch: not installed (bootstrap not run yet?)"
fi

# --- 13-15. Docker ----------------------------------------------------------
info ""
info "DOCKER"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    pass "docker: daemon running"
    if docker info 2>/dev/null | grep -qi 'nvidia'; then
        pass "docker: nvidia runtime configured"
    else
        warn "docker: nvidia runtime not visible in docker info"
    fi
    if command -v nvidia-container-toolkit >/dev/null 2>&1 || command -v nvidia-ctk >/dev/null 2>&1; then
        pass "nvidia-container-toolkit: installed"
    else
        fail "nvidia-container-toolkit: not installed"
    fi
    if docker images 2>/dev/null | grep -qi 'nvidia/cuda'; then
        if docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
            pass "docker: GPU passthrough verified (real container run)"
        else
            fail "docker: GPU passthrough FAILED (real container run)"
        fi
    else
        unknown "docker: GPU passthrough not tested (no local nvidia/cuda image; refusing to pull during diagnostics)"
    fi
else
    fail "docker: daemon not running"
fi

# --- 16-22. AI runtimes -----------------------------------------------------
info ""
info "AI RUNTIMES"
info "  Python: $("${PY:-python3}" --version 2>/dev/null || echo unknown)"
if [[ -x "${HOME}/ai/venv/bin/python" ]]; then pass "venv: ${HOME}/ai/venv exists"; else unknown "venv: ~/ai/venv missing (bootstrap not run)"; fi
if command -v huggingface-cli >/dev/null 2>&1 || "${PY:-python3}" -c "import huggingface_hub" >/dev/null 2>&1; then pass "huggingface: available"; else unknown "huggingface: not installed"; fi
if "${PY:-python3}" -c "import llama_cpp" >/dev/null 2>&1; then
    pass "llama.cpp: importable"
    if "${PY:-python3}" -c "import llama_cpp; print(llama_cpp.llama_supports_gpu_offload())" 2>/dev/null | grep -q True; then
        pass "llama.cpp: CUDA/GPU offload supported"
    else
        fail "llama.cpp: GPU offload NOT supported (CPU-only build)"
    fi
else
    unknown "llama.cpp: not installed"
fi
if command -v ollama >/dev/null 2>&1; then pass "ollama: installed ($(ollama --version 2>/dev/null | head -1))"; else unknown "ollama: not installed"; fi
if "${PY:-python3}" -c "import vllm" >/dev/null 2>&1; then pass "vllm: importable"; else unknown "vllm: not installed"; fi

# --- 23. Model directories --------------------------------------------------
info ""
info "MODEL DIRECTORIES"
for d in models cache config logs bin venv backups; do
    if [[ -d "${HOME}/ai/${d}" ]]; then pass "dir: ~/ai/${d}"; else unknown "dir: ~/ai/${d} missing"; fi
done
if [[ -f "${HOME}/ai/config/machine.env" ]]; then pass "machine.env: present"; else unknown "machine.env: missing"; fi

# --- 24. Storage ------------------------------------------------------------
info ""
info "STORAGE (diagnostic only — no durability claim)"
df -hT 2>/dev/null | grep -vE 'tmpfs|overlay|proc|sysfs' | head -10 | sed 's/^/  /'
if [[ -d /mnt ]] && [[ "$(df -h /mnt 2>/dev/null | tail -1 | awk '{print $6}')" != "/" ]]; then
    warn "storage: /mnt appears to be a separate mount (durability unverified)"
fi
if [[ -f /.dockerenv ]] || grep -qE 'docker|kubepods' /proc/1/cgroup 2>/dev/null; then
    warn "storage: running inside a container — local writes die with the container"
fi
unknown "storage: rental-level persistence cannot be verified from inside the machine"

# --- 25-26. Ports + API -----------------------------------------------------
info ""
info "NETWORK PORTS / API"
LISTEN=""
if command -v ss >/dev/null 2>&1; then LISTEN="$(ss -tln 2>/dev/null)"; elif command -v netstat >/dev/null 2>&1; then LISTEN="$(netstat -tln 2>/dev/null)"; fi
for port in 8000 8080 11434 5000; do
    if echo "${LISTEN}" | grep -qE ":${port}[[:space:]]"; then
        info "  port ${port}: LISTENING"
        if curl -s --max-time 3 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
            pass "api: http://127.0.0.1:${port}/health responds"
        elif curl -s --max-time 3 "http://127.0.0.1:${port}/v1/models" >/dev/null 2>&1; then
            pass "api: http://127.0.0.1:${port}/v1/models responds"
        else
            unknown "api: port ${port} listening but no health/model endpoint"
        fi
    else
        info "  port ${port}: not listening"
    fi
done
if ! echo "${LISTEN}" | grep -qE ':8000|:8080|:11434'; then
    unknown "api: no inference server currently running"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  RESULTS: ${PASS} PASS, ${FAIL} FAIL, ${UNKNOWN} UNKNOWN, ${WARN} WARN"
echo "  (REAL diagnostics — run on the actual machine)"
echo "════════════════════════════════════════════════════════"
exit 0
