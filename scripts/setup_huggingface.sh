#!/usr/bin/env bash
# =============================================================================
# setup_huggingface.sh — Hugging Face CLI and authentication setup
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'

# =============================================================================
# install_huggingface_cli — install huggingface_hub CLI
# =============================================================================
install_huggingface_cli() {
    local venv_dir="${VENV_DIR:-${AI_HOME:-${HOME}/ai}/venv}"

    echo -e "${C_BOLD}[huggingface]${C_RESET} Setting up Hugging Face CLI..."

    if [[ ! -f "${venv_dir}/bin/python" ]]; then
        echo -e "${C_YELLOW}[SKIP]${C_RESET} Python venv not found. Run setup_python.sh first."
        return 0
    fi

    "${venv_dir}/bin/pip" install -q huggingface_hub[cli] 2>/dev/null || true

    # Create HF config directory
    local hf_home="${HF_HOME:-${AI_HOME:-${HOME}/ai}/cache/huggingface}"
    mkdir -p "${hf_home}" "${hf_home}/hub"

    # Check if HF token exists
    local hf_token="${HF_TOKEN:-}"
    if [[ -n "${hf_token}" ]]; then
        echo -e "${C_GREEN}[OK]${C_RESET} HF_TOKEN is set."
        "${venv_dir}/bin/huggingface-cli" whoami 2>/dev/null || \
            echo -e "${C_YELLOW}[INFO]${C_RESET} HF token set but login check failed."
    else
        echo -e "${C_YELLOW}[INFO]${C_RESET} HF_TOKEN not set."
        echo -e "  Set it to access gated models: export HF_TOKEN=hf_..."
        echo -e "  Or run: ${venv_dir}/bin/huggingface-cli login"
    fi

    echo -e "${C_GREEN}[OK]${C_RESET} Hugging Face CLI ready."
}

# =============================================================================
# create_hf_download_script — model download helper
# =============================================================================
create_hf_download_script() {
    local ai_home="${AI_HOME:-${HOME}/ai}"
    local venv_dir="${VENV_DIR:-${ai_home}/venv}"

    cat > "${ai_home}/bin/hf-download" <<'HFSCRIPT'
#!/usr/bin/env bash
# hf-download — Download a model from Hugging Face
set -Eeuo pipefail

AI_HOME="${AI_HOME:-${HOME}/ai}"
VENV="${AI_HOME}/venv"
MODELS_DIR="${AI_MODELS_DIR:-${AI_HOME}/models}"

if [[ $# -lt 1 ]]; then
    echo "Usage: hf-download <model_id> [--local-dir DIR]"
    echo "Example: hf-download Qwen/Qwen2.5-7B-Instruct-GPTQ-Int4"
    exit 1
fi

MODEL="$1"
LOCAL_DIR="${MODELS_DIR}/$(echo "${MODEL}" | tr '/' '_')"

shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --local-dir) LOCAL_DIR="$2"; shift 2 ;;
        *) shift ;;
    esac
done

echo "Downloading ${MODEL} → ${LOCAL_DIR} ..."

exec "${VENV}/bin/huggingface-cli" download "${MODEL}" \
    --local-dir "${LOCAL_DIR}" \
    --local-dir-use-symlinks False \
    --resume-download
HFSCRIPT

    chmod +x "${ai_home}/bin/hf-download"

    echo -e "${C_GREEN}[OK]${C_RESET} HF download helper created: ${ai_home}/bin/hf-download"
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    install_huggingface_cli
    create_hf_download_script
fi