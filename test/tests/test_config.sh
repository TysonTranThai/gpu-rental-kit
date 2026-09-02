#!/usr/bin/env bash
# =============================================================================
# test_config.sh — configuration parsing and safety checks
# =============================================================================
TEST_NAME="config"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

# --- defaults.env resolves with default HOME ---
result="$(HOME="${TEST_TMP}/home-default" bash -c '
    source "'"${KIT_ROOT}"'/config/defaults.env"
    echo "${AI_HOME}|${AI_MODELS_DIR}|${AI_LOGS_DIR}"
')"
assert_eq "${TEST_TMP}/home-default/ai|${TEST_TMP}/home-default/ai/models|${TEST_TMP}/home-default/ai/logs" \
    "${result}" "defaults.env resolves relative to HOME"

# --- defaults.env respects user-provided env vars (no override) ---
result="$(HOME="${TEST_TMP}/home-a" AI_HOME="/custom/ai" bash -c '
    source "'"${KIT_ROOT}"'/config/defaults.env"
    echo "${AI_HOME}|${AI_MODELS_DIR}"
')"
assert_eq "/custom/ai|/custom/ai/models" "${result}" "defaults.env respects AI_HOME override"

# --- defaults.env can be sourced twice safely (idempotent) ---
result="$(HOME="${TEST_TMP}/home-b" bash -c '
    source "'"${KIT_ROOT}"'/config/defaults.env"
    source "'"${KIT_ROOT}"'/config/defaults.env"
    echo "${AI_HOME}"
')"
assert_eq "${TEST_TMP}/home-b/ai" "${result}" "defaults.env double-source is stable"

# --- models.yaml contains expected aliases ---
# Legacy names (llama3-8b-gguf, mistral-7b-gguf) must survive refreshes — they
# are referenced in all three READMEs and user workflows.
# Current-generation families (qwen3, gemma3, deepseek-r1) must be present.
if [[ -f "${KIT_ROOT}/config/models.yaml" ]]; then
    for alias in "qwen3-8b" "gemma3-4b" "deepseek-r1-8b" "llama3.3-70b" \
                 "llama3.1-8b" "llama3-70b" "qwen3-8b-gguf" "llama3-8b-gguf" "mistral-7b-gguf"; do
        if grep -q "${alias}:" "${KIT_ROOT}/config/models.yaml" 2>/dev/null; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo "  ✘ models.yaml missing alias: ${alias}"
        fi
    done
    # no legacy TheBloke mirrors — actively maintained quantizers only
    if grep -q "TheBloke/" "${KIT_ROOT}/config/models.yaml"; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ models.yaml still references unmaintained TheBloke repos"
    else
        PASS_COUNT=$((PASS_COUNT + 1))
    fi

    # YAML-ish sanity: lines look like "key: value"
    bad_lines="$(grep -nE '^[^#[:space:]]' "${KIT_ROOT}/config/models.yaml" | grep -vE ':[[:space:]]*$|:[[:space:]].*' | grep -v '^[0-9]*: *#' || true)"
    if [[ -z "${bad_lines}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ models.yaml has malformed entries:"
        echo "${bad_lines}" | sed 's/^/      /'
    fi
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  ✘ config/models.yaml missing"
fi

# --- no secrets committed ---
secrets="$(grep -rInE '(hf_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)' \
    "${KIT_ROOT}" --exclude-dir=.git 2>/dev/null || true)"
if [[ -z "${secrets}" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  ✘ potential secrets found:"
    echo "${secrets}" | sed 's/^/      /'
fi

report_results
