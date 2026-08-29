#!/usr/bin/env bash
# =============================================================================
# privileges.sh — Shared privilege abstraction (root / sudo)
# =============================================================================
# Single source of truth for privileged command execution.
#
# Behavior:
#   - Running as root            -> SUDO="" (commands run directly)
#   - Non-root + sudo available  -> SUDO="sudo"
#   - Non-root + no sudo         -> fail with an actionable error
#
# Usage:
#   source scripts/privileges.sh
#   SUDO="$(resolve_sudo)"          # or: require_privileges
#   $SUDO apt-get install -y foo    # works with empty SUDO when root
#
# Minimal provider containers (Ubuntu root, no sudo, no systemd) are fully
# supported: when already root, sudo is never required or invoked.
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'

# =============================================================================
# resolve_sudo — echo the sudo prefix for the current user.
# Empty string when running as root; "sudo" when available; fails otherwise.
# Never blindly calls sudo: it is only executed for the availability probe
# when NOT running as root.
# =============================================================================
resolve_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        printf ''
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        printf 'sudo'
        return 0
    fi

    echo -e "${C_RED}[ERROR]${C_RESET} Not running as root and 'sudo' is not installed." >&2
    echo "  Rerun as root (recommended on rented GPU containers), or install sudo:" >&2
    echo "    apt-get install -y sudo   (as root)" >&2
    return 1
}

# =============================================================================
# require_privileges — resolve privileges and export SUDO for callers.
# Returns non-zero (with a clear message) when privileges are unavailable.
# =============================================================================
require_privileges() {
    SUDO="$(resolve_sudo)" || return 1
    export SUDO
    return 0
}
