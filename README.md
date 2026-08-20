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

The exact upstream images are centralized in `docker-bake.hcl`. MI300X and
MI325X happen to share the `gfx942` ISA, but this repository deliberately treats
them as separate deployment targets. An upstream tag containing `mi300x` or the
ambiguous `mi30x` family name is rejected at build time. AMD images with generic
`gfx94X`/CDNA support may be used only after validation on physical MI325X
hardware. Pin release builds to the validated immutable digest.

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

Images are `linux/amd64`; the GitHub Actions workflow builds pull requests and
publishes `edge` or version-tagged images to GHCR from the default branch/tags.
It intentionally uses a high-disk, self-hosted x86_64 runner because the three
ROCm bases are too large for typical hosted-runner disks.

## Run on an MI325X host

ROCm containers need `/dev/kfd`, `/dev/dri`, the video group, and generous shared
memory. The included Compose configuration supplies these:

```bash
export IMAGE=ghcr.io/featherless-ai/rocm-pytorch:edge
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
  ghcr.io/featherless-ai/rocm-pytorch:edge bash
```

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
