# Phase 1 — ai-doctor: SUMMARY

Date: 2026-09-02
Status: ✅ COMPLETE — full local suite 1385 passed / 0 failed / 6 honest SKIPs;
`./bootstrap.sh --validate` green.

## What was built

`ai-doctor` — one read-only command that diagnoses the whole GPU stack,
automating the README troubleshooting table.

**Checks (each honestly SKIPPED when prerequisites are absent):**
disk space (FAIL < 1GB, WARN < 5GB) · GPU/driver via nvidia-smi ·
python venv + PyTorch CUDA · runtimes (ollama / llamacpp-serve / vllm) ·
port listeners + HTTP API probes (Ollama /v1/tags-style, llama.cpp, vLLM) ·
9Router + OmniRoute (disabled → SKIP, port clash detected) ·
log sweep for ERROR/FATAL (WARN, never FAIL — errors may be stale) ·
storage-persistence advisory from machine.env.

**Contract:** verdicts are exactly PASS / WARN / FAIL / SKIP; SKIP is never a
failure; exit code = number of FAILs (cap 125); `--json` for tooling;
`--lines N` log depth; `--help`. Verdicts never silently upgraded.

## Files

| File | Change |
|---|---|
| `bin/ai-doctor` | NEW — 400-line bash health check (i18n-aware, macOS-safe) |
| `bin/ai-doctor.ps1` | NEW — Windows remote twin (SSH forward, grk-client-lib) |
| `setup.sh` | install list + quick-commands summary |
| `bin/ai-info` | commands section |
| `config/i18n/{en,vi,zh-CN}.env` | DOCTOR_* keys ×5 each |
| `README.md` / `.vi.md` / `.zh-CN.md` | command reference, troubleshooting row, diagnosis snippet, Windows twins list, SOURCE-REVISION 795807885 |
| `config/defaults.env` | BOOTSTRAP_VERSION 1.4.2 → 1.5.0 |
| `test/tests/test_ai_doctor.sh` | NEW — 40 assertions, fully mocked (sandbox AI_HOME, mock df/lsof via PATH) |
| `test/tests/test_consistency.sh` | ai-doctor in required bins |
| `test/tests/test_windows_client.sh` | ai-doctor.ps1 in PS_FILES |
| `.planning/ROADMAP.md`, `PHASE-1-PLAN.md`, `PHASE-1-SUMMARY.md` | GSD artifacts |

## Bugs caught by the suite during development

1. `set -e` + pipefail: `df` on a missing path aborted the whole script →
   disk check now SKIPs when AI_HOME doesn't exist.
2. Mock heredocs without `chmod +x` were silently bypassed by PATH lookup.
3. Command substitutions inheriting the doctor's FAIL exit code aborted the
   test itself under `set -e` (fixed with inner `|| true`).

## Next phases (per ROADMAP)

2. stack.env integration — wire wizard choices into ai-start/ai-info
3. Client parity — `bin/api-status` bash twin + windows-latest CI job
4. Model registry refresh — current-generation models
