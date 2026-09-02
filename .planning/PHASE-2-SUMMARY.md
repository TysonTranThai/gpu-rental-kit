# Phase 2 — stack.env integration: SUMMARY

Date: 2026-09-02
Status: ✅ COMPLETE — wizard/localization/syntax/doctor tests green; docs-parity
48 passed / 0 failed.

## What was built

The guided wizard's `stack.env` is no longer a write-only record:

- **`ai-start --stack`** — launches the saved runtime with the saved MODEL and,
  when the wizard chose 9Router/OmniRoute as gateway, starts that router first.
  Honest failures: no stack.env, missing MODEL for vllm/llamacpp, unknown
  RUNTIME — all exit 1 with a fix hint.
- **`ai-start --stack dry-run`** — prints the exact launch commands and exits 0
  without touching anything (testable, and safe for users to inspect).
- **`ai-start stack`** — renders the saved configuration.
- **`ai-info`** — shows the saved stack and points at the launcher.
- **Wizard final summary** — now tells the user about `ai-start --stack`
  (new i18n key WIZARD_STACK_LAUNCH_HINT in en/vi/zh-CN).

## Files

bin/ai-start (--stack/--stack dry-run/stack + help), bin/ai-info,
scripts/wizard.sh (launch hint), config/i18n/{en,vi,zh-CN}.env,
test/tests/test_wizard.sh (section 8: 12 new assertions incl. real
sandboxed dry-run executions), READMEs ×3 + SOURCE-REVISION.
