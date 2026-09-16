# syntax=docker/dockerfile:1.7
# Generated from templates/rocm.Dockerfile; run scripts/render-dockerfiles.
ARG BASE_IMAGE=rocm/pytorch:rocm7.14_ubuntu24.04_py3.12_pytorch_release_2.12.0@sha256:c38eeda81d85f00fbe35d3d50ce42ce59c524e87d810624f4eb5c52fddb3b9ad
FROM ${BASE_IMAGE}
ARG BASE_IMAGE
ARG CLOUD_USER=cloud
ARG CLOUD_UID=1000
ARG CLOUD_GID=1000
ARG CREATE_NEW_USER=false

LABEL org.opencontainers.image.source="https://github.com/featherless-ai/featherless-cloud-docker-hub" \
      org.opencontainers.image.description="Featherless Cloud Axolotl ROCm training image for AMD Instinct MI325X" \
      com.featherless.gpu.arch="gfx942" \
      com.featherless.gpu.model="AMD Instinct MI325X"

ENV DEBIAN_FRONTEND=noninteractive \
    CLOUD_USER=${CLOUD_USER} \
    CREATE_NEW_USER=${CREATE_NEW_USER} \
    SSH_PORT=22 \
    JUPYTER_PORT=8888 \
    ENABLE_SSH=true \
    ENABLE_JUPYTER=false \
    REQUIRE_MI325X=true \
    SSH_USERS_FILE= \
    SSH_AUTHORIZED_KEYS_DIR= \
    SSH_LOGIN_GROUP=featherless-ssh \
    JUPYTER_ROOT_DIR=/workspace \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/usr/local/bin:${PATH}

COPY scripts/featherless-init /usr/local/bin/featherless-init
COPY scripts/featherless-login-banner /etc/profile.d/10-featherless-banner.sh
RUN chmod 0755 /usr/local/bin/featherless-init \
    && chmod 0644 /etc/profile.d/10-featherless-banner.sh \
    && case "${BASE_IMAGE}" in *mi300x*) echo "Refusing an MI300X-specific base for an MI325X image: ${BASE_IMAGE}" >&2; exit 1;; esac \
    && /usr/local/bin/featherless-init install \
    && printf '%s\n' 'export VIRTUAL_ENV=/opt/venv' 'export PATH=/opt/venv/bin:$PATH' \
         > /etc/profile.d/00-featherless-rocm.sh \
    && chmod 0644 /etc/profile.d/00-featherless-rocm.sh \
    && if [ "${CREATE_NEW_USER}" = true ]; then \
         existing_group="$(getent group | awk -F: -v gid="${CLOUD_GID}" '$3 == gid { print $1; exit }')"; \
         if [ -z "$existing_group" ]; then groupadd --gid "${CLOUD_GID}" "${CLOUD_USER}"; fi; \
         if ! id "${CLOUD_USER}" >/dev/null 2>&1; then useradd --uid "${CLOUD_UID}" --gid "${CLOUD_GID}" --create-home --shell /bin/bash "${CLOUD_USER}"; fi; \
         target_user="${CLOUD_USER}"; \
       else \
         target_user="$(id -un)"; \
       fi \
    && target_gid="$(id -g "$target_user")" \
    && target_home="$(getent passwd "$target_user" | cut -d: -f6)" \
    && mkdir -p /workspace "$target_home/.ssh" \
    && chown -R "$target_user:$target_gid" /workspace "$target_home/.ssh" \
    && chmod 0700 "$target_home/.ssh"

WORKDIR /workspace
EXPOSE 22 8888
# The launcher configures sshd and must start as root. Services drop to
# CLOUD_USER where appropriate after setup.
USER root
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/featherless-init"]
CMD ["run"]

# Axolotl-specific extension appended to the shared ROCm template by the renderer.
ARG AXOLOTL_COMMIT=2f5cb9da62a0fe763a1ddeb7798fc9acb2f4a417
# FlashAttention is a pinned wheel; only the smaller DeepSpeed build uses MAX_JOBS.
ARG MAX_JOBS=8
LABEL org.opencontainers.image.source="https://github.com/featherless-ai-integrations/featherless-cloud-docker-hub" \
      com.featherless.axolotl.version="0.18.0" \
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
