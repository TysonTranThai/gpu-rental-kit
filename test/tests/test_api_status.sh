#!/usr/bin/env bash
# =============================================================================
# test_api_status.sh — bash api-status client command (tunnel checker)
# =============================================================================
# Fully mocked: no network, no tunnel, no GPU. Verifies:
#   1. exists/executable, bash -n clean, --help works
#   2. --port without a number fails honestly
#   3. listening port + JSON response → [OK], exit 0, model count shown
#   4. listening port + silent curl → [DOWN], exit 1
#   5. nothing listening → honest [DOWN] with tunnel hint, exit 1
#   6. Windows twin exists and checks the SAME default ports
# =============================================================================
TEST_NAME="api-status"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/helpers.sh"

API_STATUS="${KIT_ROOT}/bin/api-status"
assert_ok "api-status exists" test -f "${API_STATUS}"
assert_ok "api-status is executable" test -x "${API_STATUS}"
assert_ok "api-status passes bash -n" bash -n "${API_STATUS}"

help_out="$(bash "${API_STATUS}" -h 2>&1)"
assert_contains "${help_out}" "--port" "help documents --port"
assert_contains "${help_out}" "SSH tunnel" "help explains the tunnel prerequisite"

# bad flag usage fails honestly
bad_code=0
bash "${API_STATUS}" --port abc >/dev/null 2>&1 || bad_code=$?
assert_eq "1" "${bad_code}" "--port with a non-number fails"

# ── mocked environments ──
MOCKBIN="$(mktemp -d)"
SANDBOX="$(mktemp -d)"
for helper in grep wc tr cat sed lsof; do
    if command -v "${helper}" >/dev/null 2>&1; then
        ln -sf "$(command -v "${helper}")" "${MOCKBIN}/${helper}"
    fi
done

# lsof mock: 8080 and 8000 listen, everything else closed
cat > "${MOCKBIN}/lsof.new" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *:8080*|*:8000*) exit 0 ;;
    *) exit 1 ;;
esac
EOF
chmod +x "${MOCKBIN}/lsof.new" && mv -f "${MOCKBIN}/lsof.new" "${MOCKBIN}/lsof"

# curl mock: answers on 8080, silent failure on 8000 (service behind tunnel dead)
cat > "${MOCKBIN}/curl.new" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *127.0.0.1:8080*) echo '{"object":"list","data":[{"id":"llama-3-8b"},{"id":"qwen-2.5"}]}' ;;
    *) exit 7 ;;
esac
EOF
chmod +x "${MOCKBIN}/curl.new" && mv -f "${MOCKBIN}/curl.new" "${MOCKBIN}/curl"

run_mocked() { PATH="${MOCKBIN}:${PATH}" bash "${API_STATUS}" "$@" 2>&1; }

ok_out="$(run_mocked || true)"
assert_contains "${ok_out}" "[OK]" "listening port with JSON response reports OK"
assert_contains "${ok_out}" "2 model(s)" "model count is derived from the response"
assert_contains "${ok_out}" "127.0.0.1:8080/v1" "OK line shows the endpoint"

# single-port mode still works
one_out="$(run_mocked --port 8000 || true)"
assert_contains "${one_out}" "[DOWN]" "port 8000 without HTTP answers honestly DOWN"
one_code=0
run_mocked --port 8000 >/dev/null 2>&1 || one_code=$?
assert_eq "1" "${one_code}" "DOWN on the only port → exit 1"

ok_code=0
run_mocked >/dev/null 2>&1 || ok_code=$?
assert_eq "0" "${ok_code}" "one reachable API → exit 0"

# closed ports: honest DOWN + tunnel hint
closed_out="$(run_mocked --port 9999 || true)"
assert_contains "${closed_out}" "nothing is listening" "closed port is reported honestly"
assert_contains "${closed_out}" "ssh -N -L 9999" "closed port shows the tunnel command"
closed_code=0
run_mocked --port 9999 >/dev/null 2>&1 || closed_code=$?
assert_eq "1" "${closed_code}" "all ports closed → exit 1"

# ── Windows twin parity: same default ports ──
ps1="${KIT_ROOT}/bin/api-status.ps1"
assert_ok "Windows twin exists" test -f "${ps1}"
assert_contains "$(cat "${ps1}")" "8080" "twin knows llama.cpp default port"
assert_contains "$(cat "${ps1}")" "8000" "twin knows vLLM default port"
assert_contains "$(cat "${ps1}")" "v1/models" "twin probes the same endpoint"

rm -rf "${MOCKBIN}" "${SANDBOX}"
report_results
