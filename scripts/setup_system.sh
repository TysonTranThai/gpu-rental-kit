#!/usr/bin/env bash
# =============================================================================
# setup_system.sh — Install base system dependencies
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'

# =============================================================================
# install_base_packages — install essential utilities
# Privileges: uses the shared abstraction (scripts/privileges.sh). Running as
# root (typical on rented GPU containers) executes commands directly — sudo is
# never required or invoked. Non-root uses sudo when present, else fails.
# =============================================================================
install_base_packages() {
    echo -e "${C_BOLD}[system]${C_RESET} Installing base packages..."

    # Resolve privileges via the shared helper (root -> SUDO="", no sudo call).
    # Non-root without sudo is a clear failure: base packages are essential.
    # shellcheck source=privileges.sh
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/privileges.sh"
    require_privileges || return 1

    if command -v apt-get &>/dev/null; then
        export DEBIAN_FRONTEND=noninteractive
        ${SUDO} apt-get update -qq
        ${SUDO} apt-get install -y -qq \
            curl wget git build-essential \
            htop tmux jq python3 python3-pip python3-venv \
            ca-certificates gnupg lsb-release \
            pciutils nvtop 2>/dev/null || true

        # Ensure python3 → python
        if ! command -v python &>/dev/null && command -v python3 &>/dev/null; then
            ${SUDO} update-alternatives --install /usr/bin/python python /usr/bin/python3 1 2>/dev/null || true
        fi

        echo -e "${C_GREEN}[OK]${C_RESET} Base packages installed."

    elif command -v dnf &>/dev/null; then
        ${SUDO} dnf install -y curl wget git htop tmux jq python3 python3-pip pciutils 2>/dev/null || true
        echo -e "${C_GREEN}[OK]${C_RESET} Base packages installed (dnf)."

    elif command -v yum &>/dev/null; then
        ${SUDO} yum install -y curl wget git htop tmux jq python3 python3-pip pciutils 2>/dev/null || true
        echo -e "${C_GREEN}[OK]${C_RESET} Base packages installed (yum)."

    else
        echo -e "${C_RED}[ERROR]${C_RESET} No supported package manager found."
        return 1
    fi

    # Ensure pip is available
    if ! command -v pip3 &>/dev/null && ! command -v pip &>/dev/null; then
        python3 -m ensurepip --upgrade 2>/dev/null || true
    fi
}

# =============================================================================
# create_ai_directories — create the standard ~/ai directory structure
# =============================================================================
create_ai_directories() {
    local ai_home="${AI_HOME:-${HOME}/ai}"
    echo -e "${C_BOLD}[system]${C_RESET} Creating AI directory structure at ${ai_home}..."

    mkdir -p "${ai_home}/models" \
             "${ai_home}/cache" \
             "${ai_home}/projects" \
             "${ai_home}/config" \
             "${ai_home}/logs" \
             "${ai_home}/bin" \
             "${ai_home}/backups" \
             "${ai_home}/data"

    echo -e "${C_GREEN}[OK]${C_RESET} AI directories created."
}

# =============================================================================
# write_machine_env — write detected environment to ~/ai/config/machine.env
# =============================================================================
write_machine_env() {
    local ai_home="${AI_HOME:-${HOME}/ai}"
    local env_file="${AI_CONFIG_DIR:-${ai_home}/config}/machine.env"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p "$(dirname "${env_file}")"

    echo -e "${C_BOLD}[system]${C_RESET} Writing machine configuration..."

    # Source detection variables if available
    # shellcheck disable=SC2154
    cat > "${env_file}" <<MACHINE_EOF
# =============================================================================
# Machine Environment — auto-generated $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================
GENERATED_AT="${timestamp}"
BOOTSTRAP_VERSION="${BOOTSTRAP_VERSION:-1.0.0}"

# --- OS ---
OS_ID="${OS_ID:-unknown}"
OS_VERSION="${OS_VERSION:-unknown}"
OS_NAME="${OS_NAME:-unknown}"
KERNEL="$(uname -r)"
ARCH="$(uname -m)"
IS_DOCKER="${IS_DOCKER:-no}"
IS_VM="${IS_VM:-no}"
IS_WSL="${IS_WSL:-no}"

# --- CPU ---
CPU_MODEL="${CPU_MODEL:-unknown}"
CPU_CORES="${CPU_CORES:-0}"

# --- RAM ---
RAM_TOTAL_GB="${RAM_TOTAL_GB:-0}"
RAM_AVAILABLE_GB="${RAM_AVAILABLE_GB:-0}"

# --- Disk ---
DISK_TOTAL_GB="${DISK_TOTAL_GB:-0}"
DISK_AVAILABLE_GB="${DISK_AVAILABLE_GB:-0}"

# --- GPU ---
HAS_NVIDIA_GPU="${HAS_NVIDIA_GPU:-no}"
GPU_COUNT="${GPU_COUNT:-0}"
GPU_NAME="${GPU_NAME:-unknown}"
GPU_VRAM_MB="${GPU_VRAM_MB:-0}"
GPU_VRAM_GB="${GPU_VRAM_GB:-0}"
GPU_ARCHITECTURE="${GPU_ARCHITECTURE:-unknown}"
GPU_COMPUTE_CAPABILITY="${GPU_COMPUTE_CAPABILITY:-unknown}"
GPU_PROFILE="${GPU_PROFILE:-unknown}"
NVIDIA_DRIVER_VERSION="${NVIDIA_DRIVER_VERSION:-}"
NVIDIA_DRIVER_OK="${NVIDIA_DRIVER_OK:-no}"
CUDA_DRIVER_VERSION="${CUDA_DRIVER_VERSION:-}"
CUDA_MAX_SUPPORTED="${CUDA_MAX_SUPPORTED:-}"

# --- AI Paths ---
AI_HOME="${ai_home}"
AI_MODELS_DIR="${AI_MODELS_DIR:-${ai_home}/models}"
AI_CACHE_DIR="${AI_CACHE_DIR:-${ai_home}/cache}"
AI_CONFIG_DIR="${AI_CONFIG_DIR:-${ai_home}/config}"
AI_LOGS_DIR="${AI_LOGS_DIR:-${ai_home}/logs}"
AI_BIN_DIR="${AI_BIN_DIR:-${ai_home}/bin}"
AI_VENV_DIR="${AI_VENV_DIR:-${ai_home}/venv}"
AI_BACKUPS_DIR="${AI_BACKUPS_DIR:-${ai_home}/backups}"
MACHINE_EOF

    echo -e "${C_GREEN}[OK]${C_RESET} Machine config written to ${env_file}"
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    install_base_packages
    create_ai_directories
    write_machine_env
fi