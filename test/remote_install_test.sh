#!/usr/bin/env bash
# =============================================================================
# remote_install_test.sh — PART 5: automated remote install test (REAL)
# =============================================================================
# Connects to a rented Linux NVIDIA machine, uploads the current repository,
# runs ./bootstrap.sh --remote-gpu -y, captures ALL output and the exit code,
# then verifies the installed environment (dirs, binaries, llama.cpp, CUDA,
# runtimes). Does NOT download a large model.
#
# Usage:
#   bash test/remote_install_test.sh --host IP [--user root] [--port 22]
#                                    [--repo https://...] [--local-repo PATH]
#   or env: GPU_HOST GPU_PORT GPU_USER
#
# Output: test/results/remote-install-report.txt
# =============================================================================
set -Eeuo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "${TEST_ROOT}/.." && pwd)"
# shellcheck source=ssh_lib.sh
source "${TEST_ROOT}/ssh_lib.sh"
# shellcheck source=report_lib.sh
source "${TEST_ROOT}/report_lib.sh"

REPO_URL=""
LOCAL_REPO="${KIT_ROOT}"

show_help() {
    cat <<'EOF'
remote_install_test.sh — AUTOMATED REMOTE INSTALL TEST (REAL)

  Uploads this repository to a rented GPU machine and runs the full
  one-command bootstrap, then verifies the result. No large model downloads.

  Usage:
    bash test/remote_install_test.sh --host 1.2.3.4 [--user root] [--port 22]
        [--repo https://github.com/you/gpu-rental-kit.git]
        [--local-repo /path/to/gpu-rental-kit]

  Connection (same as remote_gpu_test.sh):
    --host HOST     Target IP/hostname      (env: GPU_HOST)
    --port PORT     SSH port (default 22)   (env: GPU_PORT)
    --user USER     SSH user                (env: GPU_USER)
    --auth METHOD   key | agent | config    (default: agent)
    --key FILE      SSH private key (implies --auth key)

  Repo source (default: this local repository is uploaded via scp):
    --repo URL          git clone URL instead of uploading
    --local-repo PATH   upload a different local copy

  What happens:
    1. Upload/clone the repo to /tmp/grk-kit on the remote
    2. Run: ./bootstrap.sh --remote-gpu -y   (ALL output + exit code captured)
    3. Wait for services, then run gpu-status, gpu-test, ai-info
    4. Run the post-install verification suite
    5. Write test/results/remote-install-report.txt

  Report: test/results/remote-install-report.txt
EOF
}

# --- arg parsing: strip repo args, pass the rest to ssh_parse_args ----------
REPO_URL=""; LOCAL_REPO="${KIT_ROOT}"
clean_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) REPO_URL="$2"; shift 2 ;;
        --local-repo) LOCAL_REPO="$2"; shift 2 ;;
        *) clean_args+=("$1"); shift ;;
    esac
done
set -- "${clean_args[@]}"
parse_status=0
ssh_parse_args "$@" || parse_status=$?
if [[ "${parse_status}" -eq 2 ]]; then show_help; exit 0; fi
if [[ "${parse_status}" -ne 0 ]]; then exit 1; fi

REPORT="${RESULTS_DIR}/remote-install-report.txt"
REPORT_FILE="${REPORT}"
report_init "remote_install"

if ! ssh_target_ok; then
    echo "  [SKIP] No GPU_HOST set — remote install test skipped (set GPU_HOST/GPU_PORT/GPU_USER or pass --host)."
    report_skip "remote install skipped — no SSH target configured"
    report_summary
    exit 0
fi

report_section "Remote install test (REAL)"
report_out "  Target: $(ssh_target) port ${REMOTE_PORT}"
report_out "  Repo:   ${REPO_URL:-${LOCAL_REPO} (local upload)}"

REMOTE_DIR="/tmp/grk-kit"

# --- 1. Upload or clone ------------------------------------------------------
report_section "Step 1: deliver repository"
if [[ -n "${REPO_URL}" ]]; then
    if ssh_run "rm -rf ${REMOTE_DIR} && git clone --depth 1 ${REPO_URL} ${REMOTE_DIR}"; then
        report_pass "git clone ${REPO_URL}"
    else
        report_fail "git clone failed"
        report_summary
        exit 1
    fi
else
    if [[ ! -d "${LOCAL_REPO}/bootstrap.sh" ]] && [[ ! -f "${LOCAL_REPO}/bootstrap.sh" ]]; then
        report_fail "local repo not found: ${LOCAL_REPO}"
        report_summary
        exit 1
    fi
    upload_tmp="$(mktemp -d "${TMPDIR:-/tmp}/grk-upload.XXXXXX")"
    cp -R "${LOCAL_REPO}" "${upload_tmp}/grk-kit"
    rm -rf "${upload_tmp}/grk-kit/.git" "${upload_tmp}/grk-kit/test/results"
    # scp the upload dir
    cargs=(-o "BatchMode=${SSH_BATCH}" -o "ConnectTimeout=15")
    [[ -n "${REMOTE_PORT}" ]] && cargs+=(-P "${REMOTE_PORT}")
    [[ "${REMOTE_AUTH}" == "key" ]] && cargs+=(-i "${REMOTE_KEY}")
    if ssh_run "rm -rf ${REMOTE_DIR}" && scp "${cargs[@]}" -r "${upload_tmp}/grk-kit" "$(ssh_target):/tmp/grk-kit"; then
        report_pass "uploaded local repo (${LOCAL_REPO})"
    else
        report_fail "scp upload failed"
        rm -rf "${upload_tmp}"
        report_summary
        exit 1
    fi
    rm -rf "${upload_tmp}"
fi

# --- 2. Run bootstrap --------------------------------------------------------
report_section "Step 2: ./bootstrap.sh --remote-gpu -y"
boot_out="${RESULTS_DIR}/.remote-bootstrap-output.txt"
boot_status=0
ssh_run "cd ${REMOTE_DIR} && ./bootstrap.sh --remote-gpu -y" > "${boot_out}" 2>&1 || boot_status=$?
report_out "  bootstrap exit code: ${boot_status}"
report_out "  (full output: ${boot_out})"
# Summarize key lines
grep -E '\[(OK|ERROR|WARN|INFO)\]|SETUP (COMPLETE|FAILED)|Profile|Storage|GPU:' "${boot_out}" | head -40 | sed 's/^/    /' >> "${REPORT}" || true

if [[ "${boot_status}" -ne 0 ]]; then
    report_fail "bootstrap.sh --remote-gpu exited ${boot_status} — see ${boot_out}"
    report_summary
    exit 1
fi
report_pass "bootstrap.sh --remote-gpu exited 0"

# --- 3. Wait + command smoke -------------------------------------------------
report_section "Step 3: service warm-up + command smoke"
sleep 5
for cmd in "gpu-status" "gpu-test" "ai-info"; do
    out="$(ssh_run "cd ${REMOTE_DIR} && ${cmd} 2>&1 | head -30" || true)"
    echo "" >> "${REPORT}"
    echo "  --- ${cmd} (remote) ---" >> "${REPORT}"
    echo "${out}" | sed 's/^/    /' >> "${REPORT}"
    if [[ -n "${out}" ]]; then
        report_pass "${cmd} produced output"
    else
        report_fail "${cmd} produced no output"
    fi
done

# --- 4. Post-install verification suite --------------------------------------
report_section "Step 4: post-install verification (REAL)"
check_out="${RESULTS_DIR}/.remote-install-check.txt"
if ssh_run_stdin "${TEST_ROOT}/remote/install_check.sh" > "${check_out}" 2>&1; then
    cat "${check_out}" | tee -a "${REPORT}"
    c_pass="$(grep -c '^\[PASS\]' "${check_out}" || true)"
    c_fail="$(grep -c '^\[FAIL\]' "${check_out}" || true)"
    c_unk="$(grep -c '^\[UNKNOWN\]' "${check_out}" || true)"
    report_out "  Verification: ${c_pass} PASS, ${c_fail} FAIL, ${c_unk} UNKNOWN"
    if [[ "${c_fail}" -eq 0 ]]; then
        report_pass "post-install verification clean"
    else
        report_fail "${c_fail} post-install verification failures"
    fi
else
    report_fail "post-install verification script failed to run"
fi

report_section "Summary"
report_summary
echo ""
echo "  Report: ${REPORT}"
exit $([[ "${boot_status}" -eq 0 ]])
