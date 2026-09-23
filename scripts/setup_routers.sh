#!/usr/bin/env bash
# =============================================================================
# setup_routers.sh — 9Router + OmniRoute installation and management
# =============================================================================
# Sourced by setup.sh (installer) and bin/ai-router-* (management).
#
# Upstream install methods (verified 2026-08-29):
#   9Router   https://github.com/decolua/9router          npm install -g 9router   (Node >=18)
#   OmniRoute https://github.com/diegosouzapw/OmniRoute   npm install -g omniroute (Node >=22)
#
# Both provide an OpenAI-compatible API + dashboard on port 20128 (default).
# This module NEVER vendors upstream source: packages come from the npm
# registry. All services bind 127.0.0.1. Secrets are never printed.
# =============================================================================
# Source guard
if [[ -z "${_GPU_RENTAL_KIT_ROUTERS_LOADED:-}" ]]; then
_GPU_RENTAL_KIT_ROUTERS_LOADED="1"

# Optional i18n (works standalone too)
if [[ -z "${_GPU_RENTAL_KIT_I18N_LOADED:-}" && -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/i18n.sh" ]]; then
    # shellcheck source=scripts/i18n.sh
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/i18n.sh"
fi
if ! command -v tr >/dev/null 2>&1 || ! type tr | grep -q "function" 2>/dev/null; then
    tr() { local k="$1"; shift; echo "${k}"; }
fi

# --- Router defaults (override via environment) ------------------------------
ROUTER_9ROUTER_PORT="${ROUTER_9ROUTER_PORT:-20128}"
ROUTER_9ROUTER_ENABLED="${ROUTER_9ROUTER_ENABLED:-yes}"
ROUTER_OMNIROUTE_PORT="${ROUTER_OMNIROUTE_PORT:-20128}"
ROUTER_OMNIROUTE_ENABLED="${ROUTER_OMNIROUTE_ENABLED:-yes}"
ROUTER_BIND_ADDRESS="${ROUTER_BIND_ADDRESS:-127.0.0.1}"
ROUTER_NODE_MIN_MAJOR="${ROUTER_NODE_MIN_MAJOR:-22}"
ROUTER_STATE_DIR="${ROUTER_STATE_DIR:-${AI_HOME:-${HOME}/ai}/routers}"
ROUTER_LOG_DIR="${ROUTER_LOG_DIR:-${AI_HOME:-${HOME}/ai}/logs}"

ROUTER_9ROUTER_STATUS="unknown"
ROUTER_OMNIROUTE_STATUS="unknown"

# -----------------------------------------------------------------------------
# port_in_use PORT — 0 if something is listening
# -----------------------------------------------------------------------------
port_in_use() {
    local port="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    elif command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | grep -q ":${port} "
    elif command -v netstat >/dev/null 2>&1; then
        netstat -an 2>/dev/null | grep -q "[.:]${port} .*LISTEN"
    else
        # Last resort: try to connect
        (exec 3<>"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1
    fi
}

# -----------------------------------------------------------------------------
# port_owner_info PORT — human-readable "PID CMD" of the listener (or empty)
# -----------------------------------------------------------------------------
port_owner_info() {
    local port="$1" out=""
    if command -v lsof >/dev/null 2>&1; then
        out="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | tail -n +2 | awk '{print $1" (pid "$2")"}' | head -1)"
    fi
    echo "${out}"
}

# -----------------------------------------------------------------------------
# resolve_router_port DEFAULT_PORT NAME — interactive conflict resolution.
# Returns chosen port in ROUTER_PORT_CHOSEN. Never kills processes on its own.
# -----------------------------------------------------------------------------
resolve_router_port() {
    local default_port="$1" name="$2"
    ROUTER_PORT_CHOSEN="${default_port}"
    port_in_use "${default_port}" || return 0

    local owner; owner="$(port_owner_info "${default_port}")"
    echo ""
    echo "  $(tr PORT_IN_USE "${default_port}")"
    [[ -n "${owner}" ]] && echo "  $(tr PORT_CONFLICT_PID "${owner%% *}" "${owner#* }")"
    echo "  $(tr PORT_OPTIONS)"
    echo "  $(tr PORT_OPT_AUTO)"
    echo "  $(tr PORT_OPT_STOP)"
    echo "  $(tr PORT_OPT_CANCEL)"

    if [[ "${AUTO_CONFIRM:-no}" == "yes" ]]; then
        # Non-interactive: pick a free port automatically (never kill).
        local p="${default_port}"
        while port_in_use "${p}" && [[ "${p}" -lt "$((default_port + 100))" ]]; do
            p=$((p + 1))
        done
        ROUTER_PORT_CHOSEN="${p}"
        echo "  [AUTO] $(tr PORT_AUTO_PICKED "${p}")"
        return 0
    fi

    local choice
    read -rp "  $(tr PORT_PROMPT) " -n 1 -r choice
    echo
    case "${choice}" in
        1)
            local p="${default_port}"
            while port_in_use "${p}" && [[ "${p}" -lt "$((default_port + 100))" ]]; do
                p=$((p + 1))
            done
            ROUTER_PORT_CHOSEN="${p}"
            echo "  $(tr PORT_AUTO_PICKED "${p}")"
            ;;
        2)
            echo "  $(tr PORT_CONFLICT_PID "$(port_owner_info "${default_port}" | awk '{print $2}')" "$(port_owner_info "${default_port}")")"
            echo "  $(tr PORT_OPT_STOP_HINT)"
            read -rp "  Kill it? Type the PID to confirm (anything else cancels): " confirm_pid
            if [[ "${confirm_pid}" =~ ^[0-9]+$ ]] && kill "${confirm_pid}" 2>/dev/null; then
                sleep 1
                ROUTER_PORT_CHOSEN="${default_port}"
            else
                echo "  $(tr PORT_CANCELLED)"
                return 1
            fi
            ;;
        *)
            echo "  $(tr PORT_CANCELLED)"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# node_major_version — echo major version, empty if node missing
# -----------------------------------------------------------------------------
node_major_version() {
    command -v node >/dev/null 2>&1 || return 1
    node --version 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/'
}

# -----------------------------------------------------------------------------
# ensure_node — Node.js >= ROUTER_NODE_MIN_MAJOR for the routers.
# Installs Node 22 LTS from NodeSource under $SUDO when missing/old.
# Never touches an existing newer Node.
# -----------------------------------------------------------------------------
ensure_node() {
    local major
    if major="$(node_major_version)"; then
        if [[ "${major}" -ge "${ROUTER_NODE_MIN_MAJOR}" ]]; then
            echo "  Node.js $(node --version) — OK"
            return 0
        fi
        echo "  Node.js v${major} is too old for OmniRoute (needs >= ${ROUTER_NODE_MIN_MAJOR}); installing Node 22 LTS..."
    else
        echo "  Node.js not found; installing Node 22 LTS..."
    fi

    if [[ ! -f /etc/debian_version ]]; then
        echo "  [WARN] Non-Debian system: install Node.js >= ${ROUTER_NODE_MIN_MAJOR} manually, then re-run."
        return 1
    fi

    # Preferred: NodeSource (pins Node 22 LTS). Fallback: distro repo (Ubuntu
    # 22.04 ships Node 12 — too old alone, but keeps a `node` present so the
    # error below is actionable instead of a missing-command crash).
    if ! curl -fsSL https://deb.nodesource.com/setup_22.x | ${SUDO:-} -E bash -; then
        echo "  [WARN] NodeSource setup failed — trying the distro repository..."
        ${SUDO:-} apt-get update -y >/dev/null 2>&1 || true
        ${SUDO:-} apt-get install -y nodejs npm \
            || { echo "  [ERROR] nodejs install failed (both NodeSource and distro)."; return 1; }
    fi
    ${SUDO:-} apt-get install -y nodejs \
        || { echo "  [ERROR] nodejs install failed."; return 1; }

    major="$(node_major_version || true)"
    if [[ -z "${major}" || "${major}" -lt "${ROUTER_NODE_MIN_MAJOR}" ]]; then
        echo "  [ERROR] Node.js still missing/too old after install."
        return 1
    fi
    echo "  Node.js $(node --version) installed."
}

# -----------------------------------------------------------------------------
# npm_global_prefix — a user-writable global prefix (avoids sudo npm -g)
# -----------------------------------------------------------------------------
npm_global_prefix() {
    echo "${ROUTER_STATE_DIR}/npm-global"
}

# -----------------------------------------------------------------------------
# install_npm_router PKG BIN_NAME — idempotent global npm install
# -----------------------------------------------------------------------------
install_npm_router() {
    local pkg="$1" bin_name="$2"
    local prefix; prefix="$(npm_global_prefix)"
    mkdir -p "${prefix}"

    if [[ -x "${prefix}/bin/${bin_name}" ]]; then
        echo "  ${bin_name} already installed ($( "${prefix}/bin/${bin_name}" --version 2>/dev/null | head -1 ))."
        return 0
    fi

    echo "  $(tr ROUTER_INSTALLING "${pkg}")"
    if ! npm install -g --prefix "${prefix}" "${pkg}" >/dev/null 2>&1; then
        echo "  [ERROR] npm install ${pkg} failed (see ${ROUTER_LOG_DIR})."
        return 1
    fi

    [[ -x "${prefix}/bin/${bin_name}" ]] || { echo "  [ERROR] ${bin_name} binary not found after install."; return 1; }
    echo "  $(tr ROUTER_INSTALLED "${pkg}" "$("${prefix}/bin/${bin_name}" --version 2>/dev/null | head -1 || echo '?')")"
}

# -----------------------------------------------------------------------------
# update_npm_router PKG BIN_NAME — keep an installed router current with the
# upstream repo. Compares the installed version against the npm registry
# (`@latest`) and reinstalls only when they differ. Never fails the run:
#   * not installed yet  → no-op (install_npm_router handles the fresh install)
#   * registry unreachable → keep the working version (offline-safe)
#   * update fails       → warn and keep the old binary
# -----------------------------------------------------------------------------
update_npm_router() {
    local pkg="$1" bin_name="$2"
    local prefix; prefix="$(npm_global_prefix)"
    [[ -x "${prefix}/bin/${bin_name}" ]] || return 0

    local latest="" inst=""
    latest="$(npm view "${pkg}" version 2>/dev/null | tr -d '[:space:]' || true)"
    inst="$("${prefix}/bin/${bin_name}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)*' | head -1 || true)"
    if [[ -z "${latest}" ]]; then
        echo "  ${bin_name}: version check skipped (npm registry unreachable)."
        return 0
    fi
    if [[ -z "${inst}" || "${inst}" != "${latest}" ]]; then
        echo "  $(tr ROUTER_UPDATING "${pkg}")"
        if npm install -g --prefix "${prefix}" "${pkg}@latest" >/dev/null 2>&1; then
            echo "  ✓ ${bin_name} updated to $("${prefix}/bin/${bin_name}" --version 2>/dev/null | head -1 || echo '?')."
        else
            echo "  [WARN] npm update ${pkg} failed — keeping installed version $("${prefix}/bin/${bin_name}" --version 2>/dev/null | head -1 || echo '?')."
        fi
    else
        echo "  ${bin_name} is up to date (v${latest})."
    fi
    return 0
}

# -----------------------------------------------------------------------------
# write_router_systemd_unit NAME BIN_PATH PORT LOGFILE — user-level systemd
# unit (`systemd --user`) so the routers survive SSH logout. Root fallback:
# a system-level unit in /etc/systemd/system. No-op when systemd is absent
# (Docker containers) — nohup keeps those running for the session.
# -----------------------------------------------------------------------------
write_router_systemd_unit() {
    local name="$1" bin="$2" port="$3" logfile="$4"
    command -v systemctl >/dev/null 2>&1 || return 1
    [[ -x "${bin}" ]] || return 1

    local unit_content
    unit_content="[Unit]
Description=GPU Rental Kit — ${name} (OpenAI-compatible gateway)
After=network.target

[Service]
Environment=PORT=${port}
Environment=HOSTNAME=${ROUTER_BIND_ADDRESS}
ExecStart=${bin}
Restart=on-failure
RestartSec=5
StandardOutput=append:${logfile}
StandardError=append:${logfile}

[Install]
WantedBy=default.target
"

    if [[ "$(id -u)" -eq 0 && -d /run/systemd/system ]]; then
        # System manager available (rental VM / bare metal): real boot persistence.
        echo "${unit_content}" > "/etc/systemd/system/gpu-kit-${name}.service" || return 1
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable "gpu-kit-${name}.service" >/dev/null 2>&1 || true
        return 0
    fi

    # Rootless: user unit (survives logout; boot start needs loginctl enable-linger).
    local unit_dir="${HOME}/.config/systemd/user"
    mkdir -p "${unit_dir}" 2>/dev/null || return 1
    echo "${unit_content}" > "${unit_dir}/gpu-kit-${name}.service" || return 1
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable "gpu-kit-${name}.service" >/dev/null 2>&1 || true
    return 0
}

# -----------------------------------------------------------------------------
# enable_router_persistence — best-effort boot persistence for both routers.
# Already-running setups keep running: the unit is enabled alongside the
# nohup process, and systemd takes over on the next boot.
# -----------------------------------------------------------------------------
enable_router_persistence() {
    local prefix; prefix="$(npm_global_prefix)"
    local persisted=0
    if [[ "${ROUTER_9ROUTER_ENABLED}" == "yes" && -x "${prefix}/bin/9router" ]]; then
        write_router_systemd_unit "9router" "${prefix}/bin/9router" "${ROUTER_9ROUTER_PORT}" "${ROUTER_LOG_DIR}/9router.log" && persisted=1
    fi
    if [[ "${ROUTER_OMNIROUTE_ENABLED}" == "yes" && -x "${prefix}/bin/omniroute" ]]; then
        write_router_systemd_unit "omniroute" "${prefix}/bin/omniroute" "${ROUTER_OMNIROUTE_PORT}" "${ROUTER_LOG_DIR}/omniroute.log" && persisted=1
    fi
    if [[ "${persisted}" -eq 1 ]]; then
        echo "  $(tr ROUTER_PERSIST_OK)"
    else
        echo "  $(tr ROUTER_PERSIST_SKIP)"
    fi
    return 0
}

# -----------------------------------------------------------------------------
# export_router_npm_prefix — put the router binaries on PATH for future shells
# (npm installs with a custom --prefix, so plain `9router` is not found by
# default). Adds one PATH line to ~/.bashrc guarded by the prefix path.
# -----------------------------------------------------------------------------
export_router_npm_prefix() {
    local prefix; prefix="$(npm_global_prefix)"
    mkdir -p "${prefix}/bin" 2>/dev/null || true
    if [[ -d "${HOME}" ]] && ! grep -qF "${prefix}/bin" "${HOME}/.bashrc" 2>/dev/null; then
        {
            echo ""
            echo "# GPU Rental Kit — AI routers (9Router / OmniRoute)"
            echo "export PATH=\"${prefix}/bin:\$PATH\""
        } >> "${HOME}/.bashrc" 2>/dev/null || true
    fi
    export ROUTER_NPM_PREFIX="${prefix}"
    return 0
}

# -----------------------------------------------------------------------------
# start_router BIN_NAME PORT LOGFILE [ARGS...] — nohup start + readiness wait
# -----------------------------------------------------------------------------
start_router() {
    local bin_name="$1" port="$2" logfile="$3"; shift 3
    local prefix; prefix="$(npm_global_prefix)"
    local bin="${prefix}/bin/${bin_name}"
    [[ -x "${bin}" ]] || { echo "  [ERROR] ${bin} not found."; return 1; }

    if port_in_use "${port}"; then
        echo "  $(tr ROUTER_RUNNING "${bin_name}") (port ${port} already serving)"
        return 0
    fi

    echo "  $(tr ROUTER_STARTING "${bin_name}" "${port}")"
    PORT="${port}" HOSTNAME="${ROUTER_BIND_ADDRESS}" nohup "${bin}" "$@" >> "${logfile}" 2>&1 &
    echo $! > "${logfile%.log}.pid"

    # Readiness: wait up to 30s for the port to listen
    local waited=0
    while [[ "${waited}" -lt 30 ]]; do
        port_in_use "${port}" && return 0
        sleep 2
        waited=$((waited + 2))
    done
    echo "  [ERROR] ${bin_name} did not start listening on ${port} within 30s (log: ${logfile})."
    return 1
}

# -----------------------------------------------------------------------------
# router_health PORT PATH — curl a health endpoint; 0 on HTTP 200/3xx
# -----------------------------------------------------------------------------
router_health() {
    local port="$1" path="${2:-/}"
    curl -fsS -o /dev/null -m 5 "http://127.0.0.1:${port}${path}" >/dev/null 2>&1
}

# =============================================================================
# run_routers_setup — main entry called by setup.sh
# =============================================================================
run_routers_setup() {
    mkdir -p "${ROUTER_STATE_DIR}" "${ROUTER_LOG_DIR}"
    local failed=0

    # Node.js is required by both routers
    if [[ "${ROUTER_9ROUTER_ENABLED}" == "yes" || "${ROUTER_OMNIROUTE_ENABLED}" == "yes" ]]; then
        ensure_node || failed=1
    fi

    # --- 9Router ---
    if [[ "${ROUTER_9ROUTER_ENABLED}" == "yes" ]]; then
        echo "  ── 9Router ──"
        # Keep parity with the upstream repo: update in place when a newer
        # release exists, then guarantee the binary is present.
        update_npm_router "9router" "9router"
        if install_npm_router "9router" "9router"; then
            if resolve_router_port "${ROUTER_9ROUTER_PORT}" "9Router"; then
                ROUTER_9ROUTER_PORT="${ROUTER_PORT_CHOSEN}"
                if start_router "9router" "${ROUTER_9ROUTER_PORT}" "${ROUTER_LOG_DIR}/9router.log"; then
                    if router_health "${ROUTER_9ROUTER_PORT}" "/"; then
                        ROUTER_9ROUTER_STATUS="running"
                        echo "  $(tr ROUTER_HEALTH_OK "9Router" "http://${ROUTER_BIND_ADDRESS}:${ROUTER_9ROUTER_PORT}")"
                    else
                        ROUTER_9ROUTER_STATUS="not-responding"
                        echo "  [WARN] $(tr ROUTER_HEALTH_FAIL "9Router" "dashboard not responding")"
                        failed=1
                    fi
                else
                    ROUTER_9ROUTER_STATUS="installed-not-running"
                    echo "  [WARN] $(tr ROUTER_INSTALLED_NOT_RUNNING "9Router")"
                    failed=1
                fi
            else
                ROUTER_9ROUTER_STATUS="skipped-port-conflict"
                failed=1
            fi
        else
            ROUTER_9ROUTER_STATUS="install-failed"
            echo "  [ERROR] $(tr ROUTER_INSTALL_FAILED "9Router")"
            failed=1
        fi
    else
        ROUTER_9ROUTER_STATUS="disabled"
        echo "  $(tr ROUTER_SKIP_BY_CONFIG "9Router")"
    fi

    # --- OmniRoute ---
    if [[ "${ROUTER_OMNIROUTE_ENABLED}" == "yes" ]]; then
        echo "  ── OmniRoute ──"
        update_npm_router "omniroute" "omniroute"
        if install_npm_router "omniroute" "omniroute"; then
            if resolve_router_port "${ROUTER_OMNIROUTE_PORT}" "OmniRoute"; then
                ROUTER_OMNIROUTE_PORT="${ROUTER_PORT_CHOSEN}"
                if start_router "omniroute" "${ROUTER_OMNIROUTE_PORT}" "${ROUTER_LOG_DIR}/omniroute.log"; then
                    if router_health "${ROUTER_OMNIROUTE_PORT}" "/"; then
                        ROUTER_OMNIROUTE_STATUS="running"
                        echo "  $(tr ROUTER_HEALTH_OK "OmniRoute" "http://${ROUTER_BIND_ADDRESS}:${ROUTER_OMNIROUTE_PORT}")"
                    else
                        ROUTER_OMNIROUTE_STATUS="not-responding"
                        echo "  [WARN] $(tr ROUTER_HEALTH_FAIL "OmniRoute" "dashboard not responding")"
                        failed=1
                    fi
                else
                    ROUTER_OMNIROUTE_STATUS="installed-not-running"
                    echo "  [WARN] $(tr ROUTER_INSTALLED_NOT_RUNNING "OmniRoute")"
                    failed=1
                fi
            else
                ROUTER_OMNIROUTE_STATUS="skipped-port-conflict"
                failed=1
            fi
        else
            ROUTER_OMNIROUTE_STATUS="install-failed"
            echo "  [ERROR] $(tr ROUTER_INSTALL_FAILED "OmniRoute")"
            failed=1
        fi
    else
        ROUTER_OMNIROUTE_STATUS="disabled"
        echo "  $(tr ROUTER_SKIP_BY_CONFIG "OmniRoute")"
    fi

    # Persist across SSH logout / reboots (systemd when available, nohup
    # otherwise) and expose the binaries on PATH for future shells.
    enable_router_persistence
    export_router_npm_prefix

    export ROUTER_9ROUTER_STATUS ROUTER_OMNIROUTE_STATUS
    export ROUTER_9ROUTER_PORT ROUTER_OMNIROUTE_PORT
    return "${failed}"
}

fi # _GPU_RENTAL_KIT_ROUTERS_LOADED
