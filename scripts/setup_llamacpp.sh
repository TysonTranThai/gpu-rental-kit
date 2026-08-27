#!/usr/bin/env bash
# =============================================================================
# setup_llamacpp.sh — Prepare llama.cpp runtime
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'

# =============================================================================
# detect_llamacpp_available
# =============================================================================
detect_llamacpp_available() {
    local venv_dir="${VENV_DIR:-${AI_HOME:-${HOME}/ai}/venv}"

    if [[ -f "${venv_dir}/bin/python" ]] && \
       "${venv_dir}/bin/python" -c "import llama_cpp" &>/dev/null 2>&1; then
        echo -e "${C_GREEN}[OK]${C_RESET} llama-cpp-python is available."
        return 0
    else
        echo -e "${C_YELLOW}[INFO]${C_RESET} llama-cpp-python is not installed. Run setup_python.sh first."
        return 1
    fi
}

# =============================================================================
# configure_llamacpp — create the llama.cpp server wrapper
# =============================================================================
configure_llamacpp() {
    local ai_home="${AI_HOME:-${HOME}/ai}"

    echo -e "${C_BOLD}[llamacpp]${C_RESET} Configuring llama.cpp..."

    mkdir -p "${ai_home}/bin"
    local llamacpp_wrapper="${ai_home}/bin/llamacpp-serve"
    cat > "${llamacpp_wrapper}" <<'LCPP_WRAPPER'
#!/usr/bin/env bash
# =============================================================================
# llamacpp-serve — Start llama.cpp OpenAI-compatible server
# =============================================================================
set -Eeuo pipefail

AI_HOME="${AI_HOME:-${HOME}/ai}"
VENV="${AI_HOME}/venv"

usage() {
    echo "Usage: llamacpp-serve <MODEL_PATH> [--port PORT] [--host HOST] [--api-key KEY] [--extra-args ...]"
    echo ""
    echo "Examples:"
    echo "  llamacpp-serve ~/ai/models/llama-3-8b-q4.gguf"
    echo "  llamacpp-serve TheBloke/Llama-3-8B-Instruct-GGUF --port 8081 --n-gpu-layers 35"
    echo "  LLAMACPP_API_KEY=secret llamacpp-serve ~/ai/models/llama-3-8b-q4.gguf"
    exit 1
}

MODEL="${1:-}"
if [[ -z "${MODEL}" ]]; then
    usage
fi
shift || true

PORT="${LLAMACPP_PORT:-8080}"
HOST="${LLAMACPP_HOST:-127.0.0.1}"
API_KEY="${LLAMACPP_API_KEY:-}"

# Parse args
REST_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --api-key) API_KEY="$2"; shift 2 ;;
        *) REST_ARGS+=("$1"); shift ;;
    esac
done

echo "Starting llama.cpp server..."
echo "  Model: ${MODEL}"
echo "  Endpoint: http://${HOST}:${PORT}"
[[ -n "${API_KEY}" ]] && echo "  API auth: enabled (Bearer key required)"

if [[ -n "${API_KEY}" ]]; then
    exec "${VENV}/bin/python" -u -m llama_cpp.server \
        --model "${MODEL}" \
        --host "${HOST}" \
        --port "${PORT}" \
        --api-key "${API_KEY}" \
        "${REST_ARGS[@]}"
else
    exec "${VENV}/bin/python" -u -m llama_cpp.server \
        --model "${MODEL}" \
        --host "${HOST}" \
        --port "${PORT}" \
        "${REST_ARGS[@]}"
fi
LCPP_WRAPPER

    chmod +x "${llamacpp_wrapper}"

    echo -e "${C_GREEN}[OK]${C_RESET} llama.cpp configured."
    echo -e "  Wrapper: ${llamacpp_wrapper}"
    echo -e "  Default port: ${LLAMACPP_PORT:-8080}"
}

# =============================================================================
# run_llamacpp_setup
# =============================================================================
run_llamacpp_setup() {
    detect_llamacpp_available || return 0
    configure_llamacpp
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    run_llamacpp_setup
fi