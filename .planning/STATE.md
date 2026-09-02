# Milestone State — v1.5 "Doctor & Parity"

Date: 2026-09-02
Status: ✅ MILESTONE COMPLETE — all 4 phases executed, audited, green.

## Verification (final audit)

- `./bootstrap.sh --validate` → PASS
- `bash test/run_all.sh local` → **1445 passed / 0 failed / 6 honest SKIPs**
  (baseline before milestone: 1385 passed)
- documentation-languages 48/48, consistency 65/65, config 15/15,
  wizard 35/35, ai-doctor 40/40, api-status 19/19

## Phases shipped

1. ✅ ai-doctor — whole-stack health check (+ Windows twin, i18n ×3,
   40-assertion suite)
2. ✅ stack.env integration — `ai-start --stack [dry-run]` + `ai-start stack`
   + ai-info surface; wizard now advertises the launcher (12 new assertions)
3. ✅ Client parity + Windows CI — `bin/api-status` bash twin (19 assertions);
   windows-latest CI job (real PowerShell parse + structure + smoke-run)
4. ✅ Model registry refresh — Qwen3/Gemma3/DeepSeek-R1/Llama3.3 families,
   bartowski GGUF quants, verified live against ollama.com + HF; legacy
   aliases preserved; TheBloke regression-gated

Version: 1.4.2 → 1.5.0 (config/defaults.env)

## Deferred / known follow-ups

- README "BETA" banner: Windows runtime testing still needs REAL hardware
  (CI now parses .ps1 + smoke-runs help paths — honest partial coverage).
- Multi-GPU verdicts on heterogeneous rigs remain NEEDS VERIFICATION by design.
- Possible next milestone: OpenWebUI/Chat UI integration, `ai-update`
  self-update command, provider recipes (RunPod/Vast/Lambda).
