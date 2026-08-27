#!/usr/bin/env bash
# =============================================================================
# install_check.sh — post-bootstrap verification (REAL, runs on the GPU machine)
# =============================================================================
# Run AFTER ./bootstrap.sh --remote-gpu. Verifies the environment the toolkit
# was supposed to create. No installs, no model downloads.
# =============================================================================
set -uo pipefail

PASS=0; FAIL=0; UNKNOWN=0; WARN=0
pass()   { PASS=$((PASS+1));   echo "[PASS] $*"; }
fail()   { FAIL=$((FAIL+1));   echo "[FAIL] $*"; }
unknown(){ UNKNOWN=$((UNKNOWN+1)); echo "[UNKNOWN] $*"; }
warn()   { WARN=$((WARN+1));   echo "[WARN] $*"; }
info()   { echo "[INFO] $*"; }

echo "════════════════════════════════════════════════════════"
echo "  GPU RENTAL KIT — Post-Install Verification (REAL)"
echo "════════════════════════════════════════════════════════"

# --- Directories ------------------------------------------------------------
info ""
info "DIRECTORIES"
for d in models cache projects config logs bin venv backups data; do
    if [[ -d "${HOME}/ai/${d}" ]]; then pass "dir: ~/ai/${d}"; else fail "dir: ~/ai/${d} missing"; fi
done

# --- Generated files --------------------------------------------------------
for f in config/machine.env logs/machine-report.txt REBUILD.md; do
    if [[ -f "${HOME}/ai/${f}" ]]; then pass "file: ~/ai/${f}"; else fail "file: ~/ai/${f} missing"; fi
done

# --- Management commands ----------------------------------------------------
info ""
info "MANAGEMENT COMMANDS"
for c in gpu-status gpu-test model-list model-download model-run model-stop model-logs ai-start ai-stop ai-logs ai-info ai-backup; do
    if [[ -x "${HOME}/ai/bin/${c}" ]]; then pass "bin: ${c}"; else fail "bin: ${c} missing/not executable"; fi
done
if grep -q "${HOME}/ai/bin" "${HOME}/.bashrc" 2>/dev/null; then pass "bashrc: PATH updated"; else warn "bashrc: PATH entry missing"; fi

# --- Python / PyTorch -------------------------------------------------------
info ""
info "PYTHON / PYTORCH"
PY="${HOME}/ai/venv/bin/python"
if [[ -x "${PY}" ]]; then
    pass "venv: python exists"
    if "${PY}" -c "import torch" >/dev/null 2>&1; then
        pass "pytorch: installed ($( "${PY}" -c 'import torch; print(torch.__version__)' 2>/dev/null ))"
        if "${PY}" -c "import torch; print(torch.cuda.is_available())" 2>/dev/null | grep -q True; then
            pass "pytorch: CUDA available"
        else
            fail "pytorch: CUDA NOT available"
        fi
    else
        fail "pytorch: not installed in venv"
    fi
else
    fail "venv: ~/ai/venv/bin/python missing"
fi

# --- llama.cpp (PRIMARY runtime) --------------------------------------------
info ""
info "LLAMA.CPP (primary runtime)"
if "${PY:-python3}" -c "import llama_cpp" >/dev/null 2>&1; then
    pass "llama.cpp: importable"
    if "${PY:-python3}" -c "import llama_cpp; print(llama_cpp.llama_supports_gpu_offload())" 2>/dev/null | grep -q True; then
        pass "llama.cpp: CUDA/GPU offload supported"
    else
        fail "llama.cpp: GPU offload NOT supported"
    fi
else
    fail "llama.cpp: not importable"
fi
if [[ -x "${HOME}/ai/bin/llamacpp-serve" ]]; then pass "llamacpp-serve: wrapper present"; else fail "llamacpp-serve: wrapper missing"; fi

# --- Other runtimes ---------------------------------------------------------
info ""
info "OTHER RUNTIMES"
if command -v ollama >/dev/null 2>&1; then
    pass "ollama: installed"
    if pgrep -f "ollama serve" >/dev/null 2>&1 || systemctl is-active ollama >/dev/null 2>&1; then
        pass "ollama: serving"
    else
        warn "ollama: installed but not running"
    fi
else
    fail "ollama: not installed"
fi
if "${PY:-python3}" -c "import vllm" >/dev/null 2>&1; then pass "vllm: importable"; else warn "vllm: not importable (optional)"; fi

# --- Docker ----------------------------------------------------------------
info ""
info "DOCKER"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    pass "docker: running"
    if command -v nvidia-ctk >/dev/null 2>&1 || command -v nvidia-container-toolkit >/dev/null 2>&1; then
        pass "nvidia-container-toolkit: installed"
    else
        warn "nvidia-container-toolkit: not installed"
    fi
else
    warn "docker: not running (optional on native setups)"
fi

# --- gpu-status / gpu-test smoke -------------------------------------------
info ""
info "COMMAND SMOKE"
if "${HOME}/ai/bin/gpu-status" >/dev/null 2>&1; then pass "gpu-status: runs"; else fail "gpu-status: failed"; fi
if [[ -f "${HOME}/ai/logs/machine-report.txt" ]] && grep -q '^GPU NAME:' "${HOME}/ai/logs/machine-report.txt"; then
    pass "machine-report: contains GPU section"
else
    warn "machine-report: GPU section missing"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  RESULTS: ${PASS} PASS, ${FAIL} FAIL, ${UNKNOWN} UNKNOWN, ${WARN} WARN"
echo "════════════════════════════════════════════════════════"
exit 0
