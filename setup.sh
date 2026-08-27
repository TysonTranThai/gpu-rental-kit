#!/usr/bin/env bash
# =============================================================================
# setup.sh — GPU Rental Kit main setup orchestrator
# =============================================================================
# Idempotent, safe, GPU-aware environment setup for short-lived rental machines.
# =============================================================================
set -Eeuo pipefail

# =============================================================================
# Global setup
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KIT_DIR="${SCRIPT_DIR}"
export _GPU_RENTAL_KIT_LOADED="1"

# --- Argument parsing ---
#   -y|--yes           auto-confirm all prompts
#   --remote-gpu       remote GPU-machine mode (Linux + NVIDIA GPU, non-interactive)
#   --interactive      force prompts even in remote mode
AUTO_CONFIRM="no"
REMOTE_MODE="no"
for arg in "$@"; do
    case "${arg}" in
        -y|--yes|--auto) AUTO_CONFIRM="yes" ;;
        --remote-gpu)    REMOTE_MODE="yes" ;;
        --interactive)   AUTO_CONFIRM="no" ;;
        -h|--help)
            echo "Usage: setup.sh [-y|--yes] [--remote-gpu] [--interactive]"
            echo ""
            echo "  -y, --yes       Auto-confirm all prompts"
            echo "  --remote-gpu    Remote GPU mode: requires Linux + NVIDIA GPU"
            echo "                  (implies -y unless --interactive is passed)"
            echo "  --interactive   Force prompts (overrides --remote-gpu auto-confirm)"
            exit 0
            ;;
    esac
done
if [[ "${REMOTE_MODE}" == "yes" ]] && [[ "${AUTO_CONFIRM}" == "no" ]] && [[ " $* " != *" --interactive "* ]]; then
    AUTO_CONFIRM="yes"
fi
export AUTO_CONFIRM REMOTE_MODE

# --- Colors ---
C_RESET='\033[0m'; C_BOLD='\033[1m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'

# =============================================================================
# Platform guard — setup.sh is for Linux GPU machines only.
# Placed BEFORE any filesystem writes so macOS runs have zero side effects.
# macOS users get the development workflow from bootstrap.sh.
# =============================================================================
if [[ "$(uname -s)" == "Darwin" ]]; then
    echo -e "${C_RED}[ERROR]${C_RESET} setup.sh is for Linux GPU machines only."
    echo -e "  Detected macOS. NVIDIA GPU setup cannot run here."
    echo -e "  Run ./bootstrap.sh instead — it offers local validation,"
    echo -e "  shell tests, and mock GPU tests for macOS development."
    exit 1
fi

# --- Load defaults ---
if [[ -f "${SCRIPT_DIR}/config/defaults.env" ]]; then
    # shellcheck source=config/defaults.env
    source "${SCRIPT_DIR}/config/defaults.env"
fi

# Allow overrides
export AI_HOME="${AI_HOME:-${HOME}/ai}"
export AI_MODELS_DIR="${AI_MODELS_DIR:-${AI_HOME}/models}"
export AI_CACHE_DIR="${AI_CACHE_DIR:-${AI_HOME}/cache}"
export AI_PROJECTS_DIR="${AI_PROJECTS_DIR:-${AI_HOME}/projects}"
export AI_CONFIG_DIR="${AI_CONFIG_DIR:-${AI_HOME}/config}"
export AI_LOGS_DIR="${AI_LOGS_DIR:-${AI_HOME}/logs}"
export AI_BIN_DIR="${AI_BIN_DIR:-${AI_HOME}/bin}"
export AI_VENV_DIR="${AI_VENV_DIR:-${AI_HOME}/venv}"
export AI_BACKUPS_DIR="${AI_BACKUPS_DIR:-${AI_HOME}/backups}"
export AI_DATA_DIR="${AI_DATA_DIR:-${AI_HOME}/data}"

# =============================================================================
# Logging
# =============================================================================
mkdir -p "${AI_LOGS_DIR}"
LOG_FILE="${AI_LOGS_DIR}/setup-$(date '+%Y%m%d-%H%M%S').log"
export LOG_FILE

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${timestamp} [${level}] ${msg}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_ok() { log "OK" "$@"; }

# =============================================================================
# Error handler
# =============================================================================
on_error() {
    local exit_code=$?
    log_error "Script failed at line ${BASH_LINENO[0]} (exit ${exit_code})"
    log_error "Check the log: ${LOG_FILE}"
    echo ""
    echo -e "${C_RED}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_RED}  SETUP FAILED — see ${LOG_FILE}${C_RESET}"
    echo -e "${C_RED}══════════════════════════════════════════════════════════${C_RESET}"
    exit "${exit_code}"
}
trap on_error ERR

# =============================================================================
# write_machine_report — concise summary at ~/ai/logs/machine-report.txt
# =============================================================================
write_machine_report() {
    local report="${AI_LOGS_DIR}/machine-report.txt"
    mkdir -p "${AI_LOGS_DIR}"

    # Determine runtime states for the report
    local pytorch_status="not installed"
    if [[ "${PYTORCH_INSTALLED:-no}" == "yes" ]]; then
        pytorch_status="installed"
        if [[ "${PYTORCH_CUDA_AVAILABLE:-no}" == "yes" ]]; then
            pytorch_status="installed (CUDA available)"
        else
            pytorch_status="installed (CUDA NOT available)"
        fi
    fi

    local docker_status="${HAS_DOCKER:-no}"
    local nctk_status="not installed"
    if command -v nvidia-container-toolkit &>/dev/null || command -v nvidia-ctk &>/dev/null; then
        nctk_status="installed"
    fi
    [[ "${DOCKER_GPU_OK:-no}" == "yes" ]] && nctk_status="working (GPU passthrough verified)"

    cat > "${report}" <<REPORT_EOF
# GPU Rental Kit — Machine Report
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

GPU:
  GPU NAME:            ${GPU_NAME:-not detected}
  VRAM:                ${GPU_VRAM_MB:-0} MiB (${GPU_VRAM_GB:-0} GB)
  GPU COUNT:           ${GPU_COUNT:-0}
  DRIVER:              ${NVIDIA_DRIVER_VERSION:-not detected}
  CUDA (driver):       ${CUDA_DRIVER_VERSION:-N/A}
  CUDA MAX SUPPORTED:  ${CUDA_MAX_SUPPORTED:-N/A}
  CUDA AVAILABLE:      ${PYTORCH_CUDA_AVAILABLE:-no}
  GPU PROFILE:         ${GPU_PROFILE:-unknown}
  PYTORCH:             ${pytorch_status}
  DOCKER:              ${docker_status}
  NVIDIA CONTAINER TOOLKIT: ${nctk_status}
  OLLAMA:              ${OLLAMA_STATUS:-${OLLAMA_INSTALLED:-no}}
  VLLM:                ${VLLM_INSTALLED:-no}
  LLAMA.CPP:           ${LLAMACPP_INSTALLED:-no}

CPU:
  CPU MODEL:           ${CPU_MODEL:-unknown}
  CPU CORES:           ${CPU_CORES:-0}

RAM:
  RAM TOTAL:           ${RAM_TOTAL_GB:-0} GB
  RAM AVAILABLE:       ${RAM_AVAILABLE_GB:-0} GB

DISK:
  DISK TOTAL:          ${DISK_TOTAL_GB:-0} GB
  DISK AVAILABLE:      ${DISK_AVAILABLE_GB:-0} GB

NETWORK:
  INTERNET:            ${INTERNET_AVAILABLE:-no}

PERSISTENT STORAGE:
  CLASSIFICATION:      ${STORAGE_CLASSIFICATION:-TEMPORARY}
  CONFIDENCE:          ${STORAGE_CONFIDENCE:-unknown}
  STATE:               ${STORAGE_STATE:-unknown}
  SURVIVES RESTART:    ${STORAGE_SURVIVES_RESTART:-unknown}
  SURVIVES DELETE:     ${STORAGE_SURVIVES_DELETE:-unknown}
  SURVIVES RENTAL END: ${STORAGE_SURVIVES_RENTAL_END:-unknown}
  ADVISORY:            ${STORAGE_ADVISORY:-}
REPORT_EOF

    log_info "Machine report written to ${report}"
}

# =============================================================================
# Header
# =============================================================================
echo -e "${C_BOLD}${C_BLUE}"
echo "══════════════════════════════════════════════════════════════"
echo "  GPU RENTAL KIT — Automated Environment Setup"
echo "══════════════════════════════════════════════════════════════"
echo -e "${C_RESET}"
echo ""
log_info "Starting setup (version ${BOOTSTRAP_VERSION:-1.0.0}, mode: $([[ "${REMOTE_MODE}" == "yes" ]] && echo remote-gpu || echo local))"
log_info "Log file: ${LOG_FILE}"
echo ""

# =============================================================================
# Step 1: Check privileges
# =============================================================================
echo -e "${C_BOLD}[1/15] Checking privileges...${C_RESET}"
if [[ "${EUID}" -eq 0 ]]; then
    log_info "Running as root."
    SUDO=""
elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
    log_info "Running as ${USER} with passwordless sudo."
    SUDO="sudo"
    export SUDO
elif command -v sudo &>/dev/null; then
    echo -e "${C_YELLOW}[INFO]${C_RESET} sudo is available but requires a password."
    echo -e "  You'll be prompted for your password when needed."
    SUDO="sudo"
    export SUDO
    sudo -v
else
    echo -e "${C_RED}[ERROR]${C_RESET} No sudo available. Some steps require root."
    echo -e "  Continue in non-root mode where possible..."
    SUDO=""
    export SUDO
fi
log_info "Privilege check complete (SUDO='${SUDO}')."

# =============================================================================
# Step 2: Detect OS
# =============================================================================
echo -e "${C_BOLD}[2/15] Detecting OS...${C_RESET}"
# shellcheck source=scripts/detect_environment.sh
source "${SCRIPT_DIR}/scripts/detect_environment.sh"
detect_os
check_distro_support || true
log_info "OS: ${OS_NAME} (${OS_ID} ${OS_VERSION})"
if [[ "${OS_ID}" == "darwin" ]]; then
    log_error "macOS detected — this is a development machine, not a GPU rental target."
    exit 1
fi

# =============================================================================
# Step 3: Detect Docker container
# =============================================================================
echo -e "${C_BOLD}[3/15] Checking container/virtualization...${C_RESET}"
detect_virtualization
log_info "Docker: ${IS_DOCKER}, VM: ${IS_VM}, WSL: ${IS_WSL}"

# =============================================================================
# Step 4: Detect GPU
# =============================================================================
echo -e "${C_BOLD}[4/15] Detecting GPU...${C_RESET}"
# shellcheck source=scripts/detect_gpu.sh
source "${SCRIPT_DIR}/scripts/detect_gpu.sh"
run_gpu_detection
log_info "GPU: ${GPU_NAME} (${GPU_VRAM_GB}GB, ${GPU_PROFILE} profile)"

if [[ "${HAS_NVIDIA_GPU}" != "yes" ]]; then
    echo ""
    echo -e "${C_RED}[ERROR]${C_RESET} No NVIDIA GPU detected."
    echo -e "  This toolkit is designed for NVIDIA GPU machines."
    echo -e "  If you expected a GPU, check with your provider."
    echo ""
    if [[ "${REMOTE_MODE}" == "yes" ]]; then
        echo -e "  ${C_RED}Remote GPU mode requires an NVIDIA GPU. Aborting.${C_RESET}"
        exit 1
    fi
    read -rp "  Continue anyway (CPU-only setup)? [y/N] " -n 1 -r
    echo
    if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 1
    fi
fi

# =============================================================================
# Step 5: Detect NVIDIA driver
# =============================================================================
echo -e "${C_BOLD}[5/15] Checking NVIDIA driver...${C_RESET}"
if [[ "${HAS_NVIDIA_GPU}" == "yes" ]] && [[ "${NVIDIA_DRIVER_OK}" != "yes" ]]; then
    echo -e "${C_RED}[ERROR]${C_RESET} NVIDIA GPU detected but driver not working."
    echo -e "  Install the driver with: sudo apt install -y nvidia-driver-550"
    echo -e "  Then reboot and re-run ./bootstrap.sh"
    echo ""
    echo -e "  ${C_YELLOW}This toolkit will NOT automatically install NVIDIA drivers.${C_RESET}"
    echo -e "  (Driver installation requires a reboot and provider-specific steps.)"
    echo ""
    if [[ "${REMOTE_MODE}" == "yes" ]]; then
        echo -e "  ${C_RED}Remote GPU mode requires a working NVIDIA driver. Aborting.${C_RESET}"
        exit 1
    fi
    read -rp "  Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 1
    fi
fi
log_info "Driver: ${NVIDIA_DRIVER_VERSION:-not detected}"

# =============================================================================
# Step 6: Detect CUDA compatibility
# =============================================================================
echo -e "${C_BOLD}[6/15] Checking CUDA compatibility...${C_RESET}"
detect_cuda_compat
log_info "CUDA driver: ${CUDA_DRIVER_VERSION}, max supported: ${CUDA_MAX_SUPPORTED}"

# =============================================================================
# Step 7: Detect CPU/RAM/disk/network
# =============================================================================
echo -e "${C_BOLD}[7/15] Detecting system resources...${C_RESET}"
detect_cpu
detect_ram
detect_disk
detect_internet
log_info "CPU: ${CPU_MODEL:0:40} (${CPU_CORES} cores), RAM: ${RAM_TOTAL_GB}GB, Disk: ${DISK_AVAILABLE_GB}GB free"

if [[ "${INTERNET_AVAILABLE}" != "yes" ]]; then
    echo -e "${C_RED}[ERROR]${C_RESET} No internet connectivity detected."
    echo -e "  This toolkit requires internet access to install packages."
    exit 1
fi

# =============================================================================
# Step 8: Detect Docker
# =============================================================================
echo -e "${C_BOLD}[8/15] Checking Docker...${C_RESET}"
# shellcheck source=scripts/setup_docker.sh
source "${SCRIPT_DIR}/scripts/setup_docker.sh"
detect_docker
log_info "Docker: ${HAS_DOCKER}"

# =============================================================================
# Step 9: Detect persistent storage
# =============================================================================
echo -e "${C_BOLD}[9/15] Detecting persistent storage...${C_RESET}"
# shellcheck source=scripts/setup_storage.sh
source "${SCRIPT_DIR}/scripts/setup_storage.sh"
detect_storage
log_info "Storage classification: ${STORAGE_CLASSIFICATION}"

# =============================================================================
# Print environment summary (concise)
# =============================================================================
echo ""
echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_BOLD}  ENVIRONMENT SUMMARY${C_RESET}"
echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
print_environment_summary
print_gpu_summary
echo ""

# =============================================================================
# Step 10: Confirmation before destructive actions
# =============================================================================
echo -e "${C_YELLOW}${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_YELLOW}${C_BOLD}  ABOUT TO INSTALL${C_RESET}"
echo -e "${C_YELLOW}${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
echo ""
echo "  The following will be installed/configured:"
echo "    - Base system utilities (curl, git, build-essential, etc.)"
echo "    - Python virtual environment at ${AI_VENV_DIR}"
echo "    - PyTorch (GPU-aware)"
echo "    - AI packages (transformers, accelerate, etc.)"
echo "    - Ollama (if not present)"
echo "    - vLLM and llama.cpp (if GPU supports)"
echo "    - Docker + NVIDIA container toolkit (if safe)"
echo ""
echo -e "  ${C_YELLOW}This may take 10-30 minutes depending on network speed.${C_RESET}"
echo ""

if [[ "${AUTO_CONFIRM:-no}" == "yes" ]]; then
    echo -e "${C_GREEN}[AUTO]${C_RESET} Proceeding automatically (AUTO_CONFIRM=yes)."
else
    read -rp "  Proceed with installation? [y/N] " -n 1 -r
    echo
    if [[ ! "${REPLY}" =~ ^[Yy]$ ]]; then
        echo "Aborting. No changes were made."
        exit 0
    fi
fi

# =============================================================================
# Step 11: Install base utilities
# =============================================================================
echo ""
echo -e "${C_BOLD}[11/15] Installing base utilities...${C_RESET}"
# shellcheck source=scripts/setup_system.sh
source "${SCRIPT_DIR}/scripts/setup_system.sh"
install_base_packages

# =============================================================================
# Step 12: Create AI directory structure
# =============================================================================
echo -e "${C_BOLD}[12/15] Creating AI directory structure...${C_RESET}"
create_ai_directories

# =============================================================================
# Step 13: Configure storage (models/cache location)
# =============================================================================
echo -e "${C_BOLD}[13/15] Configuring model/cache storage...${C_RESET}"
ALLOW_STORAGE_PROMPT="${ALLOW_STORAGE_PROMPT:-no}"
configure_model_storage

# =============================================================================
# Step 14: Configure Python environment
# =============================================================================
echo -e "${C_BOLD}[14/15] Configuring Python environment...${C_RESET}"
# shellcheck source=scripts/setup_python.sh
source "${SCRIPT_DIR}/scripts/setup_python.sh"
run_python_setup

# =============================================================================
# Step 15: Configure runtimes (Ollama, vLLM, llama.cpp, HF, Docker)
# =============================================================================
echo -e "${C_BOLD}[15/15] Configuring AI runtimes...${C_RESET}"

# Hugging Face
# shellcheck source=scripts/setup_huggingface.sh
source "${SCRIPT_DIR}/scripts/setup_huggingface.sh"
install_huggingface_cli
create_hf_download_script

# Ollama (optional; failures do not abort the primary llama.cpp setup)
# shellcheck source=scripts/setup_ollama.sh
source "${SCRIPT_DIR}/scripts/setup_ollama.sh"
run_ollama_setup

# vLLM
# shellcheck source=scripts/setup_vllm.sh
source "${SCRIPT_DIR}/scripts/setup_vllm.sh"
run_vllm_setup

# llama.cpp
# shellcheck source=scripts/setup_llamacpp.sh
source "${SCRIPT_DIR}/scripts/setup_llamacpp.sh"
run_llamacpp_setup

# Docker (last, since it's optional)
# shellcheck source=scripts/setup_docker.sh
source "${SCRIPT_DIR}/scripts/setup_docker.sh"
install_docker
install_nvidia_container_toolkit
verify_docker_gpu

# =============================================================================
# Write machine config report
# =============================================================================
echo -e "${C_BOLD}[final] Writing machine configuration...${C_RESET}"
write_machine_env

# Add storage classification + runtime status to machine.env
cat >> "${AI_CONFIG_DIR}/machine.env" <<EOF

# --- Storage ---
STORAGE_CLASSIFICATION="${STORAGE_CLASSIFICATION}"
STORAGE_CONFIDENCE="${STORAGE_CONFIDENCE:-unknown}"
STORAGE_STATE="${STORAGE_STATE:-unknown}"
STORAGE_SURVIVES_RESTART="${STORAGE_SURVIVES_RESTART:-unknown}"
STORAGE_SURVIVES_DELETE="${STORAGE_SURVIVES_DELETE:-unknown}"
STORAGE_SURVIVES_RENTAL_END="${STORAGE_SURVIVES_RENTAL_END:-unknown}"
STORAGE_ADVISORY="${STORAGE_ADVISORY:-}"
HAS_DOCKER="${HAS_DOCKER}"
DOCKER_GPU_OK="${DOCKER_GPU_OK:-no}"
INTERNET_AVAILABLE="${INTERNET_AVAILABLE}"

# --- Runtimes ---
OLLAMA_INSTALLED="${OLLAMA_INSTALLED:-no}"
OLLAMA_STATUS="${OLLAMA_STATUS:-${OLLAMA_INSTALLED:-no}}"
OLLAMA_FAILURE_REASON="${OLLAMA_FAILURE_REASON:-}"
VLLM_INSTALLED="${VLLM_INSTALLED:-no}"
LLAMACPP_INSTALLED="${LLAMACPP_INSTALLED:-no}"
PYTORCH_INSTALLED="${PYTORCH_INSTALLED:-no}"
PYTORCH_CUDA_AVAILABLE="${PYTORCH_CUDA_AVAILABLE:-no}"
EOF

# =============================================================================
# Install management commands
# =============================================================================
echo -e "${C_BOLD}[final] Installing management commands...${C_RESET}"

# Copy/symlink bin commands into AI_HOME/bin
for cmd in gpu-status gpu-test model-list model-download model-run model-stop model-logs ai-start ai-stop ai-logs ai-info ai-backup; do
    if [[ -f "${SCRIPT_DIR}/bin/${cmd}" ]]; then
        cp -f "${SCRIPT_DIR}/bin/${cmd}" "${AI_BIN_DIR}/${cmd}" 2>/dev/null || true
        chmod +x "${AI_BIN_DIR}/${cmd}" 2>/dev/null || true
    fi
done

# Add AI_HOME/bin to PATH in .bashrc
if ! grep -q "${AI_BIN_DIR}" "${HOME}/.bashrc" 2>/dev/null; then
    cat >> "${HOME}/.bashrc" <<EOF

# GPU Rental Kit
export PATH="${AI_BIN_DIR}:\$PATH"
export AI_HOME="${AI_HOME}"
EOF
    log_info "Added ${AI_BIN_DIR} to PATH in ~/.bashrc"
fi

# =============================================================================
# Run GPU tests
# =============================================================================
echo -e "${C_BOLD}[final] Running GPU tests...${C_RESET}"
# shellcheck source=scripts/test_gpu.sh
source "${SCRIPT_DIR}/scripts/test_gpu.sh"
if [[ "${HAS_NVIDIA_GPU}" == "yes" ]]; then
    run_gpu_tests || {
        log_warn "GPU tests had failures. Setup continues but verify manually."
    }
else
    echo -e "${C_YELLOW}[SKIP]${C_RESET} No GPU — skipping GPU tests."
fi

# =============================================================================
# Write machine report
# =============================================================================
echo -e "${C_BOLD}[final] Writing machine report...${C_RESET}"
write_machine_report || log_warn "Could not write machine report."

# =============================================================================
# Create rebuild instructions
# =============================================================================
echo -e "${C_BOLD}[final] Creating rebuild instructions...${C_RESET}"
cat > "${AI_HOME}/REBUILD.md" <<'REBUILD'
# GPU Rental Kit — Rebuild Instructions

This machine was configured by the GPU Rental Kit.
To rebuild this environment on a fresh machine:

```bash
git clone https://github.com/TysonTranThai/gpu-rental-kit.git gpu-rental-kit
cd gpu-rental-kit
./bootstrap.sh
```

Or, if you have a backup:

```bash
# First restore your config
tar -xzf ai-backup-*.tar.gz
./gpu-rental-kit/bootstrap.sh
```
REBUILD

log_info "Rebuild instructions written to ${AI_HOME}/REBUILD.md"

# =============================================================================
# Final summary
# =============================================================================
echo ""
echo -e "${C_GREEN}${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}  SETUP COMPLETE ✓${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
echo ""
echo -e "  ${C_BOLD}Environment:${C_RESET}"
echo -e "    AI Home:     ${AI_HOME}"
echo -e "    GPU:         ${GPU_NAME} (${GPU_VRAM_GB}GB)"
echo -e "    Profile:     ${GPU_PROFILE}"
echo -e "    Storage:     ${STORAGE_CLASSIFICATION}"
echo ""
echo -e "  ${C_BOLD}Quick commands:${C_RESET}"
echo -e "    gpu-status                     # Check GPU"
echo -e "    gpu-test                       # Test GPU compute"
echo -e "    model-list                     # List available models"
echo -e "    model-download <model>         # Download a model"
echo -e "    ai-start                       # Interactive menu"
echo -e "    ai-start vllm <model>          # Start vLLM API server"
echo -e "    ai-backup                      # Back up configuration"
echo ""
echo -e "  ${C_YELLOW}Note:${C_RESET} Run 'source ~/.bashrc' or open a new shell"
echo -e "  to use the management commands directly."
echo ""
echo -e "  ${C_BOLD}To start an AI model now:${C_RESET}"
if [[ "${HAS_NVIDIA_GPU}" == "yes" ]]; then
    if [[ "${OLLAMA_STATUS:-${OLLAMA_INSTALLED:-no}}" == "FAILED / OPTIONAL" ]]; then
        echo -e "    ${C_YELLOW}Ollama: FAILED / OPTIONAL${C_RESET}"
    else
        echo -e "    ${C_GREEN}ai-start ollama llama3.1:8b${C_RESET}  (simplest)"
    fi
    echo -e "    ${C_GREEN}ai-start vllm Qwen/Qwen2.5-7B-Instruct${C_RESET}  (OpenAI API)"
else
    echo -e "    (No GPU — CPU-only operation)"
fi
echo ""
echo -e "  Full log: ${LOG_FILE}"
echo ""
echo -e "${C_GREEN}${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"

log_info "Setup completed successfully."

exit 0