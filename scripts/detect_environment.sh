#!/usr/bin/env bash
# =============================================================================
# detect_environment.sh — Detect OS, virtualization, resources
# =============================================================================
# This script detects the environment (OS, VM/Docker, CPU, RAM, disk, network).
# It is sourced by setup.sh — do not execute standalone unless testing.
# =============================================================================

# Source guard
if [[ -z "${_GPU_RENTAL_KIT_LOADED:-}" ]]; then
    set -Eeuo pipefail
fi

# --- Colors ---
C_RESET='\033[0m'; C_BOLD='\033[1m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'

# --- State variables (populated by this script) ---
OS_ID=""
OS_VERSION=""
OS_NAME=""
IS_DOCKER="no"
IS_VM="no"
IS_WSL="no"
CPU_MODEL=""
CPU_CORES=""
CPU_THREADS=""
RAM_TOTAL_GB=""
RAM_AVAILABLE_GB=""
DISK_TOTAL_GB=""
DISK_AVAILABLE_GB=""
INTERNET_AVAILABLE="no"
HAS_SYSTEMD="no"

# =============================================================================
# detect_os — detect Linux distribution and version
# =============================================================================
detect_os() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        OS_ID="darwin"
        OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
        OS_NAME="macOS ${OS_VERSION}"
        export OS_ID OS_VERSION OS_NAME
        return 0
    fi

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_NAME="${PRETTY_NAME:-${OS_ID} ${OS_VERSION}}"
    elif [[ -f /etc/lsb-release ]]; then
        # shellcheck source=/dev/null
        source /etc/lsb-release
        OS_ID="ubuntu"
        OS_VERSION="${DISTRIB_RELEASE:-unknown}"
        OS_NAME="${DISTRIB_DESCRIPTION:-Ubuntu ${OS_VERSION}}"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_NAME="Unknown Linux"
    fi
    export OS_ID OS_VERSION OS_NAME
}

# =============================================================================
# check_distro_support — verify the OS is supported
# =============================================================================
check_distro_support() {
    case "${OS_ID}" in
        ubuntu|debian)
            if [[ "$(echo "${OS_VERSION}" | cut -d. -f1)" -lt 20 ]]; then
                echo -e "${C_RED}[ERROR]${C_RESET} Ubuntu/Debian ${OS_VERSION} is too old. Minimum: 20.04 / 11."
                return 1
            fi
            ;;
        centos|rhel|fedora|rocky|almalinux)
            echo -e "${C_YELLOW}[WARN]${C_RESET} ${OS_ID} ${OS_VERSION} detected. Primary support is for Ubuntu. YMMV."
            ;;
        *)
            echo -e "${C_RED}[ERROR]${C_RESET} Unsupported OS: ${OS_NAME}"
            echo "This toolkit is designed for Ubuntu 20.04/22.04/24.04."
            echo "You may continue at your own risk, but things may break."
            ;;
    esac
}

# =============================================================================
# detect_virtualization — check if running in Docker or a VM
# =============================================================================
detect_virtualization() {
    # Docker detection
    if grep -qE 'docker|containerd|/kubepods' /proc/1/cgroup 2>/dev/null; then
        IS_DOCKER="yes"
    elif [[ -f /.dockerenv ]]; then
        IS_DOCKER="yes"
    elif [[ -n "${DOCKER_CONTAINER:-}" ]] || [[ -n "${container:-}" ]]; then
        IS_DOCKER="yes"
    fi

    # VM detection
    if command -v systemd-detect-virt &>/dev/null; then
        local virt
        virt="$(systemd-detect-virt 2>/dev/null || true)"
        case "${virt}" in
            kvm|qemu|vmware|virtualbox|xen|microsoft) IS_VM="yes" ;;
            wsl) IS_WSL="yes" ;;
            none|"") ;;
            *) [[ -n "${virt}" ]] && IS_VM="maybe-${virt}" ;;
        esac
    elif grep -qE 'hypervisor|VMware|VirtualBox|QEMU' /proc/cpuinfo 2>/dev/null; then
        IS_VM="yes"
    fi

    export IS_DOCKER IS_VM IS_WSL
}

# =============================================================================
# detect_cpu — detect CPU model and cores (Linux + macOS safe)
# =============================================================================
# KIT_PROC_DIR can be set to a fake /proc directory for tests.
detect_cpu() {
    local proc_dir="${KIT_PROC_DIR:-/proc}"
    local cpuinfo="${proc_dir}/cpuinfo"

    if [[ -f "${cpuinfo}" ]]; then
        CPU_MODEL="$(grep -m1 'model name' "${cpuinfo}" 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//' || true)"
        CPU_CORES="$(grep -c '^processor' "${cpuinfo}" 2>/dev/null || true)"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        CPU_MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")"
        CPU_CORES="$(sysctl -n hw.ncpu 2>/dev/null || echo "0")"
    fi
    CPU_MODEL="${CPU_MODEL:-unknown}"
    CPU_CORES="${CPU_CORES:-0}"
    CPU_THREADS="${CPU_CORES}"
    export CPU_MODEL CPU_CORES CPU_THREADS
}

# =============================================================================
# detect_ram — detect total and available RAM in GB (Linux + macOS safe)
# =============================================================================
detect_ram() {
    local proc_dir="${KIT_PROC_DIR:-/proc}"
    local meminfo="${proc_dir}/meminfo"
    local mem_total_kb="0"
    local mem_avail_kb="0"

    if [[ -f "${meminfo}" ]]; then
        mem_total_kb="$(grep MemTotal "${meminfo}" 2>/dev/null | awk '{print $2}' || echo "0")"
        mem_avail_kb="$(grep MemAvailable "${meminfo}" 2>/dev/null | awk '{print $2}' || echo "0")"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        local mem_bytes
        mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || echo "0")"
        mem_total_kb="$(awk "BEGIN {printf \"%.0f\", ${mem_bytes}/1024}")"
        mem_avail_kb="${mem_total_kb}"
    fi

    RAM_TOTAL_GB="$(awk "BEGIN {printf \"%.1f\", ${mem_total_kb}/1024/1024}")"
    RAM_AVAILABLE_GB="$(awk "BEGIN {printf \"%.1f\", ${mem_avail_kb}/1024/1024}")"
    export RAM_TOTAL_GB RAM_AVAILABLE_GB
}

# =============================================================================
# detect_disk — detect available disk space on / in GB (Linux + macOS safe)
# =============================================================================
detect_disk() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS df has no -B flag; use -g (1GB blocks)
        DISK_TOTAL_GB="$(df -g / 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")"
        DISK_AVAILABLE_GB="$(df -g / 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")"
    else
        DISK_TOTAL_GB="$(df -BG / 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo "0")"
        DISK_AVAILABLE_GB="$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo "0")"
    fi
    DISK_TOTAL_GB="${DISK_TOTAL_GB:-0}"
    DISK_AVAILABLE_GB="${DISK_AVAILABLE_GB:-0}"
    export DISK_TOTAL_GB DISK_AVAILABLE_GB
}

# =============================================================================
# detect_internet — basic connectivity check
# =============================================================================
detect_internet() {
    if command -v curl &>/dev/null; then
        if curl -s --connect-timeout 5 --max-time 10 https://huggingface.co >/dev/null 2>&1; then
            INTERNET_AVAILABLE="yes"
        elif curl -s --connect-timeout 5 --max-time 10 https://pypi.org >/dev/null 2>&1; then
            INTERNET_AVAILABLE="yes"
        elif curl -s --connect-timeout 5 --max-time 10 https://github.com >/dev/null 2>&1; then
            INTERNET_AVAILABLE="yes"
        fi
    elif command -v wget &>/dev/null; then
        if wget -q --timeout=10 -O /dev/null https://huggingface.co 2>/dev/null; then
            INTERNET_AVAILABLE="yes"
        fi
    fi
    export INTERNET_AVAILABLE
}

# =============================================================================
# detect_systemd — check if systemd is available
# =============================================================================
detect_systemd() {
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        HAS_SYSTEMD="yes"
    fi
    export HAS_SYSTEMD
}

# =============================================================================
# Run all detections
# =============================================================================
run_environment_detection() {
    detect_os
    detect_virtualization
    detect_cpu
    detect_ram
    detect_disk
    detect_internet
    detect_systemd
}

# =============================================================================
# print_environment_summary — display a formatted summary
# =============================================================================
print_environment_summary() {
    echo ""
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}  ENVIRONMENT SUMMARY${C_RESET}"
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    printf "  %-20s %s\n" "OS:"          "${OS_NAME}"
    printf "  %-20s %s\n" "Kernel:"      "$(uname -r 2>/dev/null || echo 'N/A')"
    printf "  %-20s %s\n" "Architecture:" "$(uname -m 2>/dev/null || echo 'N/A')"
    printf "  %-20s %s\n" "Architecture:" "$(uname -m)"
    printf "  %-20s %s\n" "Container env?:" "${IS_DOCKER}"
    printf "  %-20s %s\n" "VM?:"         "${IS_VM}"
    printf "  %-20s %s\n" "WSL?:"        "${IS_WSL}"
    echo ""
    printf "  %-20s %s\n" "CPU:"         "${CPU_MODEL:0:60}"
    printf "  %-20s %s cores\n" "CPU Cores:" "${CPU_CORES}"
    printf "  %-20s %s GB\n" "RAM Total:" "${RAM_TOTAL_GB}"
    printf "  %-20s %s GB\n" "RAM Avail:" "${RAM_AVAILABLE_GB}"
    printf "  %-20s %s GB\n" "Disk Total:" "${DISK_TOTAL_GB}"
    printf "  %-20s %s GB\n" "Disk Avail:" "${DISK_AVAILABLE_GB}"
    printf "  %-20s %s\n" "Internet:"    "${INTERNET_AVAILABLE}"
    printf "  %-20s %s\n" "systemd:"     "${HAS_SYSTEMD}"
    echo ""
}

# If executed directly (not sourced), run and print
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_environment_detection
    print_environment_summary
fi