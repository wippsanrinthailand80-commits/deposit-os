# Deposit OS

**A Linux distribution built from the kernel up** — we compile our own Linux
kernel from upstream source and assemble a minimal, apt-compatible userspace.
Deposit OS runs standard Ubuntu/Debian `.deb` packages (via `apt`/`dpkg`) and
adds its own packaging format (`.mlpds`) and installer (`aqa`).

- **Own kernel**: Linux 6.6.58 (LTS), configured from `defconfig` plus
  `build/kernel-fragments/deposit-broad.cfg`.
- **Lean userspace**: `debootstrap` of Ubuntu 24.04 (Noble), glibc-based,
  systemd init — ABI-compatible with the Debian/Ubuntu package pool.
- **`.mlpds` packages + `aqa` installer**: fast, unified package management
  with native `.mlpds` support and direct `.deb`/`apt` compatibility.
- **Turbo mode**: one command flips the CPU/GPU into maximum-performance
  (`performance` governor + GPU power profile) with a spinning/fade transition FX.
- **Security**: AppArmor (in the kernel), ClamAV antivirus, and a firewall
  (`ufw`) — surfaced in the quick menu.
- **Samsung-style quick menu**: a floating, toggleable panel
  (`Super+Q`) with Wi‑Fi, Airplane, Turbo, LAN toggles, Brightness **and
  Volume** sliders, a Security section, and a drive-centric file manager.
- **Thai language** support out of the box, plus a rounded, branded aesthetic.

## Screenshots

| Boot screen | Desktop + quick menu | Turbo transition | `.mlpds` info | Tool demo |
|-------------|---------------------|------------------|---------------|-----------|
| ![boot](docs/assets/boot.png) | ![desktop](docs/assets/desktop.png) | ![turbo](docs/assets/turbo.png) | ![mlpds](docs/assets/mlpds.png) | ![demo](docs/assets/tool-demo.png) |

(Generated automatically in CI and embedded in each Actions run Summary.)

## Architecture

| Layer        | Choice |
|--------------|--------|
| Kernel       | Linux 6.6.58, built from kernel.org source (`build/build-kernel.sh`) |
| C library    | glibc (via Ubuntu Noble debootstrap) |
| Init system  | systemd |
| Packaging    | `dpkg`/`apt` + Deposit `.mlpds` (`tools/mlpds`) |
| Installer    | `aqa` (`tools/aqa`) |
| Desktop      | XFCE4 + LightDM, autologin |
| Live media   | GRUB2 + `live-boot` + SquashFS ISO (`ci/make-iso.sh`) |
| Security     | AppArmor (kernel) · ClamAV · ufw |

## Quick Start

### Build with GitHub Actions (recommended)

Push to `main` (or open a PR). The CI pipeline:

1. **mlpds tool + scripts + demo** — unit tests and a tool-demo screenshot.
2. **build-kernel** — compiles the kernel (cached between runs).
3. **build-rootfs** — debootstraps the userspace.
4. **package .mlpds + live boot** — packages the OS as `.mlpds`, boots it under
   QEMU, captures screenshots, builds the **ISO**, and publishes a continuous
   release.

The bootable ISO is attached to the **continuous** GitHub Release and also
uploaded as the `deposit-os.iso` workflow artifact.

### Build locally

```bash
bash build/build-kernel.sh          # -> build/output/kernel
bash build/build-rootfs.sh          # -> build/output/rootfs
# Raw disk image (boots via QEMU -kernel):
bash ci/make-disk.sh build/output/rootfs build/output/kernel build/output/deposit-disk.img 4096
# Bootable ISO (BIOS + UEFI):
bash ci/make-iso.sh  build/output/rootfs build/output/kernel build/output/deposit-os.iso
```

Boot the ISO:

```bash
qemu-system-x86_64 -m 2048 -smp 2 -cpu max -cdrom build/output/deposit-os.iso -boot d
```

## Package management quick reference

```bash
aqa install <URL>          # install from a .deb or .mlpds URL
aqa install chrome         # install a pre-bundled offline package
aqa install steam
aqa install turbo
aqa list                   # list installed packages
```

## Specifications (minimum hardware)

| Resource     | Minimum | Recommended |
|--------------|---------|-------------|
| Architecture | x86_64 (amd64) | x86_64; ARM64 is *test-only, not yet supported* |
| RAM          | 1 GB    | 2 GB+ |
| Storage      | 8 GB    | 16 GB+ |
| Graphics     | VGA / any (boots headless too) | GPU with open drivers for Turbo |
| Network      | optional | Ethernet or Wi‑Fi |

## Project layout

```
build/                 kernel + rootfs build scripts and config
tools/                 aqa, mlpds, deposit-turbo, deposit-quickmenu, deposit-files, deposit-av, deposit-turbo-fx
ci/                    make-disk.sh, make-iso.sh, live-boot.sh, demo + render helpers
docs/assets/           screenshots used in this README
```

## License

GPL-3.0 — see [LICENSE](LICENSE). The OS bundles many upstream components
(Linux kernel, glibc, XFCE, …) each under their own licenses.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
