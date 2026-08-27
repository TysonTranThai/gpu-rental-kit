#!/usr/bin/env bash
# =============================================================================
# benchmark.sh — PART 8: short GPU performance benchmark (REAL)
# =============================================================================
# Measures against a running inference server (default 127.0.0.1:8080):
#   GPU name, VRAM total, VRAM used, GPU utilization, generation speed,
#   prompt-processing speed, context size, model load time (optional).
# Short by design — a handful of small requests, no stress test.
#
# Usage:
#   bash test/benchmark.sh [--base-url http://127.0.0.1:8080] [--model NAME]
#                          [--load-time SECS] [--max-tokens 48]
#   bash test/benchmark.sh --host 1.2.3.4 [--api-port 8080]
#
# Output: test/results/gpu-benchmark.txt
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ssh_lib.sh
source "${TEST_ROOT}/ssh_lib.sh"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"

BASE_URL="http://127.0.0.1:8080"
API_PORT="8080"
MODEL=""
LOAD_TIME=""
MAX_TOKENS="48"
PROMPT="Explain what a GPU does in two short sentences."

show_help() {
    cat <<'EOF'
benchmark.sh — SHORT GPU BENCHMARK (REAL, localhost by default)

  Usage:
    bash test/benchmark.sh [--base-url http://127.0.0.1:8080]
                           [--model NAME] [--load-time SECS] [--max-tokens 48]
    bash test/benchmark.sh --host 1.2.3.4 [--api-port 8080] [--user root]

  --host  runs the benchmark ON the remote machine via SSH (against its own
          127.0.0.1), so the API is never exposed to the network.

  Output: test/results/gpu-benchmark.txt
EOF
}

# --- parse args ---
clean_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url) BASE_URL="$2"; shift 2 ;;
        --api-port) API_PORT="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --load-time) LOAD_TIME="$2"; shift 2 ;;
        --max-tokens) MAX_TOKENS="$2"; shift 2 ;;
        --prompt) PROMPT="$2"; shift 2 ;;
        *) clean_args+=("$1"); shift ;;
    esac
done
set -- "${clean_args[@]}"
parse_status=0
ssh_parse_args "$@" || parse_status=$?
if [[ "${parse_status}" -eq 2 ]]; then show_help; exit 0; fi
if [[ "${parse_status}" -ne 0 ]]; then exit 1; fi

PY="$(command -v python3 || echo /usr/bin/python3)"
REPORT="${RESULTS_DIR}/gpu-benchmark.txt"

# Build the benchmark body (runs locally or on the remote via bash -s)
BENCH_BODY="$(cat <<BENCH_EOF
set -uo pipefail
BASE_URL="\${1:-${BASE_URL}}"
MODEL="\${2:-${MODEL}}"
MAX_TOKENS="${MAX_TOKENS}"
PROMPT="$(echo "${PROMPT}" | sed 's/"/\\"/g')"
PY="\$(command -v python3 || echo /usr/bin/python3)"

if [[ -z "\${MODEL}" ]]; then
    MODEL="\$(curl -s --max-time 5 "\${BASE_URL}/v1/models" | "\${PY}" -c 'import sys,json; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null || echo unknown)"
fi

echo "──────────────────────────────────────────────────────────"
echo "  GPU BENCHMARK (REAL)"
echo "  base: \${BASE_URL}  model: \${MODEL}"
echo "──────────────────────────────────────────────────────────"

# GPU identity + VRAM
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "  GPU NAME:        \$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
    echo "  VRAM TOTAL:      \$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -1)"
else
    echo "  GPU NAME:        (no nvidia-smi)"
fi

# context size via /props when available (llama.cpp)
CTX="\$(curl -s --max-time 5 "\${BASE_URL}/props" 2>/dev/null | "\${PY}" -c 'import sys,json; print(json.load(sys.stdin).get("default_generation_settings",{}).get("n_ctx","unknown"))' 2>/dev/null || echo unknown)"
echo "  CONTEXT SIZE:    \${CTX}"

# GPU sampling during the request
GPU_SAMPLE=/tmp/grk-bench-gpu.txt
if command -v nvidia-smi >/dev/null 2>&1; then
    ( for i in \$(seq 1 30); do
          nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader 2>/dev/null
          sleep 0.2
      done > \${GPU_SAMPLE} ) &
    SPID=\$!
fi

BODY="{\\\"model\\\":\\\"\${MODEL}\\\",\\\"messages\\\":[{\\\"role\\\":\\\"user\\\",\\\"content\\\":\\\"\${PROMPT}\\\"}],\\\"max_tokens\\\":\${MAX_TOKENS},\\\"stream\\\":false}"
T="\$(curl -s --max-time 180 -o /tmp/grk-bench-resp.json -w '%{time_starttransfer}|%{time_total}' \\
    -H 'Content-Type: application/json' -d "\${BODY}" "\${BASE_URL}/v1/chat/completions" 2>/dev/null || echo '0|0')"
[[ -n "\${SPID:-}" ]] && kill "\${SPID}" 2>/dev/null || true

TTFT="\${T%%|*}"
TOTAL="\${T##*|}"
USAGE="\$(cat /tmp/grk-bench-resp.json 2>/dev/null | "\${PY}" -c 'import sys,json; u=json.load(sys.stdin)["usage"]; print(u.get("prompt_tokens",0), u.get("completion_tokens",0))' 2>/dev/null || echo '0 0')"
PT="\${USAGE%% *}"
CT="\${USAGE##* }"
P_SECS="\$(awk "BEGIN { print (\${TTFT} > 0 ? \${TTFT} : 0.001) }")"
G_SECS="\$(awk "BEGIN { print (\${TOTAL} > \${TTFT} ? \${TOTAL}-\${TTFT} : 0.001) }")"
P_TPS="\$(awk "BEGIN { printf \\"%.1f\\", \${PT:-0}/\${P_SECS} }")"
G_TPS="\$(awk "BEGIN { printf \\"%.1f\\", \${CT:-0}/\${G_SECS} }")"

echo "  PROMPT PROCESSING: ~\${P_TPS} tok/s (\${PT} tokens in \${P_SECS}s)"
echo "  GENERATION:       ~\${G_TPS} tok/s (\${CT} tokens in \${G_SECS}s)"
echo "  TIME TO FIRST TOKEN: \${TTFT}s"
echo "  MODEL LOAD TIME:  ${LOAD_TIME:-not measured here (see llamacpp test)}"

if [[ -f \${GPU_SAMPLE} ]]; then
    echo "  VRAM USED (max):  \$(awk -F', ' 'BEGIN{m=0} {gsub(/ MiB/,"",\$2); if(\$2+0>m)m=\$2+0} END{print m" MiB"}' \${GPU_SAMPLE})"
    echo "  GPU UTIL (max):   \$(awk -F', ' 'BEGIN{m=0} {gsub(/%/,"",\$1); if(\$1+0>m)m=\$1+0} END{print m"%"}' \${GPU_SAMPLE})"
else
    echo "  VRAM USED:        (not sampled)"
    echo "  GPU UTIL:         (not sampled)"
fi
rm -f \${GPU_SAMPLE} /tmp/grk-bench-resp.json
BENCH_EOF
)"

# Write a copy of the benchmark body for the local path
BENCH_LOCAL="${RESULTS_DIR}/.benchmark-body.sh"
printf '%s\n' "${BENCH_BODY}" > "${BENCH_LOCAL}"
chmod +x "${BENCH_LOCAL}"

if ssh_target_ok; then
    echo "  Running benchmark ON remote $(ssh_target) (127.0.0.1:${API_PORT})..."
    if ! ssh_run_stdin "${BENCH_LOCAL}" "http://127.0.0.1:${API_PORT}" "${MODEL}" > "${REPORT}" 2>&1; then
        echo "  [FAIL] remote benchmark failed" | tee -a "${REPORT}"
        exit 1
    fi
else
    echo "  Running benchmark locally against ${BASE_URL}..."
    bash "${BENCH_LOCAL}" "${BASE_URL}" "${MODEL}" > "${REPORT}" 2>&1
fi

cat "${REPORT}"
echo ""
echo "  Report: ${REPORT}"
exit 0
