#!/usr/bin/env bash
# =============================================================================
# setup_vllm.sh — Prepare vLLM for high-performance inference
# =============================================================================
# vLLM is installed as a Python package in setup_python.sh.
# This script prepares the runtime configuration.
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'

# =============================================================================
# detect_vllm_available — check if vLLM is installed
# =============================================================================
detect_vllm_available() {
    local venv_dir="${VENV_DIR:-${AI_HOME:-${HOME}/ai}/venv}"

    if [[ -f "${venv_dir}/bin/python" ]] && \
       "${venv_dir}/bin/python" -c "import vllm" &>/dev/null 2>&1; then
        echo -e "${C_GREEN}[OK]${C_RESET} vLLM is available."
        return 0
    else
        echo -e "${C_YELLOW}[INFO]${C_RESET} vLLM is not installed. Run setup_python.sh first."
        return 1
    fi
}

# =============================================================================
# configure_vllm — create vLLM configuration and helper script
# =============================================================================
configure_vllm() {
    local ai_home="${AI_HOME:-${HOME}/ai}"

    echo -e "${C_BOLD}[vllm]${C_RESET} Configuring vLLM..."

    mkdir -p "${ai_home}/bin"
    # Create the vLLM server wrapper
    local vllm_wrapper="${ai_home}/bin/vllm-serve"
    cat > "${vllm_wrapper}" <<'VLLM_WRAPPER'
#!/usr/bin/env bash
# =============================================================================
# vllm-serve — Start vLLM OpenAI-compatible server
# =============================================================================
set -Eeuo pipefail

AI_HOME="${AI_HOME:-${HOME}/ai}"
VENV="${AI_HOME}/venv"

usage() {
    echo "Usage: vllm-serve <MODEL_PATH> [--port PORT] [--host HOST] [--extra-args ...]"
    echo ""
    echo "Examples:"
    echo "  vllm-serve Qwen/Qwen2.5-7B-Instruct"
    echo "  vllm-serve meta-llama/Llama-3-8B-Instruct --port 8001"
    echo "  vllm-serve /path/to/model --tensor-parallel-size 2"
    exit 1
}

MODEL="${1:-}"
if [[ -z "${MODEL}" ]]; then
    usage
fi
shift || true

PORT="${VLLM_PORT:-8000}"
HOST="${VLLM_HOST:-127.0.0.1}"
API_KEY="${VLLM_API_KEY:-}"

# Parse --port, --host and --api-key
REST_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --api-key) API_KEY="$2"; shift 2 ;;
        *) REST_ARGS+=("$1"); shift ;;
    esac
done

echo "Starting vLLM server..."
echo "  Model: ${MODEL}"
echo "  Endpoint: http://${HOST}:${PORT}/v1"

[[ -n "${API_KEY}" ]] && echo "  API auth: enabled (Bearer key required)"

exec "${VENV}/bin/python" -u -m vllm.entrypoints.openai.api_server \
    --model "${MODEL}" \
    --host "${HOST}" \
    --port "${PORT}" \
    --trust-remote-code \
    $([[ -n "${API_KEY}" ]] && echo --api-key "${API_KEY}") \
    "${REST_ARGS[@]}"
VLLM_WRAPPER

    chmod +x "${vllm_wrapper}"

    echo -e "${C_GREEN}[OK]${C_RESET} vLLM configured."
    echo -e "  Wrapper: ${vllm_wrapper}"
    echo -e "  Default port: ${VLLM_PORT:-8000}"
    echo -e "  ${C_YELLOW}Note:${C_RESET} vLLM binds to 127.0.0.1 by default (safe)."
    echo -e "        To expose on LAN: vllm-serve MODEL --host 0.0.0.0"
}

# =============================================================================
# run_vllm_setup
# =============================================================================
run_vllm_setup() {
    detect_vllm_available || return 0
    configure_vllm
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    run_vllm_setup
fi