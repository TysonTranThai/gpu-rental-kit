# Phase 4 — model registry refresh: SUMMARY

Date: 2026-09-02
Status: ✅ COMPLETE — config 15/15 + all touched suites green.

## What changed in config/models.yaml

Removed the 2024-era TheBloke mirrors and stale families; added
current-generation models **verified live against ollama.com/library and
Hugging Face** before writing:

- **Ollama families (tags confirmed on the library pages):** qwen3 (0.6b–235b
  incl. the 30b MoE), gemma3 (270m–27b, vision), deepseek-r1 (1.5b–671b),
  llama3.3:70b, qwen3-coder:30b
- **vLLM entries:** Qwen/Qwen3-8B-FP8 (official FP8), Qwen/Qwen3-32B-AWQ,
  casperhansen/llama-3.3-70b-instruct-awq,
  hugging-quants/Meta-Llama-3.1-70B-Instruct-AWQ-INT4 (kept — still canonical)
- **GGUF:** bartowski quantizers (actively maintained) for Qwen3-8B,
  gemma-3-12b-it, Llama-3-8B-Instruct, Mistral-7B-Instruct-v0.2

**Backward compatibility preserved:** README-referenced aliases
`llama3.1-8b`, `llama3-8b-gguf`, `mistral-7b-gguf`, `llama3-70b` keep their
names (sources upgraded); all three READMEs therefore stay valid without
edits.

**Contract hardened:** test_config.sh now requires qwen3/gemma3/deepseek-r1
families + legacy alias survival, and FAILS if any TheBloke mirror returns.
