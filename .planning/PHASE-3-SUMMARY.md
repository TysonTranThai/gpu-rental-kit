# Phase 3 — client parity + Windows CI: SUMMARY

Date: 2026-09-02
Status: ✅ COMPLETE — api-status 19/19, consistency 65/65, docs 48/48; CI
YAML valid.

## What was built

**`bin/api-status`** (NEW) — bash twin of `api-status.ps1`, closing the
macOS/Linux client parity gap. Probes `http://127.0.0.1:<port>/v1/models`
through an open SSH tunnel; same defaults as the Windows twin (8080, 8000);
`--port N` for a single port; counts models from the JSON; honest DOWN
verdicts with the exact `ssh -N -L` command to run; exit 0 only when at
least one API answers.

**Windows CI job** (`.github/workflows/ci.yml`) — new `windows-latest` job:
1. Parse every `.ps1` with the real PowerShell language parser
   (`[System.Management.Automation.Language.Parser]::ParseFile`).
2. Structural checks: every documented Windows command exists; no `.ps1`
   claims to perform a local GPU inspection (comment lines excluded).
3. Smoke-run `api-status.ps1 -Help` and `ai-doctor.ps1` (remote-not-configured
   non-zero exit is expected and tolerated; parse/runtime crashes are not).

This starts honest Windows runtime validation without claiming full
hardware coverage — the README banner still says Windows runtime testing
is pending real hardware.

## Files

bin/api-status (NEW), .github/workflows/ci.yml (windows job),
test/tests/test_api_status.sh (NEW, 19 assertions, mocked curl/lsof),
READMEs ×3 (tunnel-verification section + SOURCE-REVISION).
