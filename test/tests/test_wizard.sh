#!/usr/bin/env bash
# =============================================================================
# test_wizard.sh — Guided Setup Wizard regression tests (fully mocked)
# =============================================================================
# No internet, no real installs. Verifies:
#   1. Flag wiring: bootstrap --configure -> setup.sh --wizard -> run_wizard
#   2. i18n: every tr WIZARD_* key exists in en/vi/zh-CN catalogs
#   3. stack.env persistence: set/get/overwrite semantics
#   4. Port helpers: pick_port skips occupied ports
#   5. Invalid menu choice re-asks
#   6. No secret keys persisted
#   7. Wizard reuses existing installers (no duplicated logic)
# =============================================================================
TEST_NAME="wizard"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

WIZARD="${KIT_ROOT}/scripts/wizard.sh"
assert_ok "wizard.sh exists" test -f "${WIZARD}"

# ── 1. Flag wiring ──
assert_contains "$(cat "${KIT_ROOT}/bootstrap.sh")" "--configure" "bootstrap --configure flag"
assert_contains "$(cat "${KIT_ROOT}/bootstrap.sh")" "SETUP_ARGS+=(--wizard)" "bootstrap forwards --wizard"
assert_contains "$(cat "${KIT_ROOT}/setup.sh")" '--wizard)        WIZARD_MODE="yes"' "setup parses --wizard"
assert_contains "$(cat "${KIT_ROOT}/setup.sh")" "run_wizard" "setup invokes run_wizard"

# ── 2. i18n key coverage (en / vi / zh-CN) ──
used_keys="$(grep -o 'tr WIZARD_[A-Z_0-9]*' "${WIZARD}" | sed 's/tr //' | sort -u)"
assert_ok "wizard references WIZARD_* keys" test -n "${used_keys}"
missing=0
for lang in en vi zh-CN; do
    catalog="${KIT_ROOT}/config/i18n/${lang}.env"
    while IFS= read -r k; do
        grep -q "^${k}=" "${catalog}" || { missing=$((missing+1)); echo "  missing in ${lang}: ${k}"; }
    done <<< "${used_keys}"
done
assert_eq "0" "${missing}" "all WIZARD keys exist in en/vi/zh-CN"

# ── 3. stack.env persistence (extract functions into sandbox) ──
TMP_AI="$(mktemp -d)"
fn_src="$(mktemp)"
for fn in wizard_stack_get wizard_stack_set wizard_port_available wizard_pick_port wizard_ask_choice; do
    sed -n "/^${fn}()/,/^}/p" "${WIZARD}" >> "${fn_src}"
done
cat >> "${fn_src}" <<'EOF'
tr() { echo "stub"; }
EOF
# shellcheck source=/dev/null
source "${fn_src}"

export WIZARD_STACK_ENV="${TMP_AI}/config/stack.env"
wizard_stack_set "RUNTIME" "ollama"
assert_eq "ollama" "$(wizard_stack_get "RUNTIME")" "stack.env stores RUNTIME"
wizard_stack_set "RUNTIME" "vllm"
assert_eq "vllm" "$(wizard_stack_get "RUNTIME")" "stack.env overwrites existing key"
wizard_stack_set "PORT" "20128"
assert_eq "20128" "$(wizard_stack_get "PORT")" "stack.env stores PORT"
assert_contains "$(cat "${WIZARD_STACK_ENV}")" "RUNTIME=vllm" "stack.env plain KEY=VALUE"
assert_fail "no .bak litter" test -f "${WIZARD_STACK_ENV}.bak"
assert_eq "" "$(wizard_stack_get "ABSENT")" "missing key returns empty"

# ── 4. Port helpers (mocked) ──
wizard_port_available(){ [[ "$1" == "19999" ]] && return 1 || return 0; }
assert_eq "20000" "$(wizard_pick_port 19999)" "pick_port skips occupied port"
assert_eq "21000" "$(wizard_pick_port 21000)" "pick_port keeps free port"

# ── 5. Invalid choice re-asks ──
# wizard_ask_choice writes the prompt to stderr and the chosen number to stdout,
# so stdout holds exactly the echoed choice. Capture it directly (no `tail`, so
# pipefail + SIGPIPE can't abort the test under set -Eeuo pipefail).
ask_out="$(printf '9\nabc\n2\n' | wizard_ask_choice "Pick" "3" 2>/dev/null)"
assert_eq "2" "${ask_out}" "invalid choices rejected, valid returned"

# ── 6. No secrets persisted ──
# The stub `tr` function (defined above for wizard_ask_choice's i18n call)
# shadows the real `tr` binary for the rest of this test. Drop it so the
# grep/tr pipeline below uses the system `tr`.
unset -f tr
persisted="$(grep -o 'wizard_stack_set "[A-Z_]*"' "${WIZARD}" | grep -oE '"[A-Z_]+"' | tr -d '"' | sort -u | tr '\n' ' ')"
case "${persisted}" in
    *TOKEN*|*SECRET*|*PASSWORD*|*KEY*) assert_eq "no-secrets" "${persisted}" "no secret keys persisted" ;;
    *) assert_ok "only non-secret keys persisted (${persisted})" true ;;
esac

# ── 7. Wizard reuses existing installers (no duplicated logic) ──
assert_contains "$(cat "${WIZARD}")" "run_routers_setup" "gateway reuses routers"
assert_contains "$(cat "${WIZARD}")" "run_ollama_setup" "ollama reuse"
assert_contains "$(cat "${WIZARD}")" "run_vllm_setup" "vllm reuse"
assert_contains "$(cat "${WIZARD}")" "run_llamacpp_setup" "llamacpp reuse"
assert_contains "$(cat "${WIZARD}")" "model-download" "model-download reuse"

# ── 8. stack.env consumption: ai-start --stack turns the wizard's choices
#    into a launchable stack (write-only file would be a dead end) ──
AI_START="${KIT_ROOT}/bin/ai-start"
assert_contains "$(cat "${AI_START}")" "--stack" "ai-start accepts --stack"
assert_contains "$(cat "${AI_START}")" "start_stack" "ai-start implements start_stack"
assert_contains "$(cat "${AI_START}")" 'ai-router" start "${gateway_cmd}"' "stack launch starts the chosen gateway"

STACK_AI="$(mktemp -d)"
mkdir -p "${STACK_AI}/config"
RUN_STACK() { AI_HOME="${STACK_AI}/ai" bash "${AI_START}" "$@" 2>&1; }

# no stack.env → honest error, exit 1
nostack_code=0
RUN_STACK --stack >/dev/null 2>&1 || nostack_code=$?
assert_eq "1" "${nostack_code}" "--stack without stack.env fails honestly"

# ollama stack with gateway → dry-run shows both launch lines, exit 0
mkdir -p "${STACK_AI}/ai/config"
printf 'RUNTIME=ollama\nMODEL=llama3.1:8b\nGATEWAY=9router\nPORT=20128\nBIND_ADDRESS=127.0.0.1\n' > "${STACK_AI}/ai/config/stack.env"
dry_code=0
dry_out="$(RUN_STACK --stack dry-run)" || dry_code=$?
assert_eq "0" "${dry_code}" "--stack dry-run exits 0 on valid ollama stack"
assert_contains "${dry_out}" "ai-start ollama llama3.1:8b" "dry-run resolves runtime+model"
assert_contains "${dry_out}" "ai-router start 9router" "dry-run includes gateway start"

# llamacpp/vllm without MODEL → honest failure
printf 'RUNTIME=vllm\n' > "${STACK_AI}/ai/config/stack.env"
nomodel_code=0
RUN_STACK --stack dry-run >/dev/null 2>&1 || nomodel_code=$?
assert_eq "1" "${nomodel_code}" "vllm stack without MODEL fails honestly"

# unknown runtime → honest failure
printf 'RUNTIME=banana\n' > "${STACK_AI}/ai/config/stack.env"
banana_code=0
RUN_STACK --stack dry-run >/dev/null 2>&1 || banana_code=$?
assert_eq "1" "${banana_code}" "unknown RUNTIME fails honestly"

# ai-start stack (no --) shows the saved config
printf 'RUNTIME=ollama\nMODEL=llama3.1:8b\n' > "${STACK_AI}/ai/config/stack.env"
show_out="$(RUN_STACK stack)"
assert_contains "${show_out}" "RUNTIME        ollama" "ai-start stack renders saved config"

# ai-info surfaces the saved stack
info_out="$(AI_HOME="${STACK_AI}/ai" bash "${KIT_ROOT}/bin/ai-info" 2>&1 || true)"
assert_contains "${info_out}" "ai-start --stack" "ai-info points at --stack launcher"
assert_contains "${info_out}" "RUNTIME=ollama" "ai-info shows saved RUNTIME"

rm -rf "${STACK_AI}"

rm -rf "${TMP_AI}" "${fn_src}"

[[ ${FAIL_COUNT} -eq 0 ]] && exit 0 || exit 1
