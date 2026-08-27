#!/usr/bin/env bash
# =============================================================================
# cleanup.sh — Clean up temporary files, caches, and exited processes
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'

# =============================================================================
# cleanup_logs — remove old logs beyond retention period
# =============================================================================
cleanup_logs() {
    local ai_home="${AI_HOME:-${HOME}/ai}"
    local logs_dir="${AI_LOGS_DIR:-${ai_home}/logs}"
    local retention="${LOG_RETENTION_DAYS:-30}"

    if [[ -d "${logs_dir}" ]]; then
        echo -e "${C_BOLD}[cleanup]${C_RESET} Removing logs older than ${retention} days..."
        find "${logs_dir}" -name "*.log" -mtime "+${retention}" -delete 2>/dev/null || true
        echo -e "${C_GREEN}[OK]${C_RESET} Old logs removed."
    fi
}

# =============================================================================
# cleanup_hf_cache — clean Hugging Face cache of unused files
# =============================================================================
cleanup_hf_cache() {
    local hf_cache="${HF_HOME:-${HOME}/ai/cache/huggingface}"

    if [[ -d "${hf_cache}" ]]; then
        echo -e "${C_BOLD}[cleanup]${C_RESET} Hugging Face cache: $(du -sh "${hf_cache}" 2>/dev/null | cut -f1)"
        echo -e "  Run 'huggingface-cli delete-cache' for interactive cleanup."
    fi
}

# =============================================================================
# cleanup_stopped_containers — remove exited Docker containers
# =============================================================================
cleanup_stopped_containers() {
    if command -v docker &>/dev/null; then
        echo -e "${C_BOLD}[cleanup]${C_RESET} Cleaning Docker..."
        docker container prune -f 2>/dev/null || true
        docker image prune -f 2>/dev/null || true
        echo -e "${C_GREEN}[OK]${C_RESET} Docker cleaned."
    fi
}

# =============================================================================
# stop_ai_services — stop running AI services
# =============================================================================
stop_ai_services() {
    local ai_home="${AI_HOME:-${HOME}/ai}"

    echo -e "${C_BOLD}[cleanup]${C_RESET} Stopping AI services..."

    # Ollama
    if command -v ollama &>/dev/null; then
        if [[ -f "${ai_home}/logs/ollama.pid" ]]; then
            kill "$(cat "${ai_home}/logs/ollama.pid")" 2>/dev/null || true
            rm -f "${ai_home}/logs/ollama.pid"
        fi
        pkill -f "ollama serve" 2>/dev/null || true
    fi

    # vLLM
    pkill -f "vllm.entrypoints" 2>/dev/null || true

    # llama.cpp
    pkill -f "llama_cpp.server" 2>/dev/null || true

    echo -e "${C_GREEN}[OK]${C_RESET} AI services stopped."
}

# =============================================================================
# show_system_usage — display current resource usage
# =============================================================================
show_system_usage() {
    echo -e "${C_BOLD}[usage]${C_RESET}"
    echo ""
    echo -e "${C_CYAN}AI directory:${C_RESET}"
    du -sh "${AI_HOME:-${HOME}/ai}"/*/ 2>/dev/null || true
    echo ""
    echo -e "${C_CYAN}Disk usage:${C_RESET}"
    df -h / 2>/dev/null | tail -1
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    case "${1:-}" in
        --logs)     cleanup_logs ;;
        --docker)   cleanup_stopped_containers ;;
        --stop)     stop_ai_services ;;
        --usage)    show_system_usage ;;
        *)
            cleanup_logs
            cleanup_stopped_containers
            show_system_usage
            ;;
    esac
fi