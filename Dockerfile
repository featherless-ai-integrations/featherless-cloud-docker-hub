# syntax=docker/dockerfile:1.7
# Generated from templates/rocm.Dockerfile; run scripts/render-dockerfiles.
ARG BASE_IMAGE=rocm/pytorch:latest
FROM ${BASE_IMAGE}
ARG BASE_IMAGE
ARG CLOUD_USER=cloud
ARG CLOUD_UID=1000
ARG CLOUD_GID=1000

LABEL org.opencontainers.image.source="https://github.com/featherless-ai/featherless-cloud-docker-hub" \
      org.opencontainers.image.description="Featherless AI ROCm development image for AMD Instinct MI325X" \
      com.featherless.gpu.arch="gfx942" \
      com.featherless.gpu.model="AMD Instinct MI325X"

ENV DEBIAN_FRONTEND=noninteractive \
    CLOUD_USER=${CLOUD_USER} \
    SSH_PORT=22 \
    JUPYTER_PORT=8888 \
    ENABLE_SSH=true \
    ENABLE_JUPYTER=false \
    REQUIRE_MI325X=true \
    JUPYTER_ROOT_DIR=/workspace \
    PATH=/usr/local/bin:${PATH}

COPY scripts/featherless-init /usr/local/bin/featherless-init
RUN chmod 0755 /usr/local/bin/featherless-init \
    && case "${BASE_IMAGE}" in *mi300x*|*mi30x*) echo "Refusing MI300X/MI30X base for an MI325X image: ${BASE_IMAGE}" >&2; exit 1;; esac \
    && /usr/local/bin/featherless-init install \
    && if ! getent group "${CLOUD_GID}" >/dev/null; then groupadd --gid "${CLOUD_GID}" "${CLOUD_USER}"; fi \
    && if ! id "${CLOUD_USER}" >/dev/null 2>&1; then useradd --uid "${CLOUD_UID}" --gid "${CLOUD_GID}" --create-home --shell /bin/bash "${CLOUD_USER}"; fi \
    && mkdir -p /workspace "/home/${CLOUD_USER}/.ssh" \
    && chown -R "${CLOUD_USER}:${CLOUD_GID}" /workspace "/home/${CLOUD_USER}" \
    && chmod 0700 "/home/${CLOUD_USER}/.ssh"

WORKDIR /workspace
EXPOSE 22 8888
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/featherless-init"]
CMD ["run"]
