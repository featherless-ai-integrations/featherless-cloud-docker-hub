# syntax=docker/dockerfile:1.7
# Generated from templates/rocm.Dockerfile; run scripts/render-dockerfiles.
ARG BASE_IMAGE=rocm/sgl-dev:v0.5.17-rocm720-mi30x-20260819@sha256:3d48aacbd9c445cc55e02ad1431cb5173a603baf17b6acf9e4378858f2d70aa3
FROM ${BASE_IMAGE}
ARG BASE_IMAGE
ARG CLOUD_USER=cloud
ARG CLOUD_UID=1000
ARG CLOUD_GID=1000

LABEL org.opencontainers.image.source="https://github.com/featherless-ai/featherless-cloud-docker-hub" \
      org.opencontainers.image.description="Featherless AI ROCm SGLang image for AMD Instinct MI325X" \
      com.featherless.gpu.arch="gfx942" \
      com.featherless.gpu.model="AMD Instinct MI325X"

ENV DEBIAN_FRONTEND=noninteractive \
    CLOUD_USER=${CLOUD_USER} \
    SSH_PORT=22 \
    JUPYTER_PORT=8888 \
    ENABLE_SSH=true \
    ENABLE_JUPYTER=false \
    REQUIRE_MI325X=true \
    SSH_USERS_FILE= \
    SSH_AUTHORIZED_KEYS_DIR= \
    SSH_LOGIN_GROUP=featherless-ssh \
    JUPYTER_ROOT_DIR=/workspace \
    PATH=/usr/local/bin:${PATH}

COPY scripts/featherless-init /usr/local/bin/featherless-init
RUN chmod 0755 /usr/local/bin/featherless-init \
    && case "${BASE_IMAGE}" in *mi300x*) echo "Refusing an MI300X-specific base for an MI325X image: ${BASE_IMAGE}" >&2; exit 1;; esac \
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
