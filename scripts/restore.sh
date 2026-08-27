#!/usr/bin/env bash
# =============================================================================
# restore.sh — Restore AI configuration from a backup tarball
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_CYAN='\033[0;36m'

# =============================================================================
# restore_ai_backup — restore from tarball
# =============================================================================
restore_ai_backup() {
    local tarball="${1:-}"
    local ai_home="${AI_HOME:-${HOME}/ai}"

    if [[ -z "${tarball}" ]] || [[ ! -f "${tarball}" ]]; then
        echo -e "${C_RED}[ERROR]${C_RESET} Backup file not found: ${tarball}"
        echo "Usage: restore.sh <backup.tar.gz>"
        return 1
    fi

    echo -e "${C_BOLD}[restore]${C_RESET} Restoring from: ${tarball}"

    # Extract to temp first to avoid clobbering
    local temp_dir
    temp_dir="$(mktemp -d)"
    tar -xzf "${tarball}" -C "${temp_dir}" 2>/dev/null || {
        echo -e "${C_RED}[ERROR]${C_RESET} Failed to extract backup."
        return 1
    }

    # Find the actual backup directory inside
    local inner_dir
    inner_dir="$(find "${temp_dir}" -maxdepth 1 -mindepth 1 -type d | head -1)"

    if [[ -z "${inner_dir}" ]]; then
        echo -e "${C_RED}[ERROR]${C_RESET} Invalid backup structure."
        return 1
    fi

    # Restore config
    if [[ -d "${inner_dir}/config" ]]; then
        mkdir -p "${ai_home}/config"
        cp -r "${inner_dir}/config/." "${ai_home}/config/" 2>/dev/null || true
        echo -e "${C_GREEN}[OK]${C_RESET} Config restored."
    fi

    # Restore scripts/bin
    if [[ -d "${inner_dir}/bin" ]]; then
        mkdir -p "${ai_home}/bin"
        cp -r "${inner_dir}/bin/." "${ai_home}/bin/" 2>/dev/null || true
        echo -e "${C_GREEN}[OK]${C_RESET} Scripts restored."
    fi

    # Restore machine.env
    if [[ -f "${inner_dir}/machine.env" ]]; then
        cp "${inner_dir}/machine.env" "${ai_home}/config/machine.env" 2>/dev/null || true
        echo -e "${C_GREEN}[OK]${C_RESET} Machine env restored."
    fi

    # Restore projects
    if [[ -d "${inner_dir}/projects" ]]; then
        mkdir -p "${ai_home}/projects"
        cp -r "${inner_dir}/projects/." "${ai_home}/projects/" 2>/dev/null || true
        echo -e "${C_GREEN}[OK]${C_RESET} Projects restored."
    fi

    # Restore gpu-rental-kit
    if [[ -d "${inner_dir}/gpu-rental-kit" ]]; then
        mkdir -p "${HOME}/gpu-rental-kit"
        cp -r "${inner_dir}/gpu-rental-kit/." "${HOME}/gpu-rental-kit/" 2>/dev/null || true
        echo -e "${C_GREEN}[OK]${C_RESET} gpu-rental-kit scripts restored."
    fi

    rm -rf "${temp_dir}"

    echo -e "${C_GREEN}[OK]${C_RESET} Restore complete."
    echo -e "  ${C_CYAN}Next:${C_RESET} Re-run ./bootstrap.sh to reconfigure the environment."
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    restore_ai_backup "${1:-}"
fi