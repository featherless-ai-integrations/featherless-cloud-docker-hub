# featherless-init (instance init)

A custom image starts with its own entrypoint and usually has no sshd and no tmux. Featherless
Cloud mounts this image read-only into every custom-image and template instance and runs it in
front of the instance's own command: it starts the SSH side in the background, then becomes that
command, which keeps PID 1, its signals and its exit code. Nothing it starts writes to the
container's output. SSH, tmux and the login banner then behave the same in every instance.

This is not the template images' entrypoint (`scripts/featherless-init`), which still runs after
it: their template files set `bootstrapVersion: "2"`, and the launcher sees this init at
`/run/featherless/init/featherless-init`, leaves SSH to it and keeps the MI325X check, JupyterLab
and the startup command.

## Contract

| Path | What |
|---|---|
| `/run/featherless/init` | This image, mounted read-only |
| `/run/featherless/init/featherless-init -- <command...>` | The container command: the instance's command, or the image's ENTRYPOINT and CMD |
| `/run/featherless/init/sh` | Static busybox, featherless-init's interpreter, so it starts in images without a shell |
| `/run/featherless/init/bin/tmux` | Static tmux (`FEATHERLESS_INIT_TMUX_VERSION`), the only file in `bin/` |
| `/run/featherless/init/terminfo` | Terminal definitions (`xterm-256color`, `tmux-256color`, `screen-256color` and a few basics) for images that ship none |
| `/run/featherless/init/banner` | The login banner, `scripts/featherless-login-banner`, the same one template images bake in |
| `/run/featherless/state` | Written at runtime: `init.log`, the generated `sshd_config`, the host key, the sshd PID file |
| `/etc/profile.d/00-featherless.sh` | Linked to `profile.d/featherless.sh` at start (image volumes mount only directories), named to run before the image's own profile scripts |
| `FEATHERLESS_AUTHORIZED_KEYS_PATH` | The platform-managed keys file sshd reads on every login |

An image without `/bin/sh`, or one that runs as a non-root user, runs only its command, exactly as
without featherless-init: there is nothing for SSH to log in to, or no way to set it up. With no
command, `tini` becomes PID 1 and keeps the container up.

## What runs

```
PID 1  <instance command>
└─ tini -s                      adopts and reaps whatever SSH sessions leave behind
   └─ services
      └─ sshd -D -p 22          restarted 5 s after it exits
```

tmux is bundled, so it works from the container's first second in any image with `/bin/sh`, as any
user, with or without a package manager. Every client of a tmux server must be the server's
version, so whatever starts or attaches tmux puts `bin/` first on `PATH`: SSH sessions get it from
`services`, and the cluster agent's tmux commands set it themselves. Shells in tmux panes inherit
it, so `tmux` typed inside a session is the bundled one even when the image has its own.
`TERMINFO_DIRS` lists the usual system directories, then the bundled definitions.

`services` installs `openssh-server` with the image's package manager (`apt-get`, `dnf`,
`microdnf`, `yum`, `apk` or `zypper`) when it is missing, never upgrading what the image already
has. The instance command does not wait for it. A busy package
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
scripts, so what they print appears inside the session. It then shows the banner in every new shell
of the session, or on a login that stays a plain shell; template images skip their own copy. A terminal the image has no terminfo entry for, such as Ghostty's `xterm-ghostty`,
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

The `featherless-init` workflow lints the scripts and runs `test/lab.sh` on Ubuntu, Debian,
Rocky, Fedora, UBI, openSUSE and Alpine for every change to the image or the template launcher, and
`test/lab.sh template` on a template image built on Ubuntu. It exits non-zero when a check fails,
and checks:
- the instance command is PID 1 and owns the container's output;
- SSH login and environment;
- the `default` tmux session runs the bundled tmux, and the opt-out;
- the bundled tmux without a package manager and as a non-root user;
- `PATH` in login shells;
- scp;
- sshd restarts;
- zombie reaping;
- SIGTERM;
- in a template image, that only this init's sshd runs, the launcher keeps the container up, and
  the banner shows once.
