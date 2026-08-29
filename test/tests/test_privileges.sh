#!/usr/bin/env bash
# =============================================================================
# test_privileges.sh — privilege abstraction regression (root / sudo)
# =============================================================================
# Field regression (v1.3.0 report): a minimal Ubuntu 22.04 GPU container runs
# as root with NO sudo and NO systemd. The old setup scripts hardcoded `sudo`
# and died with "sudo: command not found" (exit 127) at
# "Installing base utilities...".
#
# Scenarios (fully isolated PATH — mockbin only, so "sudo absent" is real):
#   resolve_sudo:     root -> "" | non-root+sudo -> "sudo" | non-root-no-sudo -> fail
#   setup_system.sh:  root runs apt directly; non-root wraps via sudo;
#                     non-root without sudo fails clearly
#   setup_docker.sh:  root + no sudo -> install paths exit 0 without sudo
#   setup_ollama.sh:  ensure_zstd root runs apt directly; non-root w/o sudo fails
# =============================================================================
TEST_NAME="privileges"
# shellcheck source=../helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

KIT_SCRIPTS="${KIT_ROOT}/scripts"
MOCKBIN="${TEST_TMP}/priv-mockbin"
mkdir -p "${MOCKBIN}"
export PRIV_APT_LOG="${TEST_TMP}/priv-apt.log"
: > "${PRIV_APT_LOG}"

# Make bash resolvable inside the isolated PATH (snippets + sourced scripts
# re-invoke bash). A symlink keeps the mockbin self-contained so the real
# /usr/bin can never leak into resolution.
ln -sf "$(command -v bash)" "${MOCKBIN}/bash"

# --- mock apt-get: logs calls; simulates zstd becoming available on install --
cat > "${MOCKBIN}/apt-get" <<'MOCK_APT'
#!/usr/bin/env bash
echo "APT $*" >> "${PRIV_APT_LOG}"
if [[ "$*" == *"install"*zstd* ]]; then
    printf '#!/usr/bin/env bash\nexit 0\n' > "${MOCK_ZSTD_PATH}"
    chmod +x "${MOCK_ZSTD_PATH}"
fi
exit 0
MOCK_APT
chmod +x "${MOCKBIN}/apt-get"

# --- mock id: uid from MOCK_UID (default 1000 = plain user) ------------------
cat > "${MOCKBIN}/id" <<'MOCK_ID'
#!/usr/bin/env bash
echo "${MOCK_UID:-1000}"
MOCK_ID
chmod +x "${MOCKBIN}/id"

# --- mock cat / dirname (needed by snippets + module-level source lines) -----
cat > "${MOCKBIN}/cat" <<'MOCK_CAT'
#!/usr/bin/env bash
for f in "$@"; do
    while IFS= read -r line || [[ -n "${line}" ]]; do
        printf '%s\n' "${line}"
    done < "${f}"
done
MOCK_CAT
chmod +x "${MOCKBIN}/cat"

cat > "${MOCKBIN}/dirname" <<'MOCK_DIRNAME'
#!/usr/bin/env bash
printf '%s\n' "${1%/*}"
MOCK_DIRNAME
chmod +x "${MOCKBIN}/dirname"

# --- mock sudo: logs wrapper calls, execs the real command -------------------
mock_sudo_on() {
    cat > "${MOCKBIN}/sudo" <<'MOCK_SUDO'
#!/usr/bin/env bash
echo "SUDO $*" >> "${PRIV_APT_LOG}"
exec "$@"
MOCK_SUDO
    chmod +x "${MOCKBIN}/sudo"
}
mock_sudo_off() {
    rm -f "${MOCKBIN}/sudo"
}
mock_sudo_off

# Run a snippet with FULLY isolated PATH (mockbin only) so that "sudo absent"
# is genuinely absent — the real /usr/bin/sudo can never be reached.
run_with_mock() {
    PATH="${MOCKBIN}" MOCK_UID="${MOCK_UID:-1000}" \
        PRIV_APT_LOG="${PRIV_APT_LOG}" MOCK_ZSTD_PATH="${MOCKBIN}/zstd" \
        bash -c "$1"
}

reset_log() { : > "${PRIV_APT_LOG}"; }

# =============================================================================
# resolve_sudo — unit behavior
# =============================================================================

result="$(MOCK_UID=0 run_with_mock 'source "'"$KIT_SCRIPTS"'/privileges.sh"; resolve_sudo')"
assert_eq "" "${result}" "root -> SUDO empty"

mock_sudo_on
result="$(MOCK_UID=1000 run_with_mock 'source "'"$KIT_SCRIPTS"'/privileges.sh"; resolve_sudo')"
mock_sudo_off
assert_eq "sudo" "${result}" "non-root + sudo -> SUDO=sudo"

result="$(MOCK_UID=1000 run_with_mock 'export _GPU_RENTAL_KIT_LOADED=1; source "'"$KIT_SCRIPTS"'/privileges.sh"; resolve_sudo' 2>&1; echo "rc=$?")"
assert_contains "${result}" "rc=1" "non-root without sudo -> rc=1"
assert_contains "${result}" "install -y sudo" "non-root without sudo -> actionable message"

# =============================================================================
# setup_system.sh — wiring (root + no sudo: the field failure)
# =============================================================================

reset_log
result="$(MOCK_UID=0 run_with_mock '
    export _GPU_RENTAL_KIT_LOADED=1
    source "'"$KIT_SCRIPTS"'/setup_system.sh"
    install_base_packages >/dev/null 2>&1
    echo "rc=$?"
    cat "'"$PRIV_APT_LOG"'"
')"
assert_contains "${result}" "rc=0" "root + no sudo: install_base_packages succeeds"
assert_contains "${result}" "APT update -qq" "root + no sudo: apt-get update ran directly"
assert_contains "${result}" "APT install -y -qq curl wget git" "root + no sudo: apt-get install ran directly"
if [[ "${result}" == *"SUDO "* ]]; then
    assert_eq "none" "found" "root + no sudo: sudo never invoked"
else
    assert_eq "none" "none" "root + no sudo: sudo never invoked"
fi

# --- non-root + sudo: privileged calls wrapped -------------------------------
reset_log
mock_sudo_on
result="$(MOCK_UID=1000 run_with_mock '
    export _GPU_RENTAL_KIT_LOADED=1
    source "'"$KIT_SCRIPTS"'/setup_system.sh"
    install_base_packages >/dev/null 2>&1
    echo "rc=$?"
    cat "'"$PRIV_APT_LOG"'"
')"
mock_sudo_off
assert_contains "${result}" "rc=0" "non-root + sudo: install_base_packages succeeds"
assert_contains "${result}" "SUDO apt-get update -qq" "non-root + sudo: update wrapped by sudo"
assert_contains "${result}" "SUDO apt-get install -y -qq curl wget git" "non-root + sudo: install wrapped by sudo"

# --- non-root + no sudo: fails clearly, apt untouched -------------------------
reset_log
result="$(MOCK_UID=1000 run_with_mock '
    export _GPU_RENTAL_KIT_LOADED=1
    source "'"$KIT_SCRIPTS"'/setup_system.sh"
    install_base_packages >/dev/null 2>&1
    echo "rc=$?"
')"
assert_contains "${result}" "rc=1" "non-root + no sudo: install_base_packages fails clearly"

result="$(MOCK_UID=1000 run_with_mock '
    export _GPU_RENTAL_KIT_LOADED=1
    source "'"$KIT_SCRIPTS"'/setup_system.sh"
    install_base_packages 2>&1 || true
')"
assert_contains "${result}" "sudo" "non-root + no sudo: error mentions sudo"
assert_contains "${result}" "apt-get install -y sudo" "non-root + no sudo: suggests fix"

# --- no package manager: package-manager error, not privilege error ----------
mv "${MOCKBIN}/apt-get" "${TEST_TMP}/apt-get.bak"
result="$(MOCK_UID=0 run_with_mock '
    export _GPU_RENTAL_KIT_LOADED=1
    source "'"$KIT_SCRIPTS"'/setup_system.sh"
    install_base_packages 2>&1
    echo "rc=$?"
')"
assert_contains "${result}" "No supported package manager" "no package manager -> package-manager error"
assert_contains "${result}" "rc=1" "no package manager -> fails"
mv "${TEST_TMP}/apt-get.bak" "${MOCKBIN}/apt-get"

# =============================================================================
# setup_docker.sh — root + no sudo: install paths exit 0 without sudo
# =============================================================================

reset_log
result="$(MOCK_UID=0 run_with_mock '
    export _GPU_RENTAL_KIT_LOADED=1
    export HAS_DOCKER=no
    export IS_DOCKER=no
    export HAS_NVIDIA_GPU=yes
    source "'"$KIT_SCRIPTS"'/setup_docker.sh"
    install_docker >/dev/null 2>&1
    echo "docker_rc=$?"
    install_nvidia_container_toolkit >/dev/null 2>&1
    echo "toolkit_rc=$?"
    cat "'"$PRIV_APT_LOG"'"
')"
assert_contains "${result}" "docker_rc=0" "setup_docker root + no sudo: install_docker exits 0"
assert_contains "${result}" "toolkit_rc=0" "setup_docker root + no sudo: toolkit path exits 0"
if [[ "${result}" == *"SUDO "* ]]; then
    assert_eq "none" "found" "setup_docker root + no sudo: sudo never invoked"
else
    assert_eq "none" "none" "setup_docker root + no sudo: sudo never invoked"
fi

# =============================================================================
# setup_ollama.sh — ensure_zstd root + no sudo (was: hardcoded sudo branch)
# =============================================================================

reset_log
result="$(MOCK_UID=0 run_with_mock '
    export _GPU_RENTAL_KIT_LOADED=1
    export MOCK_ZSTD_PATH="'"${MOCKBIN}"'/zstd"
    source "'"$KIT_SCRIPTS"'/setup_ollama.sh"
    ensure_zstd >/dev/null 2>&1
    echo "rc=$?"
    cat "'"$PRIV_APT_LOG"'"
')"
assert_contains "${result}" "rc=0" "setup_ollama root + no sudo: ensure_zstd succeeds"
assert_contains "${result}" "APT install" "setup_ollama root + no sudo: zstd installed via direct apt"
if [[ "${result}" == *"SUDO "* ]]; then
    assert_eq "none" "found" "setup_ollama root + no sudo: sudo never invoked"
else
    assert_eq "none" "none" "setup_ollama root + no sudo: sudo never invoked"
fi

# --- non-root + no sudo: zstd prerequisite fails clearly ----------------------
reset_log
rm -f "${MOCKBIN}/zstd"
result="$(MOCK_UID=1000 run_with_mock '
    export _GPU_RENTAL_KIT_LOADED=1
    source "'"$KIT_SCRIPTS"'/setup_ollama.sh"
    ensure_zstd >/dev/null 2>&1
    echo "rc=$?"
')"
assert_contains "${result}" "rc=1" "setup_ollama non-root + no sudo: ensure_zstd fails clearly"

report_results
