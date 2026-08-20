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
  (`ufw`) — surfaced in the quick menu. `.mlpds` packages are GPG-signed and
  verified on install; `aqa` requires a sha256 for any web-sourced `.deb`, and
  `deposit-install` refuses to wipe the disk the OS is currently running from.
- **Samsung-style quick menu**: a floating, toggleable panel
  (`Super+Q`) with Wi‑Fi, Airplane, Turbo, LAN toggles, Brightness **and
  Volume** sliders, a Security section, and a **Settings** + **About** tile.
- **Settings hub**: a simple Samsung One UI / Android-hybrid settings app
  (gear icon) with Wi‑Fi/Airplane/Turbo toggles, Brightness/Volume sliders,
  and one-tap access to Security, Updates and About.
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

## Install to a disk (USB)

The ISO is a **live + installer** image. To put Deposit OS on real hardware:

1. Write the ISO to a USB stick (replace `sdX` with your stick):
   ```bash
   sudo dd if=build/output/deposit-os.iso of=/dev/sdX bs=4M status=progress; sync
   ```
2. Boot from the USB stick.
 3. From the live desktop, double-click **Install Deposit OS** (or run
    `sudo deposit-install /dev/sda` in a terminal). It will ask you to type
    `yes` to confirm the disk wipe before proceeding. It GPT-partitions the disk
    (ESP + ext4 root), copies the system, builds an initramfs, writes `/etc/fstab`
    and installs GRUB for both BIOS and UEFI.
4. Reboot into the installed disk.

## Releases

Each successful CI run publishes a rolling **continuous** GitHub Release that
attaches the bootable `deposit-os.iso` and the `deposit.os.mlpds` package. The
same artifacts are also uploaded to the workflow run.

## Package management quick reference

```bash
aqa install <URL>          # install from a .deb or .mlpds URL. A direct file URL
                           # (e.g. http://x/pkg.deb) is downloaded as-is; a page
                           # URL is scanned for .deb/.mlpds links. .mlpds are GPG
                           # verified. Arbitrary web .deb REQUIRE a checksum:
                           # append #sha256=<hash> to the URL (or pass it as the
                           # 2nd argument). --no-verify does NOT bypass this.
aqa install chrome         # curated app: installs on its registered sha256, or
aqa install steam          # with --no-verify when no checksum is registered
aqa install turbo          # (trusted source only)
aqa list                   # list installed packages
```

## Specifications (minimum hardware)

| Resource     | Minimum | Recommended |
|--------------|---------|-------------|
| Architecture | x86_64 (amd64) | x86_64; ARM64 is *test-only, not yet supported* ([port plan #1](https://github.com/wippsanrinthailand80-commits/deposit-os/issues/1)) |
| RAM          | 1 GB    | 2 GB+ |
| Storage      | 8 GB    | 16 GB+ |
| Graphics     | VGA / any (boots headless too) | GPU with open drivers for Turbo |
| Network      | optional | Ethernet or Wi‑Fi |

## Status & roadmap

Deposit OS is functional and reproducibly built in CI, but is still maturing:

- **Long-term stability** — not yet validated across a wide range of hardware.
- **Update path** — OS updates today rely on `apt` + `aqa`; a unified,
  user-centric updater is planned.
- **Hardware support** — the ~45 MB kernel aims for broad support but is not yet
  extensively field-tested. **ARM64** is tracked in
  [issue #1](https://github.com/wippsanrinthailand80-commits/deposit-os/issues/1).
- **UI/UX polish** — the full feature set exists (quick menu, Settings hub, Turbo
  FX); visual refinement continues.
- **Docs & support** — a user manual and built-in troubleshooting tool are still
  TODO.

## Project layout

```
build/                 kernel + rootfs build scripts and config
tools/                 aqa, mlpds, deposit-turbo, deposit-quickmenu, deposit-settings,
                       deposit-files, deposit-av, deposit-turbo-fx, deposit-security,
                       deposit-store, deposit-updater, deposit-oobe, deposit-install
ci/                    make-disk.sh, make-iso.sh, live-boot.sh, demo + render helpers
docs/assets/           screenshots used in this README
```

## License

GPL-3.0 — see [LICENSE](LICENSE). The OS bundles many upstream components
(Linux kernel, glibc, XFCE, …) each under their own licenses.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
