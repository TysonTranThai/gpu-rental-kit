# Phase 1 — ai-doctor health command

Status: IN PROGRESS
Objective: single honest health-check command for the whole GPU stack.

## Plan

1. `bin/ai-doctor` — bash, macOS-safe (SKIP where prerequisites are absent),
   no mutation. Sections: disk, GPU/driver/CUDA, python venv/torch,
   runtimes, ports, API probes, routers, log sweep, persistence advisory.
   Flags: `--json`, `--lines N` (log sweep depth, default 200), `-h`.
2. i18n: add AI_DOCTOR_* keys to en/vi/zh-CN catalogs (title + summary).
3. Windows twin `bin/ai-doctor.ps1` forwarding `ai-doctor` over SSH.
4. `setup.sh`: install `ai-doctor` with the other bin commands; add to
   machine-report command list.
5. `bin/ai-info`: list ai-doctor in Commands section.
6. READMEs (en/vi/zh-CN): command reference row + troubleshooting row +
   SOURCE-REVISION marker updates.
7. Tests: new `test/tests/test_ai_doctor.sh` (auto-discovered);
   add ai-doctor to required bins in test_consistency.sh and to PS_FILES
   in test_windows_client.sh.

## Acceptance

- `bash test/tests/test_ai_doctor.sh` green
- `bash test/run_all.sh local` green (all FAIL:0)
- `./bootstrap.sh --validate` green
- `bin/ai-doctor` runs cleanly on macOS dev box with honest SKIPs
