#!/usr/bin/env bash
# =============================================================================
# wizard.sh — Guided AI Server Setup Wizard
# =============================================================================
# Sourced by setup.sh (wizard mode) and runnable via bootstrap.sh --configure.
#
# Flow:
#   ENV DETECTION SUMMARY → RUNTIME CHOICE → RUNTIME INSTALL → MODEL CHOICE
#   → GPU CONFIG (multi-GPU) → GATEWAY CHOICE → PORT/BIND/DOMAIN → STACK.ENV
#   → FINAL SUMMARY
#
# Design rules:
#   * All user-facing text via tr() (i18n) — en/vi/zh-CN
#   * Reuses existing layers: setup_{ollama,llamacpp,vllm}.sh, model-download,
#     setup_routers.sh, gpu_select.sh — no duplicated install logic
#   * Persists non-secret choices to ${AI_HOME}/config/stack.env
#   * Never prints secrets; binds 127.0.0.1 unless user opts out explicitly
# =============================================================================
# Source guard
if [[ -z "${_GPU_RENTAL_KIT_WIZARD_LOADED:-}" ]]; then
_GPU_RENTAL_KIT_WIZARD_LOADED="1"

# Self-locate the repo's scripts/ directory. setup.sh sources this file, but
# the variable it historically relied on (${_GPU_KIT_SCRIPT_DIR}) was never
# exported by any caller — under `set -u` the wizard crashed on first use
# (unbound variable). Every consumer below uses WIZARD_SCRIPT_DIR.
_GPU_KIT_SCRIPT_DIR="${_GPU_KIT_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
WIZARD_SCRIPT_DIR="${_GPU_KIT_SCRIPT_DIR}"

# Lazy module loading: setup.sh only sources modules it needs for the fixed
# 15-stage flow, so the wizard must pull in whatever a chosen step requires.
# Sourcing here (not at the top) keeps `--wizard` startup fast and avoids
# loading installers the user never picks.
wizard_require() {
    case "$1" in
        runtime-ollama)   [[ -n "${_GPU_RENTAL_KIT_OLLAMA_LOADED:-}" ]] || source "${WIZARD_SCRIPT_DIR}/setup_ollama.sh" ;;
        runtime-vllm)     [[ -n "${_GPU_RENTAL_KIT_VLLM_LOADED:-}" ]]   || source "${WIZARD_SCRIPT_DIR}/setup_vllm.sh" ;;
        runtime-llamacpp) [[ -n "${_GPU_RENTAL_KIT_LLAMACPP_LOADED:-}" ]] || source "${WIZARD_SCRIPT_DIR}/setup_llamacpp.sh" ;;
        routers)          [[ -n "${_GPU_RENTAL_KIT_ROUTERS_LOADED:-}" ]] || source "${WIZARD_SCRIPT_DIR}/setup_routers.sh" ;;
    esac
}

WIZARD_AI_HOME="${AI_HOME:-${HOME}/ai}"
WIZARD_STACK_ENV="${WIZARD_STACK_ENV:-${WIZARD_AI_HOME}/config/stack.env}"
WIZARD_MODELS_YAML="${WIZARD_MODELS_YAML:-}"

# =============================================================================
# stack.env persistence (non-secret settings only)
# =============================================================================
wizard_stack_get() {
    local key="$1"
    [[ -f "${WIZARD_STACK_ENV}" ]] || return 0
    grep -E "^${key}=" "${WIZARD_STACK_ENV}" 2>/dev/null | head -1 | cut -d= -f2-
}

wizard_stack_set() {
    local key="$1" value="$2"
    mkdir -p "$(dirname "${WIZARD_STACK_ENV}")"
    touch "${WIZARD_STACK_ENV}"
    if grep -qE "^${key}=" "${WIZARD_STACK_ENV}" 2>/dev/null; then
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "${WIZARD_STACK_ENV}" && rm -f "${WIZARD_STACK_ENV}.bak"
    else
        echo "${key}=${value}" >> "${WIZARD_STACK_ENV}"
    fi
}

# =============================================================================
# helpers
# =============================================================================
wizard_header() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    printf "║ %-44s ║\n" "$1"
    echo "╚══════════════════════════════════════════════╝"
}

wizard_ask_choice() {
    # $1=prompt  $2=max  → echoes chosen number (1..max); re-asks on invalid
    # Prompt is written to stderr so stdout carries only the echoed choice,
    # letting callers capture the value via "$(wizard_ask_choice ...)".
    local prompt="$1" max="$2" choice
    while true; do
        printf "%s [1-%s]: " "${prompt}" "${max}" >&2
        read -r choice || choice=""
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le "${max}" ]] 2>/dev/null; then
            echo "${choice}"
            return 0
        fi
        echo "  $(tr WIZARD_INVALID_CHOICE "${max}")" >&2
    done
}

wizard_ask_yes_no() {
    # $1=prompt → returns 0 for yes, 1 for no (default yes on empty)
    local prompt="$1" answer
    printf "%s [Y/n]: " "${prompt}"
    read -r answer || answer=""
    case "${answer}" in
        n|N|no|NO) return 1 ;;
        *) return 0 ;;
    esac
}

wizard_port_available() {
    local port="$1"
    if command -v lsof >/dev/null 2>&1; then
        ! lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    elif command -v ss >/dev/null 2>&1; then
        ! ss -ltn 2>/dev/null | grep -q ":${port} "
    else
        (exec 3<>"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1 && return 1 || return 0
    fi
}

wizard_pick_port() {
    # $1=default port → echoes a free port (auto-increments up to +100)
    local port="$1"
    while ! wizard_port_available "${port}" && [[ "${port}" -lt "$((port + 100))" ]]; do
        port=$((port + 1))
    done
    echo "${port}"
}

# =============================================================================
# step 1 — environment / GPU detection summary (reuses existing detection)
# =============================================================================
wizard_env_summary() {
    wizard_header "$(tr WIZARD_ENV_TITLE)"

    # GPU detection (module sets GPU_* globals) + multi-GPU selection helpers
    # (mg_max_single_vram_mb / mg_auto_select live in gpu_select.sh and are
    # used by the model menu & GPU config steps below).
    source "${_GPU_KIT_SCRIPT_DIR}/detect_gpu.sh"
    run_gpu_detection
    # shellcheck source=gpu_select.sh
    source "${_GPU_KIT_SCRIPT_DIR}/gpu_select.sh"

    if [[ "${HAS_NVIDIA_GPU}" == "yes" ]]; then
        echo "  ✓ $(tr WIZARD_ENV_NVIDIA_DRIVER) (${NVIDIA_DRIVER_VERSION})"
        echo "  ✓ $(tr WIZARD_ENV_GPU_COUNT) ${GPU_COUNT}"
        local i
        for (( i=0; i<GPU_COUNT; i++ )); do
            printf "  %s %d: %s — %sGB\n" "$(tr WIZARD_ENV_GPU)" "${i}" "$(gpu_name_at "${i}")" "$(gpu_vram_gb_at "${i}")"
        done
        echo "  $(tr WIZARD_ENV_AGGREGATE_VRAM) ${GPU_TOTAL_VRAM_GB}GB"
        echo "  ($(tr WIZARD_ENV_AGGREGATE_NOTE))"
        if [[ "${GPU_MIXED_WARNING}" == "yes" ]]; then
            echo "  ⚠ $(tr WIZARD_ENV_MIXED_GPU_WARNING)"
        fi
    else
        echo "  ✗ $(tr WIZARD_ENV_NO_GPU)"
    fi
    echo ""
}

# =============================================================================
# step 2 — runtime choice (uses existing installers, idempotent)
# =============================================================================
wizard_runtime_menu() {
    wizard_header "$(tr WIZARD_RUNTIME_TITLE)"
    echo "  1) Ollama     — $(tr WIZARD_RUNTIME_OLLAMA_DESC)"
    echo "  2) llama.cpp  — $(tr WIZARD_RUNTIME_LLAMACPP_DESC)"
    echo "  3) vLLM       — $(tr WIZARD_RUNTIME_VLLM_DESC)"
    echo "  4) $(tr WIZARD_RUNTIME_RECOMMENDED)"
    echo ""
}

wizard_runtime_recommend() {
    # hardware-aware: small VRAM → ollama/llamacpp; large → all viable
    if [[ "${HAS_NVIDIA_GPU}" != "yes" ]]; then
        echo "ollama"
    elif [[ "${GPU_MULTI_PROFILE}" == "multi-gpu-mixed" ]] || [[ "${GPU_PROFILE}" == "small" || "${GPU_PROFILE}" == "small-medium" ]]; then
        echo "ollama"
    else
        echo "vllm"
    fi
}

wizard_runtime_installed() {
    case "$1" in
        ollama)   command -v ollama >/dev/null 2>&1 ;;
        llamacpp) [[ -x "${WIZARD_AI_HOME}/bin/llamacpp-serve" ]] || command -v llama-server >/dev/null 2>&1 ;;
        vllm)     [[ -x "${WIZARD_AI_HOME}/venv/bin/python" ]] && "${WIZARD_AI_HOME}/venv/bin/python" -c "import vllm" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

wizard_runtime_install() {
    local runtime="$1"
    if wizard_runtime_installed "${runtime}"; then
        echo "  ✓ $(tr WIZARD_RUNTIME_ALREADY_INSTALLED "${runtime}")"
        return 0
    fi
    echo "  $(tr WIZARD_RUNTIME_INSTALLING "${runtime}")"
    case "${runtime}" in
        ollama)   wizard_require runtime-ollama;   run_ollama_setup ;;
        llamacpp) wizard_require runtime-llamacpp; run_llamacpp_setup ;;
        vllm)     wizard_require runtime-vllm;     run_vllm_setup ;;
    esac
}

# =============================================================================
# step 3 — model selection (reads config/models.yaml, reuses model-download)
# =============================================================================
wizard_model_menu() {
    local runtime="$1"
    wizard_header "$(tr WIZARD_MODEL_TITLE "${runtime}")"

    if ! wizard_ask_yes_no "$(tr WIZARD_MODEL_ASK_DOWNLOAD)"; then
        echo ""
        return 1
    fi

    # list aliases from models.yaml matching the runtime backend
    local yaml="${WIZARD_MODELS_YAML}"
    [[ -z "${yaml}" ]] && yaml="${_GPU_KIT_SCRIPT_DIR}/../config/models.yaml"
    if [[ ! -f "${yaml}" ]]; then
        echo "  $(tr WIZARD_MODEL_NO_REGISTRY)"
        return 1
    fi

    local -a aliases=() backs=() names=() mins=()
    local alias="" backend="" name="" minvram="" in_model=0
    while IFS= read -r line; do
        if [[ "${line}" =~ ^[[:space:]]{2}([a-zA-Z0-9_.-]+): ]]; then
            if [[ "${in_model}" == "1" && -n "${alias}" ]]; then
                aliases+=("${alias}"); backs+=("${backend}"); names+=("${name}"); mins+=("${minvram}")
            fi
            alias="${BASH_REMATCH[1]}"; backend=""; name=""; minvram=""; in_model=1
        elif [[ "${in_model}" == "1" ]]; then
            [[ "${line}" =~ backend:[[:space:]]*([^ ]+) ]] && backend="${BASH_REMATCH[1]}"
            [[ "${line}" =~ name:[[:space:]]*(.+)$ ]] && name="${BASH_REMATCH[1]//\"/}"
            [[ "${line}" =~ min_vram_gb:[[:space:]]*([0-9]+) ]] && minvram="${BASH_REMATCH[1]}"
        fi
    done < "${yaml}"
    [[ "${in_model}" == "1" && -n "${alias}" ]] && { aliases+=("${alias}"); backs+=("${backend}"); names+=("${name}"); mins+=("${minvram}"); }

    # filter: backend matches runtime (auto counts as match) AND fits max single-GPU VRAM
    local -a fit=()
    local i max_vram=0
    [[ "${HAS_NVIDIA_GPU}" == "yes" ]] && max_vram="$(mg_max_single_vram_mb 2>/dev/null || echo 0)"
    max_vram=$(( max_vram / 1024 ))
    for (( i=0; i<${#aliases[@]}; i++ )); do
        local b="${backs[${i}]}"
        [[ "${b}" == "auto" ]] && b="${runtime}"
        [[ "${b}" != "${runtime}" ]] && continue
        if [[ "${HAS_NVIDIA_GPU}" == "yes" && -n "${mins[${i}]}" ]]; then
            [[ "${mins[${i}]}" -gt "${max_vram}" ]] && continue
        fi
        fit+=("${i}")
    done

    if [[ ${#fit[@]} -eq 0 ]]; then
        echo "  $(tr WIZARD_MODEL_NONE_FIT "${runtime}")"
        return 1
    fi

    echo "  $(tr WIZARD_MODEL_RECOMMENDED_FOR)"
    local n=1 choice idx
    for idx in "${fit[@]}"; do
        printf "  %d) %-20s %s (min %sGB)\n" "${n}" "${aliases[${idx}]}" "${names[${idx}]}" "${mins[${idx}]:-?}"
        n=$((n + 1))
    done
    printf "  %d) %s\n" "${n}" "$(tr WIZARD_MODEL_MANUAL_ENTRY)"
    local manual_opt="${n}"
    n=$((n + 1))
    printf "  %d) %s\n" "${n}" "$(tr WIZARD_MODEL_SKIP)"
    local skip_opt="${n}"

    choice="$(wizard_ask_choice "$(tr WIZARD_MODEL_CHOICE_PROMPT)" "${n}")"
    echo ""
    if [[ "${choice}" -eq "${skip_opt}" ]]; then
        return 1
    elif [[ "${choice}" -eq "${manual_opt}" ]]; then
        printf "%s: " "$(tr WIZARD_MODEL_MANUAL_PROMPT)"
        read -r manual_model
        WIZARD_SELECTED_MODEL="${manual_model}"
    else
        idx="${fit[$((choice - 1))]}"
        WIZARD_SELECTED_MODEL="${aliases[${idx}]}"
        # confirm before download (show name/source/size info)
        echo "  $(tr WIZARD_MODEL_CONFIRM_LABEL): ${WIZARD_SELECTED_MODEL} (${names[${idx}]})"
        wizard_ask_yes_no "$(tr WIZARD_MODEL_CONFIRM_DOWNLOAD)" || { echo ""; return 1; }
    fi

    echo "  $(tr WIZARD_MODEL_DOWNLOADING "${WIZARD_SELECTED_MODEL}")"
    "${_GPU_KIT_SCRIPT_DIR}/../bin/model-download" "${WIZARD_SELECTED_MODEL}" || {
        echo "  $(tr WIZARD_MODEL_DOWNLOAD_FAILED)"
        return 1
    }
    echo "  ✓ $(tr WIZARD_MODEL_DOWNLOADED "${WIZARD_SELECTED_MODEL}")"
}

# =============================================================================
# step 4 — GPU usage configuration (multi-GPU only)
# =============================================================================
wizard_gpu_config() {
    WIZARD_GPU_IDS=""
    [[ "${GPU_COUNT}" -le 1 ]] && { WIZARD_GPU_IDS="0"; return 0; }

    wizard_header "$(tr WIZARD_GPU_TITLE)"
    echo "  1) $(tr WIZARD_GPU_AUTO)"
    echo "  2) $(tr WIZARD_GPU_SINGLE "0")"
    echo "  3) $(tr WIZARD_GPU_SELECT)"
    echo "  4) $(tr WIZARD_GPU_ALL_COMPATIBLE)"
    if [[ "${GPU_MIXED_WARNING}" == "yes" ]]; then
        echo "  ⚠ $(tr WIZARD_GPU_MIXED_WARNING)"
    fi
    local choice
    choice="$(wizard_ask_choice "$(tr WIZARD_GPU_CHOICE_PROMPT)" "4")"
    case "${choice}" in
        1) WIZARD_GPU_IDS="" ;;  # empty = auto (mg_auto_select decides)
        2) WIZARD_GPU_IDS="0" ;;
        3)
            local ids="" id
            printf "%s (e.g. 0,1): " "$(tr WIZARD_GPU_ENTER_IDS)"
            read -r ids
            WIZARD_GPU_IDS="${ids// /}"
            ;;
        4) WIZARD_GPU_IDS="$(seq -s, 0 $((GPU_COUNT - 1)))" ;;
    esac
    echo ""
}

# =============================================================================
# step 5 — gateway choice (reuses setup_routers.sh)
# =============================================================================
wizard_gateway_menu() {
    wizard_header "$(tr WIZARD_GATEWAY_TITLE)"
    echo "  1) $(tr WIZARD_GATEWAY_INTEGRATED) — $(tr WIZARD_GATEWAY_INTEGRATED_DESC)"
    echo "  2) 9Router     — $(tr WIZARD_GATEWAY_9ROUTER_DESC)"
    echo "  3) OmniRoute   — $(tr WIZARD_GATEWAY_OMNIROUTE_DESC)"
    echo "  4) $(tr WIZARD_GATEWAY_NONE)"
    echo ""
}

wizard_gateway_install() {
    local gateway="$1"
    case "${gateway}" in
        integrated)
            # The runtime's own OpenAI-compatible endpoint IS the integrated
            # gateway (no extra component): ollama/vllm/llamacpp-serve expose
            # /v1 natively. Nothing to install — endpoint = runtime endpoint.
            WIZARD_GATEWAY_PORT="${WIZARD_RUNTIME_PORT}"
            ;;
        9router)
            wizard_require routers
            ROUTER_9ROUTER_ENABLED="yes"; ROUTER_OMNIROUTE_ENABLED="no"
            run_routers_setup
            WIZARD_GATEWAY_PORT="${ROUTER_9ROUTER_PORT}"
            ;;
        omniroute)
            wizard_require routers
            ROUTER_9ROUTER_ENABLED="no"; ROUTER_OMNIROUTE_ENABLED="yes"
            run_routers_setup
            WIZARD_GATEWAY_PORT="${ROUTER_OMNIROUTE_PORT}"
            ;;
        none) WIZARD_GATEWAY_PORT="${WIZARD_RUNTIME_PORT}" ;;
    esac
}

# =============================================================================
# step 6 — port / bind / domain / security
# =============================================================================
wizard_access_config() {
    wizard_header "$(tr WIZARD_ACCESS_TITLE)"

    # gateway port
    local default_port="${WIZARD_GATEWAY_PORT}"
    if ! wizard_port_available "${default_port}"; then
        echo "  ⚠ $(tr WIZARD_PORT_IN_USE "${default_port}")"
        echo "  1) $(tr WIZARD_PORT_AUTO_PICK)"
        echo "  2) $(tr WIZARD_PORT_MANUAL)"
        echo "  3) $(tr WIZARD_PORT_CANCEL)"
        local choice
        choice="$(wizard_ask_choice "$(tr WIZARD_PORT_CHOICE_PROMPT)" "3")"
        case "${choice}" in
            1) WIZARD_GATEWAY_PORT="$(wizard_pick_port "${default_port}")" ;;
            2)
                printf "%s: " "$(tr WIZARD_PORT_ENTER)"
                read -r WIZARD_GATEWAY_PORT
                ;;
            *) return 1 ;;
        esac
    fi

    # bind / exposure
    echo ""
    echo "  1) $(tr WIZARD_ACCESS_LOCALHOST) — $(tr WIZARD_ACCESS_LOCALHOST_DESC)"
    echo "  2) $(tr WIZARD_ACCESS_LAN)"
    echo "  3) $(tr WIZARD_ACCESS_PUBLIC) — ⚠ $(tr WIZARD_ACCESS_PUBLIC_WARNING)"
    local choice
    choice="$(wizard_ask_choice "$(tr WIZARD_ACCESS_CHOICE_PROMPT)" "3")"
    case "${choice}" in
        1) WIZARD_BIND="127.0.0.1" ;;
        2) WIZARD_BIND="0.0.0.0" ;;
        3)
            WIZARD_BIND="0.0.0.0"
            echo "  ⚠ $(tr WIZARD_ACCESS_AUTH_REQUIRED)"
            ;;
    esac

    # domain (optional)
    WIZARD_DOMAIN=""
    if wizard_ask_yes_no "$(tr WIZARD_DOMAIN_ASK)"; then
        printf "%s: " "$(tr WIZARD_DOMAIN_ENTER)"
        read -r WIZARD_DOMAIN
        echo "  $(tr WIZARD_DOMAIN_DNS_NOTE)"
    fi
    echo ""
}

wizard_ssh_tunnel_hint() {
    [[ "${WIZARD_BIND}" != "127.0.0.1" ]] && return 0
    echo ""
    echo "  $(tr WIZARD_SSH_TUNNEL_TITLE)"
    echo "  ssh -L ${WIZARD_GATEWAY_PORT}:127.0.0.1:${WIZARD_GATEWAY_PORT} \$(whoami)@\$(hostname -I | awk '{print \$1}')"
    echo "  $(tr WIZARD_SSH_TUNNEL_URL): http://127.0.0.1:${WIZARD_GATEWAY_PORT}/v1"
}

# =============================================================================
# step 7 — final summary + persistence
# =============================================================================
wizard_persist() {
    wizard_stack_set "LANGUAGE" "$(i18n_lang 2>/dev/null || echo en)"
    wizard_stack_set "RUNTIME" "${WIZARD_RUNTIME}"
    [[ -n "${WIZARD_SELECTED_MODEL:-}" ]] && wizard_stack_set "MODEL" "${WIZARD_SELECTED_MODEL}"
    [[ -n "${WIZARD_GPU_IDS:-}" ]] && wizard_stack_set "GPU_IDS" "${WIZARD_GPU_IDS}"
    wizard_stack_set "GATEWAY" "${WIZARD_GATEWAY}"
    wizard_stack_set "PORT" "${WIZARD_GATEWAY_PORT}"
    wizard_stack_set "BIND_ADDRESS" "${WIZARD_BIND}"
    [[ -n "${WIZARD_DOMAIN:-}" ]] && wizard_stack_set "DOMAIN" "${WIZARD_DOMAIN}"
    echo "  $(tr WIZARD_STACK_SAVED "${WIZARD_STACK_ENV}")"
    echo "  $(tr WIZARD_STACK_LAUNCH_HINT)"
}

wizard_final_summary() {
    wizard_header "$(tr WIZARD_FINAL_TITLE)"
    echo "  $(tr WIZARD_FINAL_RUNTIME): ${WIZARD_RUNTIME}"
    [[ -n "${WIZARD_SELECTED_MODEL:-}" ]] && echo "  $(tr WIZARD_FINAL_MODEL): ${WIZARD_SELECTED_MODEL}"
    echo "  $(tr WIZARD_FINAL_GATEWAY): ${WIZARD_GATEWAY}"
    echo "  $(tr WIZARD_FINAL_ENDPOINT): http://${WIZARD_BIND}:${WIZARD_GATEWAY_PORT}/v1"
    [[ -n "${WIZARD_DOMAIN:-}" ]] && echo "  $(tr WIZARD_FINAL_DOMAIN): https://${WIZARD_DOMAIN}/v1"
    wizard_ssh_tunnel_hint
    echo ""
    wizard_persist
}

# =============================================================================
# model setup assistant — post-install model chooser (automated mode)
#
# setup.sh asks "automated or manual?" right after the language pick. When the
# user chooses automated, the assistant runs at the END of setup (all runtimes
# already installed): pick a runtime → pick/download a model → optionally
# launch it in the background. Choices persist to stack.env so
# `ai-start --stack` can relaunch the exact same stack later.
# =============================================================================
assistant_require_runtime() {
    case "$1" in
        ollama)   wizard_require runtime-ollama;   run_ollama_setup ;;
        llamacpp) wizard_require runtime-llamacpp; run_llamacpp_setup ;;
        vllm)     wizard_require runtime-vllm;     run_vllm_setup ;;
    esac
}

assistant_start_model() {
    # Background-launch the model (never exec): setup must stay in control and
    # print its final summary. Mirrors ai-start's launch commands minus exec.
    local runtime="$1" model="$2"
    local logs_dir="${AI_LOGS_DIR:-${AI_HOME}/logs}"
    local log_file="${logs_dir}/${runtime}-model.log"
    local port
    port="$("${WIZARD_SCRIPT_DIR}/../config/runtime_port.sh" "${runtime}" 2>/dev/null || echo "")"
    case "${runtime}" in
        ollama)
            command -v ollama >/dev/null 2>&1 || return 1
            if ! pgrep -f "ollama serve" >/dev/null 2>&1; then
                nohup ollama serve >> "${logs_dir}/ollama.log" 2>&1 &
                sleep 2
            fi
            ;;
        vllm)
            [[ -x "${AI_HOME}/bin/vllm-serve" ]] || return 1
            nohup "${AI_HOME}/bin/vllm-serve" "${model}" >> "${log_file}" 2>&1 &
            ;;
        llamacpp)
            [[ -x "${AI_HOME}/bin/llamacpp-serve" ]] || return 1
            nohup "${AI_HOME}/bin/llamacpp-serve" "${model}" >> "${log_file}" 2>&1 &
            ;;
        *) return 1 ;;
    esac
    echo "  ✓ $(tr ASSISTANT_MODEL_STARTED "${model}")"
    [[ -n "${port}" ]] && echo "  $(tr ASSISTANT_ENDPOINT "http://127.0.0.1:${port}/v1")"
    echo "  $(tr ASSISTANT_LOG_HINT "${log_file}")"
    return 0
}

run_model_setup_assistant() {
    local model=""
    wizard_header "$(tr ASSISTANT_TITLE)"

    # Runtime choice — same menu as the wizard, hardware-aware recommendation.
    wizard_runtime_menu
    local rec; rec="$(wizard_runtime_recommend)"
    echo "  $(tr WIZARD_RUNTIME_RECOMMEND_HINT "${rec}")"
    local choice
    choice="$(wizard_ask_choice "$(tr WIZARD_RUNTIME_CHOICE_PROMPT)" "4")"
    case "${choice}" in
        1) ASSISTANT_RUNTIME="ollama" ;;
        2) ASSISTANT_RUNTIME="llamacpp" ;;
        3) ASSISTANT_RUNTIME="vllm" ;;
        4) ASSISTANT_RUNTIME="${rec}" ;;
    esac
    echo ""

    # Ensure the runtime exists (no-op after stage 15; recovery path if the
    # runtime's stage-15 install failed).
    assistant_require_runtime "${ASSISTANT_RUNTIME}" || true

    # Model choice + download (wizard_model_menu handles registry, VRAM fit,
    # manual entry, and skip).
    if wizard_model_menu "${ASSISTANT_RUNTIME}"; then
        model="${WIZARD_SELECTED_MODEL}"
    fi

    # Persist so `ai-start --stack` relaunches exactly this stack later.
    wizard_stack_set "MODEL_SETUP_MODE" "automated"
    wizard_stack_set "RUNTIME" "${ASSISTANT_RUNTIME}"
    wizard_stack_set "GATEWAY" "integrated"
    wizard_stack_set "BIND_ADDRESS" "127.0.0.1"
    local rt_port
    rt_port="$("${WIZARD_SCRIPT_DIR}/../config/runtime_port.sh" "${ASSISTANT_RUNTIME}" 2>/dev/null || echo "")"
    [[ -n "${rt_port}" ]] && wizard_stack_set "PORT" "${rt_port}"
    [[ -n "${model}" ]] && wizard_stack_set "MODEL" "${model}"

    # Optional immediate launch
    wizard_header "$(tr ASSISTANT_DONE_TITLE)"
    if [[ -n "${model}" ]]; then
        echo "  $(tr WIZARD_FINAL_RUNTIME): ${ASSISTANT_RUNTIME}"
        echo "  $(tr WIZARD_FINAL_MODEL): ${model}"
        echo ""
        echo "  $(tr ASSISTANT_START_NOW_PROMPT)"
        if wizard_ask_yes_no "$(tr ASSISTANT_START_NOW)"; then
            if ! assistant_start_model "${ASSISTANT_RUNTIME}" "${model}"; then
                echo "  $(tr ASSISTANT_START_LATER "ai-start ${ASSISTANT_RUNTIME} ${model}")"
            fi
        else
            echo "  $(tr ASSISTANT_START_LATER "ai-start ${ASSISTANT_RUNTIME} ${model}")"
        fi
    else
        echo "  $(tr ASSISTANT_NO_MODEL_LATER)"
    fi
    echo ""
    return 0
}

# =============================================================================
# main entry — run_wizard
# =============================================================================
run_wizard() {
    wizard_env_summary

    # runtime
    wizard_runtime_menu
    local rec; rec="$(wizard_runtime_recommend)"
    echo "  $(tr WIZARD_RUNTIME_RECOMMEND_HINT "${rec}")"
    local choice
    choice="$(wizard_ask_choice "$(tr WIZARD_RUNTIME_CHOICE_PROMPT)" "4")"
    case "${choice}" in
        1) WIZARD_RUNTIME="ollama" ;;
        2) WIZARD_RUNTIME="llamacpp" ;;
        3) WIZARD_RUNTIME="vllm" ;;
        4) WIZARD_RUNTIME="${rec}" ;;
    esac
    WIZARD_RUNTIME_PORT="$("${_GPU_KIT_SCRIPT_DIR}/../config/runtime_port.sh" "${WIZARD_RUNTIME}" 2>/dev/null || echo "")"
    wizard_runtime_install "${WIZARD_RUNTIME}"
    echo ""

    # model
    WIZARD_SELECTED_MODEL=""
    wizard_model_menu "${WIZARD_RUNTIME}" || true

    # gpu config
    wizard_gpu_config

    # gateway
    wizard_gateway_menu
    choice="$(wizard_ask_choice "$(tr WIZARD_GATEWAY_CHOICE_PROMPT)" "4")"
    case "${choice}" in
        1) WIZARD_GATEWAY="integrated" ;;
        2) WIZARD_GATEWAY="9router" ;;
        3) WIZARD_GATEWAY="omniroute" ;;
        4) WIZARD_GATEWAY="none" ;;
    esac
    wizard_gateway_install "${WIZARD_GATEWAY}"

    # access config
    wizard_access_config || return 1

    # summary + persist
    wizard_final_summary
}

fi # _GPU_RENTAL_KIT_WIZARD_LOADED
