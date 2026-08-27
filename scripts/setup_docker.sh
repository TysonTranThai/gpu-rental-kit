#!/usr/bin/env bash
# =============================================================================
# setup_docker.sh — Install/configure Docker with NVIDIA GPU passthrough
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'

HAS_DOCKER="no"
DOCKER_GPU_OK="no"

# =============================================================================
# detect_docker — check if Docker is installed and working
# =============================================================================
detect_docker() {
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        HAS_DOCKER="yes"
        echo -e "${C_GREEN}[OK]${C_RESET} Docker is installed and running."
    else
        HAS_DOCKER="no"
    fi
    export HAS_DOCKER
}

# =============================================================================
# install_docker — install Docker Engine on Ubuntu/Debian
# =============================================================================
install_docker() {
    if [[ "${HAS_DOCKER}" == "yes" ]]; then
        return 0
    fi

    echo -e "${C_BOLD}[docker]${C_RESET} Installing Docker Engine..."

    if [[ "${IS_DOCKER:-no}" == "yes" ]]; then
        echo -e "${C_YELLOW}[SKIP]${C_RESET} Already running inside Docker. Cannot install Docker-in-Docker by default."
        echo "  If you need Docker-in-Docker, install it manually."
        return 0
    fi

    if ! command -v apt-get &>/dev/null; then
        echo -e "${C_YELLOW}[SKIP]${C_RESET} Not on Debian/Ubuntu. Install Docker manually."
        return 0
    fi

    # Official Docker install script (most reliable)
    if command -v curl &>/dev/null; then
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sudo sh /tmp/get-docker.sh 2>/dev/null || true
        rm -f /tmp/get-docker.sh
    fi

    # Add user to docker group
    if getent group docker &>/dev/null; then
        sudo usermod -aG docker "${USER}" 2>/dev/null || true
    fi

    # Verify
    if command -v docker &>/dev/null; then
        HAS_DOCKER="yes"
        echo -e "${C_GREEN}[OK]${C_RESET} Docker installed."
        echo -e "  ${C_YELLOW}Note:${C_RESET} You may need to log out and back in for docker group to take effect."
        echo -e "  Or run: newgrp docker"
    else
        echo -e "${C_YELLOW}[WARN]${C_RESET} Docker installation may have failed. Check manually."
    fi

    export HAS_DOCKER
}

# =============================================================================
# install_nvidia_container_toolkit — install NVIDIA Docker runtime
# =============================================================================
install_nvidia_container_toolkit() {
    if [[ "${HAS_DOCKER}" != "yes" ]]; then
        return 0
    fi

    if [[ "${HAS_NVIDIA_GPU:-no}" != "yes" ]]; then
        echo -e "${C_YELLOW}[SKIP]${C_RESET} No NVIDIA GPU — skipping container toolkit."
        return 0
    fi

    # Check if nvidia-container-toolkit is already installed
    if command -v nvidia-container-toolkit &>/dev/null; then
        echo -e "${C_GREEN}[OK]${C_RESET} nvidia-container-toolkit already installed."
        DOCKER_GPU_OK="yes"
        export DOCKER_GPU_OK
        return 0
    fi

    echo -e "${C_BOLD}[docker]${C_RESET} Installing NVIDIA Container Toolkit..."

    if ! command -v apt-get &>/dev/null; then
        echo -e "${C_YELLOW}[SKIP]${C_RESET} Not on Debian/Ubuntu."
        return 0
    fi

    # Add NVIDIA container toolkit repo
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null || true

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

    sudo apt-get update -qq 2>/dev/null || true
    sudo apt-get install -y -qq nvidia-container-toolkit 2>/dev/null || true

    # Configure Docker to use nvidia runtime
    if command -v nvidia-ctk &>/dev/null; then
        sudo nvidia-ctk runtime configure --runtime=docker 2>/dev/null || true
    fi

    # Restart Docker
    if command -v systemctl &>/dev/null; then
        sudo systemctl restart docker 2>/dev/null || true
    fi

    # Verify GPU passthrough
    if docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi &>/dev/null 2>&1; then
        DOCKER_GPU_OK="yes"
        echo -e "${C_GREEN}[OK]${C_RESET} NVIDIA Docker GPU passthrough working."
    else
        echo -e "${C_YELLOW}[WARN]${C_RESET} GPU passthrough test failed. Docker may not have GPU access."
        echo -e "  Check: docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi"
    fi

    export DOCKER_GPU_OK
}

# =============================================================================
# verify_docker_gpu — quick GPU passthrough check
# =============================================================================
verify_docker_gpu() {
    if [[ "${HAS_DOCKER}" != "yes" ]]; then
        echo -e "  Docker: not installed"
        return
    fi

    echo -e "${C_BOLD}[docker]${C_RESET} Verifying Docker GPU passthrough..."

    if docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi &>/dev/null 2>&1; then
        DOCKER_GPU_OK="yes"
        echo -e "${C_GREEN}[OK]${C_RESET} Docker GPU passthrough: WORKING"
    else
        echo -e "${C_YELLOW}[WARN]${C_RESET} Docker GPU passthrough: NOT WORKING"
    fi
    export DOCKER_GPU_OK
}

# =============================================================================
# run_docker_setup
# =============================================================================
run_docker_setup() {
    detect_docker
    install_docker
    install_nvidia_container_toolkit
    verify_docker_gpu
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_docker_setup
fi