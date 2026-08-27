#!/usr/bin/env bash
# =============================================================================
# llamacpp_run.sh — llama.cpp test (REAL, runs on the GPU machine)
# =============================================================================
# llama.cpp is the PRIMARY inference runtime for this kit.
#  1. Downloads a SMALL test GGUF model (~100MB, override with GRK_TEST_MODEL_*)
#  2. Records model load time
#  3. Starts the llama.cpp OpenAI-compatible server on 127.0.0.1:8080
#  4. Waits until the API is ready
#  5. Sends a real chat completion request and verifies generated content
#  6. Measures generation speed, prompt-processing speed, GPU utilization, VRAM
#  7. Stops the server and cleans up
#
# Env overrides: GRK_TEST_MODEL_REPO, GRK_TEST_MODEL_PATTERN, GRK_TEST_PORT
# =============================================================================
set -uo pipefail

PASS=0; FAIL=0; UNKNOWN=0; WARN=0
pass()   { PASS=$((PASS+1));   echo "[PASS] $*"; }
fail()   { FAIL=$((FAIL+1));   echo "[FAIL] $*"; }
unknown(){ UNKNOWN=$((UNKNOWN+1)); echo "[UNKNOWN] $*"; }
warn()   { WARN=$((WARN+1));   echo "[WARN] $*"; }
info()   { echo "[INFO] $*"; }

MODEL_REPO="${GRK_TEST_MODEL_REPO:-HuggingFaceTB/SmolLM2-135M-Instruct-GGUF}"
MODEL_PATTERN="${GRK_TEST_MODEL_PATTERN:-*Q4_K_M.gguf}"
PORT="${GRK_TEST_PORT:-8080}"
MODEL_DIR="${HOME}/ai/models/test-grun"
LOG="/tmp/grk-llamacpp.log"
PID_FILE="/tmp/grk-llamacpp.pid"

PY="${HOME}/ai/venv/bin/python"
[[ -x "${PY}" ]] || PY="python3"
HFCLI="${HOME}/ai/venv/bin/huggingface-cli"
[[ -x "${HFCLI}" ]] || HFCLI="$(command -v huggingface-cli || echo '')"

echo "════════════════════════════════════════════════════════"
echo "  LLAMA.CPP TEST (REAL) — primary runtime"
echo "  Model repo: ${MODEL_REPO} (${MODEL_PATTERN})"
echo "════════════════════════════════════════════════════════"

cleanup() {
    [[ -f "${PID_FILE}" ]] && kill "$(cat "${PID_FILE}")" 2>/dev/null || true
    rm -f "${PID_FILE}"
    pkill -f "llama_cpp.server.*${PORT}" 2>/dev/null || true
    pkill -f "llamacpp-serve.*${PORT}" 2>/dev/null || true
    rm -rf "${MODEL_DIR}"
    info "cleanup: server stopped, test model removed (logs kept)"
}
trap cleanup EXIT

# ── 1. Obtain a small GGUF ─────────────────────────────────────────────────
info ""
info "STEP 1: obtaining small test GGUF"
mkdir -p "${MODEL_DIR}"
GGUF=""
if ! GGUF="$(find "${MODEL_DIR}" -name '*.gguf' 2>/dev/null | head -1)" || [[ -z "${GGUF}" ]]; then
    if [[ -z "${HFCLI}" ]]; then
        fail "huggingface-cli not available — cannot download test model"
        echo "  RESULTS: ${PASS} PASS, ${FAIL} FAIL, ${UNKNOWN} UNKNOWN, ${WARN} WARN"
        exit 0
    fi
    if "${HFCLI}" download "${MODEL_REPO}" --include "${MODEL_PATTERN}" --local-dir "${MODEL_DIR}" >/dev/null 2>&1; then
        GGUF="$(find "${MODEL_DIR}" -name '*.gguf' 2>/dev/null | head -1)"
        if [[ -z "${GGUF}" ]]; then
            fail "download completed but no .gguf found in ${MODEL_DIR}"
            echo "  RESULTS: ${PASS} PASS, ${FAIL} FAIL, ${UNKNOWN} UNKNOWN, ${WARN} WARN"
            exit 0
        fi
        pass "downloaded small test model: $(basename "${GGUF}") ($(du -h "${GGUF}" | cut -f1))"
    else
        fail "model download failed (${MODEL_REPO})"
        echo "  RESULTS: ${PASS} PASS, ${FAIL} FAIL, ${UNKNOWN} UNKNOWN, ${WARN} WARN"
        exit 0
    fi
else
    info "reusing existing GGUF: $(basename "${GGUF}")"
fi

# ── 2+3. Start server, record load time ────────────────────────────────────
info ""
info "STEP 2: starting llama.cpp server on 127.0.0.1:${PORT}"
if ! "${PY}" -c "import llama_cpp" >/dev/null 2>&1; then
    fail "llama_cpp not importable — cannot run test"
    echo "  RESULTS: ${PASS} PASS, ${FAIL} FAIL, ${UNKNOWN} UNKNOWN, ${WARN} WARN"
    exit 0
fi
LOAD_START="$(date +%s)"
if [[ -x "${HOME}/ai/bin/llamacpp-serve" ]]; then
    nohup "${HOME}/ai/bin/llamacpp-serve" "${GGUF}" --port "${PORT}" --n-gpu-layers 999 > "${LOG}" 2>&1 &
    echo $! > "${PID_FILE}"
else
    nohup "${PY}" -u -m llama_cpp.server --model "${GGUF}" --host 127.0.0.1 --port "${PORT}" --n_gpu_layers 999 > "${LOG}" 2>&1 &
    echo $! > "${PID_FILE}"
fi

READY=0
for i in $(seq 1 90); do
    if curl -s --max-time 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 || \
       curl -s --max-time 2 "http://127.0.0.1:${PORT}/v1/models" >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 2
done
LOAD_END="$(date +%s)"
LOAD_SECS=$((LOAD_END - LOAD_START))

if [[ "${READY}" -ne 1 ]]; then
    fail "server did not become ready within 180s"
    tail -20 "${LOG}" | sed 's/^/    /'
    echo "  RESULTS: ${PASS} PASS, ${FAIL} FAIL, ${UNKNOWN} UNKNOWN, ${WARN} WARN"
    exit 0
fi
pass "server ready (model load time: ${LOAD_SECS}s)"
info "  load time recorded"

# ── 4. Model name + context size ───────────────────────────────────────────
MODEL_NAME="$(curl -s --max-time 5 "http://127.0.0.1:${PORT}/v1/models" | "${PY}" -c 'import sys,json; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null || echo 'gpt-3.5-turbo')"
info "  API model id: ${MODEL_NAME}"

# ── 5. GPU sampling during generation ──────────────────────────────────────
GPU_SAMPLE="/tmp/grk-gpu-sample.txt"
if command -v nvidia-smi >/dev/null 2>&1; then
    ( for i in $(seq 1 40); do
          nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader 2>/dev/null
          sleep 0.25
      done > "${GPU_SAMPLE}" ) &
    SAMPLE_PID=$!
else
    SAMPLE_PID=""
fi

# ── 6. Real chat completion request ────────────────────────────────────────
info ""
info "STEP 3: sending real chat completion request"
BODY="{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"What is 2+2? Answer with just the number.\"}],\"max_tokens\":32,\"stream\":false}"
RESP="/tmp/grk-llamacpp-response.json"
TIMING="/tmp/grk-llamacpp-timing.txt"
curl -s --max-time 120 -w '%{time_starttransfer}|%{time_total}' \
    -H 'Content-Type: application/json' \
    -d "${BODY}" \
    -o "${RESP}" \
    "http://127.0.0.1:${PORT}/v1/chat/completions" 2>/dev/null > "${TIMING}"

[[ -n "${SAMPLE_PID}" ]] && kill "${SAMPLE_PID}" 2>/dev/null || true

# ── 7. Verify response ─────────────────────────────────────────────────────
CONTENT="$(cat "${RESP}" | "${PY}" -c 'import sys,json; print(json.load(sys.stdin)["choices"][0]["message"]["content"])' 2>/dev/null || echo '')"
if [[ -n "${CONTENT}" ]]; then
    pass "valid response with generated content: '$(echo "${CONTENT}" | head -c 80)'"
else
    fail "empty/invalid response — check ${RESP}"
    head -c 400 "${RESP}" | sed 's/^/    /'
fi

# ── 8. Metrics ─────────────────────────────────────────────────────────────
info ""
info "METRICS"
USAGE="$(cat "${RESP}" | "${PY}" -c 'import sys,json; u=json.load(sys.stdin)["usage"]; print(u.get("prompt_tokens",0), u.get("completion_tokens",0))' 2>/dev/null || echo '0 0')"
PROMPT_TOKENS="${USAGE%% *}"
COMPLETION_TOKENS="${USAGE##* }"
TIMING_VAL="$(cat "${TIMING}" 2>/dev/null || echo '0|0')"
TTFT="${TIMING_VAL%%|*}"
TOTAL="${TIMING_VAL##*|}"
# crude splits: prompt phase ≈ time to first token; gen phase ≈ total - ttft
PROMPT_SECS="$(awk "BEGIN { print (${TTFT} > 0 ? ${TTFT} : 0.001) }")"
GEN_SECS="$(awk "BEGIN { print (${TOTAL} > ${TTFT} ? ${TOTAL}-${TTFT} : 0.001) }")"
PROMPT_TPS="$(awk "BEGIN { printf \"%.1f\", ${PROMPT_TOKENS:-0}/${PROMPT_SECS} }")"
GEN_TPS="$(awk "BEGIN { printf \"%.1f\", ${COMPLETION_TOKENS:-0}/${GEN_SECS} }")"
info "  prompt tokens: ${PROMPT_TOKENS:-0}, completion tokens: ${COMPLETION_TOKENS:-0}"
info "  time-to-first-token: ${TTFT}s"
info "  total request time: ${TOTAL}s"
info "  prompt processing speed: ~${PROMPT_TPS} tok/s"
info "  generation speed: ~${GEN_TPS} tok/s"
info "  model load time: ${LOAD_SECS}s"
if [[ -f "${GPU_SAMPLE}" ]]; then
    UTIL_MAX="$(awk -F', ' 'BEGIN{m=0} {gsub(/%/,"",$1); if($1+0>m)m=$1+0} END{print m}' "${GPU_SAMPLE}")"
    VRAM_USED_MAX="$(awk -F', ' 'BEGIN{m=0} {gsub(/ MiB/,"",$2); if($2+0>m)m=$2+0} END{print m}' "${GPU_SAMPLE}")"
    VRAM_TOTAL="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)"
    GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
    info "  GPU: ${GPU_NAME}"
    info "  VRAM total: ${VRAM_TOTAL}"
    info "  VRAM used (max during test): ${VRAM_USED_MAX} MiB"
    info "  GPU utilization (max during test): ${UTIL_MAX}%"
else
    unknown "GPU metrics not sampled (no nvidia-smi)"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  RESULTS: ${PASS} PASS, ${FAIL} FAIL, ${UNKNOWN} UNKNOWN, ${WARN} WARN"
echo "  (REAL llama.cpp run on the actual machine)"
echo "════════════════════════════════════════════════════════"
exit 0
