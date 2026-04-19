# ============================================================
# Stage 1: Builder — install dependencies with uv
# ============================================================
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_TORCH_BACKEND=cpu \
    UV_EXTRA_INDEX_URL=https://download.pytorch.org/whl/cpu

WORKDIR /app

# Install system dependencies needed at build time (docling, faiss, sentence-transformers)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    poppler-utils \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Two-pass uv sync for maximum layer caching:
# Pass 1 — install only project dependencies (no project source) so this layer is
#           cached as long as pyproject.toml/uv.lock don't change.
COPY pyproject.toml ./
RUN touch uv.lock
COPY uv.lock* ./
RUN uv sync --no-dev --no-install-project

# Pass 2 — install the project itself (invalidated only when source changes)
COPY README.md ./
COPY app/ ./app/
RUN uv sync --no-dev

# uv.lock resolves torchvision from PyPI (macOS-generated lock), but the PyPI
# wheel is compiled against CUDA-capable torch ABI which is incompatible with
# torch+cpu. Force-reinstall the CPU build from the pytorch WHL index.
RUN uv pip install \
    --index-url https://download.pytorch.org/whl/cpu \
    "torch==2.6.0+cpu" "torchvision==0.21.0+cpu"

# Pre-download the cross-encoder model weights at build time so there is
# no HuggingFace network call at container startup. Uses snapshot_download
# (pure HTTP, no torch/torchvision init) to avoid ABI issues at build time.
RUN uv run python -c "\
from huggingface_hub import snapshot_download; \
snapshot_download('cross-encoder/ms-marco-MiniLM-L-6-v2')"


# ============================================================
# Stage 2: Runtime — lean image with only what is needed
# ============================================================
FROM python:3.12-slim-bookworm AS runtime

# System deps required at runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    poppler-utils \
    libgomp1 \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Non-root user for security
RUN useradd --create-home --shell /bin/bash appuser

WORKDIR /app

# Copy the fully-installed virtualenv from the builder stage
COPY --from=builder --chown=appuser:appuser /app/.venv /app/.venv
COPY --from=builder --chown=appuser:appuser /app/app /app/app

# Copy the pre-downloaded HuggingFace model cache
COPY --from=builder --chown=appuser:appuser /root/.cache /home/appuser/.cache

# Ensure the venv's Python/scripts are on PATH
ENV PATH="/app/.venv/bin:$PATH" \
    HF_HOME="/home/appuser/.cache/huggingface"

# torchvision/_meta_registrations.py registers abstract (fake) op implementations
# used exclusively by torch.compile() / FakeTensorMode. Our app does not use
# torch.compile(), so these registrations are unnecessary. In CPU-only builds,
# torchvision._C.so is a plain shared library loaded lazily by torchvision.ops,
# but _meta_registrations is imported before ops in __init__.py, so the
# torchvision::nms op is not yet in the dispatch table when register_fake runs.
# Emptying the file eliminates the import-order crash without any runtime impact.
RUN echo "# disabled: not needed for inference-only CPU deployment" \
    > /app/.venv/lib/python3.12/site-packages/torchvision/_meta_registrations.py

# Verify critical imports work in this runtime environment — fails the build
# with the actual error if torch or sentence-transformers can't be loaded.
RUN /app/.venv/bin/python -c "\
import sys; \
import torch; print('torch', torch.__version__); \
import torchvision; print('torchvision', torchvision.__version__); \
from transformers import PreTrainedModel; print('transformers OK'); \
from sentence_transformers import CrossEncoder; print('CrossEncoder OK')"

# Create uploads directory (ephemeral — vectors persist in Qdrant Cloud)
RUN mkdir -p /var/app/uploads && chown appuser:appuser /var/app/uploads

USER appuser

EXPOSE 8000

# --workers 1: sentence-transformers and faiss are not fork-safe.
# Scale horizontally by adding more Beanstalk instances instead.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
