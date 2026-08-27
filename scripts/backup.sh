#!/usr/bin/env bash
# =============================================================================
# backup.sh — Back up AI configuration (NOT huge model files by default)
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_CYAN='\033[0;36m'

# =============================================================================
# backup_ai_config — backup scripts, config, manifests, environment info
# =============================================================================
backup_ai_config() {
    local ai_home="${AI_HOME:-${HOME}/ai}"
    local backups_dir="${AI_BACKUPS_DIR:-${ai_home}/backups}"
    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    local backup_name="ai-backup-${timestamp}"
    local backup_path="${backups_dir}/${backup_name}"

    echo -e "${C_BOLD}[backup]${C_RESET} Creating backup..."

    mkdir -p "${backup_path}"

    # Backup scripts
    if [[ -d "${ai_home}/bin" ]]; then
        cp -r "${ai_home}/bin" "${backup_path}/bin" 2>/dev/null || true
    fi

    # Backup config
    if [[ -d "${ai_home}/config" ]]; then
        cp -r "${ai_home}/config" "${backup_path}/config" 2>/dev/null || true
    fi

    # Backup model manifests (list of models, not the models themselves)
    if [[ -d "${ai_home}/models" ]]; then
        find "${ai_home}/models" -maxdepth 2 -type d > "${backup_path}/model-directories.txt" 2>/dev/null || true
        find "${ai_home}/models" -maxdepth 2 -name "*.yaml" -o -name "*.yml" -o -name "*.json" 2>/dev/null | \
            while read -r f; do cp "${f}" "${backup_path}/" 2>/dev/null || true; done
    fi

    # Backup environment info
    if [[ -f "${ai_home}/config/machine.env" ]]; then
        cp "${ai_home}/config/machine.env" "${backup_path}/machine.env" 2>/dev/null || true
    fi

    # Backup git config / project config
    if [[ -d "${ai_home}/projects" ]]; then
        find "${ai_home}/projects" -maxdepth 2 -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.env" 2>/dev/null | \
            while read -r f; do
                mkdir -p "${backup_path}/projects/$(dirname "${f}" | sed "s#${ai_home}/projects/##")"
                cp "${f}" "${backup_path}/projects/$(dirname "${f}" | sed "s#${ai_home}/projects/##")/" 2>/dev/null || true
            done
    fi

    # Backup the gpu-rental-kit repo itself (scripts + config)
    local kit_dir="${KIT_DIR:-}"
    if [[ -n "${kit_dir}" ]] && [[ -d "${kit_dir}" ]]; then
        mkdir -p "${backup_path}/gpu-rental-kit"
        cp -r "${kit_dir}/scripts" "${backup_path}/gpu-rental-kit/" 2>/dev/null || true
        cp -r "${kit_dir}/config" "${backup_path}/gpu-rental-kit/" 2>/dev/null || true
        cp -r "${kit_dir}/bin" "${backup_path}/gpu-rental-kit/" 2>/dev/null || true
        cp "${kit_dir}/bootstrap.sh" "${backup_path}/gpu-rental-kit/" 2>/dev/null || true
        cp "${kit_dir}/setup.sh" "${backup_path}/gpu-rental-kit/" 2>/dev/null || true
    fi

    # Create tarball
    local tarball="${backups_dir}/${backup_name}.tar.gz"
    tar -czf "${tarball}" -C "${backups_dir}" "${backup_name}" 2>/dev/null || true

    # Clean up temp dir
    rm -rf "${backup_path}"

    # Write manifest
    cat > "${backups_dir}/${backup_name}.manifest" <<MANIFEST
Backup: ${backup_name}
Created: $(date)
Machine: $(hostname)
Contains: scripts, config, model manifests, environment info
NOTE: Model files are NOT included by default.
MANIFEST

    echo -e "${C_GREEN}[OK]${C_RESET} Backup created: ${tarball}"
    echo -e "  Manifest: ${backups_dir}/${backup_name}.manifest"
    echo -e "  ${C_YELLOW}Size:${C_RESET} $(du -sh "${tarball}" 2>/dev/null | cut -f1 || echo 'unknown')"
    echo ""
    echo -e "  ${C_CYAN}To restore:${C_RESET} ai-backup --restore ${tarball}"
    echo ""
    echo -e "  ${C_YELLOW}IMPORTANT:${C_RESET} Model files are NOT backed up."
    echo -e "  If you need models too, run: ai-backup --include-models"
}

# =============================================================================
# backup_ai_full — backup including models (explicitly requested)
# =============================================================================
backup_ai_full() {
    local ai_home="${AI_HOME:-${HOME}/ai}"
    local backups_dir="${AI_BACKUPS_DIR:-${ai_home}/backups}"
    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    local backup_name="ai-backup-full-${timestamp}"
    local backup_path="${backups_dir}/${backup_name}"

    echo -e "${C_BOLD}[backup]${C_RESET} Creating FULL backup (including models)..."

    mkdir -p "${backup_path}"

    # Everything in ai_home except backups dir itself
    if [[ -d "${ai_home}" ]]; then
        find "${ai_home}" -maxdepth 1 -mindepth 1 ! -name backups -exec cp -r {} "${backup_path}/" \; 2>/dev/null || true
    fi

    # Create tarball
    local tarball="${backups_dir}/${backup_name}.tar.gz"
    tar -czf "${tarball}" -C "${backups_dir}" "${backup_name}" 2>/dev/null || true
    rm -rf "${backup_path}"

    echo -e "${C_GREEN}[OK]${C_RESET} Full backup created: ${tarball}"
    echo -e "  ${C_YELLOW}Size:${C_RESET} $(du -sh "${tarball}" 2>/dev/null | cut -f1 || echo 'unknown')"
}

# =============================================================================
# list_backups — list existing backups
# =============================================================================
list_backups() {
    local backups_dir="${AI_BACKUPS_DIR:-${HOME}/ai/backups}"
    if [[ -d "${backups_dir}" ]]; then
        echo -e "${C_BOLD}Available backups:${C_RESET}"
        for f in "${backups_dir}"/ai-backup*.tar.gz; do
            [[ -f "${f}" ]] || continue
            printf "  %s (%s KB)\n" "$(basename "${f}")" "$(du -k "${f}" 2>/dev/null | cut -f1)"
        done | sort
    else
        echo "No backups found."
    fi
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    case "${1:-}" in
        --include-models|--full)
            backup_ai_full
            ;;
        --list)
            list_backups
            ;;
        *)
            backup_ai_config
            ;;
    esac
fi