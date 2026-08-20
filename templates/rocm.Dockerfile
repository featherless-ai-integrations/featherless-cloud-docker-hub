# syntax=docker/dockerfile:1.7
# Generated from templates/rocm.Dockerfile; run scripts/render-dockerfiles.
ARG BASE_IMAGE=@@BASE_IMAGE@@
FROM ${BASE_IMAGE}
ARG BASE_IMAGE
ARG CLOUD_USER=cloud
ARG CLOUD_UID=1000
ARG CLOUD_GID=1000
ARG CREATE_NEW_USER=false

LABEL org.opencontainers.image.source="https://github.com/featherless-ai/featherless-cloud-docker-hub" \
      org.opencontainers.image.description="@@DESCRIPTION@@" \
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
    PATH=/usr/local/bin:${PATH}

COPY scripts/featherless-init /usr/local/bin/featherless-init
RUN chmod 0755 /usr/local/bin/featherless-init \
    && case "${BASE_IMAGE}" in *mi300x*) echo "Refusing an MI300X-specific base for an MI325X image: ${BASE_IMAGE}" >&2; exit 1;; esac \
    && /usr/local/bin/featherless-init install \
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
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/featherless-init"]
CMD ["run"]
