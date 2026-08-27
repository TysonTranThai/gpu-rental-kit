## Summary

<!-- What does this change do, and why? One or two sentences. -->

## Related issue

<!-- Link the issue this closes, if any: Closes #123 -->

## Test plan

<!-- How did you verify this change? Paste the relevant output. -->

- [ ] `./test/run_all.sh all` passes locally (remote tests may `SKIP` — that's fine)
- [ ] `bash -n` clean on touched scripts
- [ ] `shellcheck` (error severity) clean on touched scripts
- [ ] New behavior has test coverage (mock profiles/tests where applicable)

## Checklist

- [ ] Change is as small as it can be
- [ ] No secrets, credentials, or machine-specific paths are committed
- [ ] README/docs updated if user-facing behavior changed
