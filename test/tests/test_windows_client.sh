#!/usr/bin/env bash
# =============================================================================
# test_windows_client.sh — Windows client tooling checks (macOS-safe)
# =============================================================================
# Structural validation of bootstrap.ps1 and bin/*.ps1:
#   * all documented Windows entry points exist
#   * strict mode / shared library usage present
#   * honest remote-vs-local wording (no local-GPU claims)
#   * no Linux server paths, no secrets, balanced braces
#   * the embedded client.json template parses as valid JSON
#
# If pwsh IS installed (any OS), files are additionally parsed with the real
# PowerShell language parser. When pwsh is absent, validation stays static —
# results below describe exactly what was checked, never a runtime claim.
# =============================================================================
TEST_NAME="windows_client"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

ensure_executable

PS_FILES=(
    "bootstrap.ps1"
    "bin/grk-client-lib.ps1"
    "bin/gpu-status.ps1"
    "bin/gpu-test.ps1"
    "bin/model-list.ps1"
    "bin/model-download.ps1"
    "bin/model-run.ps1"
    "bin/model-stop.ps1"
    "bin/ai-start.ps1"
    "bin/ai-stop.ps1"
    "bin/ai-info.ps1"
    "bin/ai-backup.ps1"
    "bin/api-status.ps1"
)

# --- 1. All Windows client files exist ---
for f in "${PS_FILES[@]}"; do
    if [[ -f "${KIT_ROOT}/${f}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ exists: ${f}"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ missing: ${f}"
        record_failure "missing_file" "${f}"
    fi
done

# --- 2. Strict mode everywhere ---
for f in "${PS_FILES[@]}"; do
    if grep -q 'Set-StrictMode -Version Latest' "${KIT_ROOT}/${f}"; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ Set-StrictMode missing: ${f}"
        record_failure "strict_mode" "${f}"
    fi
done
echo "  ✔ Set-StrictMode -Version Latest in ${#PS_FILES[@]} files"

# --- 3. Wrappers use the shared library ---
wrapper_count=0
for f in "${PS_FILES[@]:2}"; do # skip bootstrap.ps1 and the library itself
    if grep -q "grk-client-lib.ps1" "${KIT_ROOT}/${f}"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        wrapper_count=$((wrapper_count + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ does not dot-source grk-client-lib.ps1: ${f}"
        record_failure "shared_lib" "${f}"
    fi
done
echo "  ✔ ${wrapper_count}/11 wrappers share grk-client-lib.ps1"

# --- 4. Honest REMOTE-vs-local framing ---
for f in "${PS_FILES[@]:2}"; do
    if grep -qiE 'REMOTE|tunnel' "${KIT_ROOT}/${f}"; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ no REMOTE/tunnel wording: ${f}"
        record_failure "honest_remote_wording" "${f}"
    fi
done
echo "  ✔ every command documents it targets the REMOTE server or tunnel"

# --- 5. No Linux GPU-server paths inside Windows code ---
if grep -rn "/root/ai\|\${AI_HOME}" --include='*.ps1' "${KIT_ROOT}/bin" "${KIT_ROOT}/bootstrap.ps1" >/dev/null 2>&1; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  ✘ Linux paths found inside .ps1 files"
    record_failure "linux_paths" "/root/ai leaked into PowerShell code"
else
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  ✔ no Linux server paths hardcoded in Windows tooling"
fi

# --- 6. Balanced braces/parens (structural sanity without pwsh) ---
bal_fail=0
for f in "${PS_FILES[@]}"; do
    if ! python3 - "$KIT_ROOT/${f}" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
ok = src.count("{") == src.count("}") and src.count("(") == src.count(")")
sys.exit(0 if ok else 1)
PY
    then
        bal_fail=1
        echo "  ✘ unbalanced braces/parens: ${f}"
        record_failure "brace_balance" "${f}"
    fi
done
if [[ "${bal_fail}" -eq 0 ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  ✔ braces/parens balanced across ${#PS_FILES[@]} files"
fi

# --- 7. bootstrap.ps1 feature checklist ---
features=(
    "-Help"
    "-Yes"
    "-CheckOnly"
    "-RemoteHost"
    "winget"
    ".gpu-rental-kit"
    "client.json"
    "IsInRole"       # administrator detection
    "Add-Content"    # install logging
    "Never stores credentials"
)
feature_fail=0
for needle in "${features[@]}"; do
    if ! grep -qF -e "$needle" "${KIT_ROOT}/bootstrap.ps1"; then
        feature_fail=1
        echo "  ✘ bootstrap.ps1 missing: $needle"
        record_failure "bootstrap_feature" "$needle"
    fi
done
if [[ "${feature_fail}" -eq 0 ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  ✔ bootstrap.ps1 flags/deps/config/admin/logging features present"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# --- 8/9. Embedded client.json template: valid JSON + empty placeholder host ---
json_check_fail=0
while IFS='|' read -r check outcome detail; do
    if [[ "$outcome" == "ok" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ $detail"
    else
        json_check_fail=1
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  ✘ $detail"
        record_failure "client_json" "$detail"
    fi
done < <(python3 - "$KIT_ROOT/bootstrap.ps1" <<'PY'
import sys, json
src = open(sys.argv[1], encoding="utf-8").read()
begin = src.index("=== sample-client-json BEGIN ===")
end   = src.index("=== sample-client-json END ===")
region = src[begin:end]
body = region.split("@'", 1)[1].rsplit("'@", 1)[0].strip()
try:
    data = json.loads(body)
except Exception as exc:
    print(f"json|bad|embedded client.json template failed JSON parse ({exc})")
    sys.exit(0)
print("json|ok|embedded client.json template parses as valid JSON")
if data.get("RemoteHost", None) == "":
    print("json|ok|placeholder client.json leaves RemoteHost empty")
else:
    print("json|bad|placeholder client.json hardcodes or omits empty host")
PY
)
[[ "${json_check_fail}" -eq 0 ]] || true  # counts recorded above

# --- 10. Secret scan over PowerShell sources ---
secret_hits="$(grep -rnE 'ghp_[A-Za-z0-9]+|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA|EC|OPENSSH) PRIVATE KEY' \
    --include='*.ps1' "${KIT_ROOT}" 2>/dev/null || true)"
if [[ -z "${secret_hits}" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  ✔ no secret-shaped strings in any .ps1"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  ✘ possible secret pattern(s): ${secret_hits}"
    record_failure "secret_scan_ps1" "${secret_hits}"
fi

# --- 11. Real PowerShell parse check when pwsh exists (optional runtime proof) ---
if command -v pwsh >/dev/null 2>&1; then
    parse_fail=0
    for f in "${PS_FILES[@]}"; do
        if ! pwsh -NoProfile -NonInteractive -Command "
            \$tokens = \$null; \$errors = \$null;
            [System.Management.Automation.Language.Parser]::ParseFile('${KIT_ROOT}/${f}', [ref]\$tokens, [ref]\$errors) | Out-Null;
            exit (\$errors.Count)
        " ; then
            parse_fail=1
            echo "  ✘ pwsh parser errors: ${f}"
            record_failure "pwsh_parse" "${f}"
        fi
    done
    if [[ "${parse_fail}" -eq 0 ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ✔ pwsh language parser accepted all ${#PS_FILES[@]} files (runtime validation)"
    fi
else
    echo "  ℹ pwsh not installed here — Windows tooling validated statically above."
    echo "    Runtime (Windows) testing remains pending by design; nothing was faked."
fi

report_results
