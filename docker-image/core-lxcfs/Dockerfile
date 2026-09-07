# syntax=docker/dockerfile:1.7
# Generated from templates/core-lxcfs.Dockerfile; run scripts/render-dockerfiles.
ARG BASE_IMAGE=ubuntu:24.04@sha256:1e0a86e57d247923571b75e0aaf48a1449cf8c543d51fb3e07a4a7d7bfa79316
FROM ${BASE_IMAGE}
LABEL org.opencontainers.image.source="https://github.com/featherless-ai/featherless-cloud-docker-hub" \
      org.opencontainers.image.description="Featherless Cloud LXCFS node service"
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       lxcfs=5.0.4-1 fuse3 util-linux coreutils ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/lib/lxcfs \
    && /usr/bin/lxcfs --version
# Host access and mount propagation must be granted by the platform manifest.
# No automatic unmount or restart logic; consumers may hold existing mounts.
USER root
ENTRYPOINT ["/usr/bin/lxcfs"]
CMD ["-f", "--enable-cfs", "/var/lib/lxcfs"]
