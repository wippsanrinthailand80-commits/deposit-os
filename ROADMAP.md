# Deposit OS — Roadmap (Beta 0.1.1)

Where we are, and what is honestly still missing. This file is the
anti-vaporware contract: every claim here is checked against the tree.

## Shipped (Beta 0.1.1) — verified in-tree & CI

- **Kernel**: own Linux 6.6.58 from source; `broad` + `80m` fragments
  (KVM/VFIO, RDMA, CAN, EROFS/ZRAM, Thunderbolt, tracing, **Android Binder**
  for Waydroid). Fragment-signature guard so cached CI builds pick up config
  changes.
- **Userspace**: Noble debootstrap; runs jammy/focal binaries via pinned
  compat sonames (`deposit-compat`).
- **Packages**: `.deb`/apt · `.mlpds` (GPG) · `aqa` multi-format URL scanner
  with interactive picker · **both `.apk` kinds** (Android via Waydroid/adb,
  Alpine via static apk-tools into an isolated prefix) · **`.rpm` and Arch
  `.pkg.tar.zst`** via `deposit-pkg` isolated prefixes.
- **Windows layer**: Wine sandboxed (firejail/bwrap), SHA256 allowlist with
  no CLI bypass, Windows-style taskbar mode (`deposit-winmode`, Breeze-dark).
- **UI**: Andromeda purple-blue theme, quick menu (Super+Q), Settings hub,
  Turbo FX, Plymouth splash, compositor ON by default, dual release channels
  (`continuous` secure / `continuous-liveboot` auto-login media).
- **ARM64**: cross-compiled kernel + UEFI image built and QEMU-`virt`
  smoke-booted on every dispatch.
- **Bluetooth A2DP** audio profiles; Thai fonts + IBus typing.

## Known gaps — the honest list

| # | Gap | Class | Plan |
|---|-----|-------|------|
| 1 | Kernel not field-tested across real hardware | needs hardware | HW matrix program (below) |
| 2 | ARM64 is build/QEMU-proven, not laptop-proven | needs hardware | Pi5-UEFI + Snapdragon-X bring-up checklist |
| 3 | Updater still apt-centric UX | code (medium) | Updater v2 spec (below) |
| 4 | No A/B / atomic updates | design decision | btrfs-snapshot proposal (below) |
| 5 | Alpine prefix less hardened than deposit-win | code (small) | add `/etc/deposit/apk.conf` HASH_POLICY mirror of win.conf |
| 6 | Waydroid session friction | ✅ improved 0.1.1 | container auto-start via pkexec in `deposit-apk` |
| 7 | UI polish below commercial distros | ongoing | compositing ON now; animation/icon pass tracked below |
| 8 | No Thai manual for general users | docs | ✅ `docs/MANUAL_TH.md` shipped with 0.1.1 |

## Next slices (priority order)

### S1 — Updater v2 ("one button, everything")
Single window, four sections, one progress bar:
1. System (apt) — current behaviour kept.
2. Deposit apps (.mlpds/aqa) — refresh registry, upgrade installed set.
3. Runtimes — Wine prefix health check, Waydroid image update hint,
   Alpine prefix `apk upgrade`.
4. Firmware-ish — `fwupd` optional toggle.
Delta downloads later; never auto-reboot; changelog summary per section.
Non-goal: replacing apt — orchestrating it.

### S2 — Atomic/A-B updates (design decision needed)
Two viable routes:
- **A. btrfs snapshots** (recommended): installer switches root fs ext4→btrfs;
  pre-upgrade snapshot + GRUB "previous snapshot" entry = rollback in one
  reboot. Cost: installer change + ~1 GB disk overhead.
- **B. Image-based (ostree-like)**: true A/B partitions, atomic swap.
  Cost: new update infra + double storage; overkill until S1 exists.
Decision gate: after S1 ships and HW testing starts.

### S3 — Real-hardware test matrix
Recruit N machines per class: legacy BIOS laptop, UEFI laptop w/ NVIDIA,
Intel iGPU ultrabook, AMD APU desktop, Wi-Fi-only netbook, ARM: Pi5 (UEFI),
one Snapdragon-X device when accessible. Per machine: boot ISO → install →
OOBE → audio/Wi-Fi/BT/suspend/resume/Turbo/winmode/wine-smoke/apk-smoke →
file report template `docs/HW-REPORT-template.md`.

### S4 — Polish pass ("beautiful and smooth")
Compositor defaults done. Then: consistent 200ms ease animations (xfwm4 +
GTK), Papirus-Dark full-coverage audit, quick-menu spring animation,
window-rounded-corners everywhere, boot→login→desktop timing budget <20s.

### S5 — Hardening parity for apk/pkg prefixes
Mirror deposit-win policy: `/etc/deposit/apk.conf` + `/etc/deposit/pkg.conf`
with HASH_POLICY allowlists; `--insecure` requires explicit conf opt-in.

---
*We are not famous; this file keeps us honest.*
