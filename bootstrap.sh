#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Single entry point for GPU Rental Kit
# =============================================================================
# On a fresh Linux NVIDIA GPU machine (after SSH):
#
#   git clone <repo> gpu-rental-kit
#   cd gpu-rental-kit
#   ./bootstrap.sh --remote-gpu
#
# On a macOS development machine:
#
#   ./bootstrap.sh
#
#   → detects macOS, prints "macOS development environment detected.
#     NVIDIA GPU setup tests are skipped." and offers the dev menu
#     (local validation, shell tests, mock GPU tests, remote instructions).
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'

print_banner() {
    echo -e "${C_BLUE}${C_BOLD}"
    echo "══════════════════════════════════════════════════════════════"
    echo "  GPU RENTAL KIT — Bootstrap"
    echo "══════════════════════════════════════════════════════════════"
    echo -e "${C_RESET}"
    echo ""
}

usage() {
    cat <<'USAGE'
Usage: ./bootstrap.sh [OPTIONS]

Options:
  --remote-gpu    Remote GPU mode. Run this after SSH-ing into a rented
                  Linux NVIDIA GPU machine. Performs full setup
                  (detect → configure → test → report).
  -y, --yes       Auto-confirm all prompts (safe with --remote-gpu).
  --interactive   Force interactive prompts (overrides remote auto-confirm).
  --validate      Run local project validation (syntax + consistency) only.
  --test          Run the full local test suite (mock GPU tests, etc.).
  -h, --help      Show this help.

On macOS (no flags): shows the development menu:
  1. Run local project validation
  2. Run shell tests (full test suite)
  3. Run mock GPU tests
  4. Show remote setup instructions
  5. Exit

Examples:
  ./bootstrap.sh                      # macOS: dev menu / Linux: interactive setup
  ./bootstrap.sh --remote-gpu         # THE command on a rented GPU machine
  ./bootstrap.sh --remote-gpu -y      # same, fully non-interactive
  ./bootstrap.sh --validate           # quick local sanity check
  ./bootstrap.sh --test               # full local test suite
USAGE
}

# =============================================================================
# Local project validation (safe on any OS — no system changes)
# =============================================================================
run_local_validation() {
    local failed=0
    echo -e "${C_BOLD}── Local project validation ──${C_RESET}"
    echo ""

    # 1. Bash syntax check on every .sh file
    local files
    files="$(find "${SCRIPT_DIR}" -type f -name '*.sh' 2>/dev/null || true)"
    local file
    while IFS= read -r file; do
        if ! bash -n "${file}" 2>/dev/null; then
            echo -e "  ${C_RED}[FAIL]${C_RESET} syntax: ${file}"
            failed=1
        fi
    done <<<"${files}"

    # 2. Every referenced script/bin exists
    local required=(setup.sh bootstrap.sh)
    local i
    for i in scripts/detect_environment.sh scripts/detect_gpu.sh scripts/test_gpu.sh \
             scripts/setup_system.sh scripts/setup_python.sh scripts/setup_docker.sh \
             scripts/setup_ollama.sh scripts/setup_vllm.sh scripts/setup_llamacpp.sh \
             scripts/setup_huggingface.sh scripts/setup_storage.sh \
             scripts/backup.sh scripts/restore.sh scripts/cleanup.sh; do
        if [[ ! -f "${SCRIPT_DIR}/${i}" ]]; then
            echo -e "  ${C_RED}[FAIL]${C_RESET} missing: ${i}"
            failed=1
        fi
    done
    for i in gpu-status gpu-test model-list model-download model-run model-stop model-logs \
             ai-start ai-stop ai-logs ai-info ai-backup; do
        if [[ ! -f "${SCRIPT_DIR}/bin/${i}" ]]; then
            echo -e "  ${C_RED}[FAIL]${C_RESET} missing: bin/${i}"
            failed=1
        fi
    done

    # 3. Executable bits on entry points
    for i in bootstrap.sh setup.sh bin/*; do
        if [[ -f "${SCRIPT_DIR}/${i}" ]] && [[ ! -x "${SCRIPT_DIR}/${i}" ]]; then
            echo -e "  ${C_YELLOW}[WARN]${C_RESET} not executable: ${i}"
            chmod +x "${SCRIPT_DIR}/${i}" 2>/dev/null || true
        fi
    done

    # 4. shellcheck if available
    if command -v shellcheck &>/dev/null; then
        echo -e "  ${C_BOLD}shellcheck:${C_RESET}"
        shellcheck --version | head -1 | sed 's/^/    /'
        # Non-fatal: report issues but don't fail the whole validation
        find "${SCRIPT_DIR}" -type f -name '*.sh' -o -path '*/bin/*' -type f 2>/dev/null | sort | while read -r f; do
            if [[ -f "${f}" ]] && head -1 "${f}" | grep -q '^#!.*bash'; then
                shellcheck -x -S error "${f}" 2>&1 | sed "s|^|    [${f##*/}] |" | grep -v '^$' || true
            fi
        done
    else
        echo -e "  ${C_YELLOW}[INFO]${C_RESET} shellcheck not installed — skipping (install with: brew install shellcheck)"
    fi

    if [[ "${failed}" -eq 0 ]]; then
        echo ""
        echo -e "${C_GREEN}✔ Validation passed.${C_RESET}"
    else
        echo ""
        echo -e "${C_RED}✘ Validation failed — fix the issues above.${C_RESET}"
    fi
    return "${failed}"
}

# =============================================================================
# Full test suite
# =============================================================================
run_test_suite() {
    if [[ -f "${SCRIPT_DIR}/test/run_tests.sh" ]]; then
        bash "${SCRIPT_DIR}/test/run_tests.sh"
    else
        echo -e "${C_RED}[ERROR]${C_RESET} test/run_tests.sh not found."
        return 1
    fi
}

# =============================================================================
# Mock GPU tests (subset of the suite)
# =============================================================================
run_mock_gpu_tests() {
    if [[ -f "${SCRIPT_DIR}/test/run_tests.sh" ]]; then
        bash "${SCRIPT_DIR}/test/run_tests.sh" gpu
    else
        echo -e "${C_RED}[ERROR]${C_RESET} test/run_tests.sh not found."
        return 1
    fi
}

# =============================================================================
# Remote setup instructions
# =============================================================================
show_remote_instructions() {
    cat <<'EOF'

  ── How to set up a rented GPU machine ─────────────────────────────

  1. Rent an NVIDIA GPU machine (e.g. RTX 3090/4090/5090, V100).
  2. SSH into it:
       ssh root@SERVER_IP
  3. Copy this project and run ONE command:

       git clone https://github.com/TysonTranThai/gpu-rental-kit.git gpu-rental-kit
       cd gpu-rental-kit
       ./bootstrap.sh --remote-gpu

     (Fully non-interactive: ./bootstrap.sh --remote-gpu -y)

  4. When setup finishes, check the machine report:
       cat ~/ai/logs/machine-report.txt

  5. Start a model:
       ai-start ollama llama3.1:8b
       # or vLLM (OpenAI-compatible API):
       ai-start vllm Qwen/Qwen2.5-7B-Instruct

  6. When the rental ends: ai-backup, then rebuild on the next machine.

  ⚠ Always clone the full repository — bootstrap.sh needs setup.sh,
    scripts/, and config/ next to it. Prefer cloning a pinned
    repo/commit and inspecting it first. The toolkit itself never
    installs NVIDIA drivers or exposes servers publicly.

EOF
}

# =============================================================================
# macOS development menu
# =============================================================================
macos_menu() {
    echo -e "${C_YELLOW}macOS development environment detected. NVIDIA GPU setup tests are skipped.${C_RESET}"
    echo ""
    while true; do
        echo -e "${C_BOLD}  GPU Rental Kit — macOS Development Menu${C_RESET}"
        echo ""
        echo "  1. Run local project validation"
        echo "  2. Run shell tests (full suite)"
        echo "  3. Run mock GPU tests"
        echo "  4. Show remote setup instructions"
        echo "  5. Exit"
        echo ""
        echo -n "  Choose [1-5]: "
        local choice
        read -r choice
        echo ""
        case "${choice}" in
            1) run_local_validation || true ;;
            2) run_test_suite || true ;;
            3) run_mock_gpu_tests || true ;;
            4) show_remote_instructions ;;
            5|q|quit|exit) echo -e "${C_GREEN}Bye!${C_RESET}"; exit 0 ;;
            *) echo -e "${C_YELLOW}Invalid choice.${C_RESET}" ;;
        esac
        echo ""
    done
}

# =============================================================================
# Main
# =============================================================================
print_banner

# Early flags that work on any OS
for arg in "$@"; do
    case "${arg}" in
        -h|--help|help)
            usage
            exit 0
            ;;
        --validate)
            run_local_validation
            exit $?
            ;;
        --test)
            run_test_suite
            exit $?
            ;;
    esac
done

REMOTE_GPU="no"
AUTO_CONFIRM="no"
EXTRA_ARGS=()
for arg in "$@"; do
    case "${arg}" in
        --remote-gpu) REMOTE_GPU="yes" ;;
        -y|--yes|--auto) AUTO_CONFIRM="yes" ;;
        --interactive) AUTO_CONFIRM="no" ;;
        *) EXTRA_ARGS+=("${arg}") ;;
    esac
done

PLATFORM="$(uname -s)"

if [[ "${PLATFORM}" == "Darwin" ]]; then
    if [[ "${REMOTE_GPU}" == "yes" ]]; then
        echo -e "${C_RED}[ERROR]${C_RESET} --remote-gpu requires a Linux machine with an NVIDIA GPU."
        echo -e "  Detected macOS. Use ./bootstrap.sh without flags for the dev menu."
        exit 1
    fi
    macos_menu
    exit 0
fi

if [[ "${PLATFORM}" != "Linux" ]]; then
    echo -e "${C_RED}[ERROR]${C_RESET} Unsupported platform: ${PLATFORM}"
    echo -e "  This toolkit supports Linux (Ubuntu/Debian) GPU machines and macOS development."
    exit 1
fi

# ── Linux ────────────────────────────────────────────────────────────
# Verify bash version
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo -e "${C_RED}[ERROR]${C_RESET} Bash 4+ required. Detected: ${BASH_VERSION}"
    exit 1
fi

if [[ ! -f "${SCRIPT_DIR}/setup.sh" ]]; then
    echo -e "${C_RED}[ERROR]${C_RESET} setup.sh not found in ${SCRIPT_DIR}"
    echo "  Make sure you cloned the full repository."
    exit 1
fi

if [[ "${REMOTE_GPU}" == "yes" ]]; then
    echo -e "${C_BOLD}Remote GPU mode.${C_RESET} Detecting environment..."
    echo ""
    if [[ "${AUTO_CONFIRM}" != "yes" ]] && [[ " $* " != *" --interactive "* ]]; then
        AUTO_CONFIRM="yes"
    fi
    SETUP_ARGS=(--remote-gpu)
    [[ "${AUTO_CONFIRM}" == "yes" ]] && SETUP_ARGS+=(-y)
else
    SETUP_ARGS=()
    [[ "${AUTO_CONFIRM}" == "yes" ]] && SETUP_ARGS+=(-y)
fi
SETUP_ARGS+=("${EXTRA_ARGS[@]}")

export AUTO_CONFIRM
echo -e "${C_BOLD}Running setup...${C_RESET}"
echo ""
bash "${SCRIPT_DIR}/setup.sh" "${SETUP_ARGS[@]}"
exit $?
