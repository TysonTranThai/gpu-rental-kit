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

rm -rf "${TMP_AI}" "${fn_src}"

[[ ${FAIL_COUNT} -eq 0 ]] && exit 0 || exit 1
