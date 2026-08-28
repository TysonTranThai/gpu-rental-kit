<!-- ==========================================================================
  TRANSLATION TEMPLATE — README.<code>.md
  ==========================================================================
  Copy this file to README.<code>.md (e.g. README.ja.md) and translate the
  PROSE. Everything inside code fences, every filename, every environment
  variable, every URL, and every technical identifier is preserved VERBATIM
  — commands must stay byte-identical to the English README.

  Before starting:
    1. Read docs/TRANSLATIONS.md (naming, status, selector, validation).
    2. Base your translation on the CURRENT English README.md, not on this
       template alone — the template shows the structure; the live English
       README is the source of truth for the latest content.
    3. Replace the SOURCE-REVISION placeholder below with the value from
       the current English README.md when you finish.

  Project positioning (keep in every translation):
  GPU Rental Kit saves time when renting and setting up GPU servers.
  Workflow: RENT → INSTALL → TEST → RUN.
  Multi-GPU is an important feature, not the sole purpose.
  ========================================================================== -->

<p align="center">
  <!-- PASTE the full selector row here: run `bash docs/lang-selector.sh` -->
  🇬🇧 <a href="README.md">English</a> &nbsp;|&nbsp; 🇻🇳 <a href="README.vi.md">Tiếng Việt</a> &nbsp;|&nbsp; 🇨🇳 <a href="README.zh-CN.md">中文</a>
</p>

<!-- SOURCE-REVISION: <set to the current README.md revision> -->

---

<p align="center">
  <img src="docs/logo.svg" width="110" alt="GPU Rental Kit logo" />
</p>

<h1 align="center">GPU Rental Kit</h1>

<p align="center">
  <strong>TRANSLATE: one-sentence tagline — "Turn a rented NVIDIA GPU VM into a ready-to-use self-hosted LLM server."</strong>
</p>

<!-- Keep the same badge block as README.md (do not invent new badges). -->

> [!IMPORTANT]
> TRANSLATE: the BETA note about Windows client support and the stable
> macOS/Linux release link. Keep the release URL unchanged.

> TRANSLATE: the simple idea — the rented GPU server runs the model; your
> computer does not need an NVIDIA GPU.

> TRANSLATE: the workflow — RENT → INSTALL → TEST → RUN.

## TRANSLATE: What is gpu-rental-kit?

TRANSLATE the introduction paragraph and the automation list:

- TRANSLATE: GPU detection and CUDA validation
- TRANSLATE: Python virtual environments and GPU-aware PyTorch
- TRANSLATE: Ollama, llama.cpp, and vLLM runtimes
- TRANSLATE: Hugging Face model downloads and model aliases
- TRANSLATE: OpenAI-compatible inference servers
- TRANSLATE: Optional Docker GPU support
- TRANSLATE: Storage and persistence diagnostics
- TRANSLATE: Backups, restore helpers, logs, and health checks
- TRANSLATE: Local, mock, and real remote testing

TRANSLATE: provider-agnostic statement.

## TRANSLATE: Platform Support

TRANSLATE the two-environment explanation and the platform table.

| Platform | Local Client | GPU Server |
|---|:---:|:---:|
| Windows | ✅ | ❌ |
| macOS | ✅ | ❌ |
| Linux | ✅ | ✅ |

### TRANSLATE: GPU Server

TRANSLATE: the rented machine must be Linux + NVIDIA GPU + working driver.

## TRANSLATE: Windows Support

TRANSLATE: Windows is a supported local client platform with `bootstrap.ps1`
and `bin\*.ps1`. Explain the LOCAL CLIENT vs REMOTE GPU SERVER split.

### TRANSLATE: What gets installed
### TRANSLATE: How to install
### TRANSLATE: How to connect to a GPU server
### TRANSLATE: How SSH tunneling works
### TRANSLATE: How to use the model
### TRANSLATE: Do you need WSL2, Docker Desktop, or an NVIDIA GPU?

KEEP verbatim (commands): all `powershell` code fences, `ssh` commands,
`git clone ... && cd gpu-rental-kit`, `./bootstrap.sh --remote-gpu`.

## TRANSLATE: 5-minute quick start

### 1. TRANSLATE: Rent a Linux NVIDIA GPU VM
### 2. TRANSLATE: SSH into the GPU server
### 3. TRANSLATE: Clone the repository and bootstrap the server
### 4. TRANSLATE: Verify the machine
### 5. TRANSLATE: Download a small model
### 6. TRANSLATE: Start inference
### 7. TRANSLATE: Connect from your own computer

KEEP verbatim: every `bash` code fence (`ssh`, `git clone`,
`./bootstrap.sh --remote-gpu -y`, `source ~/.bashrc`, `gpu-status`,
`gpu-test`, `model-list`, `model-download llama3.1-8b`,
`ai-start ollama llama3.1:8b`, ...).

## TRANSLATE: How the pieces fit together

KEEP verbatim: the `mermaid` diagram. TRANSLATE the explanation below it.

## TRANSLATE: Runtime choices

KEEP verbatim: the runtime table commands and the note that llama.cpp is
the primary runtime.

## TRANSLATE: Multi-GPU support

### TRANSLATE: One model across multiple GPUs (sharding)
### TRANSLATE: Choosing GPUs automatically (`--gpus auto`)
### TRANSLATE: Mixed GPUs (heterogeneous setups)
### TRANSLATE: Benchmarking (optional)
### TRANSLATE: Multiple models on different GPUs (workload parallelism)
### TRANSLATE: Inspecting GPUs
### TRANSLATE: Important — what multi-GPU does and does not do

KEEP verbatim: all `model-run`/`gpu-status`/`gpu-list`/`gpu-topology`/
`gpu-test` commands and the `GPU_MODE`/`GPU_IDS`/`CUDA_VISIBLE_DEVICES`
environment variables.

IMPORTANT: translate "aggregate VRAM" honestly — multiple GPUs are separate
devices; memory is never pooled into one GPU.

## TRANSLATE: Windows Users
## TRANSLATE: macOS Users

Explain the client/server split accurately. Do NOT claim the Linux GPU
bootstrap runs natively on macOS or Windows.

## TRANSLATE: Remote API access

### A. TRANSLATE: SSH tunnel — recommended for beginners
### B. TRANSLATE: Public IP and port — advanced
### C. TRANSLATE: Domain + HTTPS — advanced/future deployment

## TRANSLATE: OpenAI-compatible APIs: what that means

## TRANSLATE: Security warning

TRANSLATE the warning fully; keep the security recommendations accurate.

## TRANSLATE: Storage and rental warning

KEEP verbatim the text-block warning: `PERSISTENCE UNKNOWN — DO NOT RELY ON LOCAL STORAGE`.

## TRANSLATE: Command reference

KEEP verbatim: every command name in the table (`bootstrap.sh`, `gpu-status`,
`gpu-list`, `gpu-topology`, `gpu-test`, `model-list`, `model-download`,
`model-run`, `model-stop`, `ai-start`, `ai-stop`, `ai-info`, `ai-backup`).
TRANSLATE the "Purpose" column.

## TRANSLATE: Common workflows

KEEP verbatim: all commands. TRANSLATE the workflow headings.

### TRANSLATE: I just rented a GPU
### TRANSLATE: I want to run Ollama
### TRANSLATE: I want llama.cpp
### TRANSLATE: I want an OpenAI-compatible API
### TRANSLATE: I want to connect from Windows
### TRANSLATE: I want to connect from Mac
### TRANSLATE: My rental is ending

## TRANSLATE: Troubleshooting

KEEP verbatim: the `nvidia-smi`, `ssh`, `ss`, `curl`, `docker run`,
`Get-ExecutionPolicy`, `winget` commands inside the table. TRANSLATE the
symptom/next-step columns.

## TRANSLATE: FAQ

## TRANSLATE: Supported environments and limitations

## TRANSLATE: Project layout

KEEP verbatim: the `text` tree block.

## TRANSLATE: Testing

KEEP verbatim: `./test/run_all.sh local|mock|all` commands.

## TRANSLATE: Contributing

Keep the link to `CONTRIBUTING.md` and the test command.

## TRANSLATE: License

Keep the `[MIT](LICENSE)` link.

---

<!-- When finished:
  1. bash docs/lang-selector.sh  → paste the selector row at the top
  2. Set SOURCE-REVISION to the current README.md revision
  3. bash test/tests/test_documentation_languages.sh  → all checks pass
  4. Add your language to docs/languages.env and open a PR
-->
