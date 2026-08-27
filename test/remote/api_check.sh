#!/usr/bin/env bash
# =============================================================================
# api_check.sh — OpenAI-compatible API verification (REAL)
# =============================================================================
# Tests against a running inference server (default 127.0.0.1:8080).
# Never exposes anything publicly — localhost only unless --base-url says
# otherwise (and even then it only makes requests; it never binds).
#
# Usage: bash test/remote/api_check.sh [--base-url http://127.0.0.1:8080]
#                                      [--model NAME] [--auth TOKEN]
# =============================================================================
set -uo pipefail

PASS=0; FAIL=0; UNKNOWN=0; WARN=0
pass()   { PASS=$((PASS+1));   echo "[PASS] $*"; }
fail()   { FAIL=$((FAIL+1));   echo "[FAIL] $*"; }
unknown(){ UNKNOWN=$((UNKNOWN+1)); echo "[UNKNOWN] $*"; }
warn()   { WARN=$((WARN+1));   echo "[WARN] $*"; }
info()   { echo "[INFO] $*"; }

BASE_URL="http://127.0.0.1:8080"
MODEL=""
AUTH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url) BASE_URL="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --auth) AUTH="$2"; shift 2 ;;
        *) warn "unknown arg: $1"; shift ;;
    esac
done

PY="$(command -v python3 || echo /usr/bin/python3)"
AUTH_HEADER=()
[[ -n "${AUTH}" ]] && AUTH_HEADER=(-H "Authorization: Bearer ${AUTH}")

echo "════════════════════════════════════════════════════════"
echo "  API TEST (REAL) — ${BASE_URL}"
echo "════════════════════════════════════════════════════════"

# ── /health ────────────────────────────────────────────────────────────────
info ""
info "ENDPOINT: GET /health"
HTTP="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${BASE_URL}/health" 2>/dev/null || echo '000')"
case "${HTTP}" in
    200) pass "GET /health → 200" ;;
    000) warn "GET /health → unreachable (server down?)" ;;
    404) warn "GET /health → 404 (endpoint not present — some servers omit it)" ;;
    *)   warn "GET /health → HTTP ${HTTP}" ;;
esac

# ── /v1/models ─────────────────────────────────────────────────────────────
info ""
info "ENDPOINT: GET /v1/models"
MODELS_JSON="$(curl -s --max-time 5 "${AUTH_HEADER[@]}" "${BASE_URL}/v1/models" 2>/dev/null || echo '')"
if [[ -n "${MODELS_JSON}" ]] && echo "${MODELS_JSON}" | "${PY}" -c 'import sys,json; json.load(sys.stdin)' >/dev/null 2>&1; then
    pass "GET /v1/models → valid JSON"
    if [[ -z "${MODEL}" ]]; then
        MODEL="$(echo "${MODELS_JSON}" | "${PY}" -c 'import sys,json; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null || echo '')"
    fi
    info "  model id: ${MODEL:-unknown}"
else
    fail "GET /v1/models → invalid/empty response"
fi

if [[ -z "${MODEL}" ]]; then
    fail "no model name available — cannot test chat completions"
    echo "  RESULTS: ${PASS} PASS, ${FAIL} FAIL, ${UNKNOWN} UNKNOWN, ${WARN} WARN"
    exit 0
fi

# ── /v1/chat/completions ───────────────────────────────────────────────────
info ""
info "ENDPOINT: POST /v1/chat/completions (model=${MODEL})"
BODY="{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: pong\"}],\"max_tokens\":16,\"stream\":false}"
RESP_FILE="$(mktemp /tmp/grk-api-response.XXXXXX)"
HTTP="$(curl -s -o "${RESP_FILE}" -w '%{http_code}' --max-time 120 \
    -H 'Content-Type: application/json' "${AUTH_HEADER[@]}" \
    -d "${BODY}" "${BASE_URL}/v1/chat/completions" 2>/dev/null || echo '000')"
info "  HTTP status: ${HTTP}"
case "${HTTP}" in
    200)
        CONTENT="$(cat "${RESP_FILE}" | "${PY}" -c 'import sys,json; print(json.load(sys.stdin)["choices"][0]["message"]["content"])' 2>/dev/null || echo '')"
        if [[ -n "${CONTENT}" ]]; then
            pass "chat completion → 200 with generated content: '$(echo "${CONTENT}" | head -c 60)'"
        else
            fail "chat completion → 200 but empty/missing content"
            head -c 300 "${RESP_FILE}" | sed 's/^/    /'
        fi
        ;;
    401|403)
        fail "chat completion → HTTP ${HTTP} (authentication required?)"
        ;;
    000)
        fail "chat completion → unreachable"
        ;;
    *)
        fail "chat completion → HTTP ${HTTP}"
        head -c 300 "${RESP_FILE}" | sed 's/^/    /'
        ;;
esac
rm -f "${RESP_FILE}"

# ── auth check (informational) ─────────────────────────────────────────────
if [[ -z "${AUTH}" ]]; then
    warn "no auth token supplied — server accepted anonymous request (informational)"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  RESULTS: ${PASS} PASS, ${FAIL} FAIL, ${UNKNOWN} UNKNOWN, ${WARN} WARN"
echo "════════════════════════════════════════════════════════"
exit 0
