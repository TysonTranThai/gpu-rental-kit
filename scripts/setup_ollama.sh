#!/usr/bin/env bash
# =============================================================================
# setup_ollama.sh — Install and configure Ollama
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'

OLLAMA_INSTALLED="no"
OLLAMA_STATUS="NOT INSTALLED"
OLLAMA_FAILURE_REASON=""

# =============================================================================
# ensure_zstd — install Ollama's extraction prerequisite when supported
# =============================================================================
ensure_zstd() {
    if command -v zstd &>/dev/null; then
        echo -e "${C_GREEN}[OK]${C_RESET} zstd is available."
        return 0
    fi

    echo -e "${C_BOLD}[ollama]${C_RESET} Installing required prerequisite: zstd..."

    if command -v apt-get &>/dev/null; then
        local apt_cmd="apt-get"
        if [[ "${EUID}" -ne 0 ]]; then
            if command -v sudo &>/dev/null; then
                apt_cmd="sudo apt-get"
            else
                echo -e "${C_RED}[ERROR]${C_RESET} zstd is missing and neither root nor sudo is available."
                return 1
            fi
        fi
        if [[ "${apt_cmd}" == "sudo apt-get" ]]; then
            if ! sudo apt-get update -qq || ! sudo apt-get install -y -qq zstd; then
                echo -e "${C_RED}[ERROR]${C_RESET} Could not install zstd with apt-get."
                return 1
            fi
        elif ! apt-get update -qq || ! apt-get install -y -qq zstd; then
            echo -e "${C_RED}[ERROR]${C_RESET} Could not install zstd with apt-get."
            return 1
        fi
    elif command -v dnf &>/dev/null; then
        local dnf_cmd="dnf"
        [[ "${EUID}" -ne 0 ]] && dnf_cmd="sudo dnf"
        if ! ${dnf_cmd} install -y zstd; then
            echo -e "${C_RED}[ERROR]${C_RESET} Could not install zstd with dnf."
            return 1
        fi
    elif command -v yum &>/dev/null; then
        local yum_cmd="yum"
        [[ "${EUID}" -ne 0 ]] && yum_cmd="sudo yum"
        if ! ${yum_cmd} install -y zstd; then
            echo -e "${C_RED}[ERROR]${C_RESET} Could not install zstd with yum."
            return 1
        fi
    else
        echo -e "${C_RED}[ERROR]${C_RESET} zstd is missing and no supported package manager was found."
        return 1
    fi

    if ! command -v zstd &>/dev/null; then
        echo -e "${C_RED}[ERROR]${C_RESET} zstd installation completed but the command is still unavailable."
        return 1
    fi

    echo -e "${C_GREEN}[OK]${C_RESET} zstd installed."
}

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
        OLLAMA_STATUS="INSTALLED"
        export OLLAMA_STATUS
        return 0
    fi

    echo -e "${C_BOLD}[ollama]${C_RESET} Installing Ollama..."

    if ! ensure_zstd; then
        OLLAMA_STATUS="FAILED / OPTIONAL"
        OLLAMA_FAILURE_REASON="zstd prerequisite unavailable"
        export OLLAMA_STATUS OLLAMA_FAILURE_REASON
        return 1
    fi

    if ! command -v curl &>/dev/null; then
        echo -e "${C_RED}[ERROR]${C_RESET} curl is required to install Ollama."
        OLLAMA_STATUS="FAILED / OPTIONAL"
        OLLAMA_FAILURE_REASON="curl unavailable"
        export OLLAMA_STATUS OLLAMA_FAILURE_REASON
        return 1
    fi

    if ! curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null; then
        echo -e "${C_RED}[ERROR]${C_RESET} Ollama installation failed."
        OLLAMA_STATUS="FAILED / OPTIONAL"
        OLLAMA_FAILURE_REASON="installer failed"
        export OLLAMA_STATUS OLLAMA_FAILURE_REASON
        return 1
    fi

    if command -v ollama &>/dev/null; then
        OLLAMA_INSTALLED="yes"
        OLLAMA_STATUS="INSTALLED"
        echo -e "${C_GREEN}[OK]${C_RESET} Ollama installed."
    else
        OLLAMA_STATUS="FAILED / OPTIONAL"
        OLLAMA_FAILURE_REASON="installer completed but ollama command is unavailable"
        echo -e "${C_RED}[ERROR]${C_RESET} Ollama installer completed but ollama was not found."
    fi

    export OLLAMA_INSTALLED OLLAMA_STATUS OLLAMA_FAILURE_REASON
    [[ "${OLLAMA_INSTALLED}" == "yes" ]]
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
    if [[ "${OLLAMA_INSTALLED}" == "yes" ]]; then
        OLLAMA_STATUS="INSTALLED"
        configure_ollama
    elif install_ollama; then
        configure_ollama
    else
        echo -e "${C_YELLOW}[WARN]${C_RESET} Ollama: FAILED / OPTIONAL${OLLAMA_FAILURE_REASON:+ (${OLLAMA_FAILURE_REASON})}."
        echo -e "  Primary runtime remains llama.cpp."
        return 0
    fi
    export OLLAMA_STATUS OLLAMA_FAILURE_REASON
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    run_ollama_setup
fi