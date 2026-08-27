#!/usr/bin/env bash
# =============================================================================
# setup_storage.sh — Detect and classify storage persistence
# =============================================================================
# Rental machines are disposable. This script inspects where data lives and
# classifies how likely it is to survive:
#
#   container restart   (same container, process restarted)  → usually survives
#   container deletion  (container destroyed)                 → lost
#   VM restart          (same VM, rebooted)                   → usually survives
#   VM deletion         (VM destroyed)                        → lost
#   rental termination  (provider reclaims everything)        → lost unless the
#                                                               provider mounts
#                                                               persistent storage
#
# We NEVER claim storage is persistent without evidence. When the provider
# environment cannot be verified, we report:
#
#   "PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE."
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_CYAN='\033[0;36m'

# --- State variables (populated by detect_storage) ---
STORAGE_CLASSIFICATION=""           # TEMPORARY | PERSISTENT | UNKNOWN
STORAGE_CONFIDENCE=""               # high | low | none
STORAGE_STATE=""                    # container | vm | bare-metal | unknown
STORAGE_SURVIVES_RESTART=""         # yes | no | unknown  (same container/VM restart)
STORAGE_SURVIVES_DELETE=""          # yes | no | unknown  (container/VM deletion)
STORAGE_SURVIVES_RENTAL_END=""      # yes | no | unknown  (rental termination)
STORAGE_ADVISORY=""                 # human-readable warning
PERSISTENT_MOUNTS=()

# =============================================================================
# _mount_fstype — filesystem type of a path (Linux). Portable fallback for macOS.
# =============================================================================
_mount_fstype() {
    local path="$1"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        stat -f '%T' "${path}" 2>/dev/null || echo "unknown"
    else
        stat -f -c '%T' "${path}" 2>/dev/null || echo "unknown"
    fi
}

# =============================================================================
# _detect_provider_hints — look for known cloud/provider markers
# =============================================================================
# Returns "yes" and sets PROVIDER_NAME if a provider marker is found.
# This is intentionally conservative: absence of a marker means "unknown",
# never "persistent".
# =============================================================================
PROVIDER_NAME="unknown"

_detect_provider_hints() {
    PROVIDER_NAME="unknown"
    # Cloud-init is present on most cloud images (Azure, GCP, OpenStack, AWS).
    if [[ -d /var/lib/cloud ]] || [[ -f /etc/cloud/cloud.cfg ]]; then
        PROVIDER_NAME="cloud-init (generic cloud image)"
    fi
    # Common provider-specific markers.
    for marker in /etc/cloudstack /etc/ec2 /etc/vultr /etc/linode; do
        if [[ -e "${marker}" ]]; then
            PROVIDER_NAME="${marker}"
            break
        fi
    done
    export PROVIDER_NAME
}

# =============================================================================
# classify_persistence — pure logic: derive classification from detected state
# =============================================================================
# PERSISTENT_MOUNTS, IS_DOCKER, IS_VM must already be set.
classify_persistence() {
    # --- Determine environment state ---
    if [[ "${IS_DOCKER:-no}" == "yes" ]]; then
        STORAGE_STATE="container"
        STORAGE_SURVIVES_RESTART="yes"     # container restart keeps the filesystem
        STORAGE_SURVIVES_DELETE="no"       # container deletion destroys local writes
        STORAGE_SURVIVES_RENTAL_END="no"
    elif [[ "${IS_VM:-no}" == "yes" ]] || [[ "${IS_VM:-}" == maybe-* ]]; then
        STORAGE_STATE="vm"
        STORAGE_SURVIVES_RESTART="yes"     # VM reboot keeps the disk (usually)
        STORAGE_SURVIVES_DELETE="no"       # VM deletion destroys local writes
        STORAGE_SURVIVES_RENTAL_END="no"
    else
        STORAGE_STATE="unknown"
        STORAGE_SURVIVES_RESTART="unknown"
        STORAGE_SURVIVES_DELETE="unknown"
        STORAGE_SURVIVES_RENTAL_END="unknown"
    fi

    # --- Classify ---
    if [[ "${#PERSISTENT_MOUNTS[@]}" -gt 0 ]]; then
        STORAGE_CLASSIFICATION="PERSISTENT/UNKNOWN"
        STORAGE_CONFIDENCE="low"
    else
        STORAGE_CLASSIFICATION="TEMPORARY"
        STORAGE_CONFIDENCE="high"   # high confidence that local storage is NOT durable
    fi

    # Build advisory
    STORAGE_ADVISORY="PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE."
    if [[ "${STORAGE_CLASSIFICATION}" == "TEMPORARY" ]]; then
        STORAGE_ADVISORY="Local storage is TEMPORARY. It survives: restart=${STORAGE_SURVIVES_RESTART}, deletion=${STORAGE_SURVIVES_DELETE}, rental end=${STORAGE_SURVIVES_RENTAL_END}. Back up before the rental ends."
        if [[ "${STORAGE_STATE}" == "unknown" ]]; then
            # Provider environment could not be verified → keep the hard warning.
            STORAGE_ADVISORY="${STORAGE_ADVISORY} PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE."
        fi
    elif [[ "${STORAGE_CONFIDENCE}" == "low" ]]; then
        STORAGE_ADVISORY="Potential persistent mounts found, but durability could NOT be verified with the provider. PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE."
    fi

    export STORAGE_CLASSIFICATION STORAGE_CONFIDENCE STORAGE_STATE
    export STORAGE_SURVIVES_RESTART STORAGE_SURVIVES_DELETE STORAGE_SURVIVES_RENTAL_END
    export STORAGE_ADVISORY
}

# =============================================================================
# detect_storage — inspect mounts and classify persistence
# =============================================================================
detect_storage() {
    echo -e "${C_BOLD}[storage]${C_RESET} Detecting storage persistence..."

    _detect_provider_hints

    # --- Inspect mounted filesystems ---
    # KIT_MOUNTS_FILE can point at a fixture for tests.
    local mounts_file="${KIT_MOUNTS_FILE:-/proc/mounts}"
    local all_mounts=""
    if [[ -f "${mounts_file}" ]]; then
        all_mounts="$(grep -vE '^(proc|sysfs|devpts|tmpfs|cgroup|overlay|shm|mqueue|securityfs|debugfs|hugetlbfs|fuse\.|pstore|bpf|binfmt_misc|tracefs|autofs|efivarfs|ramfs|nfsd|nsfs)' \
            "${mounts_file}" 2>/dev/null | awk '{print $2}' | sort -u || true)"
    fi

    # Common mount locations that providers use for extra/persistent storage.
    local candidate_mounts=(
        "/mnt" "/mnt/data" "/mnt/persistent" "/mnt/storage"
        "/mnt/blockstorage" "/mnt/volume" "/mnt/nvme" "/mnt/ssd"
        "/data" "/persistent" "/storage" "/vol"
        "/workspace" "/workspace/storage" "/scratch" "/job"
    )

    local root_source=""
    if command -v df &>/dev/null && [[ "$(uname -s)" != "Darwin" ]]; then
        root_source="$(df --output=source / 2>/dev/null | tail -1 || true)"
    fi

    PERSISTENT_MOUNTS=()
    local found_persistent=""
    local mount

    for mount in "${candidate_mounts[@]}"; do
        [[ -n "${mount}" ]] || continue
        [[ -d "${mount}" ]] || continue

        local fstype size_gb avail_gb
        fstype="$(_mount_fstype "${mount}")"
        if [[ "$(uname -s)" == "Darwin" ]]; then
            size_gb="$(df -g "${mount}" 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")"
            avail_gb="$(df -g "${mount}" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")"
        else
            size_gb="$(df -BG "${mount}" 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo "0")"
            avail_gb="$(df -BG "${mount}" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo "0")"
        fi
        size_gb="${size_gb:-0}"
        avail_gb="${avail_gb:-0}"

        local is_root=""
        if [[ -n "${root_source}" ]] && command -v df &>/dev/null; then
            is_root="$(df --output=source "${mount}" 2>/dev/null | tail -1 || true)"
        fi

        # Separate block device (different source than /) → candidate persistent.
        if [[ -n "${is_root}" ]] && [[ "${is_root}" != "${root_source}" ]] && [[ "${size_gb}" -gt 0 ]]; then
            found_persistent="${found_persistent} ${mount} (${fstype}, ${size_gb}GB total, ${avail_gb}GB free)"
            PERSISTENT_MOUNTS+=("${mount}")
        elif [[ "${mount}" == "/mnt"* ]] || [[ "${mount}" == "/data"* ]] || [[ "${mount}" == "/storage"* ]] || [[ "${mount}" == "/workspace"* ]]; then
            # Path convention suggests persistent intent, but we cannot verify.
            found_persistent="${found_persistent} ${mount} (${fstype}, ${size_gb}GB total, ${avail_gb}GB free) [UNVERIFIED]"
            PERSISTENT_MOUNTS+=("${mount}")
        fi
    done

    classify_persistence

    export PERSISTENT_MOUNTS PROVIDER_NAME

    echo ""
    echo -e "  ${C_BOLD}STORAGE CLASSIFICATION:${C_RESET} ${C_CYAN}${STORAGE_CLASSIFICATION}${C_RESET}"
    echo -e "  ${C_BOLD}STORAGE CONFIDENCE:${C_RESET}     ${C_CYAN}${STORAGE_CONFIDENCE}${C_RESET}"
    echo -e "  ${C_BOLD}ENVIRONMENT STATE:${C_RESET}      ${C_CYAN}${STORAGE_STATE}${C_RESET} (provider: ${PROVIDER_NAME})"
    echo ""

    if [[ "${#PERSISTENT_MOUNTS[@]}" -gt 0 ]]; then
        echo -e "  ${C_YELLOW}Potential persistent mounts (UNVERIFIED):${C_RESET}"
        for m in "${PERSISTENT_MOUNTS[@]}"; do
            echo -e "    ${m}"
        done
    else
        echo -e "  ${C_RED}No persistent storage detected.${C_RESET}"
    fi
    echo ""

    echo -e "  ${C_YELLOW}${STORAGE_ADVISORY}${C_RESET}"
    echo ""
    echo -e "  Survival matrix (local storage, ${STORAGE_STATE}):"
    echo -e "    container/VM restart  → ${STORAGE_SURVIVES_RESTART}"
    echo -e "    container/VM deletion → ${STORAGE_SURVIVES_DELETE}"
    echo -e "    rental termination    → ${STORAGE_SURVIVES_RENTAL_END}"
    echo ""
}

# =============================================================================
# configure_model_storage — configure model/cache dirs (optionally on a mount)
# =============================================================================
configure_model_storage() {
    local ai_home="${AI_HOME:-${HOME}/ai}"

    # If persistent mounts found, offer to use one
    if [[ "${#PERSISTENT_MOUNTS[@]}" -gt 0 ]] && [[ "${ALLOW_STORAGE_PROMPT:-no}" == "yes" ]]; then
        echo ""
        echo -e "${C_BOLD}  Select a storage location for models/cache:${C_RESET}"
        echo "  0) ${ai_home} (home — may be TEMPORARY)"
        local i=1
        for mount in "${PERSISTENT_MOUNTS[@]}"; do
            echo "  ${i}) ${mount}/ai (persistent/unknown — unverified)"
            ((i++))
        done
        echo -n "  Choice [0]: "
        local choice
        read -r choice
        choice="${choice:-0}"

        if [[ "${choice}" -gt 0 ]] && [[ "${choice}" -le "${#PERSISTENT_MOUNTS[@]}" ]]; then
            local selected_mount="${PERSISTENT_MOUNTS[$((choice-1))]}"
            AI_MODELS_DIR="${selected_mount}/ai/models"
            AI_CACHE_DIR="${selected_mount}/ai/cache"
            mkdir -p "${AI_MODELS_DIR}" "${AI_CACHE_DIR}"
            echo -e "${C_GREEN}[OK]${C_RESET} Models/cache → ${selected_mount}/ai"
            echo -e "  ${C_YELLOW}Note:${C_RESET} durability unverified — still back up before rental end."
        else
            echo -e "${C_YELLOW}[INFO]${C_RESET} Keeping default home location."
        fi
    fi

    # Ensure directories exist
    mkdir -p "${AI_MODELS_DIR:-${ai_home}/models}" "${AI_CACHE_DIR:-${ai_home}/cache}"

    export AI_MODELS_DIR AI_CACHE_DIR
}

# =============================================================================
# run_storage_setup
# =============================================================================
run_storage_setup() {
    detect_storage
    configure_model_storage
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    AI_HOME="${AI_HOME:-${HOME}/ai}"
    ALLOW_STORAGE_PROMPT="yes"
    run_storage_setup
fi
