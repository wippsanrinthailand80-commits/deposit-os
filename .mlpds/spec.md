# The `.mlpds` installer format

`mlpds` = **M**eta-installer / **L**ightweight **P**ackage **D**istribution **S**et.

A `.mlpds` file is a **general installation file** that Deposit OS recognises by
its extension. It is a single, self-contained, offline-capable archive used to
install *various things* onto a machine — a full OS image, an application, a
driver, or a configuration/asset bundle. The system registers the `.mlpds`
handler so any such file can be opened and installed with one command:

```
mlpds install path/to/thing.mlpds [--target ...]
```

This is the "airplane mode" ideal: everything needed to install is inside the
file — no network required at install time.

## Container

- A `.mlpds` file is a POSIX **`tar`** stream, compressed with **`xz`**
  (`application/x-xz` inside `tar`). Extension: `.mlpds`.
- It can be inspected/extracted with any `tar -xf file.mlpds`.
- A tool (`tools/mlpds`) understands the *layout* below and drives install.

## Layout (top level of the archive)

```
manifest.json            # REQUIRED. metadata + integrity (see schema)
rootfs/                  # the assembled distro tree (kind="tree")
  ...                    #   OR
rootfs.squashfs          # read-only compressed rootfs (kind="squashfs", optional)
installer/
  install.sh             # REQUIRED. idempotent installer payload
  boot/
    grub.cfg             # bootloader fragment (used when --boot is given)
    extlinux.conf        # alternative simple bootloader config
config/
  defaults.json          # default install answers (hostname, user, locale...)
```

Exactly one of `rootfs/` or `rootfs.squashfs` must be present, matching
`manifest.json -> rootfs.kind`. For `type` other than `os` (e.g. `app`,
`driver`, `bundle`) the rootfs payload is optional and `installer/install.sh`
decides what to place where.

### `type` (what the file installs)

| type      | meaning                                                        |
|-----------|----------------------------------------------------------------|
| `os`      | a full Deposit OS image (requires a `rootfs/` or `rootfs.squashfs`) |
| `app`     | an application installed into an existing system (e.g. `/opt`) |
| `driver`  | a kernel module / hardware driver pack                         |
| `bundle`  | a configuration or asset pack (dotfiles, fonts, themes...)    |

The `mlpds` tool writes `type` into the manifest and the system file handler
routes the file to the correct install path automatically.

## `manifest.json` schema

```json
{
  "format": "mlpds",
  "format_version": "1.0",
  "type": "os",
  "created": "2026-08-19T00:00:00Z",
  "builder": "deposit mlpds 1.0",
  "distro": {
    "name": "deposit",
    "pretty": "Deposit OS",
    "version": "0.1.0",
    "id": "deposit",
    "id_like": "ubuntu debian"
  },
  "target": {
    "arch": "x86_64",
    "suite": "noble",
    "components": "main,universe"
  },
  "kernel": {
    "version": "6.6.58",
    "image": "boot/vmlinuz-6.6.58",
    "modules": "lib/modules/6.6.58"
  },
  "rootfs": {
    "kind": "tree" | "squashfs",
    "checksum_sha256": "<sha256 of the rootfs payload tar>"
  },
  "packages": [ "bash", "dpkg", "apt", "..." ]
}
```

Notes:
- `rootfs.checksum_sha256` is the SHA-256 of the *rootfs payload* (the `rootfs/`
  directory tar, or the `rootfs.squashfs` blob) before it was packed. The
  installer verifies it before writing to disk.
- `packages` lists the key packages that define Ubuntu/.deb compatibility
  (informational; the real manifest lives inside the rootfs `dpkg` database).
- `format_version` is currently `1.0`. The `mlpds` tool rejects unknown majors.

## Install flow

1. `mlpds extract file.mlpds` (or the tool works in a temp dir).
2. Verify `manifest.json` and the rootfs checksum.
3. `installer/install.sh --target <dir|device> --rootfs <path> [--boot]`
   copies the rootfs, writes `/etc/hostname`, `/etc/fstab`, a default user,
   locale and timezone from `config/defaults.json`, then (with `--boot`)
   installs a bootloader config (`extlinux` or `grub`) using the bundled kernel.

## Why a new format?

- **Self-contained / offline**: the kernel + rootfs + installer ship together.
- **Verifiable**: manifest + checksum catch corruption.
- **Tool-friendly**: one command to build (`mlpds build`), inspect (`mlpds info`),
  and install (`mlpds install`).
