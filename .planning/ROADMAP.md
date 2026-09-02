# GPU Rental Kit — Milestone Roadmap

## Milestone: v1.5 "Doctor & Parity"

Created: 2026-09-02 (GSD autonomous run, no prior .planning/ existed)

Discovered from repo audit (v1.4.2, 31 commits, clean tree):

| # | Phase | Rationale | Status |
|---|---|---|---|
| 1 | **ai-doctor health command** | Automates the README troubleshooting table; biggest UX gap for disposable GPU VMs | ✅ DONE 2026-09-02 (1385 passed / 0 failed) |
| 2 | stack.env integration (wizard → ai-start/ai-info) | Wizard's saved choices are write-only today | ✅ DONE 2026-09-02 |
| 3 | Client parity: `bin/api-status` bash twin + windows-latest CI job | macOS/Linux clients lack the tunnel check; Windows runtime never exercised in CI | ✅ DONE 2026-09-02 |
| 4 | Model registry refresh (Qwen3, Gemma 3, Llama 3.3, R1 distills) | 2024-era TheBloke/phi3/gemma2 entries | ✅ DONE 2026-09-02 |

## Phase 1 — ai-doctor

**Objective:** one command that diagnoses the whole stack and prints
honest PASS / WARN / FAIL / SKIP verdicts, mirroring the suite's honesty
rules. Never mutates anything.

**Checks** (each honestly SKIPPED when its prerequisite is absent):
1. Disk space on AI_HOME (FAIL < 1 GB free, WARN < 5 GB)
2. GPU / driver / CUDA via nvidia-smi + machine.env (SKIP on dev machines)
3. Python venv + torch CUDA (SKIP when venv missing)
4. Runtime binaries: ollama / llama.cpp server / vllm (SKIP = optional)
5. Listening ports vs config (8080 / 8000 / 11434 / router 20128)
6. API reachability: GET /v1/models + /health on live ports
7. Routers enabled vs running (delegates to ai-router health semantics)
8. Log sweep: ERROR/FATAL in the last N lines of recent logs
9. Persistence advisory from machine.env (WARN when unknown)

**Outputs:** human-readable verdict table; `--json` flag for tooling;
exit code = number of FAILs (capped at 125), 0 when healthy.

**Artifacts:** bin/ai-doctor, bin/ai-doctor.ps1 (remote twin),
setup.sh install list + machine-report, READMEs ×3 (SOURCE-REVISION),
bin/ai-info command list, config/i18n/{en,vi,zh-CN}.env,
test/tests/test_ai_doctor.sh, test/tests/test_consistency.sh,
test/tests/test_windows_client.sh.
