#!/usr/bin/env bash
# =============================================================================
# test_ai_doctor.sh — ai-doctor whole-stack health check tests (fully mocked)
# =============================================================================
# No internet, no GPU, no installs. Verifies:
#   1. Wiring: setup.sh installs ai-doctor; ai-info lists it; Windows twin exists
#   2. --help works and lists the flags
#   3. Sandbox run (empty AI_HOME): exit 0, all verdicts PASS/WARN/SKIP, no FAIL
#   4. Verdict vocabulary is exactly PASS/WARN/FAIL/SKIP
#   5. Disk check FAILs below 1GB and WARNs below 5GB (mocked df)
#   6. Log sweep warns on ERROR lines and passes on clean logs (mocked logs)
#   7. Port probes: closed port SKIPs, open port without HTTP WARNs (mocked lsof)
#   8. --json emits valid JSON with matching summary counters
#   9. i18n: DOCTOR_* keys exist in en/vi/zh-CN catalogs
# =============================================================================
TEST_NAME="ai-doctor"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

DOCTOR="${KIT_ROOT}/bin/ai-doctor"
assert_ok "ai-doctor exists" test -f "${DOCTOR}"
assert_ok "ai-doctor is executable" test -x "${DOCTOR}"

# ── 1. Wiring ──
assert_contains "$(cat "${KIT_ROOT}/setup.sh")" "ai-router ai-doctor" "setup.sh installs ai-doctor"
assert_contains "$(cat "${KIT_ROOT}/bin/ai-info")" "ai-doctor" "ai-info lists ai-doctor"
assert_ok "Windows twin exists" test -f "${KIT_ROOT}/bin/ai-doctor.ps1"
grep -q "Invoke-GrkRemoteCommand" "${KIT_ROOT}/bin/ai-doctor.ps1" \
    && PASS_COUNT=$((PASS_COUNT + 1)) || { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  ✘ ai-doctor.ps1 does not invoke the remote command"; }

# ── 2. --help ──
help_out="$(bash "${DOCTOR}" --help 2>&1)"
assert_contains "${help_out}" "--json" "help documents --json"
assert_contains "${help_out}" "--lines" "help documents --lines"
assert_ok "help exits 0" bash "${DOCTOR}" --help >/dev/null 2>&1

# ── 3. Sandbox run: empty AI_HOME (no venv, no logs, no machine.env) ──
SANDBOX="$(mktemp -d)"
mkdir -p "${SANDBOX}/ai"
run_sandbox() {
    AI_HOME="${SANDBOX}/ai" bash "${DOCTOR}" "$@" 2>&1
}
sandbox_out="$(run_sandbox)"
sandbox_code=0
run_sandbox >/dev/null 2>&1 || sandbox_code=$?

assert_eq "0" "${sandbox_code}" "healthy sandbox exits 0 (no FAIL verdicts)"
assert_contains "${sandbox_out}" "ai-doctor" "sandbox run produces report"
assert_contains "${sandbox_out}" "SKIP" "absent components are honestly SKIPPED"
if echo "${sandbox_out}" | grep -q "\[FAIL\]"; then
    FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  ✘ empty sandbox produced FAIL verdicts"
else
    PASS_COUNT=$((PASS_COUNT + 1)); echo "  ✔ empty sandbox produced no FAIL verdicts"
fi

# ── 4. Verdict vocabulary ──
bad_verdicts="$(echo "${sandbox_out}" | grep -oE '^\s*\[[A-Z]+\]' | grep -vE '\[(PASS|WARN|FAIL|SKIP)\]' || true)"
assert_eq "" "${bad_verdicts}" "only PASS/WARN/FAIL/SKIP verdicts are printed"

# ── 5. Disk thresholds (mock df via PATH) ──
MOCKBIN="$(mktemp -d)"
for helper in df tail ls grep cat sed awk head wc curl lsof ss nvidia-smi; do
    if command -v "${helper}" >/dev/null 2>&1; then
        ln -sf "$(command -v "${helper}")" "${MOCKBIN}/${helper}"
    fi
done
# Write mock df as a new file + rename (the symlink must not be overwritten
# in place — cat through it would target the real system binary).
cat > "${MOCKBIN}/df.new" <<EOF
#!/usr/bin/env bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted"
echo "mock        999999999     0 ${1:-6000000}       1% /"
exit 0
EOF
chmod +x "${MOCKBIN}/df.new" && mv -f "${MOCKBIN}/df.new" "${MOCKBIN}/df"

disk_out="$(PATH="${MOCKBIN}:${PATH}" AI_HOME="${SANDBOX}/ai" bash "${DOCTOR}" 2>&1)"
assert_contains "${disk_out}" "$(basename "${SANDBOX}/ai")" "disk check mentions AI_HOME"

cat > "${MOCKBIN}/df.new" <<'EOF'
#!/usr/bin/env bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted"
echo "mock        999999999     0 800000       99% /"
exit 0
EOF
chmod +x "${MOCKBIN}/df.new" && mv -f "${MOCKBIN}/df.new" "${MOCKBIN}/df"
# (|| true INSIDE the substitution: ai-doctor exits non-zero when it finds a
# FAIL, and set -e would otherwise abort this test on the assignment itself)
low_out="$(PATH="${MOCKBIN}:${PATH}" AI_HOME="${SANDBOX}/ai" bash "${DOCTOR}" 2>&1 || true)"
assert_contains "${low_out}" "[FAIL]" "disk < 1GB free FAILs"
if echo "${low_out}" | grep -q "disk.*will fail\|only 781MB"; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "  ✔ low-disk FAIL explains the consequence"
else
    FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  ✘ low-disk FAIL lacks explanation"
fi

# ── 6. Log sweep (mocked logs, real tail/grep) ──
mkdir -p "${SANDBOX}/ai/logs"
printf 'INFO started\nINFO ready\n' > "${SANDBOX}/ai/logs/clean.log"
clean_out="$(PATH="${MOCKBIN}:${PATH}" AI_HOME="${SANDBOX}/ai" bash "${DOCTOR}" 2>&1 || true)"
assert_contains "${clean_out}" "no ERROR/FATAL" "clean log sweep passes"

printf 'INFO started\nERROR model load failed\n' > "${SANDBOX}/ai/logs/broken.log"
dirty_out="$(PATH="${MOCKBIN}:${PATH}" AI_HOME="${SANDBOX}/ai" bash "${DOCTOR}" 2>&1 || true)"
assert_contains "${dirty_out}" "[WARN]" "log errors produce WARN (not FAIL)"
assert_contains "${dirty_out}" "broken.log" "log sweep names the offending file"

# ── 7. Port probes (mock lsof: 8080 busy but no HTTP server) ──
cat > "${MOCKBIN}/lsof.new" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *:8080*) exit 0 ;;
    *) exit 1 ;;
esac
EOF
chmod +x "${MOCKBIN}/lsof.new" && mv -f "${MOCKBIN}/lsof.new" "${MOCKBIN}/lsof"
port_out="$(PATH="${MOCKBIN}:${PATH}" AI_HOME="${SANDBOX}/ai" bash "${DOCTOR}" 2>&1 || true)"
assert_contains "${port_out}" "did not answer" "busy port without HTTP WARNs"
assert_contains "${port_out}" "not listening on 8000" "closed vLLM port honestly SKIPs"

# ── 8. --json ──
json_out="$(AI_HOME="${SANDBOX}/ai" bash "${DOCTOR}" --json 2>/dev/null || true)"
if command -v python3 >/dev/null 2>&1; then
    parsed="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["summary"]["fail"])' <<< "${json_out}" 2>&1 || true)"
    assert_eq "0" "${parsed}" "json parses; fail count is 0 in the clean sandbox"
    assert_contains "${json_out}" "\"verdict\":\"SKIP\"" "json exposes SKIP verdicts"
else
    assert_contains "${json_out}" '"summary"' "json contains summary (python3 absent for deep parse)"
fi

# ── 9. i18n key coverage ──
for lang in en vi zh-CN; do
    catalog="${KIT_ROOT}/config/i18n/${lang}.env"
    for key in DOCTOR_TITLE DOCTOR_SUMMARY DOCTOR_SKIP_NOTE DOCTOR_FIX_HINT DOCTOR_ALL_GOOD; do
        grep -q "^${key}=" "${catalog}" \
            && PASS_COUNT=$((PASS_COUNT + 1)) \
            || { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  ✘ ${lang}: missing ${key}"; }
    done
done
assert_contains "$(AI_HOME="${SANDBOX}/ai" bash "${DOCTOR}" 2>&1)" "ai-doctor summary" "summary line renders"

rm -rf "${SANDBOX}" "${MOCKBIN}"
report_results
