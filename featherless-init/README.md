# featherless-init (instance init)

A custom image starts with its own entrypoint and usually has no sshd and no tmux, so platform SSH
and the shared tmux session would otherwise work only on our template images. Featherless Cloud
mounts this image read-only into every instance container and runs it in front of the instance's
own command: it starts the SSH side in the background, then becomes that command, which keeps PID
1, its signals and its exit code. Nothing it starts writes to the container's output.

This is not the template images' entrypoint (`scripts/featherless-init`); it works in any image.

## Contract

| Path | What |
|---|---|
| `/run/featherless/init` | This image, mounted read-only |
| `/run/featherless/init/featherless-init -- <command...>` | The container command: the instance's command, or the image's ENTRYPOINT and CMD |
| `/run/featherless/init/banner` | The login banner, `scripts/featherless-login-banner`, the same one template images bake in |
| `/run/featherless/state` | Written at runtime: `init.log`, the generated `sshd_config`, the host key, the sshd PID file, `started` (the banner's uptime in images without procps) |
| `/etc/profile.d/00-featherless.sh` | Linked to `profile.d/featherless.sh` at start (image volumes mount only directories), named to run before the image's own profile scripts |
| `FEATHERLESS_AUTHORIZED_KEYS_PATH` | The platform-managed keys file sshd reads on every login |

The container needs `/bin/sh` and root. With no command, `tini` becomes PID 1 and keeps the
container up.

## What runs

```
PID 1  <instance command>
└─ tini -s                      adopts and reaps whatever SSH sessions leave behind
   └─ services
      └─ sshd -D -p 22          restarted 5 s after it exits
```

`services` installs `openssh-server` and `tmux` with the image's package manager (`apt-get`, `dnf`,
`microdnf`, `yum`, `apk` or `zypper`) when either is missing, adding only what is missing and never
upgrading what the image already has. The instance command does not wait for it. A busy package
manager (the instance command's own `apt-get`, say) is retried with backoff; each attempt has a
time limit. Without a package manager or the packages, SSH stays unavailable and `init.log` says
why.

sshd runs on port 22 with its own configuration:
- **Keys:** only the keys in `FEATHERLESS_AUTHORIZED_KEYS_PATH`, read as `nobody`, or as root in
  images without `nobody`.
- **Logins:** root with keys only; no passwords.
- **SFTP:** served in-process (`internal-sftp`).
- **Environment:** sessions get the container's environment on one `SetEnv` line.
- **PAM:** `UsePAM` only when sshd is built with PAM.
- **Penalties:** `PerSourcePenalties no` where supported, since every connection comes from the
  SSH gateway.
- **Locked root:** when sshd has no PAM and root's password field is locked (`!`), it is set to
  `*`, which still allows no password but lets key logins through.

`profile.d/featherless.sh` runs in login shells, which sshd starts only for interactive logins. It
restores the container's `PATH` (`/etc/profile` resets it on most distributions) and attaches the
login to the tmux session `default`, creating it if needed. It runs before the image's other profile
scripts, so what they print appears inside the session. It then shows the banner once per session, in
the window that created it, or on every login that stays a plain shell; template images skip their
own copy. A terminal the image has no terminfo entry for, such as Ghostty's `xterm-ghostty`,
attaches as `xterm-256color`. `touch ~/.no_auto_tmux` opts out; without tmux, or if tmux cannot
start, the login stays a plain shell.

## Build and release

`docker-image/featherless-init/Dockerfile` is rendered from `templates/featherless-init.Dockerfile`.
The release workflow publishes `featherlesscloud/featherless-init:$FEATHERLESS_INIT_IMAGE_TAG` and
`:sha-<commit>`. Bump `FEATHERLESS_INIT_IMAGE_TAG` in `versions.env` on every change: instances pin
the tag, and nodes keep the image they already pulled for it.

```sh
docker build --platform linux/amd64 -f docker-image/featherless-init/Dockerfile -t featherless-init:dev .
```

## Lab

`test/lab.sh [image...]` builds the image for the local architecture and runs it from a Docker image
mount in each base image, with a client container standing in for the SSH gateway. It needs
Docker 28 or later and network access for package installs.

`test/k8s-lab.sh <image reference> [image...]` runs the same checks on a Kubernetes cluster, with the
image mounted as an image volume under the instance Pod's security settings, in a namespace
`featherless-init-lab` that it deletes afterwards. With no images it adds scenarios: an image that
runs `apt-get` at startup, no command, `wait` in bash, and an s6-overlay image.
`PULL_SECRET_FROM=<namespace>` copies that namespace's `docker-hub` pull secret for a private image.

The `featherless-init` workflow lints the scripts and runs `test/lab.sh` on Ubuntu, Debian,
Rocky and Alpine for every change to the image. Both labs exit non-zero when a check fails, and
both check:
- the instance command is PID 1 and owns the container's output;
- SSH login and environment;
- the `default` tmux session and the opt-out;
- `PATH` in login shells;
- scp;
- sshd restarts;
- zombie reaping;
- SIGTERM.
