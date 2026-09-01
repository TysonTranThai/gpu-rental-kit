#!/usr/bin/env bash
# =============================================================================
# ACCEPTANCE-RUNBOOK-GPU-SERVER.sh
# =============================================================================
# Paste-ready end-to-end acceptance test for gpu-rental-kit on a REAL Linux
# NVIDIA GPU server. Covers acceptance spec sections 1, 4-32.
#
# This file was NOT executed where it was authored: the dev machine is a
# macOS M4 box with no NVIDIA GPU, no nvidia-smi, no systemd. bootstrap.sh
# refuses to install on Darwin (platform guard in setup.sh). So sections
# requiring a GPU (4-32) are packaged here as a runbook to run on the real
# rented box.
#
# USAGE on the rented GPU server (as root or passwordless-sudo user):
#   cd gpu-rental-kit
#   bash test/ACCEPTANCE-RUNBOOK-GPU-SERVER.sh            # full matrix
#   bash test/ACCEPTANCE-RUNBOOK-GPU-SERVER.sh --lang vi # start at §6
#
# It does NOT modify source. It only runs the installer + verification curls.
# A real human must eyeball each step's output against the PASS/FAIL matrix.
# =============================================================================
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
RESULTS_DIR="${ROOT}/test/results/acceptance"
mkdir -p "${RESULTS_DIR}"
LOG="${RESULTS_DIR}/acceptance-$(date '+%Y%m%d-%H%M%S').log"
exec > >(tee -a "${LOG}") 2>&1
TRAP_MSG=""
pass() { echo "  [PASS] $*"; }
fail() { echo "  [FAIL] $*"; TRAP_MSG="${TRAP_MSG}$* | "; }
skip() { echo "  [SKIP] $*"; }
note() { echo "  [NOTE] $*"; }

echo "══════════════════════════════════════════════════════════════"
echo "  GPU RENTAL KIT — REAL GPU SERVER ACCEPTANCE TEST"
echo "  Started: $(date)"
echo "══════════════════════════════════════════════════════════════"

# ── §1. FRESH STATE / MACHINE INSPECT ──────────────────────────────────────
echo ""
echo "── §1. MACHINE CONFIGURATION ──"
echo "  OS:       $(uname -s) $(uname -r)"
echo "  Kernel:   $(uname -r)"
echo "  CPU:      $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
echo "  CPU cores: $(nproc)"
echo "  RAM:      $(awk '/MemTotal/{printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"
echo "  Disk:     $(df -h / | tail -1 | awk '{print $2" total, "$4" avail"}')"
echo "  Container: $([ -f /.dockerenv ] && echo yes || echo no)"
echo "  VM:       $(systemd-detect-virt 2>/dev/null || echo unknown)"
echo "  User:     $(id -un) (uid $(id -u))"
# sudo check without invoking the wrapper in non-interactive shells:
if [ "$(id -u)" -eq 0 ]; then echo "  Privilege: root"; else
  command -v sudo >/dev/null 2>&1 && echo "  Privilege: non-root, sudo binary present (will prompt)" \
    || { echo "  Privilege: non-root, NO sudo — install/privileged steps will fail"; }
fi
echo "  systemd:  $([ -d /run/systemd/system ] && echo present || echo absent)"
echo "  NVIDIA driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo MISSING)"
echo "  CUDA:     $(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 || echo MISSING)"
echo "  GPU count: $(nvidia-smi -L 2>/dev/null | wc -l)"
echo "  GPUs:"
nvidia-smi --query-gpu=index,name,memory.total,compute_cap --format=csv,noheader 2>/dev/null | sed 's/^/    /' || echo "    (nvidia-smi unavailable)"
echo "  GPU topology:"
nvidia-smi topo -m 2>/dev/null | sed 's/^/    /' || echo "    (n/a)"
echo ""
echo "  Existing ~/ai install?"
[ -d ~/ai ] && ls -la ~/ai | head -8 || echo "    no ~/ai (fresh)"
note "Do NOT destroy existing user data. If ~/ai exists, preserve and test alongside."

# ── §2. REPOSITORY VERSION ───────────────────────────────────────────────────
echo ""
echo "── §2. REPOSITORY VERSION ──"
echo "  remote: $(git remote get-url origin 2>/dev/null)"
echo "  branch: $(git branch --show-current 2>/dev/null)"
echo "  HEAD:   $(git log -1 --oneline 2>/dev/null)"
echo "  origin/main: $(git log -1 --oneline origin/main 2>/dev/null)"
echo "  working tree clean? $([ -z "$(git status -s)" ] && echo yes || echo "NO — uncommitted changes:")"
git status -s | sed 's/^/    /' | head
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main 2>/dev/null)" ] && pass "on origin/main HEAD" || fail "HEAD != origin/main"

# ── §3. BASE TEST SUITE (the only section that runs on macOS — re-run here too) ─
echo ""
echo "── §3. BASE TEST SUITE ──"
echo "  3a bash -n:"
sc=0; while IFS= read -r f; do bash -n "$f" 2>/dev/null || { echo "    FAIL: $f"; sc=1; }; done \
  < <(find . -type f -name '*.sh' -not -path './.git/*')
[ $sc -eq 0 ] && pass "all .sh syntax OK" || fail "syntax errors above"
echo "  3b shellcheck:"
if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r f; do shellcheck -x -S error "$f" 2>&1 | head -8; done \
    < <(find . -type f \( -name '*.sh' -o -path '*/bin/*' \) -not -path './.git/*')
  pass "shellcheck $(shellcheck --version | awk '/^version/{print $2}') ran"
else fail "shellcheck not installed"; fi
echo "  3c local suite:"
bash test/run_tests.sh >/tmp/grk_full.log 2>&1 && pass "run_tests.sh exit 0" || fail "run_tests.sh exit $?"
grep -E 'Total:|All local tests' /tmp/grk_full.log | sed 's/^/    /'
echo "  3d mock GPU:"
bash test/run_tests.sh gpu 2>&1 | grep -E 'Total:|All local' | sed 's/^/    /'
echo "  3e language tests:"
bash test/tests/test_i18n_selector.sh >/dev/null 2>&1 && pass "i18n selector" || fail "i18n selector"
bash test/tests/test_localization.sh >/dev/null 2>&1 && pass "localization" || fail "localization"
echo "  3f secret scan:"
rg -n -i -E '(api[_-]?key|secret|password|token|bearer)\s*[:=]\s*[A-Za-z0-9+/=]{12,}' \
  --type sh -g '!test/**' -g '!.git/**' . 2>/dev/null | grep -viE 'example|YOUR_|<|>' | head -5 \
  && fail "literal credential assignments found" || pass "no literal credentials"
rg -nE '-----BEGIN (RSA|OPENSSH|EC|DSA|ED25519) PRIVATE KEY-----' . 2>/dev/null | head \
  && fail "private key material in tree" || pass "no private keys"
echo "  3g idempotency:"
bash test/tests/test_idempotency.sh >/dev/null 2>&1 && pass "idempotency" || fail "idempotency"

# ── §4-7. LANGUAGE SELECTOR + en/vi/zh-CN ─────────────────────────────────────
echo ""
echo "── §4-7. LANGUAGE SELECTOR (interactive — human selects) ──"
note "Run: ./bootstrap.sh --remote-gpu  (then pick Vietnamese in the selector)"
note "Verify 🇬🇧/🇻🇳/🇨🇳 render (NOT \\U0001F escape sequences)."
note "Then repeat with: --lang en | --lang vi | --lang zh-CN"
note "Confirm installer prompts/warnings/summary are localized, no major English remains."

# ── §8-9. ENV + GPU DETECTION ───────────────────────────────────────────────
echo ""
echo "── §8-9. ENVIRONMENT + GPU DETECTION ──"
echo "  8: bootstrap.sh prints root/sudo/container/systemd/CPU/RAM/network — verify no false claims."
echo "  9 GPUs (expected: RTX 3060 Ti 8GB + GTX 1070 8GB):"
for cmd in "gpu-status" "gpu-topology" "gpu-test --multi" "gpu-status --expect 0,1"; do
  echo "    \$ ${cmd}"
  eval "${cmd}" 2>&1 | head -20 | sed 's/^/      /'
done
note "Verify the HETEROGENEOUS (mixed-GPU) WARNING is present."
note "Do NOT claim the two GPUs are a single 16GB physical GPU."

# ── §10-11. RUNTIME WIZARD + MODEL INSTALL ───────────────────────────────────
echo ""
echo "── §10-11. RUNTIME WIZARD + MODEL ──"
note "Run: ./bootstrap.sh --configure   (or ./bootstrap.sh --remote-gpu in wizard mode)"
note "Wizard must offer: 1) Ollama 2) llama.cpp 3) vLLM 4) Recommended"
note "Pick a runtime, then choose a SMALL model (e.g. llama3.1:8b / Qwen2.5-7B / a ~4GB GGUF)."
note "Record: model | size | runtime | GPU(s) used | VRAM usage | generation result."
note "Use: model-download <alias>  then  model-run <alias>  to verify load + generation."

# ── §12. MULTI-GPU / HETEROGENEOUS ───────────────────────────────────────────
echo ""
echo "── §12. MULTI-GPU / HETEROGENEOUS ──"
note "3060 Ti + GTX 1070 = heterogeneous. DO NOT force unsafe tensor parallelism."
note "Use the toolkit's automatic heterogeneous-GPU logic. If the selected runtime"
note "cannot safely shard this mixed config, report that honestly — the test PASSES"
note "if the toolkit correctly detects + handles the limitation."

# ── §13-16. GATEWAY WIZARD + 9ROUTER/OMNIROUTE/INTEGRATED ────────────────────
echo ""
echo "── §13-16. GATEWAY WIZARD ──"
note "Wizard must offer: 1) Integrated 2) 9Router 3) OmniRoute 4) No gateway"
echo "  §14 9Router (https://github.com/decolua/9router): actually start it, curl /v1/models."
echo "  §15 OmniRoute (https://github.com/degosouzapw/OmniRoute): actually start it, curl /v1/models."
echo "  §16 Integrated API: /v1, /v1/models, /v1/chat/completions (only if toolkit implements a gateway layer)."
note "Do NOT call a raw runtime endpoint an 'integrated gateway' unless the toolkit"
note "actually implements the gateway layer."

# ── §17-19. ENDPOINT + LOCAL/REMOTE API TEST ─────────────────────────────────
echo ""
echo "── §17-19. ENDPOINT + LOCAL/REMOTE API ──"
note "Installer must show http://SERVER_IP:PORT/v1 based on REAL bind/port."
note "DO NOT accept fake URLs like http://vps_ip.9router unless DNS+reverse proxy verified."
PORT="${WIZARD_GATEWAY_PORT:-20128}"
echo "  Verify port ${PORT} is actually listening:"
ss -ltn 2>/dev/null | grep -E ":${PORT} " && pass "port ${PORT} listening" || fail "port ${PORT} not listening"
echo "  §18 LOCAL API TEST:"
echo "    curl http://127.0.0.1:${PORT}/v1/models"
curl -sS http://127.0.0.1:${PORT}/v1/models 2>&1 | head -30 | sed 's/^/      /'
echo "    curl http://127.0.0.1:${PORT}/v1/chat/completions  (POST a small request)"
echo "  §19 REMOTE CLIENT (from the Mac):"
note "  On the Mac: ssh -L LOCAL_PORT:127.0.0.1:${PORT} user@SERVER_IP"
note "  then: curl http://127.0.0.1:LOCAL_PORT/v1/models  and  /v1/chat/completions"
note "  If auth enabled, send Bearer token — NEVER print the actual token."

# ── §20-25. PUBLIC/PORT/RESTART/REBOOT/IDEMPOTENCY/LANG-RERUN ────────────────
echo ""
echo "── §20-25. SECURITY/PORT/RESTART/IDEMPOTENCY/LANG-RERUN ──"
echo "  §20 Public: do NOT expose publicly unless required + safe."
echo "  §21 Port conflict: occupy ${PORT} with a temp listener, re-run wizard,"
echo "     verify it detects + asks/auto-picks another port (must NOT kill unrelated procs)."
echo "  §22 Restart: stop runtime+gateway, start again, verify API becomes healthy."
echo "  §23 Reboot/persistence: test ONLY if provider allows; else report"
echo "     'NOT TESTED — provider/container restart unavailable'. PERSISTENCE UNKNOWN."
echo "  §24 Idempotency: re-run ./bootstrap.sh; expect existing runtime/model/gateway"
echo "     detected, no duplicate PATH/downloads/processes."
echo "  §25 Language re-run: switch en/vi/zh-CN; verify status/info commands stay localized."

# ── §26-29. DOCS/SECURITY/PERF/FINAL SUITE ───────────────────────────────────
echo ""
echo "── §26-29. DOCS/SECURITY/PERF/FINAL SUITE ──"
echo "  §26 Docs: verify macOS/Linux + Windows PowerShell SSH client instructions are syntactically correct."
echo "  §27 Security: no creds in logs/reports; no accidental public bind; no firewall weakening."
echo "  §28 Performance: short real inference — record model/runtime/GPU/VRAM before+after/speed/temp/util."
echo "  §29 Final full suite AFTER install:"
bash test/run_tests.sh >/tmp/grk_after.log 2>&1 && pass "suite still green after install" || fail "suite regressed after install"
diff <(grep -E 'Total:' /tmp/grk_full.log) <(grep -E 'Total:' /tmp/grk_after.log) >/dev/null && pass "before/after totals match" || note "before/after differ — inspect"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ACCEPTANCE RUNBOOK COMPLETE (human review required for §4-§32)"
echo "  Log: ${LOG}"
echo "══════════════════════════════════════════════════════════════"
