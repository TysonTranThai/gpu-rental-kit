#!/usr/bin/env bash
# =============================================================================
# network.sh — NETWORK / API EXPOSURE DIAGNOSTIC (REAL, read-only)
# =============================================================================
# Determines whether an external client could reach an inference API.
# Never opens firewall ports, never binds anything, makes no changes.
# =============================================================================
set -uo pipefail

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
result() { echo "[RESULT] $*"; }

echo "════════════════════════════════════════════════════════"
echo "  NETWORK / API EXPOSURE DIAGNOSTIC (REAL, read-only)"
echo "════════════════════════════════════════════════════════"

# ── 1. Localhost endpoints first ────────────────────────────────────────────
info ""
info "LOCALHOST API CHECK (127.0.0.1)"
FOUND_API=0
for port in 8000 8080 11434; do
    for ep in health v1/models; do
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${port}/${ep}" 2>/dev/null || true)"
        if [[ "${code}" != "000" ]]; then
            info "  127.0.0.1:${port}/${ep} → HTTP ${code}"
            FOUND_API=1
        fi
    done
done
if [[ "${FOUND_API}" -eq 0 ]]; then
    info "  no inference API responding on 127.0.0.1 (nothing to expose)"
fi

# ── 2. Listening ports ──────────────────────────────────────────────────────
info ""
info "LISTENING TCP PORTS"
if command -v ss >/dev/null 2>&1; then
    ss -tln 2>/dev/null | sed 's/^/  /'
elif command -v netstat >/dev/null 2>&1; then
    netstat -tln 2>/dev/null | sed 's/^/  /'
elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP -sTCP:LISTEN -P 2>/dev/null | sed 's/^/  /'
else
    warn "no port-listening tool available"
fi

# ── 3. Publicly bound listeners (potential exposure) ────────────────────────
info ""
info "PUBLICLY BOUND LISTENERS (0.0.0.0 / ::)"
if command -v ss >/dev/null 2>&1; then
    exposed="$(ss -tln 2>/dev/null | grep -E '0\.0\.0\.0:|\[::\]:' || true)"
elif command -v netstat >/dev/null 2>&1; then
    exposed="$(netstat -tln 2>/dev/null | grep -E '0\.0\.0\.0:|:::' || true)"
else
    exposed=""
fi
if [[ -n "${exposed}" ]]; then
    echo "${exposed}" | sed 's/^/  /'
    warn "services bound to all interfaces — reachable from outside the machine"
else
    info "  no publicly bound listeners found (localhost-only)"
fi

# ── 4. Docker port mappings ─────────────────────────────────────────────────
info ""
info "DOCKER PORT MAPPINGS"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    maps="$(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | grep -v '^$' || true)"
    if [[ -n "${maps}" ]]; then
        echo "${maps}" | sed 's/^/  /'
        warn "container port mappings above may be reachable from outside (0.0.0.0)"
    else
        info "  no running containers with port mappings"
    fi
else
    info "  docker not running"
fi

# ── 5. Public IP (informational) ────────────────────────────────────────────
info ""
info "PUBLIC IP (informational)"
pub="$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo '')"
if [[ -n "${pub}" ]]; then
    info "  public IP: ${pub}"
    warn "  this machine has public internet presence — do NOT bind APIs to 0.0.0.0 without a firewall + auth"
else
    info "  public IP: not determined (offline or blocked)"
fi

# ── 6. Provider tunnel interfaces ───────────────────────────────────────────
info ""
info "TUNNEL / VPN INTERFACES (provider tunnels, tailscale, etc.)"
if command -v ip >/dev/null 2>&1; then
    ip -brief addr 2>/dev/null | grep -iE 'tun|tap|wg|tailscale|zt|utun' | sed 's/^/  /' || true
fi
if command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | grep -iE '^(tun|tap|utun|wg|tailscale)' | sed 's/^/  /' || true
fi

# ── conclusion ──────────────────────────────────────────────────────────────
info ""
if [[ -n "${exposed:-}" ]]; then
    result "EXPOSURE: PUBLICLY BOUND SERVICES DETECTED — an external client could reach them"
    warn "recommendation: keep inference servers on 127.0.0.1, or bind 0.0.0.0 only behind a firewall + auth"
else
    result "EXPOSURE: LOCALHOST-ONLY — no public API exposure detected"
fi
echo "════════════════════════════════════════════════════════"
exit 0
