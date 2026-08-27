#!/usr/bin/env bash
# =============================================================================
# test_ollama_setup.sh — Ollama prerequisite and optional-failure behavior
# =============================================================================
TEST_NAME="ollama_setup"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

ensure_executable

MOCK_BIN="${TEST_TMP}/bin"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/apt-get" <<'MOCK_APT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MOCK_APT_LOG}"
if [[ "$*" == *"install"* ]]; then
    cat > "${MOCK_ZSTD_PATH}" <<'MOCK_ZSTD'
#!/usr/bin/env bash
exit 0
MOCK_ZSTD
    chmod +x "${MOCK_ZSTD_PATH}"
fi
exit 0
MOCK_APT
chmod +x "${MOCK_BIN}/apt-get"
cat > "${MOCK_BIN}/sudo" <<'MOCK_SUDO'
#!/usr/bin/env bash
exec "$@"
MOCK_SUDO
chmod +x "${MOCK_BIN}/sudo"
cat > "${MOCK_BIN}/zstd" <<'MOCK_ZSTD'
#!/usr/bin/env bash
exit 0
MOCK_ZSTD
chmod +x "${MOCK_BIN}/zstd"

# Missing zstd + successful apt install should be handled without requiring
# repeated installation when zstd is subsequently available.
result="$(
    export PATH="${MOCK_BIN}:/usr/bin:/bin"
    export MOCK_APT_LOG="${TEST_TMP}/apt.log"
    export MOCK_ZSTD_PATH="${MOCK_BIN}/zstd"
    source "${KIT_ROOT}/scripts/setup_ollama.sh"
    mv "${MOCK_BIN}/zstd" "${TEST_TMP}/zstd.saved"
    ensure_zstd >/dev/null
    ensure_zstd >/dev/null
    grep -c 'install.*zstd' "${MOCK_APT_LOG}"
)"
assert_eq "1" "${result##*$'\n'}" "zstd install is idempotent"

# Missing zstd with no supported package manager fails clearly.
result="$(
    mkdir -p "${TEST_TMP}/empty-path"
    export PATH="${TEST_TMP}/empty-path"
    source "${KIT_ROOT}/scripts/setup_ollama.sh"
    if ensure_zstd >/dev/null 2>&1; then echo success; else echo failure; fi
)"
assert_eq "failure" "${result##*$'\n'}" "missing zstd without package manager fails"

# An Ollama install failure is reported as optional and does not abort setup.
result="$(
    export PATH="${MOCK_BIN}:/usr/bin:/bin"
    export OLLAMA_INSTALLED=no
    source "${KIT_ROOT}/scripts/setup_ollama.sh"
    ensure_zstd() { return 1; }
    run_ollama_setup
    echo "${OLLAMA_STATUS}"
)"
assert_eq "FAILED / OPTIONAL" "${result##*$'\n'}" "Ollama failure is optional"

report_results
