# Featherless Cloud images

Opinionated development images for the Featherless GPU cloud, targeting AMD
Instinct MI325X. The ROCm images layer SSH, [uv](https://docs.astral.sh/uv/),
JupyterLab, and a standard monitoring/troubleshooting toolkit over an
AMD-maintained ROCm image. `nvtop` provides the AMD equivalent of NVIDIA's
interactive GPU process monitor; `amd-smi monitor` remains available for
ROCm-native telemetry.

| Target | Base | Output image |
| --- | --- | --- |
| `pytorch` | `rocm/pytorch` | `rocm-pytorch` |
| `sgl-dev` | `rocm/sgl-dev` | `rocm-sgl` |
| `vllm` | `rocm/vllm` | `rocm-vllm` |
| `axolotl` | `rocm/pytorch` + pinned Axolotl | `rocm-axolotl` |
| `core-lxcfs` | Ubuntu 24.04 | `core-lxcfs` |

Each output has a dedicated Docker Hub Autobuild Dockerfile:

```text
docker-image/rocm-pytorch/Dockerfile
docker-image/rocm-sgl/Dockerfile
docker-image/rocm-vllm/Dockerfile
docker-image/rocm-axolotl/Dockerfile
docker-image/core-lxcfs/Dockerfile
```

Configure each Docker Hub build rule with **Build context `/`** and its matching
**Dockerfile location** above. The root context is required because the ROCm images
copy the shared `scripts/featherless-init` lifecycle script. Suggested Docker
Hub repositories are `rocm-pytorch`, `rocm-sgl`, `rocm-vllm`, `rocm-axolotl`,
and `core-lxcfs`.

ROCm Dockerfiles are generated from `templates/rocm.Dockerfile`; Axolotl also
appends `templates/axolotl.Dockerfile`. `core-lxcfs` uses
`templates/core-lxcfs.Dockerfile`. The root Dockerfile remains
a compatibility entrypoint for the PyTorch image. After changing the common image
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
docker build --file docker-image/rocm-pytorch/Dockerfile \
  --build-arg BASE_IMAGE=rocm/pytorch@sha256:... \
  --tag localhost/rocm-pytorch:override .
```

Images are `linux/amd64`. GitHub Actions builds all pull requests without
publishing. Pushes to `main`, version tags, and manual dispatches publish each
repository to Docker Hub with a complete stack-version tag and immutable
`sha-<commit>` tag. No `latest`, `stable`, or partially versioned aliases are
published. Each matrix entry runs on a separate GitHub-hosted Ubuntu runner, so
the four large ROCm builds do not share a runner or its local storage.

Configure the GitHub repository with:

- Secret `DOCKERHUB_USERNAME` — account allowed to push all five repositories.
- Secret `DOCKERHUB_TOKEN` — Docker Hub access token, not an account password.
- Optional repository variable `CREATE_NEW_USER=true` — create `CLOUD_USER`
  instead of retaining the upstream image's current account.

The current pinned version tags are derived from `versions.env`:

| Repository | Complete stack-version tag |
| --- | --- |
| `rocm-pytorch` | `rocm7.14-ubuntu24.04-py3.12-pytorch2.12.0` |
| `rocm-sgl` | `sglang0.5.17-rocm7.2.0-mi30x-20260819` |
| `rocm-vllm` | `rocm7.14.0-ubuntu24.04-py3.14-pytorch2.11.0-vllm0.23.0` |
| `rocm-axolotl` | `axolotl0.18.0-rocm7.14-ubuntu24.04-py3.12-pytorch2.12.0` |
| `core-lxcfs` | `5.0.4-ubuntu24.04` |

ROCm bases come from AMD's `rocm/*` Docker Hub namespace; `core-lxcfs` uses
a digest-pinned official Ubuntu base. The
resulting Featherless images are published to the separate `featherlesscloud/*`
namespace.

Image jobs pull the digest-pinned source and, except for Axolotl, the existing
complete-version Featherless image when available. The latter is passed to
`docker build --cache-from`; inline cache metadata travels inside the normal
built image rather than a separate cache artifact or floating `buildcache` tag.
Unchanged package-installation layers can then be reused.

The Axolotl job uses a standard hosted runner, removes unused Android/.NET/Haskell
and cached hosted toolchains before pulling, skips the second image pull, and
imports inline cache metadata directly from the published image through
BuildKit's registry cache importer. Native extensions compile with `MAX_JOBS=2`
to conserve RAM. This makes cold builds slower while still reusing unchanged
published layers. The AMD base alone occupies about 28 GB unpacked; runner
image changes and dependency growth can still require a larger runner. The job
checks the real entrypoint and Axolotl metadata before publishing
`featherlesscloud/rocm-axolotl:<complete-stack-version>` and
`featherlesscloud/rocm-axolotl:sha-<commit>`. CPU CI does not certify GPU kernels.

## Axolotl training workspace

The Axolotl image preserves the shared MI325X guard, SSH/Jupyter lifecycle, and
`featherless-init` entrypoint. Boot does not download models, start training, or
compile extensions. Its independent base digest and Axolotl release commit are
pinned in `versions.env`; Python dependencies and native source artifacts are
hash-locked under `docker-image/rocm-axolotl/`.

The stack includes ROCm PyTorch 2.12, Axolotl 0.18.0, Transformers/PEFT/TRL,
Liger's Triton kernels, CK FlashAttention 2.8.3 compiled for `gfx942`,
bitsandbytes 0.50.2 with its ROCm 7.14 native library, and DeepSpeed 0.18.6 with
prebuilt CPUAdam/FusedAdam. The ROCm development SDK is initialized at `/opt/rocm`
for custom HIP extensions. Build-time checks reject replacement of inherited
Torch/vision/audio/Triton binaries and NVIDIA runtime dependencies.
`/opt/axolotl-build-info.json` records the installed versions and build choices.

To resolve an intentional dependency update (using uv 0.9.30):

```bash
uv pip compile docker-image/rocm-axolotl/requirements.in \
  --excludes docker-image/rocm-axolotl/base-packages.txt \
  --python-version 3.12 --python-platform x86_64-unknown-linux-gnu \
  --generate-hashes --no-annotate --no-header \
  --output-file docker-image/rocm-axolotl/requirements.lock
```

Excluded base packages must not also be direct requirements: uv retains explicit
root requirements even when excluded transitively. Rebuild and rerun MI325X
acceptance after changing a lock, source commit, patch, or base.

```bash
docker build --file docker-image/rocm-axolotl/Dockerfile \
  --build-arg MAX_JOBS=8 --tag featherlesscloud/rocm-axolotl:local .
```

Choose compiler parallelism for the builder's RAM; this does not limit training.
Run the image through the same Compose configuration below, changing `IMAGE` to
the complete `rocm-axolotl` tag. Inside the container:

```bash
axolotl-doctor --gpu-check
axolotl-workspace /workspace/axolotl
cd /workspace/axolotl
axolotl preprocess lora-bf16.yaml
axolotl train lora-bf16.yaml --launcher python
```

`axolotl-workspace` copies bundled recipes only on request and preserves existing
files and symlinks. Initialization downloads nothing; preprocessing/training
downloads the public model and dataset revisions named in each recipe. Run from
the copied directory so relative datasets, outputs, reward modules, and DeepSpeed
configuration paths resolve. HF, Triton, and TorchInductor caches default to
`/workspace/.cache`; the mounted workspace must be writable by the training user.

Recipes cover BF16 LoRA, NF4 QLoRA, full fine-tuning, FSDP2, DeepSpeed ZeRO-2,
long-context SFT, DPO, GRPO, and vision-language LoRA. Read their comments and
adapt model, data, sequence length, batch size, and launch topology before a real
run. They are short training examples, not throughput-tuned production jobs.
Model-specific fused-kernel support still applies.

Default GRPO uses Transformers generation. Local vLLM, CUDA-only xFormers, and
NVIDIA-specific Liger backends are deliberately not installed. The remote-vLLM
recipe is conditional: TRL also needs its compatible local vLLM communicator,
which is not part of this image. A remote server alone does not enable it.
Do not install a CUDA vLLM wheel into the protected ROCm environment.

Explicit offline acceptance commands use tiny random local Llama weights and
synthetic data, without tokens or network downloads:

```bash
axolotl-doctor --metadata-only                  # CPU-safe inventory
verify-axolotl --output /workspace/check-single # new directory; retained logs
verify-axolotl --mode multi --gpus 2 \
  --output /workspace/check-multi
```

Single mode checks LoRA, real NF4 QLoRA, full training with FlashAttention/Liger,
checkpoint resume, merge/reload/generation, and fused forward/backward numerical
agreement. Multi mode checks RCCL collectives and FSDP2 training. Use `--checks`
to select workloads and `--help` for deadlines and artifact retention. These are
correctness checks, not performance benchmarks; passing them does not validate
every bundled model, trainer, optimizer, or multi-node topology.

The pinned 0.18.0 stack's exported image passed the complete offline suite on
physical MI325X hardware: single-GPU training plus two-GPU RCCL/FSDP2. All eight
visible devices passed the doctor's matmul/backward check. Additional smoke
workloads verified CPUAdam/FusedAdam updates against PyTorch AdamW, TorchCodec
CPU video decoding, workspace preservation, and the real tini/Featherless
entrypoint. Local validation used PRoot over the unpacked image, not a Docker
daemon or a live GitHub Actions publication. DPO/GRPO/VLM recipes, eight-way
distributed training, and multi-node execution were not exercised by that run.

## LXCFS node-service image

`core-lxcfs` is a platform infrastructure image, not a customer GPU template.
It contains LXCFS, FUSE tools, `nsenter`, `mountpoint`, and `timeout`; it has no
ROCm, SSH, or Jupyter dependency. The Ubuntu base digest and LXCFS package version
are pinned in `versions.env`. Other apt dependencies are resolved during build;
deploy the resulting image by digest.

```bash
VERSION=5.0.4-ubuntu24.04 REGISTRY=featherlesscloud \
  docker buildx bake core-lxcfs --load
docker run --rm featherlesscloud/core-lxcfs:5.0.4-ubuntu24.04 --version
```

The release workflow includes this image and checks its executable dependencies.
Publishing still requires a main-branch push, release tag, or manual workflow.
Building this image does not deploy LXCFS. The GPU Cloud repository owns the
DaemonSet at `deploy/lxcfs/daemonset.yaml`; supply its `LXCFS_IMAGE` using the
published digest. Privileges and host mounts belong in that platform manifest.
Do not run a second daemon over an existing LXCFS mount. Validate daemon lifecycle
and CPU/memory views on a disposable worker before attaching customer Pods.

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
| `FEATHERLESS_AUTHORIZED_KEYS_PATH` | empty | Platform-managed `authorized_keys` file (set by Featherless GPU Cloud); read on every login in addition to `~/.ssh/authorized_keys` |
| `FEATHERLESS_GPU_COUNT` | detected | Platform-assigned GPU count used by the login banner |
| `FEATHERLESS_COST_PER_HOUR_USD` | empty | Human-readable hourly instance cost used by the login banner |
| `FEATHERLESS_STORAGE_JSON` | empty | Customer-visible storage names, capacities, and mount paths used by the login banner |
| `SSH_LOGIN_GROUP` | `featherless-ssh` | Login allowlist group in file-based mode |
| `ENABLE_JUPYTER` | `false` | Start JupyterLab |
| `REQUIRE_MI325X` | `true` | Require `/dev/kfd` and verify MI325X (PCI device `1002:74a5`, with `rocm-smi` fallback) |
| `JUPYTER_PORT` | `8888` | Jupyter port inside the container |
| `JUPYTER_TOKEN` | empty | Jupyter access token |
| `JUPYTER_PASSWORD` | empty | Jupyter password hash (not plain text) |
| `JUPYTER_ROOT_DIR` | `/workspace` | Directory exposed by Jupyter |
| `CLOUD_USER` | `cloud` | Runtime user for SSH and Jupyter |
| `CREATE_NEW_USER` | `false` | Create `CLOUD_USER`, its UID/GID, and home directory |

The login environment includes `/opt/venv/bin`, where the AMD base images
install PyTorch, `amd-smi`, and `rocm-smi`. Common interactive tools include
`btop`, `nvtop`, `htop`, `tmux`, `jq`, `lsof`, `strace`, network diagnostics,
and PCI/NUMA utilities.

Interactive login shells show a compact Featherless resource summary.
Non-interactive SSH commands do not emit the banner.

Commands supplied after the image name run alongside platform services. The
stable wrapper interface is `featherless-init run -- PROGRAM [ARG...]`. The
image entrypoint must remain intact so `featherless-init` can configure SSH,
start enabled services, supervise the custom command, and stop the remaining
processes when any supervised process exits. Future custom images must either
provide this compatibility entrypoint or use a platform-injected equivalent;
preserving an arbitrary image entrypoint cannot guarantee platform services.

If neither Jupyter credential is set, authentication is disabled and a warning is
logged. Do that only behind a trusted network. Prefer `SSH_PUBLIC_KEY` over
`SSH_PASSWORD`; environment variables can be visible through container tooling.

By default the build keeps the account already provided by the upstream image.
To create the configured cloud account instead, build with:

```bash
docker build --build-arg CREATE_NEW_USER=true \
  --file docker-image/rocm-pytorch/Dockerfile --tag my-image .
```

When disabled, the build skips `groupadd` and `useradd`, uses the current
account's passwd entry and home directory, and carries the mode into runtime.
If the current account is `root`,
SSH permits root by public key only (`PermitRootLogin prohibit-password`), while
password login remains unavailable for root. Jupyter receives `--allow-root` in
that case. The file-based multi-user mode still takes precedence when
`SSH_USERS_FILE` is defined.

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
Podman. This substitutes an Ubuntu 24.04 base while executing the same Dockerfile,
installer, user creation, and entrypoint setup:

```bash
./scripts/smoke-build

# Test a Docker Hub-specific Dockerfile:
SMOKE_DOCKERFILE=docker-image/rocm-pytorch/Dockerfile ./scripts/smoke-build
```

Set `CONTAINER_ENGINE=docker` to use Docker instead. The smoke build validates
the portable add-on layer; final ROCm images still need an AMD64 build and an
MI325X runtime test before release.
This Ubuntu-base substitution does not cover Axolotl's training extension:
build that target with its pinned AMD64 ROCm base and run `verify-axolotl` instead.
