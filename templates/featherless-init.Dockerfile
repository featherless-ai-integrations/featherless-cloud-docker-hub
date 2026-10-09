# syntax=docker/dockerfile:1.7
# Generated from templates/featherless-init.Dockerfile; run scripts/render-dockerfiles.
ARG BASE_IMAGE=@@BASE_IMAGE@@
FROM ${BASE_IMAGE} AS tini
RUN apk add --no-cache tini-static busybox-static file \
    && file /sbin/tini-static /bin/busybox.static | grep -c 'statically linked' | grep -qx 2

# tmux ships in the bundle, so every instance has the same tmux from its first
# second instead of after a package install, whatever the image's distribution.
FROM ${BASE_IMAGE} AS tmux
ARG TMUX_VERSION=@@TMUX_VERSION@@
RUN apk add --no-cache build-base bison pkgconf libevent-dev libevent-static ncurses-dev ncurses-static \
      ncurses-terminfo-base file
ADD --checksum=sha256:@@TMUX_SHA256@@ \
    https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz /src/
RUN tar -xzf /src/tmux-${TMUX_VERSION}.tar.gz -C /src \
    && cd /src/tmux-${TMUX_VERSION} \
    && ./configure --enable-static --with-TERM=tmux-256color \
    && make -j"$(nproc)" \
    && strip tmux \
    && file tmux | grep -q 'statically linked' \
    && mkdir -p /out/terminfo \
    && for entry in x/xterm x/xterm-256color t/tmux t/tmux-256color s/screen s/screen-256color l/linux v/vt100 d/dumb; do \
         mkdir -p "/out/terminfo/${entry%/*}" && cp "/etc/terminfo/$entry" "/out/terminfo/$entry"; \
       done

# Instances mount this image read-only at /run/featherless/init. Nothing in it
# may depend on the libraries of the image it is mounted into.
FROM scratch
LABEL org.opencontainers.image.source="https://github.com/featherless-ai/featherless-cloud-docker-hub" \
      org.opencontainers.image.description="@@DESCRIPTION@@"
COPY --from=tini /sbin/tini-static /tini
# featherless-init's interpreter, so it starts in images without a shell.
COPY --from=tini /bin/busybox.static /sh
# bin/ holds only tmux: it goes first on PATH in tmux panes and SSH sessions,
# so every tmux client matches the server's version.
COPY --from=tmux /src/tmux-@@TMUX_VERSION@@/tmux /bin/tmux
# Terminal definitions for images that ship none, read through TERMINFO_DIRS.
COPY --from=tmux /out/terminfo /terminfo
COPY --chmod=0755 featherless-init/featherless-init featherless-init/services /
COPY --chmod=0644 featherless-init/profile.d/ /profile.d/
COPY --chmod=0644 scripts/featherless-login-banner /banner
