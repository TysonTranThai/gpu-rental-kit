#!/usr/bin/env bash
# =============================================================================
# setup_ollama.sh — Install and configure Ollama
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'

OLLAMA_INSTALLED="no"

# =============================================================================
# detect_ollama — check if ollama is installed
# =============================================================================
detect_ollama() {
    if command -v ollama &>/dev/null; then
        OLLAMA_INSTALLED="yes"
        echo -e "${C_GREEN}[OK]${C_RESET} Ollama is installed ($(ollama --version 2>/dev/null || echo 'unknown'))."
    fi
    export OLLAMA_INSTALLED
}

# =============================================================================
# install_ollama — install Ollama
# =============================================================================
install_ollama() {
    if [[ "${OLLAMA_INSTALLED}" == "yes" ]]; then
        return 0
    fi

    echo -e "${C_BOLD}[ollama]${C_RESET} Installing Ollama..."

    if command -v curl &>/dev/null; then
        curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null || {
            echo -e "${C_RED}[ERROR]${C_RESET} Ollama installation failed."
            return 1
        }
    else
        echo -e "${C_YELLOW}[SKIP]${C_RESET} curl not available. Install Ollama manually."
        return 0
    fi

    if command -v ollama &>/dev/null; then
        OLLAMA_INSTALLED="yes"
        echo -e "${C_GREEN}[OK]${C_RESET} Ollama installed."
    fi

    export OLLAMA_INSTALLED
}

# =============================================================================
# configure_ollama — set model directory and service configuration
# =============================================================================
configure_ollama() {
    if [[ "${OLLAMA_INSTALLED}" != "yes" ]]; then
        return 0
    fi

    echo -e "${C_BOLD}[ollama]${C_RESET} Configuring Ollama..."

    local ai_home="${AI_HOME:-${HOME}/ai}"
    local ollama_models="${OLLAMA_MODELS:-${ai_home}/models/ollama}"

    mkdir -p "${ollama_models}"

    # Configure via systemd override
    if command -v systemctl &>/dev/null && systemctl is-active ollama &>/dev/null 2>&1; then
        sudo systemctl stop ollama 2>/dev/null || true

        sudo mkdir -p /etc/systemd/system/ollama.service.d
        sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<OLLAMA_OVERRIDE
[Service]
Environment="OLLAMA_HOST=${OLLAMA_HOST:-127.0.0.1:11434}"
Environment="OLLAMA_MODELS=${ollama_models}"
Environment="OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE:-5m}"
OLLAMA_OVERRIDE

        sudo systemctl daemon-reload
        sudo systemctl enable ollama 2>/dev/null || true
        sudo systemctl start ollama 2>/dev/null || true
    else
        # Non-systemd: set env vars and start manually
        export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
        export OLLAMA_MODELS="${ollama_models}"
        export OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-5m}"

        # Kill existing ollama if running
        pkill ollama 2>/dev/null || true
        nohup ollama serve > "${ai_home}/logs/ollama.log" 2>&1 &
        echo $! > "${ai_home}/logs/ollama.pid"
    fi

    echo -e "${C_GREEN}[OK]${C_RESET} Ollama configured."
    echo -e "  Model directory: ${ollama_models}"
    echo -e "  Host: ${OLLAMA_HOST:-127.0.0.1:11434}"
}

# =============================================================================
# run_ollama_setup
# =============================================================================
run_ollama_setup() {
    detect_ollama
    install_ollama
    configure_ollama
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    run_ollama_setup
fi