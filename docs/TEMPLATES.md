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

The file carries the app's identity (`name`, `image`, icon) and shared
defaults. The `versions` list has one entry per published stack version,
keyed by its image tag. The catalog shows one card per
app+version entry, and all entries of a file share the `image` repository
and the icon.

## File-level fields

| Field | Type | Required | Description |
| `schemaVersion` | integer | Yes | Must be `1`. The API rejects any other value. |
| `name` | string | Yes | 1–160 characters, **unique across every file**. The app name (e.g. `PyTorch (ROCm)`) — it is the card title prefix. Include `(ROCm)` to disambiguate from future CUDA builds. |
| `image` | string | Yes | Docker Hub repository only (e.g. `featherlesscloud/rocm-pytorch`). No tag, no digest. The file's identity; imports match existing templates by this value. |
| `description` | string | No | Shared by every entry of this file. |
| `cpuCores` | integer | No | 1–256. Default `8`. |
| `memoryGiB` | integer | No | 1–2048. Default `64`. |
| `startupCommand` | string | No | Default `""`, which runs the image entrypoint `featherless-init run`. |
| `environment` | list of `{name, value}` | No | Default `[]`. |
| `bootstrapVersion` | string | No | Default `"1"`. |
| `versions` | list | Yes | At least one entry, one per published image tag. |

## Version entry fields

Each entry is one catalog card, titled `<file name> <version>`
(e.g. `PyTorch (ROCm) 2.12.0`).

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | string | Yes | 1–64 characters. The stack version (e.g. `2.12.0`); unique within the file. |
| `tag` | string | Yes | 1–255 characters. The Docker Hub tag of this image; it must exist at import time and is unique within the file. The tag is the identity key: re-importing the same tag updates the existing entry in place. |
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
name: PyTorch (ROCm)
description: AMD ROCm PyTorch on MI325X with SSH and JupyterLab.
image: featherlesscloud/rocm-pytorch
cpuCores: 8
memoryGiB: 64
startupCommand: ""
environment: []
bootstrapVersion: "1"
versions:
  - version: "2.12.0"
    tag: rocm7.14-ubuntu24.04-py3.12-pytorch2.12.0
    rocmVersion: "7.14"
```

## Adding a second version

When a new stack version ships, add another entry to the **same** file — no
new file, no icon change. Both entries import as two cards that share the
icon:

```yaml
versions:
  - version: "2.12.0"
    tag: rocm7.14-ubuntu24.04-py3.12-pytorch2.12.0
    rocmVersion: "7.14"
  - version: "2.13.0"
    tag: rocm7.14.1-ubuntu24.04-py3.12-pytorch2.13.0
    rocmVersion: "7.14.1"
```

## Import semantics

The API validates every file — schema, icon, and tag digest — **before
writing anything**. A single error rejects the whole import with HTTP 422
and a per-file list of fields; fix the file and re-import.

One file maps to one template row, matched by its `image` repository. Each
version entry maps to one version row, keyed by its `tag`.

When the import runs clean:

- Digests are resolved from each entry's tag on Docker Hub at import time
  and stored immutable.
- Each entry auto-publishes (no review step) and becomes one catalog card
  titled `<name> <version>`.
- Re-importing the same tag with the same digest is a no-op.
- Re-importing the same tag with a **new digest** updates that entry's
  digest and metadata in place; the card keeps showing.
- Adding a new entry (new tag) creates a new version row and a new card
  while existing cards keep showing.
- A file whose `name` collides with an existing template of a **different**
  image fails that file during the import phase; the other files still
  import.
- Template metadata (name, description, icon) is synced from the file on
  every import, so renaming the app or editing its icon takes effect on the
  next import.

## Schema versions

- **`1`** — exactly the field set documented here.
- Policy: additive field changes keep `schemaVersion: 1` and are documented
  here. Breaking changes bump to `2` and require an API update that accepts
  both versions.
- The API rejects unsupported versions with `Unsupported schemaVersion: N`.
