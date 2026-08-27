#!/usr/bin/env bash
# =============================================================================
# setup_python.sh — Configure Python virtual environment and PyTorch
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_CYAN='\033[0;36m'

PYTHON_BIN="python3"

# --- Runtime status (populated here, consumed by setup.sh → machine.env) ---
VLLM_INSTALLED="no"
LLAMACPP_INSTALLED="no"
PYTORCH_INSTALLED="no"
PYTORCH_CUDA_AVAILABLE="no"

# =============================================================================
# setup_python_venv — create Python virtual environment
# =============================================================================
setup_python_venv() {
    local ai_home="${AI_HOME:-${HOME}/ai}"
    local venv_dir="${AI_VENV_DIR:-${ai_home}/venv}"

    echo -e "${C_BOLD}[python]${C_RESET} Setting up Python virtual environment..."

    # Find best Python
    PYTHON_BIN="python3"
    if command -v python3.11 &>/dev/null; then
        PYTHON_BIN="python3.11"
    elif command -v python3.12 &>/dev/null; then
        PYTHON_BIN="python3.12"
    elif command -v python3.10 &>/dev/null; then
        PYTHON_BIN="python3.10"
    fi

    echo -e "  Using: ${PYTHON_BIN} ($(${PYTHON_BIN} --version 2>&1))"

    # Create venv if not exists
    if [[ ! -d "${venv_dir}" ]]; then
        ${PYTHON_BIN} -m venv "${venv_dir}"
        echo -e "${C_GREEN}[OK]${C_RESET} Virtual environment created at ${venv_dir}"
    else
        echo -e "${C_YELLOW}[SKIP]${C_RESET} Virtual environment already exists at ${venv_dir}"
    fi

    # Upgrade pip
    "${venv_dir}/bin/pip" install --upgrade pip setuptools wheel -q 2>/dev/null || true

    export PYTHON_BIN VENV_DIR="${venv_dir}"
}

# =============================================================================
# install_pytorch — install PyTorch with appropriate CUDA support
# =============================================================================
install_pytorch() {
    local venv_dir="${VENV_DIR:-${AI_HOME:-${HOME}/ai}/venv}"
    local pip="${venv_dir}/bin/pip"

    echo -e "${C_BOLD}[python]${C_RESET} Installing PyTorch..."

    # Check if PyTorch is already installed and working
    if "${venv_dir}/bin/python" -c "import torch; print(torch.__version__)" &>/dev/null 2>&1; then
        PYTORCH_INSTALLED="yes"
        local existing_version
        existing_version="$("${venv_dir}/bin/python" -c "import torch; print(torch.__version__)" 2>/dev/null)"
        local cuda_available
        cuda_available="$("${venv_dir}/bin/python" -c "import torch; print(torch.cuda.is_available())" 2>/dev/null || echo "False")"
        [[ "${cuda_available}" == "True" ]] && PYTORCH_CUDA_AVAILABLE="yes"

        echo -e "  Existing PyTorch ${existing_version} found (CUDA available: ${cuda_available})"

        if [[ "${cuda_available}" == "True" ]] && [[ "${HAS_NVIDIA_GPU:-no}" == "yes" ]]; then
            echo -e "${C_GREEN}[OK]${C_RESET} Working PyTorch with CUDA already installed. Preserving."
            return 0
        elif [[ "${HAS_NVIDIA_GPU:-no}" != "yes" ]]; then
            echo -e "${C_YELLOW}[INFO]${C_RESET} No GPU available, keeping existing PyTorch."
            return 0
        else
            echo -e "${C_YELLOW}[WARN]${C_RESET} PyTorch installed but CUDA not working. Will reinstall."
        fi
    fi

    # Determine CUDA version for PyTorch
    local torch_index="https://download.pytorch.org/whl/cpu"
    local torch_extra=""

    if [[ "${HAS_NVIDIA_GPU:-no}" == "yes" ]]; then
        local cuda_ver="${CUDA_MAX_SUPPORTED:-12.1}"
        local cuda_major
        cuda_major="$(echo "${cuda_ver}" | cut -d. -f1)"

        if [[ "${cuda_major}" -ge 12 ]]; then
            torch_index="https://download.pytorch.org/whl/cu124"
            torch_extra="--index-url ${torch_index}"
            echo -e "  Targeting CUDA 12.4 PyTorch build"
        elif [[ "${cuda_major}" -ge 11 ]]; then
            torch_index="https://download.pytorch.org/whl/cu118"
            torch_extra="--index-url ${torch_index}"
            echo -e "  Targeting CUDA 11.8 PyTorch build"
        else
            echo -e "${C_YELLOW}[WARN]${C_RESET} CUDA version unknown or too old. Installing CPU-only PyTorch."
        fi
    else
        echo -e "  No NVIDIA GPU — installing CPU-only PyTorch."
    fi

    # Install PyTorch
    if ${pip} install torch torchvision torchaudio ${torch_extra} -q 2>/dev/null; then
        PYTORCH_INSTALLED="yes"
        echo -e "${C_GREEN}[OK]${C_RESET} PyTorch installed."
    else
        # Fallback: try without index
        echo -e "${C_YELLOW}[WARN]${C_RESET} Indexed install failed, trying default PyPI..."
        ${pip} install torch torchvision torchaudio -q 2>/dev/null || {
            echo -e "${C_RED}[ERROR]${C_RESET} Failed to install PyTorch."
            return 1
        }
        PYTORCH_INSTALLED="yes"
    fi

    # Re-check CUDA availability after install
    if "${venv_dir}/bin/python" -c "import torch; print(torch.cuda.is_available())" 2>/dev/null | grep -q True; then
        PYTORCH_CUDA_AVAILABLE="yes"
    fi
    export PYTORCH_INSTALLED PYTORCH_CUDA_AVAILABLE
}

# =============================================================================
# install_ai_packages — install common AI/ML Python packages
# =============================================================================
install_ai_packages() {
    local venv_dir="${VENV_DIR:-${AI_HOME:-${HOME}/ai}/venv}"
    local pip="${venv_dir}/bin/pip"

    echo -e "${C_BOLD}[python]${C_RESET} Installing AI Python packages..."

    ${pip} install \
        transformers accelerate datasets \
        huggingface_hub[hf_transfer] \
        sentencepiece tokenizers \
        safetensors ninja packaging \
        -q 2>/dev/null || {
        echo -e "${C_YELLOW}[WARN]${C_RESET} Some AI packages failed to install. Continuing..."
    }

    echo -e "${C_GREEN}[OK]${C_RESET} AI Python packages installed."
}

# =============================================================================
# configure_huggingface — set up HF cache and environment
# =============================================================================
configure_huggingface() {
    local ai_home="${AI_HOME:-${HOME}/ai}"
    local hf_cache="${HF_HOME:-${ai_home}/cache/huggingface}"

    echo -e "${C_BOLD}[python]${C_RESET} Configuring Hugging Face..."

    mkdir -p "${hf_cache}/hub"

    # Write HF config to shell profile snippet
    local profile_snippet="${ai_home}/config/hf_env.sh"
    cat > "${profile_snippet}" <<HF_EOF
# Hugging Face environment
export HF_HOME="${hf_cache}"
export HF_HUB_CACHE="${hf_cache}/hub"
export HF_HUB_ENABLE_HF_TRANSFER="1"
# Set your token if needed:
# export HF_TOKEN="hf_..."
HF_EOF

    # shellcheck disable=SC1090
    export HF_HOME="${hf_cache}"
    export HF_HUB_CACHE="${hf_cache}/hub"
    export HF_HUB_ENABLE_HF_TRANSFER="1"

    echo -e "${C_GREEN}[OK]${C_RESET} Hugging Face configured (cache: ${hf_cache})"
    echo -e "  Source ${profile_snippet} to use in new shells."
}

# =============================================================================
# install_vllm — install vLLM
# =============================================================================
install_vllm_pkg() {
    local venv_dir="${VENV_DIR:-${AI_HOME:-${HOME}/ai}/venv}"
    local pip="${venv_dir}/bin/pip"

    echo -e "${C_BOLD}[python]${C_RESET} Installing vLLM..."

    if "${venv_dir}/bin/python" -c "import vllm" &>/dev/null 2>&1; then
        VLLM_INSTALLED="yes"
        echo -e "${C_GREEN}[OK]${C_RESET} vLLM already installed."
        export VLLM_INSTALLED
        return 0
    fi

    if ${pip} install vllm -q 2>/dev/null; then
        VLLM_INSTALLED="yes"
        echo -e "${C_GREEN}[OK]${C_RESET} vLLM installed."
    else
        echo -e "${C_YELLOW}[WARN]${C_RESET} vLLM installation failed. It requires a recent GPU."
        echo -e "  You can try manually: pip install vllm"
    fi
    export VLLM_INSTALLED
}

# =============================================================================
# install_llamacpp — install llama-cpp-python with GPU support
# =============================================================================
install_llamacpp_pkg() {
    local venv_dir="${VENV_DIR:-${AI_HOME:-${HOME}/ai}/venv}"
    local pip="${venv_dir}/bin/pip"

    echo -e "${C_BOLD}[python]${C_RESET} Installing llama-cpp-python..."

    if "${venv_dir}/bin/python" -c "import llama_cpp" &>/dev/null 2>&1; then
        LLAMACPP_INSTALLED="yes"
        echo -e "${C_GREEN}[OK]${C_RESET} llama-cpp-python already installed."
        export LLAMACPP_INSTALLED
        return 0
    fi

    # Try GPU-enabled build
    if [[ "${HAS_NVIDIA_GPU:-no}" == "yes" ]]; then
        # Try the prebuilt server binary approach first
        if CMAKE_ARGS="-DGGML_CUDA=on" ${pip} install llama-cpp-python --force-reinstall --no-cache-dir -q 2>/dev/null || \
            ${pip} install llama-cpp-python -q 2>/dev/null; then
            LLAMACPP_INSTALLED="yes"
        else
            echo -e "${C_YELLOW}[WARN]${C_RESET} llama-cpp-python install failed."
        fi
    else
        ${pip} install llama-cpp-python -q 2>/dev/null && LLAMACPP_INSTALLED="yes" || true
    fi
    export LLAMACPP_INSTALLED

    echo -e "${C_GREEN}[OK]${C_RESET} llama-cpp-python installed."
}

# =============================================================================
# run_all_python_setup
# =============================================================================
run_python_setup() {
    setup_python_venv
    install_pytorch
    install_ai_packages
    configure_huggingface
    install_vllm_pkg
    install_llamacpp_pkg
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    run_python_setup
fi