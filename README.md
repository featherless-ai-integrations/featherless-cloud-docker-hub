# Featherless Cloud AMD images

Opinionated development images for the Featherless GPU cloud, targeting AMD
Instinct MI325X. Each image layers SSH, [uv](https://docs.astral.sh/uv/),
and JupyterLab over an AMD-maintained ROCm image.

| Target | AMD base | Output image |
| --- | --- | --- |
| `pytorch` | `rocm/pytorch` | `rocm-pytorch` |
| `sgl-dev` | `rocm/sgl-dev` | `rocm-sgl-dev` |
| `vllm` | `rocm/vllm` | `rocm-vllm` |

Each output has a dedicated Docker Hub Autobuild Dockerfile:

```text
rocm-pytorch/Dockerfile
rocm-sgl/Dockerfile
rocm-vllm/Dockerfile
```

Configure each Docker Hub build rule with **Build context `/`** and its matching
**Dockerfile location** above. The root context is required because every image
copies the shared `scripts/featherless-init` lifecycle script. Suggested Docker
Hub repositories are `rocm-pytorch`, `rocm-sgl`, and `rocm-vllm`.

All Dockerfiles are generated from the canonical `templates/rocm.Dockerfile`;
only the base image and OCI description differ. After changing the common image
layer or an upstream default, regenerate and verify them with:

```bash
./scripts/render-dockerfiles
./scripts/render-dockerfiles --check
```

The exact upstream images and immutable AMD64 digests are centralized in
`versions.env`. MI300X and
MI325X happen to share the `gfx942` ISA, but this repository deliberately treats
them as separate deployment targets. An explicitly `mi300x`-only upstream tag is
rejected. AMD uses `mi30x` for some release artifacts spanning the gfx942 family;
those and generic `gfx94X`/CDNA artifacts may be used only after validation on
physical MI325X hardware. Generated Dockerfiles consume digest-pinned references.

## Build

Build all variants:

```bash
VERSION=local REGISTRY=featherless docker buildx bake --load
```

Build one variant or override an upstream image:

```bash
docker buildx bake pytorch --load
BASE_PYTORCH=rocm/pytorch@sha256:... docker buildx bake pytorch --load
```

Images are `linux/amd64`. GitHub Actions builds all pull requests without
publishing. Pushes to `main`, version tags, and manual dispatches publish each
repository to Docker Hub with a complete stack-version tag and immutable
`sha-<commit>` tag. No `latest`, `stable`, or partially versioned aliases are
published. Each matrix entry runs on a separate GitHub-hosted Ubuntu runner, so
the three large ROCm builds do not share a runner or its local storage.

Configure the GitHub repository with:

- Secret `DOCKERHUB_USERNAME` — account allowed to push the three repositories.
- Secret `DOCKERHUB_TOKEN` — Docker Hub access token, not an account password.

The current pinned version tags are derived from `versions.env`:

| Repository | Complete stack-version tag |
| --- | --- |
| `rocm-pytorch` | `rocm7.14-ubuntu24.04-py3.12-pytorch2.12.0` |
| `rocm-sgl` | `sglang0.5.17-rocm7.2.0-mi30x-20260819` |
| `rocm-vllm` | `rocm7.14.0-ubuntu24.04-py3.14-pytorch2.11.0-vllm0.23.0` |

## Run on an MI325X host

ROCm containers need `/dev/kfd`, `/dev/dri`, the video group, and generous shared
memory. The included Compose configuration supplies these:

```bash
export IMAGE=featherlesscloud/rocm-pytorch:rocm7.14-ubuntu24.04-py3.12-pytorch2.12.0
export SSH_PUBLIC_KEY="$(< ~/.ssh/id_ed25519.pub)"
export JUPYTER_TOKEN="$(openssl rand -hex 24)"
docker compose up -d
```

SSH is then available on port 2222 as user `cloud`. To also expose JupyterLab
on port 8888, set `ENABLE_JUPYTER=true`; persisted notebooks live in the
`workspace` volume.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `ENABLE_SSH` | `true` | Start OpenSSH (`true/false`, `1/0`, `yes/no`) |
| `SSH_PORT` | `22` | SSH port inside the container |
| `SSH_PUBLIC_KEY` | empty | Public key installed for `CLOUD_USER` |
| `SSH_PASSWORD` | empty | Enables password login when non-empty |
| `SSH_USERS_FILE` | empty | Enables file-based multi-user SSH provisioning |
| `SSH_AUTHORIZED_KEYS_DIR` | empty | Directory containing one public-key file per user |
| `SSH_LOGIN_GROUP` | `featherless-ssh` | Login allowlist group in file-based mode |
| `ENABLE_JUPYTER` | `false` | Start JupyterLab |
| `REQUIRE_MI325X` | `true` | Require `/dev/kfd` and verify MI325X with `rocm-smi` |
| `JUPYTER_PORT` | `8888` | Jupyter port inside the container |
| `JUPYTER_TOKEN` | empty | Jupyter access token |
| `JUPYTER_PASSWORD` | empty | Jupyter password hash (not plain text) |
| `JUPYTER_ROOT_DIR` | `/workspace` | Directory exposed by Jupyter |
| `CLOUD_USER` | `cloud` | Runtime user for SSH and Jupyter |

If neither Jupyter credential is set, authentication is disabled and a warning is
logged. Do that only behind a trusted network. Prefer `SSH_PUBLIC_KEY` over
`SSH_PASSWORD`; environment variables can be visible through container tooling.

SSH is enabled and Jupyter is disabled by default. Run one service by passing
`run ssh` or `run jupyter`; `run all` explicitly starts both. The `ENABLE_SSH`
and `ENABLE_JUPYTER` variables control services when using the default `run`
command. Passing any other command replaces the launcher:

```bash
docker run --rm -it --device=/dev/kfd --device=/dev/dri \
  featherlesscloud/rocm-pytorch:rocm7.14-ubuntu24.04-py3.12-pytorch2.12.0 bash
```

### File-based SSH accounts

Setting `SSH_USERS_FILE` switches SSH from the single `CLOUD_USER` mode to
file-based multi-user provisioning. The users file has one entry per line:

```text
# username:uid:gid:shell
alice:10001:10001:/bin/bash
bob:10002:10002:/bin/bash
```

For each account, provide a public-key file named exactly after the username:

```text
/etc/featherless/ssh/authorized_keys/alice
/etc/featherless/ssh/authorized_keys/bob
```

Run with both inputs mounted read-only:

```bash
docker run --rm \
  -e SSH_USERS_FILE=/etc/featherless/ssh/users.conf \
  -e SSH_AUTHORIZED_KEYS_DIR=/etc/featherless/ssh/authorized_keys \
  -v ./ssh/users.conf:/etc/featherless/ssh/users.conf:ro \
  -v ./ssh/authorized_keys:/etc/featherless/ssh/authorized_keys:ro \
  IMAGE
```

In this mode password authentication is always disabled, accounts are restricted
through `AllowGroups featherless-ssh`, and `SSH_PASSWORD` is rejected. Internal
private keys remain on SSH Piper; these mounted files contain public keys only.

The MI325X guard runs for `serve`, not for arbitrary commands, so images can be
inspected in CI without a GPU. Set `REQUIRE_MI325X=false` only for CPU-side smoke
tests; it is not a supported production deployment mode.

## Install on an existing Debian/Ubuntu system

The same entrypoint is also the standard standalone installer and service
supervisor. `start` installs any missing component before launching the selected
service set:

```bash
sudo SSH_PUBLIC_KEY="$(< ~/.ssh/id_ed25519.pub)" \
  JUPYTER_TOKEN="change-me" CLOUD_USER="$USER" \
  ./scripts/featherless-init start all

# Or start only one service:
sudo CLOUD_USER="$USER" SSH_PUBLIC_KEY="$(< ~/.ssh/id_ed25519.pub)" \
  ./scripts/featherless-init start ssh
sudo CLOUD_USER="$USER" JUPYTER_TOKEN="change-me" \
  ./scripts/featherless-init start jupyter
```

`start` and `install` require `apt-get`, root (or `sudo`), and internet access if
anything is missing. `run` never installs packages and is used by the container.
For a long-running host deployment, wrap `run all` in a systemd unit. The script intentionally does
not install ROCm drivers; those belong on the GPU host and must match the cloud's
validated ROCm stack.

## Validate

Fast checks do not pull the multi-gigabyte ROCm bases:

```bash
bash -n scripts/featherless-init
bats tests/init.bats
docker buildx bake --print
```

On an ARM64 development machine, test the complete add-on layer natively with
Podman. This substitutes a small Debian base while executing the same Dockerfile,
installer, user creation, and entrypoint setup:

```bash
./scripts/smoke-build

# Test a Docker Hub-specific Dockerfile:
SMOKE_DOCKERFILE=rocm-pytorch/Dockerfile ./scripts/smoke-build
```

Set `CONTAINER_ENGINE=docker` to use Docker instead. The smoke build validates
the portable add-on layer; final ROCm images still need an AMD64 build and an
MI325X runtime test before release.
