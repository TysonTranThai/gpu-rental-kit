#!/usr/bin/env bash
# =============================================================================
# ssh_lib.sh — SSH connection helpers for remote GPU tests
# =============================================================================
# Source this from remote test scripts. Never hard-codes credentials and never
# stores passwords. Supports:
#   - SSH key authentication   (--key /path/to/key)
#   - SSH agent                (--auth agent — default, uses ssh-agent)
#   - normal SSH config        (--auth config — host entry in ~/.ssh/config)
#
# Target comes from flags or env vars:
#   GPU_HOST, GPU_PORT, GPU_USER
# =============================================================================
set -Eeuo pipefail

SSH_LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Target resolution ---
REMOTE_HOST="${GPU_HOST:-}"
REMOTE_PORT="${GPU_PORT:-22}"
REMOTE_USER="${GPU_USER:-}"
REMOTE_AUTH="agent"          # agent | key | config
REMOTE_KEY=""
SSH_BATCH="yes"              # never prompt for passwords

ssh_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host) REMOTE_HOST="$2"; shift 2 ;;
            --port) REMOTE_PORT="$2"; shift 2 ;;
            --user) REMOTE_USER="$2"; shift 2 ;;
            --auth)
                case "$2" in
                    key|agent|config) REMOTE_AUTH="$2" ;;
                    *) echo "  [ERROR] --auth must be key|agent|config (got '$2')" >&2; return 1 ;;
                esac
                shift 2
                ;;
            --key) REMOTE_AUTH="key"; REMOTE_KEY="$2"; shift 2 ;;
            --batch) SSH_BATCH="yes"; shift ;;
            --interactive) SSH_BATCH="no"; shift ;;
            -h|--help) return 2 ;;
            *) echo "  [ERROR] unknown argument: $1" >&2; return 1 ;;
        esac
    done
    return 0
}

ssh_usage() {
    cat <<'EOF'
  Connection options:
    --host HOST     Target IP/hostname      (env: GPU_HOST)
    --port PORT     SSH port (default 22)   (env: GPU_PORT)
    --user USER     SSH user                (env: GPU_USER)
    --auth METHOD   key | agent | config (default: agent)
    --key FILE      SSH private key path (implies --auth key)
    --batch         Never prompt for passwords (default)
    --interactive   Allow password prompts (not recommended)

  Environment variables (used automatically when flags are omitted):
    GPU_HOST GPU_PORT GPU_USER
EOF
}

# ssh_target_ok — returns 0 when a host is configured
ssh_target_ok() {
    [[ -n "${REMOTE_HOST}" ]]
}

# ssh_build_cmd <remote-command> — echoes the full ssh invocation (array-safe
# usage: mapfile -t cmd < <(ssh_build_cmd '...'); "${cmd[@]}")
ssh_build_cmd() {
    local remote_cmd="$1"
    local -a args=(-o "BatchMode=${SSH_BATCH}" -o "ConnectTimeout=15" -o "StrictHostKeyChecking=accept-new")
    [[ -n "${REMOTE_PORT}" ]] && args+=(-p "${REMOTE_PORT}")
    case "${REMOTE_AUTH}" in
        key) args+=(-i "${REMOTE_KEY}") ;;
        agent|config) : ;;
    esac
    local target=""
    if [[ -n "${REMOTE_USER}" ]]; then
        target="${REMOTE_USER}@${REMOTE_HOST}"
    else
        target="${REMOTE_HOST}"
    fi
    printf '%s\n' "ssh ${args[*]} ${target} ${remote_cmd@Q}"
}

# ssh_build_args — assemble the ssh/scp argument array
ssh_build_args() {
    local -a args=(-o "BatchMode=${SSH_BATCH}" -o "ConnectTimeout=15" -o "StrictHostKeyChecking=accept-new")
    [[ -n "${REMOTE_PORT}" ]] && args+=(-p "${REMOTE_PORT}")
    [[ "${REMOTE_AUTH}" == "key" ]] && args+=(-i "${REMOTE_KEY}")
    printf '%s\n' "${args[@]}"
}

# ssh_target — build user@host (or host when no user)
ssh_target() {
    if [[ -n "${REMOTE_USER}" ]]; then
        echo "${REMOTE_USER}@${REMOTE_HOST}"
    else
        echo "${REMOTE_HOST}"
    fi
}

# ssh_run <remote-command> — run a command on the remote host, print output
ssh_run() {
    local remote_cmd="$1"
    local -a args=()
    while IFS= read -r a; do args+=("$a"); done < <(ssh_build_args)
    # shellcheck disable=SC2206
    args+=("$(ssh_target)" "${remote_cmd}")
    ssh "${args[@]}"
}

# ssh_run_script <script-file> — copy a script to the remote and execute it
ssh_run_script() {
    local script_file="$1" remote_name
    remote_name="grk-$(basename "${script_file}")"
    local -a cargs=(-o "BatchMode=${SSH_BATCH}" -o "ConnectTimeout=15")
    [[ -n "${REMOTE_PORT}" ]] && cargs+=(-P "${REMOTE_PORT}")
    [[ "${REMOTE_AUTH}" == "key" ]] && cargs+=(-i "${REMOTE_KEY}")
    cargs+=("${script_file}" "$(ssh_target):/tmp/${remote_name}")
    scp "${cargs[@]}"
    ssh_run "chmod +x /tmp/${remote_name} && bash /tmp/${remote_name}"
}

# ssh_run_stdin <script-file> — pipe a script to `bash -s` on the remote
ssh_run_stdin() {
    local script_file="$1"
    local -a args=()
    while IFS= read -r a; do args+=("$a"); done < <(ssh_build_args)
    args+=("$(ssh_target)" "bash -s")
    ssh "${args[@]}" < "${script_file}"
}
