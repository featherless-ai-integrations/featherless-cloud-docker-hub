
# Axolotl-specific extension appended to the shared ROCm template by the renderer.
ARG AXOLOTL_COMMIT=@@AXOLOTL_COMMIT@@
# FlashAttention is a pinned wheel; only the smaller DeepSpeed build uses MAX_JOBS.
ARG MAX_JOBS=8
LABEL org.opencontainers.image.source="https://github.com/featherless-ai-integrations/featherless-cloud-docker-hub" \
      com.featherless.axolotl.version="@@AXOLOTL_VERSION@@" \
      com.featherless.axolotl.revision="${AXOLOTL_COMMIT}" \
      com.featherless.gpu.compatibility="mi325x-only"

ENV AXOLOTL_DO_NOT_TRACK=1 \
    HF_HOME=/workspace/.cache/huggingface \
    TRITON_CACHE_DIR=/workspace/.cache/triton \
    TORCHINDUCTOR_CACHE_DIR=/workspace/.cache/torchinductor

# Native training extensions and the CPU audio/video decoding stack.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         build-essential cmake ffmpeg git-lfs libaio-dev libsndfile1 ninja-build \
    && git lfs install --system \
    && rm -rf /var/lib/apt/lists/*

COPY docker-image/rocm-axolotl/*.lock docker-image/rocm-axolotl/axolotl-rocm.patch /opt/featherless/axolotl/
COPY scripts/install-axolotl /tmp/install-axolotl
RUN MAX_JOBS="${MAX_JOBS}" AXOLOTL_COMMIT="${AXOLOTL_COMMIT}" bash /tmp/install-axolotl \
    && rm /tmp/install-axolotl

ENV ROCM_HOME=/opt/rocm ROCM_PATH=/opt/rocm HIP_PATH=/opt/rocm
# SSH login shells do not retain arbitrary container environment variables.
RUN printf '%s\n' \
      'export ROCM_HOME=/opt/rocm ROCM_PATH=/opt/rocm HIP_PATH=/opt/rocm' \
      'export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"' \
      'export TRITON_CACHE_DIR="${TRITON_CACHE_DIR:-/workspace/.cache/triton}"' \
      'export TORCHINDUCTOR_CACHE_DIR="${TORCHINDUCTOR_CACHE_DIR:-/workspace/.cache/torchinductor}"' \
      'export AXOLOTL_DO_NOT_TRACK="${AXOLOTL_DO_NOT_TRACK:-1}"' \
      > /etc/profile.d/20-featherless-axolotl.sh \
    && chmod 0644 /etc/profile.d/20-featherless-axolotl.sh \
    && rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub

COPY docker-image/rocm-axolotl/recipes/ /opt/axolotl-recipes/
COPY scripts/axolotl-workspace scripts/axolotl-doctor scripts/verify-axolotl /usr/local/bin/
RUN chmod 0755 /usr/local/bin/axolotl-workspace /usr/local/bin/axolotl-doctor /usr/local/bin/verify-axolotl

# Keep tini/featherless-init and CMD run from the shared layer. No training,
# model downloads, credential prompts, or compilation is started at container boot.
