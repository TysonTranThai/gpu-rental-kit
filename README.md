# GPU Rental Kit

One-command setup for disposable NVIDIA GPU rental machines (EZYCLOUDX and similar).
Detects your GPU, installs everything, tests it, and gets you running AI models — fast.
Developed on macOS, deployed on rented Linux GPU machines.

---

## Fresh GPU Machine — Do This

After renting an NVIDIA GPU machine and SSH-ing in:

```bash
git clone <YOUR_REPO_URL> gpu-rental-kit
cd gpu-rental-kit
./bootstrap.sh --remote-gpu
```

That's it. The toolkit:

1. Detects Linux + NVIDIA GPU, driver, CUDA, VRAM, CPU, RAM, disk, Docker
2. Classifies storage persistence (never claims durability it can't verify)
3. Installs Python/PyTorch/Ollama/vLLM/llama.cpp (skipping what already works)
4. Tests the GPU (nvidia-smi, CUDA, PyTorch matmul)
5. Writes a machine report and prints exactly how to start a model

**Fully non-interactive:** `./bootstrap.sh --remote-gpu -y`

**Check the machine report when it finishes:**

```bash
cat ~/ai/logs/machine-report.txt
```

---

## Optional: One-Line Remote Bootstrap

```bash
curl -fsSL https://YOUR-HOST/gpu-rental-kit.sh | bash
```

> **Security note:** piping a remote script into `bash` runs it as you, with no
> review. Prefer cloning a pinned repo/commit and inspecting it first. The
> toolkit itself never installs NVIDIA drivers and never exposes servers
> publicly by default.

---

## macOS Development (this repo's home)

This project is developed and tested on a Mac with **no NVIDIA GPU**. Running
`./bootstrap.sh` on macOS does **not** attempt GPU setup — it prints:

> macOS development environment detected. NVIDIA GPU setup tests are skipped.

and offers the dev menu:

```
  1. Run local project validation
  2. Run shell tests (full suite)
  3. Run mock GPU tests
  4. Show remote setup instructions
  5. Exit
```

Equivalent non-interactive commands:

```bash
./bootstrap.sh --validate    # syntax + structure checks
./bootstrap.sh --test        # full local test suite
bash test/run_tests.sh       # same thing, directly
```

**Mock GPU profiles** live in `test/mocks/profiles/` (RTX 3090, RTX 4090,
RTX 5090, RTX 5060 Ti, RTX 4070 Ti Super, V100-SXM2-32GB, V100-PCIE-16GB).
They exercise GPU detection and VRAM classification without hardware. Real GPU tests only ever run on a Linux GPU
machine — `--remote-gpu` refuses to run on macOS, and the suite never claims a
GPU test passed without a GPU.

Requires only Bash (system `/bin/bash` on macOS) and optionally `shellcheck`
(`brew install shellcheck`).

---

## Automated Testing (run everything with one command)

The test harness is designed so you never run tests manually. Everything is
Mac-safe, honestly labeled, and reports-driven.

```bash
bash test/run_all.sh local    # Mac-safe tests: full suite, mocks, persistence,
                              # network exposure, cleanup
bash test/run_all.sh mock     # GPU/provider mocks only
bash test/run_all.sh remote   # REAL tests against a rented GPU (needs SSH info)
bash test/run_all.sh all      # everything currently possible
```

`all` is the primary command. Components that genuinely cannot run are marked
`SKIP` — **never counted as passed**. All results land in `test/results/`:

| Report | Contents |
|---|---|
| `local-test-report.txt` | TOTAL / PASSED / FAILED / SKIPPED / WARNINGS + per-failure details |
| `gpu-matrix-report.txt` | detection/classification results for all 7 mock GPUs |
| `final-report.txt` | aggregated pass/fail/skip across every category |
| `persistence-report.txt` | storage durability verdict (`VERIFIED`/`UNKNOWN`) |
| `network-report.txt` | localhost-vs-public exposure verdict |
| `cleanup-report.txt` | cleanup run result |
| `remote-diagnostics-report.txt` | REAL remote checks (GPU, CUDA, Docker, …) |
| `remote-install-report.txt` | REAL remote bootstrap + post-install checks |
| `llamacpp-report.txt` | REAL llama.cpp load + generation + metrics |
| `gpu-benchmark.txt` | short REAL benchmark (tokens/s, VRAM, util) |

**Remote tests** connect over SSH and never hard-code credentials. They support
key auth, the SSH agent, and `~/.ssh/config`:

```bash
# via environment variables (no flags needed)
GPU_HOST=1.2.3.4 GPU_PORT=22 GPU_USER=root bash test/remote_gpu_test.sh

# or flags; --auth key|agent|config
bash test/remote_gpu_test.sh --host 1.2.3.4 --user root --auth key --key ~/.ssh/gpu_key

# every remote script has --help:
bash test/remote_gpu_test.sh --help
bash test/remote_install_test.sh --help
```

The remote harness is split into **read-only diagnostics** and **installation**:

- `test/remote_gpu_test.sh` — REAL read-only diagnostic (26 checks: Linux, CPU,
  RAM, disk, network, GPU, driver, CUDA, nvidia-smi, PyTorch CUDA, Docker,
  NVIDIA Container Toolkit, Docker GPU passthrough, Python, venv, Hugging Face,
  llama.cpp + CUDA, Ollama, vLLM, model dirs, storage, ports, live API).
  **Installs nothing.**
- `test/remote_install_test.sh` — clones the repo on the box, runs
  `bootstrap.sh --remote-gpu`, then verifies `gpu-status`, `gpu-test`,
  `ai-info`, directories, binaries, llama.cpp, CUDA, and a model runtime.
- `test/llamacpp_test.sh` — downloads a **small** test GGUF, starts llama.cpp
  server, sends a real OpenAI-compatible request, records VRAM/util/speed,
  then stops and cleans up. llama.cpp is the primary inference runtime.
- `test/api_test.sh` — health + `/v1/chat/completions` with real HTTP requests
  (defaults to `127.0.0.1`; never exposes the API publicly).
- `test/benchmark.sh` — short benchmark (tokens/s, prompt-processing speed,
  VRAM used, GPU utilization). Not a stress test.

**Honesty rules** baked into the harness: mock results are labeled `MOCK`,
real results are labeled `REAL`, a skipped test is never reported as passed,
and `PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE` is printed whenever
durability cannot be verified.

---

## How to Check GPU

```bash
gpu-status
```

Or the detailed test suite:

```bash
gpu-test
```

---

## How to Start a Model

```bash
# Simplest — Ollama
ai-start ollama llama3.1:8b

# High-performance OpenAI-compatible API — vLLM
ai-start vllm Qwen/Qwen2.5-7B-Instruct

# GGUF/quantized models — llama.cpp
ai-start llama ~/ai/models/my-model.gguf

# Or the interactive menu
ai-start
```

---

## How to Stop a Model

```bash
ai-stop
```

---

## How to List Models

```bash
model-list
```

---

## How to Download a Model

```bash
# Registered alias
model-download qwen2-7b

# Any Hugging Face model
model-download Qwen/Qwen2.5-7B-Instruct

# Ollama model
model-download llama3.1:8b
```

---

## How to Expose vLLM (OpenAI-Compatible API)

By default vLLM binds to `127.0.0.1` (safe, localhost only).

```bash
# Localhost (safe)
ai-start vllm Qwen/Qwen2.5-7B-Instruct
# → http://127.0.0.1:8000/v1

# LAN access (only do this on a trusted network)
ai-start vllm Qwen/Qwen2.5-7B-Instruct --host 0.0.0.0
# → http://SERVER_IP:8000/v1
```

**Warning:** binding to `0.0.0.0` exposes the API to the network.
Use a firewall and never expose publicly without authentication.

---

## How to Backup

```bash
# Config, scripts, manifests (fast — no model files)
ai-backup

# Everything including models (slow)
ai-backup --include-models

# List backups
ai-backup --list

# Restore
ai-backup --restore ~/ai/backups/ai-backup-*.tar.gz
```

**Important:** backup before your rental ends — the machine may disappear.

---

## How to Rebuild

On a fresh machine:

```bash
git clone <YOUR_REPO_URL> gpu-rental-kit
cd gpu-rental-kit
./bootstrap.sh --remote-gpu
```

Or restore a backup first, then bootstrap.

---

## Storage Persistence

Rental machines are disposable. The toolkit classifies storage as
`TEMPORARY`, `PERSISTENT/UNKNOWN`, and reports a survival matrix
(restart / deletion / rental end) for the detected environment
(container, VM, or unknown). If it cannot verify the provider's storage it
prints:

> PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE.

It never falsely claims storage is persistent.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `nvidia-smi` not found | NVIDIA driver missing. `sudo apt install -y nvidia-driver-550`, reboot, re-run bootstrap. |
| PyTorch reports no CUDA | Reinstall: `~/ai/venv/bin/pip install torch --index-url https://download.pytorch.org/whl/cu124` |
| Ollama not starting | Check: `sudo systemctl status ollama` or `cat ~/ai/logs/ollama.log` |
| vLLM out of memory | Model too large for VRAM. Try a smaller model or `--max-model-len`. |
| Docker GPU not working | Verify: `docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi` |
| Model download fails | Check internet: `curl -I https://huggingface.co`. Check HF token for gated models. |
| Commands not found after setup | `source ~/.bashrc` or open a new terminal. |
| `bootstrap.sh` on macOS | Expected — macOS is the dev environment. Use the dev menu or `--test`. |

### View logs

```bash
ai-logs
# or
cat ~/ai/logs/setup-*.log
```

---

## Supported Environments

- **Remote (runtime):** Ubuntu 20.04 / 22.04 / 24.04, Debian 11/12, NVIDIA GPUs
  (RTX 30/40/50 series, V100, A100, H100, T4, and others). Any VRAM size — the
  toolkit auto-classifies (small → very-large).
- **Development (tests):** macOS (Bash 3.2+), no GPU required.

---

## What It Does NOT Do

- **Does NOT** blindly install NVIDIA drivers (avoids breaking provider images)
- **Does NOT** download huge models automatically
- **Does NOT** expose inference servers publicly
- **Does NOT** require Docker (native execution works fine)
- **Does NOT** run real GPU tests on your Mac (no GPU there — mocks instead)

---

## Project Layout

```
gpu-rental-kit/
├── bootstrap.sh            # ONE entry point (remote-gpu / macOS dev menu)
├── setup.sh                # setup orchestrator (Linux GPU machines only)
├── config/                 # defaults.env + models.yaml aliases
├── scripts/                # detection, setup, test, backup, cleanup
├── bin/                    # gpu-status, gpu-test, model-*, ai-* commands
├── docker/                 # optional CUDA runtime image + compose
└── test/                   # macOS-safe test suite + mock GPU/docker profiles
```

---

## License

MIT — see LICENSE.
