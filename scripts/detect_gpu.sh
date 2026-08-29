#!/usr/bin/env bash
# =============================================================================
# detect_gpu.sh — Detect NVIDIA GPU, driver, CUDA compatibility, VRAM
# =============================================================================

if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'

# --- GPU state ---
HAS_NVIDIA_GPU="no"
GPU_COUNT=0
GPU_NAME=""
GPU_VRAM_MB=0
GPU_VRAM_GB=0
NVIDIA_DRIVER_VERSION=""
NVIDIA_DRIVER_OK="no"
CUDA_DRIVER_VERSION=""
CUDA_MAX_SUPPORTED=""
GPU_PROFILE="unknown"
GPU_ARCHITECTURE=""
GPU_COMPUTE_CAPABILITY=""

# --- Multi-GPU state (all pipe-separated lists, one entry per GPU) ---
GPU_NAMES_LIST=""        # e.g. "RTX 3090|RTX 3090"
GPU_VRAMS_MB_LIST=""     # e.g. "24576|24576"
GPU_VRAMS_GB_LIST=""     # e.g. "24|24"
GPU_PCI_BUSIDS_LIST=""   # e.g. "00000000:05:00.0|00000000:06:00.0"
GPU_COMPUTE_CAPS_LIST="" # e.g. "8.6|8.6"
GPU_TOTAL_VRAM_MB=0
GPU_TOTAL_VRAM_GB=0
GPU_MULTI_PROFILE="single"  # no-gpu | single | multi-gpu-small | multi-gpu-large | multi-gpu-mixed
GPU_MIXED_WARNING="no"       # yes when GPUs differ in model name or VRAM size
GPU_TOPOLOGY_AVAILABLE="no"
GPU_TOPOLOGY_RAW=""         # full `nvidia-smi topo -m` table (when available)
GPU_TOPOLOGY_LINKS=""       # lines like "GPU0 <-> GPU1: PCIe"
GPU_NUMA_LIST=""            # one entry per GPU: NUMA node or "N/A"
GPU_UUIDS_LIST=""          # one UUID per GPU (stable hardware identity)
GPU_ARCHS_LIST=""          # one architecture name per GPU (estimated)
GPU_CONFIG_TYPE="unknown"   # single | homogeneous | heterogeneous | mixed-architecture

# =============================================================================
# detect_nvidia_gpu — detect GPU via nvidia-smi, lspci, or other means
# =============================================================================
detect_nvidia_gpu() {
    # Method 1: nvidia-smi (best)
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi -L &>/dev/null 2>&1; then
            HAS_NVIDIA_GPU="yes"
            GPU_COUNT="$(nvidia-smi -L 2>/dev/null | wc -l | tr -d ' ')"
            GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")"
            GPU_VRAM_MB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1 | sed 's/ MiB//' || echo "0")"
            GPU_VRAM_GB="$(awk "BEGIN {printf \"%.0f\", ${GPU_VRAM_MB}/1024}")"
            NVIDIA_DRIVER_VERSION="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "")"
            NVIDIA_DRIVER_OK="yes"
            export GPU_COUNT GPU_NAME GPU_VRAM_MB GPU_VRAM_GB NVIDIA_DRIVER_VERSION NVIDIA_DRIVER_OK HAS_NVIDIA_GPU
            return 0
        fi
    fi

    # Method 2: lspci
    if command -v lspci &>/dev/null; then
        if lspci 2>/dev/null | grep -qiE '3D|VGA.*NVIDIA'; then
            HAS_NVIDIA_GPU="yes"
            GPU_COUNT="$(lspci 2>/dev/null | grep -ciE '3D.*NVIDIA|VGA.*NVIDIA' || echo 1)"
            GPU_NAME="$(lspci 2>/dev/null | grep -iE '3D.*NVIDIA|VGA.*NVIDIA' | head -1 | sed 's/.*: //' | sed 's/(rev.*//' || echo "unknown")"
            GPU_VRAM_MB=0
            GPU_VRAM_GB=0
            export HAS_NVIDIA_GPU GPU_COUNT GPU_NAME GPU_VRAM_MB GPU_VRAM_GB
            return 0
        fi
    fi

    # Method 3: /dev/nvidia* devices exist
    if ls /dev/nvidia* &>/dev/null 2>&1; then
        HAS_NVIDIA_GPU="yes"
        GPU_COUNT="$(ls -d /dev/nvidia[0-9]* 2>/dev/null | wc -l || echo 1)"
        GPU_NAME="NVIDIA (driver present, nvidia-smi unavailable)"
        export HAS_NVIDIA_GPU GPU_COUNT GPU_NAME
        return 0
    fi

    # No GPU found
    HAS_NVIDIA_GPU="no"
    GPU_COUNT=0
    export HAS_NVIDIA_GPU GPU_COUNT
}

# =============================================================================
# detect_cuda_compat — check CUDA driver API version compatibility
# =============================================================================
detect_cuda_compat() {
    if [[ "${HAS_NVIDIA_GPU}" != "yes" ]]; then
        CUDA_DRIVER_VERSION="N/A"
        CUDA_MAX_SUPPORTED="N/A"
        export CUDA_DRIVER_VERSION CUDA_MAX_SUPPORTED
        return
    fi

    # Check via nvidia-smi
    if command -v nvidia-smi &>/dev/null; then
        CUDA_DRIVER_VERSION="$(nvidia-smi 2>/dev/null | grep "CUDA Version" | sed 's/.*CUDA Version: //' | sed 's/ .*//' || echo "unknown")"
    fi

    # Check via nvcc if installed
    if command -v nvcc &>/dev/null; then
        CUDA_MAX_SUPPORTED="$(nvcc --version 2>/dev/null | grep "release" | sed 's/.*release //' | sed 's/,.*//' || echo "")"
    fi

    # Fallback: use driver version to estimate CUDA compat
    if [[ -z "${CUDA_MAX_SUPPORTED}" ]] && [[ -n "${NVIDIA_DRIVER_VERSION}" ]]; then
        local driver_major
        driver_major="$(echo "${NVIDIA_DRIVER_VERSION}" | cut -d. -f1)"
        # Approximate mapping: driver 550+ → CUDA 12.4, 535+ → 12.2, 525+ → 12.0, 515+ → 11.7, etc.
        if [[ "${driver_major}" -ge 550 ]]; then
            CUDA_MAX_SUPPORTED="12.4"
        elif [[ "${driver_major}" -ge 535 ]]; then
            CUDA_MAX_SUPPORTED="12.2"
        elif [[ "${driver_major}" -ge 525 ]]; then
            CUDA_MAX_SUPPORTED="12.0"
        elif [[ "${driver_major}" -ge 515 ]]; then
            CUDA_MAX_SUPPORTED="11.7"
        elif [[ "${driver_major}" -ge 470 ]]; then
            CUDA_MAX_SUPPORTED="11.4"
        else
            CUDA_MAX_SUPPORTED="unknown"
        fi
    fi

    export CUDA_DRIVER_VERSION CUDA_MAX_SUPPORTED
}

# =============================================================================
# gpu_arch_for_name <gpu-name> — print "Architecture|compute-capability"
# Estimates architecture/compute capability from the marketing name.
# (nvidia-smi does not expose compute capability; use PyTorch for exact CC.)
# =============================================================================
gpu_arch_for_name() {
    local gpu_name="$(echo "$1" | tr '[:upper:]' '[:lower:]')"

    if echo "${gpu_name}" | grep -qE 'rtx 50'; then
        echo "Blackwell|12.x"
    elif echo "${gpu_name}" | grep -qE 'rtx 40'; then
        echo "Ada Lovelace|8.9"
    elif echo "${gpu_name}" | grep -qE 'rtx 30'; then
        echo "Ampere|8.6"
    elif echo "${gpu_name}" | grep -qE 'rtx 20'; then
        echo "Turing|7.5"
    elif echo "${gpu_name}" | grep -qiE 'v100'; then
        echo "Volta|7.0"
    elif echo "${gpu_name}" | grep -qiE 'a100'; then
        echo "Ampere|8.0"
    elif echo "${gpu_name}" | grep -qiE 'h100'; then
        echo "Hopper|9.0"
    elif echo "${gpu_name}" | grep -qiE 't4|tesla t4'; then
        echo "Turing|7.5"
    elif echo "${gpu_name}" | grep -qiE 'p100'; then
        echo "Pascal|6.0"
    else
        echo "unknown|unknown"
    fi
}

# =============================================================================
# detect_gpu_details — collect per-GPU details for ALL NVIDIA GPUs
# Fills GPU_NAMES_LIST, GPU_VRAMS_MB_LIST, GPU_VRAMS_GB_LIST,
# GPU_PCI_BUSIDS_LIST, GPU_COMPUTE_CAPS_LIST, GPU_TOTAL_VRAM_MB/_GB.
# Existing single-GPU variables keep their original meaning (GPU 0 / first GPU)
# so nothing that relies on them changes.
# =============================================================================
detect_gpu_details() {
    GPU_NAMES_LIST=""
    GPU_VRAMS_MB_LIST=""
    GPU_VRAMS_GB_LIST=""
    GPU_PCI_BUSIDS_LIST=""
    GPU_COMPUTE_CAPS_LIST=""
    GPU_UUIDS_LIST=""
    GPU_ARCHS_LIST=""
    GPU_TOTAL_VRAM_MB=0
    GPU_TOTAL_VRAM_GB=0

    [[ "${HAS_NVIDIA_GPU}" != "yes" ]] && { export GPU_NAMES_LIST GPU_VRAMS_MB_LIST GPU_VRAMS_GB_LIST GPU_PCI_BUSIDS_LIST GPU_COMPUTE_CAPS_LIST GPU_UUIDS_LIST GPU_ARCHS_LIST GPU_TOTAL_VRAM_MB GPU_TOTAL_VRAM_GB; return 0; }

    local sep="" name vram_mb vram_gb pci_bus uuid cc_pair arch cc total=0

    if command -v nvidia-smi &>/dev/null && \
       nvidia-smi --query-gpu=index,name,memory.total,pci.bus_id,uuid --format=csv,noheader &>/dev/null 2>&1; then
        while IFS= read -r _row; do
            # Split on commas only (names contain spaces)
            _row="${_row#,}"; _row="${_row%,}"
            _idx="${_row%%,*}"; _rest="${_row#*,}"
            name="${_rest%%,*}"; _rest="${_rest#*,}"
            vram_mb="${_rest%%,*}"; _rest="${_rest#*,}"
            pci_bus="${_rest%%,*}"; uuid="${_rest#*,}"
            name="$(echo "${name}" | sed 's/^ *//;s/ *$//')"
            pci_bus="$(echo "${pci_bus}" | sed 's/^ *//;s/ *$//')"
            uuid="$(echo "${uuid}" | sed 's/^ *//;s/ *$//')"
            [[ -z "${name}" ]] && continue
            vram_mb="$(echo "${vram_mb}" | sed 's/[^0-9]//g')"
            [[ -z "${vram_mb}" ]] && vram_mb=0
            vram_gb="$(awk "BEGIN {printf \"%.0f\", ${vram_mb}/1024}")"
            cc_pair="$(gpu_arch_for_name "${name}")"
            arch="${cc_pair%%|*}"
            cc="${cc_pair##*|}"
            GPU_NAMES_LIST="${GPU_NAMES_LIST}${sep}${name}"
            GPU_VRAMS_MB_LIST="${GPU_VRAMS_MB_LIST}${sep}${vram_mb}"
            GPU_VRAMS_GB_LIST="${GPU_VRAMS_GB_LIST}${sep}${vram_gb}"
            GPU_PCI_BUSIDS_LIST="${GPU_PCI_BUSIDS_LIST}${sep}${pci_bus}"
            GPU_COMPUTE_CAPS_LIST="${GPU_COMPUTE_CAPS_LIST}${sep}${cc}"
            GPU_UUIDS_LIST="${GPU_UUIDS_LIST}${sep}${uuid}"
            GPU_ARCHS_LIST="${GPU_ARCHS_LIST}${sep}${arch}"
            sep="|"
            total=$((total + vram_mb))
        done < <(nvidia-smi --query-gpu=index,name,memory.total,pci.bus_id,uuid --format=csv,noheader 2>/dev/null)
    else
        # Fallback: -L lines ("GPU 0: <name> (UUID: ...)")
        local line gname luuid
        while IFS= read -r line; do
            gname="$(echo "${line}" | sed 's/^GPU[[:space:]]*[0-9]*:[[:space:]]*//' | sed 's/[[:space:]]*(UUID:.*$//' )"
            luuid="$(echo "${line}" | sed -n 's/.*(UUID: \([^)]*\)).*/\1/p')"
            [[ -z "${gname}" ]] && continue
            cc_pair="$(gpu_arch_for_name "${gname}")"
            arch="${cc_pair%%|*}"
            cc="${cc_pair##*|}"
            GPU_NAMES_LIST="${GPU_NAMES_LIST}${sep}${gname}"
            GPU_VRAMS_MB_LIST="${GPU_VRAMS_MB_LIST}${sep}0"
            GPU_VRAMS_GB_LIST="${GPU_VRAMS_GB_LIST}${sep}0"
            GPU_PCI_BUSIDS_LIST="${GPU_PCI_BUSIDS_LIST}${sep}unknown"
            GPU_COMPUTE_CAPS_LIST="${GPU_COMPUTE_CAPS_LIST}${sep}${cc}"
            GPU_UUIDS_LIST="${GPU_UUIDS_LIST}${sep}${luuid}"
            GPU_ARCHS_LIST="${GPU_ARCHS_LIST}${sep}${arch}"
            sep="|"
        done < <(nvidia-smi -L 2>/dev/null)
    fi

    GPU_TOTAL_VRAM_MB="${total}"
    GPU_TOTAL_VRAM_GB="$(awk "BEGIN {printf \"%.0f\", ${GPU_TOTAL_VRAM_MB}/1024}")"

    export GPU_NAMES_LIST GPU_VRAMS_MB_LIST GPU_VRAMS_GB_LIST GPU_PCI_BUSIDS_LIST GPU_COMPUTE_CAPS_LIST GPU_UUIDS_LIST GPU_ARCHS_LIST GPU_TOTAL_VRAM_MB GPU_TOTAL_VRAM_GB
}

# =============================================================================
# gpu_name_at <i> / gpu_vram_gb_at <i> / gpu_cc_at <i> — access list entries
# gpu_uuid_at <i> / gpu_arch_at <i> — hardware identity and architecture
# =============================================================================
gpu_name_at()      { echo "${GPU_NAMES_LIST}"      | cut -d'|' -f"$(( $1 + 1 ))"; }
gpu_vram_gb_at()   { echo "${GPU_VRAMS_GB_LIST}"   | cut -d'|' -f"$(( $1 + 1 ))"; }
gpu_pci_bus_at()   { echo "${GPU_PCI_BUSIDS_LIST}" | cut -d'|' -f"$(( $1 + 1 ))"; }
gpu_cc_at()        { echo "${GPU_COMPUTE_CAPS_LIST}" | cut -d'|' -f"$(( $1 + 1 ))"; }
gpu_uuid_at()      { echo "${GPU_UUIDS_LIST}"      | cut -d'|' -f"$(( $1 + 1 ))"; }
gpu_arch_at()      { echo "${GPU_ARCHS_LIST}"      | cut -d'|' -f"$(( $1 + 1 ))"; }

# =============================================================================
# detect_gpu_topology — parse `nvidia-smi topo -m` when available.
# Produces GPU_TOPOLOGY_LINKS lines like "GPU0 <-> GPU1: PCIe" or "...: NVLink".
# Never assumes NVLink exists; missing/failed topology is reported honestly.
# =============================================================================
detect_gpu_topology() {
    GPU_TOPOLOGY_AVAILABLE="no"
    GPU_TOPOLOGY_RAW=""
    GPU_TOPOLOGY_LINKS=""
    GPU_NUMA_LIST=""

    command -v nvidia-smi &>/dev/null || { export GPU_TOPOLOGY_AVAILABLE GPU_TOPOLOGY_RAW GPU_TOPOLOGY_LINKS; return 0; }
    GPU_TOPOLOGY_RAW="$(nvidia-smi topo -m 2>/dev/null || true)"
    [[ -z "${GPU_TOPOLOGY_RAW}" ]] && { export GPU_TOPOLOGY_AVAILABLE GPU_TOPOLOGY_RAW GPU_TOPOLOGY_LINKS; return 0; }
    GPU_TOPOLOGY_AVAILABLE="yes"

    local line row_idx tokens n=${GPU_COUNT} j cell link_type sep="" topo_sep=""
    while IFS= read -r line; do
        [[ "${line}" =~ ^GPU[0-9]+[[:space:]] ]] || continue
        row_idx="$(echo "${line}" | sed 's/^GPU\([0-9]*\).*$/\1/')"
        IFS=$'\t' read -r -a tokens <<< "$(echo "${line}" | tr -s '[:space:]' '\t')"
        for (( j=0; j<n; j++ )); do
            [[ "${j}" -le "${row_idx}" ]] || break
            cell="${tokens[$((j + 1))]:-}"
            [[ -z "${cell}" || "${cell}" == "X" ]] && continue
            [[ "${j}" -ge "${row_idx}" ]] && continue   # matrix is symmetric; keep upper triangle only
            case "${cell}" in
                NV*|nv*) link_type="NVLink" ;;
                PIX|PXB|PHB|NODE|SYS|PCIE|PIX#|PXB#|PHB#|NODE#|SYS#) link_type="PCIe" ;;
                *) link_type="${cell}" ;;
            esac
            GPU_TOPOLOGY_LINKS="${GPU_TOPOLOGY_LINKS}${sep}GPU${j} <-> GPU${row_idx}: ${link_type}"
            sep=$'\n'
        done
        # NUMA affinity is the LAST column of the row (after CPU Affinity)
        local numa
        numa="${tokens[${#tokens[@]} - 1]:-N/A}"
        [[ -z "${numa}" ]] && numa="N/A"
        GPU_NUMA_LIST="${GPU_NUMA_LIST}${topo_sep}${numa}"
        topo_sep="|"
    done <<< "${GPU_TOPOLOGY_RAW}"

    export GPU_TOPOLOGY_AVAILABLE GPU_TOPOLOGY_RAW GPU_TOPOLOGY_LINKS GPU_NUMA_LIST
}

# gpu_numa_at <i> — NUMA node for GPU i ("N/A" when unavailable)
gpu_numa_at() { echo "${GPU_NUMA_LIST}" | cut -d'|' -f"$(( $1 + 1 ))"; }

# gpu_link_type <a> <b> — print NVLink/PCIe/unknown for a GPU pair
gpu_link_type() {
    local a="$1" b="$2" tmp
    # Matrix is stored upper-triangle; normalize so a < b
    if [[ "${b}" -lt "${a}" ]]; then tmp="${a}"; a="${b}"; b="${tmp}"; fi
    local pair="GPU${a} <-> GPU${b}"
    if echo "${GPU_TOPOLOGY_LINKS}" | grep -q "^${pair}: NVLink$"; then
        echo "NVLink"
    elif echo "${GPU_TOPOLOGY_LINKS}" | grep -q "^${pair}: PCIe$"; then
        echo "PCIe"
    else
        echo "unknown"
    fi
}

# =============================================================================
# classify_gpu — determine GPU profile based on VRAM
# =============================================================================
classify_gpu() {
    if [[ "${HAS_NVIDIA_GPU}" != "yes" ]]; then
        GPU_PROFILE="no-gpu"
        GPU_ARCHITECTURE="N/A"
        GPU_COMPUTE_CAPABILITY="N/A"
        export GPU_PROFILE GPU_ARCHITECTURE GPU_COMPUTE_CAPABILITY
        return
    fi

    local vram_gb="${GPU_VRAM_GB:-0}"

    if [[ "${vram_gb}" -ge 80 ]]; then
        GPU_PROFILE="extreme"
    elif [[ "${vram_gb}" -ge 48 ]]; then
        GPU_PROFILE="extreme"
    elif [[ "${vram_gb}" -ge 32 ]]; then
        GPU_PROFILE="very-large"
    elif [[ "${vram_gb}" -ge 24 ]]; then
        GPU_PROFILE="large"
    elif [[ "${vram_gb}" -ge 16 ]]; then
        GPU_PROFILE="medium"
    elif [[ "${vram_gb}" -ge 12 ]]; then
        GPU_PROFILE="small-medium"
    elif [[ "${vram_gb}" -gt 0 ]]; then
        GPU_PROFILE="small"
    else
        GPU_PROFILE="unknown-vram"
    fi

    # Detect GPU architecture from name (estimated from marketing name)
    local cc_pair arch cc
    cc_pair="$(gpu_arch_for_name "${GPU_NAME}")"
    arch="${cc_pair%%|*}"
    cc="${cc_pair##*|}"
    GPU_ARCHITECTURE="${arch}"
    GPU_COMPUTE_CAPABILITY="${cc}"

    export GPU_PROFILE GPU_ARCHITECTURE GPU_COMPUTE_CAPABILITY
}

# =============================================================================
# classify_multi_gpu — aggregate/multi-GPU profile.
# single          — 1 GPU
# multi-gpu-small — 2+ identical GPUs, aggregate < 64GB
# multi-gpu-large — 2+ identical GPUs, aggregate >= 64GB
# multi-gpu-mixed — 2+ GPUs with differing models or VRAM sizes
# NOTE: "aggregate VRAM" is the sum of separate GPUs, NOT one pooled GPU.
# =============================================================================
classify_multi_gpu() {
    GPU_MULTI_PROFILE="single"
    GPU_MIXED_WARNING="no"

    if [[ "${HAS_NVIDIA_GPU}" != "yes" ]]; then
        GPU_MULTI_PROFILE="no-gpu"
    elif [[ "${GPU_COUNT}" -gt 1 ]]; then
        local distinct_names distinct_vrams
        distinct_names="$(echo "${GPU_NAMES_LIST}" | tr '|' '\n' | sort -u | grep -c . || true)"
        distinct_vrams="$(echo "${GPU_VRAMS_GB_LIST}" | tr '|' '\n' | sort -u | grep -c . || true)"
        if [[ "${distinct_names}" -gt 1 ]] || [[ "${distinct_vrams}" -gt 1 ]]; then
            GPU_MULTI_PROFILE="multi-gpu-mixed"
            GPU_MIXED_WARNING="yes"
        elif [[ "${GPU_TOTAL_VRAM_GB}" -ge 64 ]]; then
            GPU_MULTI_PROFILE="multi-gpu-large"
        else
            GPU_MULTI_PROFILE="multi-gpu-small"
        fi
    fi

    export GPU_MULTI_PROFILE GPU_MIXED_WARNING
}

# =============================================================================
# classify_gpu_config — formal configuration classification (spec naming).
#   single              — 1 GPU
#   homogeneous         — all GPUs share name + compute capability + VRAM
#   mixed-architecture  — GPUs differ in compute capability major version
#                         (different NVIDIA architectures, e.g. Ampere + Ada)
#   heterogeneous       — same architecture but differing VRAM or model name
# Classification uses compute capability + VRAM, NOT marketing name alone.
# =============================================================================
classify_gpu_config() {
    GPU_CONFIG_TYPE="unknown"

    if [[ "${HAS_NVIDIA_GPU}" != "yes" ]]; then
        GPU_CONFIG_TYPE="none"
    elif [[ "${GPU_COUNT}" -le 1 ]]; then
        GPU_CONFIG_TYPE="single"
    else
        local distinct_archs=0 distinct_names=0 distinct_vrams=0
        distinct_archs="$(echo "${GPU_ARCHS_LIST}" | tr '|' '\n' | sort -u | grep -c . || true)"
        distinct_names="$(echo "${GPU_NAMES_LIST}" | tr '|' '\n' | sort -u | grep -c . || true)"
        distinct_vrams="$(echo "${GPU_VRAMS_GB_LIST}" | tr '|' '\n' | sort -u | grep -c . || true)"

        if [[ "${distinct_archs}" -gt 1 ]]; then
            # Different NVIDIA architectures (e.g. Ampere + Ada, Ampere + Blackwell)
            GPU_CONFIG_TYPE="mixed-architecture"
        elif [[ "${distinct_names}" -gt 1 ]] || [[ "${distinct_vrams}" -gt 1 ]]; then
            GPU_CONFIG_TYPE="heterogeneous"
        else
            GPU_CONFIG_TYPE="homogeneous"
        fi
    fi

    export GPU_CONFIG_TYPE
}

# =============================================================================
# print_gpu_summary
# =============================================================================
print_gpu_summary() {
    echo ""
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}  GPU SUMMARY${C_RESET}"
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    printf "  %-22s %s\n" "NVIDIA GPU:"     "${HAS_NVIDIA_GPU}"
    printf "  %-22s %s\n" "GPU Count:"      "${GPU_COUNT}"
    printf "  %-22s %s\n" "GPU Name:"       "${GPU_NAME}"
    printf "  %-22s %s MB (%s GB)\n" "VRAM:" "${GPU_VRAM_MB}" "${GPU_VRAM_GB}"
    printf "  %-22s %s\n" "Architecture:"   "${GPU_ARCHITECTURE}"
    printf "  %-22s %s\n" "Compute Cap:"    "${GPU_COMPUTE_CAPABILITY}"
    printf "  %-22s %s\n" "Driver:"         "${NVIDIA_DRIVER_VERSION:-not detected}"
    printf "  %-22s %s\n" "Driver OK:"      "${NVIDIA_DRIVER_OK}"
    printf "  %-22s %s\n" "CUDA Driver:"    "${CUDA_DRIVER_VERSION:-N/A}"
    printf "  %-22s %s\n" "CUDA Max:"       "${CUDA_MAX_SUPPORTED:-N/A}"
    printf "  %-22s %s\n" "Profile:"        "${GPU_PROFILE}"
    echo ""

    # --- Multi-GPU summary (only shown when more than one GPU exists) ---
    if [[ "${HAS_NVIDIA_GPU}" == "yes" ]] && [[ "${GPU_COUNT}" -gt 1 ]]; then
        echo -e "${C_BOLD}  MULTI-GPU:${C_RESET}"
        local i
        for (( i=0; i<GPU_COUNT; i++ )); do
            printf "    GPU %-2s %-32s %6s GB  (CC %s)\n" "${i}" "$(gpu_name_at "${i}")" "$(gpu_vram_gb_at "${i}")" "$(gpu_cc_at "${i}")"
        done
        printf "    %-20s %s GB\n" "Aggregate VRAM:" "${GPU_TOTAL_VRAM_GB}"
        echo "    Note: aggregate VRAM is the SUM of separate GPUs,"
        echo "    not one pooled GPU. Usability depends on the runtime."
        if [[ "${GPU_MIXED_WARNING}" == "yes" ]]; then
            echo -e "    ${C_YELLOW}[WARN]${C_RESET} Mixed GPUs: the slower/smaller GPU can become the bottleneck."
        fi
        if [[ "${GPU_TOPOLOGY_AVAILABLE}" == "yes" ]] && [[ -n "${GPU_TOPOLOGY_LINKS}" ]]; then
            echo -e "    ${C_BOLD}Topology:${C_RESET}"
            echo "${GPU_TOPOLOGY_LINKS}" | sed 's/^/      /'
        fi
        echo ""
    fi

    if [[ "${HAS_NVIDIA_GPU}" != "yes" ]]; then
        echo -e "${C_RED}[ERROR]${C_RESET} No NVIDIA GPU detected."
        echo "This toolkit requires an NVIDIA GPU with working drivers."
        echo "If you believe this is incorrect, check: nvidia-smi"
    elif [[ "${NVIDIA_DRIVER_OK}" != "yes" ]]; then
        echo -e "${C_YELLOW}[WARN]${C_RESET} NVIDIA GPU detected but nvidia-smi is not working."
        echo "Run as root: apt install -y nvidia-driver-550 (or via sudo if available)"
    fi
    echo ""
}

# =============================================================================
# Run all detections
# =============================================================================
run_gpu_detection() {
    detect_nvidia_gpu
    detect_cuda_compat
    classify_gpu
    detect_gpu_details
    detect_gpu_topology
    classify_multi_gpu
    classify_gpu_config
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_gpu_detection
    print_gpu_summary
fi