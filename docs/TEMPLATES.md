# Template manifests

Each image collection owns a `template.yaml` manifest. An `icon.svg` tile
may sit next to it and is picked up automatically. Featherless GPU Cloud
discovers every `template.yaml` in this repository and imports it through
the admin console's **Import from repo** action, so the published Docker
Hub tags become customer-facing template cards without any manual digest
entry.

The complete schema is enforced by the GPU Cloud API; this document is the
authoring reference. Keep the two in sync.

## Layout

```
rocm-pytorch/
  Dockerfile
  icon.svg        # optional 64×64 tile shown on the catalog card and admin list
  template.yaml   # one entry per published image tag
```

The file carries image-level identity and shared defaults. The `versions`
list has one entry per image tag (stack version). Each entry becomes its
own catalog card, and all entries of a file share the `image` repository
and the icon.

## File-level fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schemaVersion` | integer | Yes | Must be `1`. The API rejects any other value. |
| `image` | string | Yes | Docker Hub repository only (e.g. `featherlesscloud/rocm-pytorch`). No tag, no digest. |
| `description` | string | No | Shared by every entry of this file. |
| `cpuCores` | integer | No | 1–256. Default `8`. |
| `memoryGiB` | integer | No | 1–2048. Default `64`. |
| `startupCommand` | string | No | Default `""`, which runs the image entrypoint `featherless-init run`. |
| `environment` | list of `{name, value}` | No | Default `[]`. |
| `bootstrapVersion` | string | No | Default `"1"`. |
| `versions` | list | Yes | At least one entry, one per published image tag. |

## Version entry fields

Each entry is one catalog card.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | 1–160 characters, **unique across every entry in every file**. The app name plus the stack version (e.g. `PyTorch (ROCm) 2.12.0`) — it is the card title. Include `(ROCm)` to disambiguate from future CUDA builds. |
| `tag` | string | Yes | 1–255 characters. The Docker Hub tag of this image; it must exist at import time and is unique within the file. |
| `rocmVersion` | string | Yes | `N.N` or `N.N.N`, e.g. `"7.14"`. |
| `cpuCores` | integer | No | Overrides the file-level value. |
| `memoryGiB` | integer | No | Overrides the file-level value. |
| `startupCommand` | string | No | Overrides the file-level value. |
| `environment` | list of `{name, value}` | No | Overrides the file-level value. |
| `bootstrapVersion` | string | No | Overrides the file-level value. |

Unknown keys are ignored, so additive fields can be introduced without
bumping the schema version.

## Example

`rocm-pytorch/template.yaml`:

```yaml
schemaVersion: 1
description: AMD ROCm PyTorch on MI325X with SSH and JupyterLab.
image: featherlesscloud/rocm-pytorch
cpuCores: 8
memoryGiB: 64
startupCommand: ""
environment: []
bootstrapVersion: "1"
versions:
  - name: PyTorch (ROCm) 2.12.0
    tag: rocm7.14-ubuntu24.04-py3.12-pytorch2.12.0
    rocmVersion: "7.14"
```

## Adding a second version

When a new stack version ships, add another entry to the **same** file — no
new file, no icon change. Both entries import as two cards that share the
icon:

```yaml
versions:
  - name: PyTorch (ROCm) 2.12.0
    tag: rocm7.14-ubuntu24.04-py3.12-pytorch2.12.0
    rocmVersion: "7.14"
  - name: PyTorch (ROCm) 2.13.0
    tag: rocm7.14.1-ubuntu24.04-py3.12-pytorch2.13.0
    rocmVersion: "7.14.1"
```

## Import semantics

The API validates every file — schema, icon, and tag digest — **before
writing anything**. A single error rejects the whole import with HTTP 422
and a per-file list of fields; fix the file and re-import.

When the import runs clean:

- Digests are resolved from each entry's tag on Docker Hub at import time
  and stored immutable.
- Each entry auto-publishes as its own template card (no review step).
- Re-importing the same tag with the same digest is a no-op.
- Re-importing the same tag with a **new digest** appends a version to the
  same line; the card shows the new digest.
- Adding a new entry creates a new line (new card) while existing lines keep
  showing.
- A `name` collision with an existing template fails that entry during the
  import phase; the other entries still import.
- Template metadata (name, description, icon) of matched lines is synced on
  every import, so renaming a line or editing its icon takes effect on the
  next import.

## Schema versions

- **`1`** — exactly the field set documented here.
- Policy: additive field changes keep `schemaVersion: 1` and are documented
  here. Breaking changes bump to `2` and require an API update that accepts
  both versions.
- The API rejects unsupported versions with `Unsupported schemaVersion: N`.
