# =============================================================================
# GPU Rental Kit — AI Runtime Dockerfile
# =============================================================================
# A CUDA-enabled container with Python + AI libraries for GPU inference.
# Build: docker build -t gpu-ai-runtime -f docker/Dockerfile docker/
# Run:   docker run --gpus all -it gpu-ai-runtime
# =============================================================================

# Use the NVIDIA CUDA runtime as base (adjust version to match driver)
FROM nvidia/cuda:12.4.0-runtime-ubuntu22.04

LABEL maintainer="GPU Rental Kit"
LABEL description="CUDA-enabled AI inference runtime"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/ai/cache/huggingface \
    HF_HUB_CACHE=/ai/cache/huggingface/hub

# Install base packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    curl git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create AI directory
RUN mkdir -p /ai/models /ai/cache /ai/projects /ai/config /ai/logs /ai/venv

# Create Python venv
RUN python3 -m venv /ai/venv
ENV PATH="/ai/venv/bin:${PATH}"
ENV VIRTUAL_ENV="/ai/venv"

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Install PyTorch (CUDA 12.4)
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# Install AI libraries
RUN pip install transformers accelerate datasets \
    huggingface_hub sentencepiece tokenizers safetensors

# Install vLLM (optional, uncomment if GPU is recent enough)
# RUN pip install vllm

# Install llama-cpp-python (CPU by default; rebuild with GPU for CUDA)
RUN pip install llama-cpp-python

WORKDIR /ai

# Default command
CMD ["/bin/bash"]