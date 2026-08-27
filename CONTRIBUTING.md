# Contributing to GPU Rental Kit

Thanks for wanting to help! This project is small by design — a portable
toolkit of Bash scripts with a Mac-safe, honestly-labeled test suite. Every
contribution that keeps it simple, honest, and tested is welcome.

## Table of contents

- [Code of conduct](#code-of-conduct)
- [What we're looking for](#what-were-looking-for)
- [Development environment](#development-environment)
- [Running the tests](#running-the-tests)
- [How the test suite works](#how-the-test-suite-works)
- [Project structure](#project-structure)
- [Making changes](#making-changes)
- [Pull request checklist](#pull-request-checklist)
- [Testing on a real GPU](#testing-on-a-real-gpu)

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be kind,
be specific, and assume good faith.

## What we're looking for

| Type | Examples |
|---|---|
| **Docs** | Clearer README, better troubleshooting, provider-specific notes |
| **Tests** | New mock GPU profiles, edge cases, regression coverage |
| **Fixes** | Honest bugs — never silent failures or fake passes |
| **Recipes** | Verified setup notes for additional GPU providers |
| **Polish** | Better error messages, friendlier UX in the CLI |

We are **not** looking for big rewrites, added dependencies, or features that
make the toolkit less portable. When in doubt, open an issue first and
discuss.

## Development environment

Any machine with **Bash 3.2+** works. The project is developed on macOS with
**no NVIDIA GPU** — all GPU tests run against mocks. Linux is the deployment
target; you can develop and run the full local suite there too.

```bash
# Optional but recommended:
brew install shellcheck        # macOS
sudo apt install shellcheck    # Debian/Ubuntu
```

Clone, then sanity-check:

```bash
git clone https://github.com/TysonTranThai/gpu-rental-kit.git
cd gpu-rental-kit
./bootstrap.sh --validate
```

## Running the tests

One command runs everything that can run on your machine:

```bash
./test/run_all.sh all
```

Targeted runs:

```bash
./test/run_all.sh local    # full local suite + mocks + diagnostics + cleanup
./test/run_all.sh mock     # GPU/provider mocks only
./test/run_all.sh remote   # REAL tests against a rented GPU (needs SSH access)
```

Results land in `test/results/` — `final-report.txt` is the summary, and each
component writes its own `*-report.txt`.

**A change is done when the suite is green:** `LOCAL TESTS: 521 PASS / 0 FAIL`
and `MOCK GPU TESTS: 9 PASS / 0 FAIL` (remote components honestly `SKIP` when
no GPU machine is configured).

## How the test suite works

- `test/local_test.sh` — the full local suite (521 checks): syntax, structure,
  config, consistency, idempotency, secret scan, argument handling, shellcheck
  at error severity, plus per-area tests in `test/tests/`.
- `test/run_gpu_matrix.sh` — runs the **real** detection logic
  (`scripts/detect_gpu.sh`) against mocked `nvidia-smi` output for 7 GPU
  profiles and verifies every parsed field.
- `test/mocks/` — fake `nvidia-smi`, fake Docker, mock `/proc`, and GPU
  profiles (`test/mocks/profiles/*.env`).
- `test/remote/` — scripts that run over SSH against a real rented machine.
  They are read-only diagnostics and install tests; they never hard-code
  credentials.

### Adding a mock GPU profile

1. Copy an existing profile: `cp test/mocks/profiles/rtx3090.env
   test/mocks/profiles/my-gpu.env`
2. Fill in the `MOCK_*` values to match a real `nvidia-smi` output for that GPU.
3. Add the matching raw output in `test/mocks/outputs/`.
4. Add the profile to the `MATRIX` in `test/run_gpu_matrix.sh` with the
   expected parsed values.
5. Run `./test/run_all.sh mock` — every field is verified.

### Adding a test

Each test file in `test/tests/` uses `test/helpers.sh` (`assert_ok`,
`assert_eq`, `assert_contains`, `capture`, mock environment setup). Tests must:

- be **Mac-safe** (mocks, no real GPU required),
- **pass or skip honestly** — never fake a pass,
- print `[PASS]`/`[FAIL]` lines the reporters can count.

## Project structure

```
bootstrap.sh            # ONE entry point (remote GPU / macOS dev menu)
setup.sh                # setup orchestrator (Linux GPU machines only)
config/                 # defaults.env + models.yaml aliases
scripts/                # detection, setup, test, backup, cleanup
bin/                    # gpu-status, gpu-test, model-*, ai-* commands
docker/                 # optional CUDA runtime image + compose
docs/                   # logo + documentation assets
test/                   # macOS-safe test suite + mocks
```

Keep changes localized: a new setup step belongs in `scripts/`, a new command
belongs in `bin/`, and its coverage belongs in `test/`.

## Making changes

1. **Open an issue first** for anything non-trivial, so we agree on direction.
2. Fork the repo and create a branch: `git checkout -b feat/your-change`.
3. Make the smallest change that solves the problem.
4. Run `./test/run_all.sh all` and make sure the suite is green.
5. Run `bash -n` on any shell script you touched, and `shellcheck` if
   installed (error severity is enforced by the test suite anyway).
6. **Never commit secrets.** If you touch config, double-check nothing real
   leaked in. `test/results/` is git-ignored on purpose.
7. Open a pull request with a clear description.

## Pull request checklist

- [ ] Change is as small as it can be
- [ ] `./test/run_all.sh all` passes locally (remote tests may SKIP — that's fine)
- [ ] `bash -n` and `shellcheck` (error severity) are clean on touched files
- [ ] New behavior has test coverage (mock profiles/tests where applicable)
- [ ] No secrets, credentials, or machine-specific paths are committed
- [ ] README/docs updated if user-facing behavior changed
- [ ] PR description explains the *why*, not just the *what*

## Testing on a real GPU

If you have access to a rented NVIDIA GPU machine, run the remote suite — it's
the closest thing to production verification:

```bash
# Environment variables (no credentials stored anywhere):
GPU_HOST=1.2.3.4 GPU_PORT=22 GPU_USER=root ./test/remote_gpu_test.sh

# Or flags:
./test/remote_gpu_test.sh --host 1.2.3.4 --user root --auth key --key ~/.ssh/gpu_key
```

`./test/remote_gpu_test.sh --help` explains every option. Note that
`remote_install_test.sh` **runs a full bootstrap on the remote machine** —
make sure that's what you want before pointing it at a box.
