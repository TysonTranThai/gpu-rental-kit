#!/usr/bin/env bash
# =============================================================================
# runtime_port.sh — default service port per AI runtime
# =============================================================================
# Usage: runtime_port.sh <ollama|llamacpp|vllm>
# Echoes the default port, honoring existing env overrides.
case "${1:-}" in
    ollama)   echo "${OLLAMA_PORT:-11434}" ;;
    llamacpp) echo "${LLAMACPP_PORT:-8080}" ;;
    vllm)     echo "${VLLM_PORT:-8000}" ;;
    *) echo "" ;;
esac
