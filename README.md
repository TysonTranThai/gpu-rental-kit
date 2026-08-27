<p align="center">
  <img src="docs/logo.svg" width="110" alt="GPU Rental Kit logo" />
</p>

<h1 align="center">GPU Rental Kit</h1>

<p align="center">
  <strong>One command. A rented GPU becomes an AI inference server.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/TysonTranThai/gpu-rental-kit/releases"><img src="https://img.shields.io/github/v/release/TysonTranThai/gpu-rental-kit?color=blue&label=release" alt="GitHub release"></a>
  <img src="https://img.shields.io/badge/shell-bash-4EAA25.svg?logo=gnubash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/platform-Linux%20%2F%20macOS-lightgrey.svg" alt="Platform: Linux / macOS">
  <img src="https://img.shields.io/badge/NVIDIA-CUDA-76B900.svg?logo=nvidia&logoColor=white" alt="NVIDIA CUDA">
  <img src="https://img.shields.io/badge/tests-530%20passing-brightgreen.svg" alt="Tests: 530 passing">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs welcome">
</p>

---

## What is this?

**GPU Rental Kit** turns a freshly rented Linux NVIDIA GPU machine into a
ready-to-use AI inference server with **one command**.

Renting a cloud GPU is easy. Setting it up is not — drivers, CUDA, Python,
PyTorch, inference runtimes, model downloads, and testing usually eat an
afternoon. This toolkit automates the whole pipeline: it detects your
hardware, configures the environment, installs the runtime you want, downloads
a model, runs it, and exposes an OpenAI-compatible API.

## Who is it for?

- **Anyone renting disposable GPU machines** (RTX 3090/4090/5090, V100, A100,
  T4, …) for a few hours or days and wanting them productive immediately.
- **Developers who want an OpenAI-compatible API** on their own rented hardware
  — for less cost and with full control.
- **People who rent repeatedly** and don't want to repeat the same setup dance
  every time.

## Why use it?

| Problem with rented GPUs | GPU Rental Kit |
|---|---|
| Setup is manual and easy to botch | One command does it all |
| You don't know what the machine actually has | Detects GPU, VRAM, driver, CUDA, storage honestly |
| Storage may vanish when the rental ends | Classifies persistence — never falsely claims durability |
| Runtimes are fiddly to install | Installs llama.cpp, Ollama, or vLLM, skipping what works |
| You can't tell if it actually works | Tests the GPU and prints a machine report |
| Machines are disposable | One-command rebuild + backup/restore |

## How do I start?

```bash
git clone https://github.com/TysonTranThai/gpu-rental-kit.git
cd gpu-rental-kit
./bootstrap.sh --remote-gpu
```

That's the whole pitch. Details below.

---

## How it works

```
┌────────────┐     ┌────────────┐     ┌──────────────────┐
│  Your Mac  │ ──▶ │    SSH     │ ──▶ │  Cloud GPU box   │
│  (dev only)│     │  one login │     │  (rented, Linux) │
└────────────┘     └────────────┘     └────────┬─────────┘
                                               │  ./bootstrap.sh --remote-gpu
                                               ▼
                                    ┌──────────────────────┐
                                    │  Detect + configure  │
                                    │  GPU · driver · CUDA │
                                    │  VRAM · storage · OS │
                                    └──────────┬───────────┘
                                               ▼
                                    ┌──────────────────────┐
                                    │  llama.cpp (primary) │
                                    │  Ollama · vLLM (opt) │
                                    └──────────┬───────────┘
                                               ▼
                                    ┌──────────────────────┐
                                    │   GGUF / quantized   │
                                    │   model downloaded   │
                                    └──────────┬───────────┘
                                               ▼
                                    ┌──────────────────────┐
                                    │  OpenAI-compatible   │
                                    │      HTTP API        │
                                    └──────────────────────┘
```

---

## Quick start

### 1. Rent a GPU machine

Any Linux NVIDIA GPU instance — RTX 30/40/50 series, V100, A100, H100, T4, or
similar. The toolkit is **provider-agnostic**: it works with EZYCLOUDX,
RunPod, Vast.ai, Lambda, or any provider that gives you SSH access to a Linux
box with an NVIDIA GPU.

### 2. SSH in and run ONE command

```bash
ssh root@SERVER_IP
git clone https://github.com/TysonTranThai/gpu-rental-kit.git
cd gpu-rental-kit
./bootstrap.sh --remote-gpu
```

Fully non-interactive (CI-friendly):

```bash
./bootstrap.sh --remote-gpu -y
```

The bootstrap will:

1. **Detect** the OS, GPU, VRAM, driver, CUDA, CPU, RAM, disk, and Docker
2. **Classify** storage persistence (never claims durability it can't verify)
3. **Install** Python/PyTorch and the inference runtimes (skipping what works)
4. **Test** the GPU (nvidia-smi, CUDA, PyTorch matmul)
5. **Report** — write a machine report and print exactly how to start a model

When it finishes, check the report:

```bash
cat ~/ai/logs/machine-report.txt
```

### 3. Check your GPU

```bash
gpu-status    # one-screen hardware summary
gpu-test      # full compute test suite + light benchmark
```

### 4. Start a model

```bash
# llama.cpp (primary runtime) — GGUF models, low VRAM
ai-start llama ~/ai/models/my-model.gguf

# Ollama — simplest possible experience
ai-start ollama llama3.1:8b

# vLLM — high-throughput OpenAI-compatible API
ai-start vllm Qwen/Qwen2.5-7B-Instruct
```

No arguments? `ai-start` shows an interactive menu.

### 5. Use the OpenAI-compatible API

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen", "messages": [{"role": "user", "content": "Hello!"}]}'
```

> **Safety first:** servers bind to `127.0.0.1` by default — localhost only.
> See [Security](#security).

---

## Runtimes

| Runtime | Role | Best for | Start with |
|---|---|---|---|
| **llama.cpp** | **Primary** | GGUF quantized models on modest VRAM; CPU fallback | `ai-start llama <model.gguf>` |
| **Ollama** | Optional | Zero-config local models | `ai-start ollama llama3.1:8b` |
| **vLLM** | Optional | High-throughput OpenAI-compatible serving | `ai-start vllm <model-id>` |

All three are installed by `bootstrap.sh` and managed through the same `ai-*`
and `model-*` commands, so you can switch backends without relearning
anything.

---

## Command reference

### `bootstrap.sh`

| Flag | What it does |
|---|---|
| `--remote-gpu` | **The one you want on a rented GPU machine.** Full setup: detect → configure → install → test → report. |
| `-y`, `--yes` | Auto-confirm all prompts (safe with `--remote-gpu`). |
| `--validate` | Local project sanity check — syntax + structure + shellcheck. Works anywhere. |
| `--test` | Run the full local test suite (mock GPU tests included). Works anywhere. |
| `--help` | Show usage. |

On macOS with no flags, `bootstrap.sh` opens the **development menu**
(validate / test / mock GPU tests / remote instructions).

### Everyday commands (installed into `~/ai/bin`)

| Command | What it does |
|---|---|
| `gpu-status` | One-screen GPU + system status (VRAM, util, temp, power, CUDA). |
| `gpu-test` | GPU compute tests + light benchmark. |
| `ai-start` | Start a runtime/model, or show the interactive menu. |
| `ai-stop` | Stop the running model/runtime. |
| `ai-info` | System + environment summary. |
| `ai-logs` | Tail logs for all runtimes. |
| `model-download` | Download a model (alias, Hugging Face ID, or Ollama name). |
| `model-list` | List downloaded models. |
| `model-run` | Run a model with backend auto-detection. |
| `model-stop` | Stop a running model. |
| `model-logs` | Per-runtime logs. |
| `ai-backup` | Back up config, scripts, manifests — or models too. |

### Managing models

```bash
model-download qwen2-7b                    # registered alias (see config/models.yaml)
model-download Qwen/Qwen2.5-7B-Instruct    # any Hugging Face model
model-download llama3.1:8b                 # any Ollama model

model-list                                 # what's on disk
model-run llama3-8b-gguf --backend llamacpp
model-stop
```

---

## Configuration

Everything lives in `config/`:

| File | Purpose |
|---|---|
| `config/defaults.env` | All defaults (paths, ports, versions). Every value can be overridden with an environment variable. |
| `config/models.yaml` | Model aliases — short names that expand to full model IDs, with backend and VRAM hints. |

```bash
# Any default can be overridden on the command line:
AI_MODELS_DIR=/mnt/ssd/models ./bootstrap.sh --remote-gpu
```

---

## Docker (optional)

Native execution works fine and is the default. If you prefer containers, a
CUDA-enabled runtime image and compose file are included:

```bash
docker build -t gpu-ai-runtime -f docker/Dockerfile docker/
docker run --gpus all -it gpu-ai-runtime
```

---

## Project layout

```
gpu-rental-kit/
├── bootstrap.sh            # ONE entry point (remote GPU / macOS dev menu)
├── setup.sh                # setup orchestrator (Linux GPU machines only)
├── config/                 # defaults.env + models.yaml aliases
├── scripts/                # detection, setup, test, backup, cleanup
├── bin/                    # gpu-status, gpu-test, model-*, ai-* commands
├── docker/                 # optional CUDA runtime image + compose
├── docs/                   # logo + documentation assets
└── test/                   # macOS-safe test suite + mock GPU/docker profiles
```

---

## Testing

Everything is Mac-safe, honestly labeled, and runnable with one command:

```bash
bash test/run_all.sh local    # full local suite: 521 checks + mocks + diagnostics
bash test/run_all.sh mock     # GPU/provider mocks only
bash test/run_all.sh all      # everything currently possible (recommended)
```

Current status: **530 checks passing** (521 local + 9 mock GPU), 0 failures —
remote tests honestly report `SKIP` when no GPU machine is configured.

**Honesty rules** baked into the harness:

- Mock results are labeled `MOCK`; real results are labeled `REAL`.
- A skipped test is **never** counted as passed.
- When storage durability can't be verified, it prints
  `PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE`.
- Remote tests connect over SSH and never hard-code credentials (key auth,
  SSH agent, and `~/.ssh/config` all supported).

Mock GPU profiles (RTX 3090/4090/5090/5060 Ti/4070 Ti Super, V100) exercise
detection and VRAM classification with no hardware. Real GPU tests only ever
run on a Linux GPU machine — `--remote-gpu` refuses to run on macOS, and the
suite never claims a GPU test passed without a GPU.

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to run and extend the tests.

---

## Supported environments

- **Remote (runtime):** Ubuntu 20.04 / 22.04 / 24.04, Debian 11/12, any NVIDIA
  GPU with a working driver and CUDA. Any VRAM size — the toolkit
  auto-classifies small → very-large and picks fitting models.
- **Development (tests):** macOS (Bash 3.2+, the system `/bin/bash` works fine), no GPU required.

---

## What it does NOT do

- **Does NOT** install NVIDIA drivers blindly (avoids breaking provider images)
- **Does NOT** download huge models automatically
- **Does NOT** expose inference servers publicly
- **Does NOT** require Docker (native execution works fine)
- **Does NOT** run real GPU tests on your Mac (no GPU there — mocks instead)

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `nvidia-smi` not found | NVIDIA driver missing. `sudo apt install -y nvidia-driver-550`, reboot, re-run bootstrap. |
| PyTorch reports no CUDA | Reinstall: `~/ai/venv/bin/pip install torch --index-url https://download.pytorch.org/whl/cu124` |
| Ollama not starting | Check: `sudo systemctl status ollama` or `cat ~/ai/logs/ollama.log` |
| vLLM out of memory | Model too large for VRAM. Try a smaller model or `--max-model-len`. |
| Docker GPU not working | Verify: `docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi` |
| Model download fails | Check internet: `curl -I https://huggingface.co`. Check HF token for gated models. |
| Commands not found after setup | `source ~/.bashrc` or open a new terminal. |
| `bootstrap.sh` on macOS | Expected — macOS is the dev environment. Use the dev menu or `--test`. |

View logs at any time:

```bash
ai-logs
# or
cat ~/ai/logs/setup-*.log
```

---

## Security

- Servers bind to `127.0.0.1` by default (`EXPOSE_PUBLICLY=false`). Binding
  to `0.0.0.0` exposes the API to the network — only do that on a trusted
  network, behind a firewall, and with authentication enabled.
- The toolkit never installs NVIDIA drivers and never opens public ports on
  its own.
- No credentials are stored or hard-coded anywhere. Secrets come from your
  environment (e.g. `HF_TOKEN`) and are git-ignored.
- Found a vulnerability? See [SECURITY.md](SECURITY.md).

---

## Contributing

Contributions are welcome — docs, tests, new mock profiles, provider
recipes, bug reports. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

## License

[MIT](LICENSE) — free to use, modify, and distribute.
