# syntax=docker/dockerfile:1.7
# Generated from templates/core-lxcfs.Dockerfile; run scripts/render-dockerfiles.
ARG BASE_IMAGE=@@BASE_IMAGE@@
FROM ${BASE_IMAGE}
LABEL org.opencontainers.image.source="https://github.com/featherless-ai/featherless-cloud-docker-hub" \
      org.opencontainers.image.description="@@DESCRIPTION@@"
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       lxcfs=@@LXCFS_PACKAGE_VERSION@@ fuse3 util-linux coreutils ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/lib/lxcfs \
    && /usr/bin/lxcfs --version
# Host access and mount propagation must be granted by the platform manifest.
# No automatic unmount or restart logic; consumers may hold existing mounts.
USER root
ENTRYPOINT ["/usr/bin/lxcfs"]
CMD ["-f", "--enable-cfs", "/var/lib/lxcfs"]
