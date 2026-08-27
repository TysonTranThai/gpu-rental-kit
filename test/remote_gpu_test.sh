#!/usr/bin/env bash
# =============================================================================
# remote_gpu_test.sh — PART 4: remote GPU diagnostics (REAL, read-only)
# =============================================================================
# Connects to a rented Linux NVIDIA machine over SSH and runs read-only
# diagnostics (no installation, no file changes). Never hard-codes
# credentials; supports SSH key, ssh-agent, and ~/.ssh/config.
#
# Usage:
#   bash test/remote_gpu_test.sh --host IP [--port 22] [--user root]
#                                [--auth key|agent|config] [--key /path/key]
#   or with env vars: GPU_HOST GPU_PORT GPU_USER
#
# Output: test/results/remote-diagnostics-report.txt
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ssh_lib.sh
source "${TEST_ROOT}/ssh_lib.sh"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"

show_help() {
    cat <<'EOF'
remote_gpu_test.sh — REMOTE GPU DIAGNOSTICS (REAL, read-only, no install)

  Runs 26 checks on your rented GPU machine over SSH:
    Linux/CPU/RAM/disk/network, NVIDIA GPU, GPU count, VRAM, driver, CUDA,
    nvidia-smi, PyTorch CUDA, Docker, NVIDIA Container Toolkit, Docker GPU
    passthrough, Python, venv, Hugging Face, llama.cpp (+CUDA), Ollama,
    vLLM, model directories, storage, ports, live API endpoints.

  Usage:
    bash test/remote_gpu_test.sh --host 1.2.3.4 [--port 22] [--user root]
        [--auth key|agent|config] [--key ~/.ssh/id_ed25519]

  Connection:
    --host HOST     Target IP/hostname      (env: GPU_HOST)
    --port PORT     SSH port (default 22)   (env: GPU_PORT)
    --user USER     SSH user                (env: GPU_USER)
    --auth METHOD   key | agent | config    (default: agent)
    --key FILE      SSH private key (implies --auth key)
    --interactive   Allow password prompts (not recommended)

  Examples:
    GPU_HOST=1.2.3.4 GPU_USER=root bash test/remote_gpu_test.sh
    bash test/remote_gpu_test.sh --host 1.2.3.4 --user root --auth key --key ~/.ssh/gpu_key
    bash test/remote_gpu_test.sh --host 1.2.3.4 --auth config   # host in ~/.ssh/config

  Report: test/results/remote-diagnostics-report.txt
EOF
}

parse_status=0
ssh_parse_args "$@" || parse_status=$?
if [[ "${parse_status}" -eq 2 ]]; then show_help; exit 0; fi
if [[ "${parse_status}" -ne 0 ]]; then exit 1; fi

REPORT="${RESULTS_DIR}/remote-diagnostics-report.txt"
REPORT_FILE="${REPORT}"
report_init "remote_diagnostics"

if ! ssh_target_ok; then
    echo "  [SKIP] No GPU_HOST set — remote GPU test skipped (set GPU_HOST/GPU_PORT/GPU_USER or pass --host)."
    report_skip "remote diagnostics skipped — no SSH target configured"
    report_summary
    exit 0
fi

report_section "Remote GPU diagnostics (REAL)"
report_out "  Target: $(ssh_target) port ${REMOTE_PORT} (auth: ${REMOTE_AUTH})"
report_out ""

diag_script="${TEST_ROOT}/remote/diagnostics.sh"
tmpout="${RESULTS_DIR}/.remote-diag-output.txt"
if ! ssh_run_stdin "${diag_script}" > "${tmpout}" 2>&1; then
    cat "${tmpout}" >> "${REPORT}" || true
    report_fail "SSH connection or remote execution failed — see ${REPORT}"
    report_summary
    exit 1
fi

# Append remote output to the report and show it
cat "${tmpout}" | tee -a "${REPORT}"
r_pass="$(grep -c '^\[PASS\]' "${tmpout}" || true)"
r_fail="$(grep -c '^\[FAIL\]' "${tmpout}" || true)"
r_unk="$(grep -c '^\[UNKNOWN\]' "${tmpout}" || true)"
r_warn="$(grep -c '^\[WARN\]' "${tmpout}" || true)"

echo ""
report_out "  Remote results: ${r_pass} PASS, ${r_fail} FAIL, ${r_unk} UNKNOWN, ${r_warn} WARN"
if [[ "${r_fail}" -eq 0 ]]; then
    report_pass "all remote diagnostics passed (${r_pass} checks)"
else
    report_fail "${r_fail} remote diagnostics failed — see ${REPORT}"
fi
report_summary
echo ""
echo "  Report: ${REPORT}"
exit $([[ "${r_fail}" -eq 0 ]])
