#!/usr/bin/env bash
# =============================================================================
# persistence.sh — PERSISTENCE DIAGNOSTIC (REAL)
# =============================================================================
# Determines what can be safely established about storage durability.
# Never claims rental-level persistence. Writes only to /tmp for probes.
# =============================================================================
set -uo pipefail

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
result() { echo "[RESULT] $*"; }

echo "════════════════════════════════════════════════════════"
echo "  PERSISTENCE DIAGNOSTIC (REAL)"
echo "════════════════════════════════════════════════════════"

# ── environment state ───────────────────────────────────────────────────────
info ""
info "ENVIRONMENT STATE"
if [[ -f /.dockerenv ]] || grep -qE 'docker|kubepods' /proc/1/cgroup 2>/dev/null; then
    warn "running inside a container — container deletion destroys local writes"
    STATE="container"
elif command -v systemd-detect-virt >/dev/null 2>&1 && [[ "$(systemd-detect-virt 2>/dev/null)" != "none" ]]; then
    info "virtualization: $(systemd-detect-virt 2>/dev/null)"
    warn "running in a VM — VM deletion destroys local writes"
    STATE="vm"
else
    STATE="unknown"
    info "virtualization: not detected (bare-metal or unknown)"
fi

# ── mounts ──────────────────────────────────────────────────────────────────
info ""
info "MOUNTS (non-virtual)"
df -hT 2>/dev/null | grep -vE 'tmpfs|overlay|proc|sysfs|devtmpfs' | sed 's/^/  /' || mount | sed 's/^/  /'

info ""
info "MOUNT CANDIDATES (provider persistent storage conventions)"
for m in /mnt /mnt/data /mnt/persistent /mnt/blockstorage /mnt/volume /mnt/nvme /mnt/ssd /data /persistent /storage /workspace /scratch /vol; do
    if [[ -d "${m}" ]]; then
        src="$(df "${m}" 2>/dev/null | tail -1 | awk '{print $1}')"
        root="$(df / 2>/dev/null | tail -1 | awk '{print $1}')"
        if [[ -n "${src}" ]] && [[ "${src}" != "${root}" ]]; then
            warn "  ${m}: SEPARATE mount (${src}) — durability unverified"
        else
            info "  ${m}: exists (same device as root)"
        fi
    fi
done

# ── writable probes (only /tmp + $HOME — never writes elsewhere) ───────────
info ""
info "WRITABLE PROBES (only /tmp and \$HOME are touched)"
if echo test > /tmp/grk-persist-probe 2>/dev/null; then
    info "  /tmp: writable (always ephemeral)"
    rm -f /tmp/grk-persist-probe
fi
if echo test > "${HOME}/.grk-persist-probe" 2>/dev/null; then
    info "  \$HOME: writable (durability depends on provider)"
    rm -f "${HOME}/.grk-persist-probe"
fi

# ── docker volumes ──────────────────────────────────────────────────────────
info ""
info "DOCKER VOLUMES"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    vols="$(docker volume ls -q 2>/dev/null | head -20)"
    if [[ -n "${vols}" ]]; then
        echo "${vols}" | sed 's/^/  /'
        warn "docker volumes survive container restarts but NOT necessarily rental end"
    else
        info "  no docker volumes"
    fi
else
    info "  docker not available"
fi

# ── disk identifiers ────────────────────────────────────────────────────────
info ""
info "DISK IDENTIFIERS"
if command -v lsblk >/dev/null 2>&1; then
    lsblk 2>/dev/null | head -15 | sed 's/^/  /'
elif [[ -r /proc/partitions ]]; then
    cat /proc/partitions 2>/dev/null | sed 's/^/  /'
else
    info "  no block-device listing available"
fi

# ── environment metadata ────────────────────────────────────────────────────
info ""
info "ENVIRONMENT METADATA"
for f in /var/lib/cloud/instance /etc/cloud/cloud.cfg /etc/cloudstack /etc/ec2; do
    if [[ -e "${f}" ]]; then info "  marker found: ${f}"; fi
done
if [[ -d /var/lib/cloud ]]; then warn "  cloud-init present — typical of cloud images (durability unknown)"; fi

# ── conclusion ──────────────────────────────────────────────────────────────
info ""
if [[ "${STATE}" == "container" ]]; then
    result "PERSISTENCE: NOT VERIFIED — container-local storage dies with the container"
elif [[ "${STATE}" == "vm" ]]; then
    result "PERSISTENCE: NOT VERIFIED — VM-local storage dies with the VM"
else
    result "PERSISTENCE: UNKNOWN"
fi
echo "  PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE."
echo "  (Only a provider statement about surviving rental termination can"
echo "   upgrade this to VERIFIED. Back up with ai-backup before the rental ends.)"
echo "════════════════════════════════════════════════════════"
exit 0
