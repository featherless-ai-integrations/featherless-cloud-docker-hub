# syntax=docker/dockerfile:1.7
# Generated from templates/featherless-init.Dockerfile; run scripts/render-dockerfiles.
ARG BASE_IMAGE=@@BASE_IMAGE@@
FROM ${BASE_IMAGE} AS tini
RUN apk add --no-cache tini-static file \
    && file /sbin/tini-static | grep -q 'statically linked'

# Instances mount this image read-only at /run/featherless/init. Nothing in it
# may depend on the libraries of the image it is mounted into.
FROM scratch
LABEL org.opencontainers.image.source="https://github.com/featherless-ai/featherless-cloud-docker-hub" \
      org.opencontainers.image.description="@@DESCRIPTION@@"
COPY --from=tini /sbin/tini-static /tini
COPY --chmod=0755 featherless-init/featherless-init featherless-init/services /
COPY --chmod=0644 featherless-init/profile.d/ /profile.d/
COPY --chmod=0644 scripts/featherless-login-banner /banner
