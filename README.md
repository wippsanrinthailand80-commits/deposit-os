# Deposit OS

A **new** Linux distribution. Unlike a respin, Deposit OS is built **from the
kernel up**: we compile our own Linux kernel from upstream source and assemble
a minimal userspace, then package it as a single offline installer — the
**`.mlpds`** file.

> **Why another distro?** The goal is a lightweight OS for older hardware that
> still *runs Ubuntu software*. So Deposit OS is **glibc / `dpkg` / `apt`
> compatible** (Ubuntu `.deb` packages install and run) while being assembled,
> not cloned, from an Ubuntu install — and it ships its **own compiled kernel**.

## The one honest contradiction

A distro that *truly runs `.deb`/`apt`* must be Debian/Ubuntu **ABI-compatible**
(glibc, dpkg, apt). You cannot have "runs Ubuntu packages" *and* "zero Debian
components" at the same time. Deposit OS resolves this by:

| Layer        | Approach                                                         |
|--------------|------------------------------------------------------------------|
| **Kernel**   | Compiled by us from `kernel.org` source (`build/build-kernel.sh`)|
| **Userspace**| *Assembled* with `debootstrap` (not a clone of an Ubuntu install)|
| **Packages** | `dpkg` + `apt` included → Ubuntu `.deb`s install and run         |
| **Installer**| Self-contained `.mlpds` file (offline / "airplane mode")         |

If you later want a *pure* from-scratch userspace (no dpkg/apt, e.g. BusyBox +
musl), set `DEPOSIT_INSTALL_KERNEL_IN_ROOTFS` aside and drop the apt layer in
`build/config.sh` — but then Ubuntu package support is lost. This trade-off is
intentional and documented here.

## What is a `.mlpds` file?

`.mlpds` = **M**eta-installer / **L**ightweight **P**ackage **D**istribution
**S**et. It is a **general installation file** the system recognises by extension
and can install *various things* with one command:

- `os`      — a full Deposit OS image
- `app`     — an application installed into an existing system
- `driver`  — a kernel module / hardware driver pack
- `bundle`  — a config or asset pack (dotfiles, fonts, themes…)

It is a `tar.xz` containing a `manifest.json`, the payload (`rootfs/` or
`rootfs.squashfs`), an `installer/install.sh`, and `config/defaults.json`.
See [`.mlpds/spec.md`](.mlpds/spec.md) for the full format.

## Build & install (local)

```bash
# 1) compile the kernel from source
sudo bash build/build-kernel.sh --deps      # install build deps (apt)
sudo bash build/build-kernel.sh

# 2) assemble the apt-compatible userspace
sudo apt-get install -y debootstrap
sudo bash build/build-rootfs.sh build/output/rootfs

# 3) package a .mlpds installer (self-contained, offline)
sudo bash tools/mlpds create \
  --rootfs build/output/rootfs \
  --kernel build/output/kernel \
  --out deposit.os.mlpds --type os

# 4) install it
sudo bash tools/mlpds install deposit.os.mlpds --target /mnt/sda1 --boot
```

Other `mlpds` commands: `info`, `extract`, `launch` (QEMU), `build-kernel`,
`build-rootfs`.

## Testing

- **Fast / offline** (no network, no real compile): `sudo bash tests/test_mlpds.sh`
  exercises `create` / `info` / `extract` / `install` against a synthetic rootfs.
- **Full** (kernel compile + real rootfs + packaged `.mlpds`): the GitHub Actions
  workflow in `.github/workflows/ci.yml` does this on every push/PR.

## Layout

```
build/
  config.sh                 distro identity + build configuration
  build-kernel.sh           compile Linux kernel from source
  build-rootfs.sh           assemble apt/.deb-compatible userspace
tools/
  mlpds                     the installer tool (create/info/extract/install/launch)
  mlpds-installer/installer/install.sh   installer payload shipped in every .mlpds
.mlpds/spec.md              the .mlpds file format specification
tests/test_mlpds.sh         offline unit/integration tests for the tool
```

## License

MIT (or your choice) — see repo for details.
