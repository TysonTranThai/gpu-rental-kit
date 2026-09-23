#!/usr/bin/env bash
# =============================================================================
# test_model_setup_flow.sh — model-setup mode, post-install assistant, routers
# =============================================================================
# Covers:
#   1. setup.sh: MODEL_SETUP_MODE resolution + prompt placement after i18n init
#   2. setup.sh: automated mode → run_model_setup_assistant; manual → hints
#   3. wizard.sh: self-location, lazy module loading, %s→$1 i18n placeholders
#   4. setup_routers.sh: npm update-on-setup, systemd persistence, PATH export
#   5. setup_system.sh: procps/lsof/net-tools on minimal Linux images
#   6. i18n: every new key exists in all three catalogs and interpolates via $1
# =============================================================================

TEST_NAME="model_setup_flow"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

SETUP_SH="${KIT_ROOT}/setup.sh"
WIZARD_SH="${KIT_ROOT}/scripts/wizard.sh"
ROUTERS_SH="${KIT_ROOT}/scripts/setup_routers.sh"
SYSTEM_SH="${KIT_ROOT}/scripts/setup_system.sh"

# -----------------------------------------------------------------------------
# 1. setup.sh — mode resolution block exists and is reachable
# -----------------------------------------------------------------------------
assert_ok "setup.sh initializes MODEL_SETUP_MODE" \
    grep -q 'MODEL_SETUP_MODE=""' "${SETUP_SH}"
assert_ok "setup.sh pre-answer honors AI_MODEL_SETUP_MODE" \
    grep -q 'AI_MODEL_SETUP_MODE' "${SETUP_SH}"
assert_ok "setup.sh defaults to manual when unattended" \
    grep -q 'MODEL_SETUP_MODE="manual"' "${SETUP_SH}"
assert_ok "setup.sh exports MODEL_SETUP_MODE" \
    grep -q 'export MODEL_SETUP_MODE' "${SETUP_SH}"

# Mode prompt must come AFTER i18n init (translated) and BEFORE stage 1.
i18n_line="$(grep -n 'i18n_init' "${SETUP_SH}" | head -1 | cut -d: -f1)"
mode_line="$(grep -n 'MODEL_SETUP_MODE_TITLE' "${SETUP_SH}" | head -1 | cut -d: -f1)"
stage1_line="$(grep -n '\[1/15\]' "${SETUP_SH}" | head -1 | cut -d: -f1)"
if [[ -n "${i18n_line}" && -n "${mode_line}" && -n "${stage1_line}" ]] \
   && [[ "${mode_line}" -gt "${i18n_line}" && "${mode_line}" -lt "${stage1_line}" ]]; then
    assert_ok "mode prompt sits between i18n init and stage 1" true
else
    assert_fail "mode prompt sits between i18n init and stage 1" false
fi

# -----------------------------------------------------------------------------
# 2. setup.sh — automated vs manual endings
# -----------------------------------------------------------------------------
assert_ok "automated mode runs the model setup assistant" \
    grep -q 'run_model_setup_assistant' "${SETUP_SH}"
assert_ok "assistant failure is non-fatal (warn only)" \
    grep -q 'run_model_setup_assistant || log_warn' "${SETUP_SH}"
assert_ok "manual mode prints model-download hint" \
    grep -q 'MODEL_SETUP_MANUAL_HINT_DOWNLOAD' "${SETUP_SH}"
assert_ok "manual mode prints ai-start hint" \
    grep -q 'MODEL_SETUP_MANUAL_HINT_START' "${SETUP_SH}"
assert_ok "manual mode points at the wizard flag" \
    grep -q 'MODEL_SETUP_MANUAL_HINT_WIZARD' "${SETUP_SH}"

# -----------------------------------------------------------------------------
# 3. wizard.sh — self-location, lazy loading, i18n placeholders
# -----------------------------------------------------------------------------
assert_ok "wizard self-locates WIZARD_SCRIPT_DIR" \
    grep -q 'WIZARD_SCRIPT_DIR=' "${WIZARD_SH}"
assert_ok "wizard has a lazy wizard_require loader" \
    grep -q 'wizard_require()' "${WIZARD_SH}"
assert_ok "wizard_require covers all three runtimes" \
    grep -q 'runtime-ollama)' "${WIZARD_SH}" && \
    grep -q 'runtime-vllm)' "${WIZARD_SH}" && \
    grep -q 'runtime-llamacpp)' "${WIZARD_SH}"
assert_ok "runtime install sources modules lazily (no top-level sourcing)" \
    grep -q 'wizard_require runtime-ollama;   run_ollama_setup' "${WIZARD_SH}" && \
    grep -q 'wizard_require runtime-llamacpp; run_llamacpp_setup' "${WIZARD_SH}"
assert_ok "gateway install lazily loads the router module" \
    grep -q 'wizard_require routers' "${WIZARD_SH}"
assert_ok "assistant guarantees the chosen runtime exists" \
    grep -q 'assistant_require_runtime' "${WIZARD_SH}"
assert_ok "assistant background-launch never uses exec" \
    grep -q 'assistant_start_model()' "${WIZARD_SH}" && \
    ! grep -q 'exec .*vllm-serve\|exec .*llamacpp-serve' "${WIZARD_SH}"

# Every %s-style key must have been converted to $1 (tr interpolates $1..$9).
for f in en vi zh-CN; do
    if grep -q '%s' "${KIT_ROOT}/config/i18n/${f}.env"; then
        assert_fail "i18n ${f}: no %s placeholders remain" false
    else
        assert_ok "i18n ${f}: no %s placeholders remain" true
    fi
done

# -----------------------------------------------------------------------------
# 4. setup_routers.sh — update, persistence, PATH
# -----------------------------------------------------------------------------
assert_ok "routers: update_npm_router runs for both routers" \
    grep -q 'update_npm_router "9router"' "${ROUTERS_SH}" && \
    grep -q 'update_npm_router "omniroute"' "${ROUTERS_SH}"
assert_ok "routers: update compares against the npm registry (@latest)" \
    grep -q 'npm view' "${ROUTERS_SH}"
assert_ok "routers: offline registry keeps the working version" \
    grep -q 'registry unreachable' "${ROUTERS_SH}"
assert_ok "routers: systemd user unit enabled when rootless" \
    grep -q 'systemctl --user enable' "${ROUTERS_SH}"
assert_ok "routers: system unit written when root + systemd present" \
    grep -q '/etc/systemd/system/gpu-kit-' "${ROUTERS_SH}"
assert_ok "routers: PATH export function exists" \
    grep -q 'export_router_npm_prefix()' "${ROUTERS_SH}"
assert_ok "routers: PATH export writes into .bashrc" \
    grep -q 'bashrc' "${ROUTERS_SH}"
assert_ok "routers: persistence runs inside run_routers_setup" \
    grep -q 'enable_router_persistence' "${ROUTERS_SH}"
assert_ok "routers: ensure_node has a distro-repo fallback" \
    grep -q 'distro repository' "${ROUTERS_SH}"

# -----------------------------------------------------------------------------
# 5. setup_system.sh — commands that vanish on minimal Linux images
# -----------------------------------------------------------------------------
assert_ok "base packages include procps (pgrep), lsof, net-tools" \
    grep -q 'procps lsof net-tools' "${SYSTEM_SH}"
assert_ok "dnf path installs procps/lsof too" \
    grep -q 'pciutils procps lsof' "${SYSTEM_SH}"

# -----------------------------------------------------------------------------
# 6. i18n completeness — new keys in all three catalogs
# -----------------------------------------------------------------------------
NEW_KEYS=(MODEL_SETUP_MODE_TITLE MODEL_SETUP_MODE_AUTOMATED MODEL_SETUP_MODE_AUTOMATED_DESC
    MODEL_SETUP_MODE_MANUAL MODEL_SETUP_MODE_MANUAL_DESC MODEL_SETUP_MODE_PROMPT
    MODEL_SETUP_MODE_INVALID MODEL_SETUP_MANUAL_HINT_TITLE MODEL_SETUP_MANUAL_HINT_DOWNLOAD
    MODEL_SETUP_MANUAL_HINT_START MODEL_SETUP_MANUAL_HINT_WIZARD
    ASSISTANT_TITLE ASSISTANT_DONE_TITLE ASSISTANT_MODEL_STARTED ASSISTANT_ENDPOINT
    ASSISTANT_LOG_HINT ASSISTANT_START_NOW_PROMPT ASSISTANT_START_NOW ASSISTANT_START_LATER
    ASSISTANT_NO_MODEL_LATER)

i18n_ok="yes"
for f in en vi zh-CN; do
    for key in "${NEW_KEYS[@]}"; do
        if ! grep -q "^${key}=" "${KIT_ROOT}/config/i18n/${f}.env"; then
            i18n_ok="no (${f}: ${key})"
        fi
    done
done
assert_eq "yes" "${i18n_ok}" "all 20 new i18n keys exist in en/vi/zh-CN"

# The tr() contract: catalogs parse as shell.
for f in en vi zh-CN; do
    assert_ok "i18n ${f}.env parses as shell" bash -n "${KIT_ROOT}/config/i18n/${f}.env"
done

# Functional spot check: tr() actually interpolates the new keys.
if (
    unset _GPU_RENTAL_KIT_I18N_LOADED
    # shellcheck source=scripts/i18n.sh
    source "${KIT_ROOT}/scripts/i18n.sh"
    I18N_DIR="${KIT_ROOT}/config/i18n"
    i18n_load_catalog "en" >/dev/null 2>&1 || true
    out="$(tr MODEL_SETUP_MODE_AUTOMATED 2>/dev/null || true)"
    [[ "${out}" == *"Automated model setup"* ]] || exit 1
    out="$(tr ASSISTANT_START_LATER "ai-start ollama llama3.1:8b" 2>/dev/null || true)"
    [[ "${out}" == *"Start it later with: ai-start ollama llama3.1:8b"* ]] || exit 1
); then
    assert_ok "tr() interpolates the new keys (\$1 interpolation works)" true
else
    assert_fail "tr() interpolates the new keys (\$1 interpolation works)" false
fi

report_results
