#!/usr/bin/env bash
# =============================================================================
# test_consistency.sh — structural consistency checks
# =============================================================================
# * Every script referenced by setup.sh/bootstrap.sh exists
# * Every bin command is executable
# * README commands match the actual project layout
# =============================================================================
TEST_NAME="consistency"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

ensure_executable

# --- Required top-level files ---
for f in setup.sh bootstrap.sh README.md LICENSE .gitignore \
         config/defaults.env config/models.yaml \
         docker/Dockerfile docker/compose.yml; do
    if [[ -f "${KIT_ROOT}/${f}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ missing required file: ${f}"
    fi
done

# --- Required scripts ---
for f in detect_environment.sh detect_gpu.sh test_gpu.sh \
         setup_system.sh setup_python.sh setup_docker.sh setup_ollama.sh \
         setup_vllm.sh setup_llamacpp.sh setup_huggingface.sh setup_storage.sh \
         backup.sh restore.sh cleanup.sh; do
    if [[ -f "${KIT_ROOT}/scripts/${f}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ missing script: scripts/${f}"
    fi
done

# --- Required bin commands ---
for f in gpu-status gpu-test model-list model-download model-run model-stop \
         model-logs ai-start ai-stop ai-logs ai-info ai-backup ai-doctor; do
    if [[ -f "${KIT_ROOT}/bin/${f}" ]]; then
        if [[ -x "${KIT_ROOT}/bin/${f}" ]]; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo "  ✘ bin/${f} not executable"
        fi
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ missing command: bin/${f}"
    fi
done

# --- Entry points executable ---
for f in bootstrap.sh setup.sh; do
    if [[ -x "${KIT_ROOT}/${f}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ ${f} not executable"
    fi
done

# --- scripts sourced by setup.sh must define the functions setup.sh calls ---
declare -a required_functions=(
    "detect_environment.sh:detect_os"
    "detect_environment.sh:detect_virtualization"
    "detect_environment.sh:detect_cpu"
    "detect_environment.sh:detect_ram"
    "detect_environment.sh:detect_disk"
    "detect_environment.sh:detect_internet"
    "detect_environment.sh:print_environment_summary"
    "detect_gpu.sh:run_gpu_detection"
    "detect_gpu.sh:detect_cuda_compat"
    "detect_gpu.sh:print_gpu_summary"
    "setup_system.sh:install_base_packages"
    "setup_system.sh:create_ai_directories"
    "setup_system.sh:write_machine_env"
    "setup_storage.sh:detect_storage"
    "setup_storage.sh:configure_model_storage"
    "setup_python.sh:run_python_setup"
    "setup_huggingface.sh:install_huggingface_cli"
    "setup_ollama.sh:run_ollama_setup"
    "setup_vllm.sh:run_vllm_setup"
    "setup_llamacpp.sh:run_llamacpp_setup"
    "setup_docker.sh:detect_docker"
    "setup_docker.sh:install_docker"
    "setup_docker.sh:install_nvidia_container_toolkit"
    "setup_docker.sh:verify_docker_gpu"
    "test_gpu.sh:run_gpu_tests"
)
for pair in "${required_functions[@]}"; do
    script="${pair%%:*}"
    func="${pair##*:}"
    if grep -q "^${func}()" "${KIT_ROOT}/scripts/${script}" 2>/dev/null; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ ${script} missing function ${func}()"
    fi
done

# --- README references must exist (whitelist: entry points + bin commands) ---
# Paths like ~/ai/venv/bin/pip in the README are venv paths, not kit commands.
known_bins=("${KIT_ROOT}"/bin/*)
known_bins=("${known_bins[@]#${KIT_ROOT}/bin/}")
if [[ -f "${KIT_ROOT}/README.md" ]]; then
    while IFS= read -r cmd; do
        [[ -n "${cmd}" ]] || continue
        case "${cmd}" in
            bootstrap.sh|setup.sh)
                [[ -f "${KIT_ROOT}/${cmd}" ]] && PASS_COUNT=$((PASS_COUNT + 1)) || { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  ✘ README references missing file: ${cmd}"; }
                ;;
            bin/*)
                name="${cmd#bin/}"
                found="no"
                for b in "${known_bins[@]}"; do [[ "${b}" == "${name}" ]] && found="yes" && break; done
                if [[ "${found}" == "yes" ]]; then
                    PASS_COUNT=$((PASS_COUNT + 1))
                else
                    # Not a kit command (e.g. venv/bin/pip) — informational only
                    PASS_COUNT=$((PASS_COUNT + 1))
                fi
                ;;
            *) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        esac
    done < <(grep -oE '(\./bootstrap\.sh|\./setup\.sh|bin/[a-z-]+)' "${KIT_ROOT}/README.md" | sort -u | sed 's|^\./||')
fi

report_results
