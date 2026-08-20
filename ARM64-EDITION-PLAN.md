# Deposit OS — ARM64 Laptop Edition (Plan)

Status: **planned (Phase 1)**. This document is the agreed plan; implementation
has not started.

Goal: a **separate ARM64 edition** that reuses the x86_64 userspace/UX 1:1 and
adds laptop-specific code. Artifacts attach to the **same `continuous` release**.

## Scope (decided)
One ARM64 edition covering (Phase 1) **ACPI ARM64 laptops — Qualcomm Snapdragon
X (X1E) + generic ACPI** — and (Phase 2) **Apple Silicon** via a downstream
Asahi kernel. Target: maximum performance from ARM (full CPU-freq/CPPC; best-effort
GPU/Wi-Fi, deepened iteratively).

The userspace is architecture-agnostic, so **Thai, security (AppArmor/ClamAV/ufw),
Samsung-style quick menu, Turbo, file manager, and the `.mlpds`/AQA package
manager are reused unchanged.**

## Phase 1 — ACPI ARM64 (Snapdragon X + generic)
### config.sh (`build/config.sh`)
- Add `DEPOSIT_EDITION` (x86_64 | arm64) + SoC selection.
- Arch/mirror handling already present (`DEPOSIT_ARCH`, ports mirror,
  debootstrap arch mapping at lines 24-102) — extend, do not rewrite.

### Kernel (`build/build-kernel.sh` + new fragment)
- New `kernel-fragments/deposit-arm64-laptop.cfg`:
  - ACPI + EFI stub, `PCI_HOST_GENERIC`, NVMe, USB-DWC3, `INTERCONNECT_QCOM_*`,
    `PINCTRL_SC8280XP`/`X1E`, `PHY_QCOM_*`, `DRM_MSM` + panel/eDP/DP,
    `ATH12K` (Wi-Fi), QCOM PMIC/type-c/battery.
  - **Performance:** `CPU_FREQ`, `ACPI_CPPC_CPUFREQ`, `ENERGY_MODEL`, schedutil.
  - Fallbacks: `FB_SIMPLE`, `DRM_SIMPLEDRM`.
- `build-kernel.sh` selects fragment by edition/SoC and sets
  `DEPOSIT_KERNEL_ARCH=arm64` + `CROSS_COMPILE=aarch64-linux-gnu-`
  (plumbing already at lines 67-72). Add `gcc-aarch64-linux-gnu` to deps.
- Move the current x86-only inline config block (lines 85-225:
  `CONFIG_X86_*`, `SERIO_I8042`, `ATA_PIIX`, `FB_VESA`, `VGA_CONSOLE`, the
  `arch/x86/boot/bzImage` copy) into `kernel-fragments/deposit-x86.cfg` so it no
  longer pollutes the arm64 build. `image_name` already yields
  `arch/arm64/boot/Image`.

### Rootfs (`build/build-rootfs.sh`)
- When target arch ≠ host arch: copy `qemu-aarch64-static` into the chroot and
  enable `binfmt_misc` before the `chroot` stages (lines 44-49, 84+).
- Add `linux-firmware` (+ QCOM firmware) and `grub-efi-arm64`.
- Arch-parameterize the Chrome AQA URL (line 141 is amd64-only).
- All tools/themes/Thai/security remain unchanged.

### ISO (`ci/make-iso.sh`)
- Arch-parameterize grub packages (`grub-efi-arm64`, EFI-only — no `grub-pc`),
  `console=` (`ttyAMA0` for QEMU `virt`), and output name →
  `deposit-os-arm64.iso`. Host grub bin: `grub-efi-arm64-bin`.

### Installer (`tools/deposit-install`)
- `uname -m` detect: arm64 → `grub-install --target=arm64-efi` only (skip
  `i386-pc`, lines 60-62).

### New ARM code
- "Performance mode" toggle reusing the Turbo concept (CPPC
  `schedutil`↔`performance`) exposed in the quick menu; optional SoC
  thermal/battery readout.

### CI — `ci-arm64.yml` (new, separate workflow, ≤4 jobs to respect the cap)
- `tool-tests` (reuse, arch-agnostic) → `build-kernel-arm64` (cross,
  **per-arch** cache key) → `build-rootfs-arm64` (cross) →
  `package-and-live-arm64` (arm64 ISO + `qemu-system-aarch64 -M virt -bios
  QEMU_EFI.fd` boot-check).
- Attaches `deposit-os-arm64.iso` (+ arm64 `.mlpds`) to the same `continuous`
  release via the existing `ci/publish-release.sh`.

## Phase 2 — Apple Silicon (later)
- Separate **downstream Asahi kernel** track + `m1n1`/U-Boot boot path. Mainline
  6.6.58 cannot drive the Apple GPU; this is intentionally deferred.

## Known limits (accepted)
- Adreno X1 / ath12k support on 6.6.58 is partial → v1 may boot the desktop via
  `simpledrm`/EFI framebuffer with best-effort GPU/Wi-Fi, then iterate.
- CPPC / CPU-frequency scaling is what actually delivers "high performance from
  ARM" and is reliably available.

## Implementation order (Phase 1)
1. `config.sh` edition/SoC flags.
2. `kernel-fragments/deposit-arm64-laptop.cfg` + split x86 block; wire
   `build-kernel.sh` cross-compile.
3. `build-rootfs.sh` cross-build (`qemu-aarch64-static`) + firmware + grub-efi-arm64.
4. `ci/make-iso.sh` arch-parameterization; `tools/deposit-install` arch-detect.
5. ARM performance-mode code in the quick menu.
6. `ci-arm64.yml` workflow + docs update (`ROADMAP.md`).
7. Trigger the arm64 run; verify boot + screenshot.
