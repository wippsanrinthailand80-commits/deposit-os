# Deposit OS — Roadmap

A living plan for what Deposit OS still needs to feel like a complete,
genuinely-new Linux distribution. Nothing here is set in stone; it is a
prioritized wish-list so we do not forget the gaps.

## What already exists
- Custom 6.6.58 kernel + debootstrapped Ubuntu Noble userspace (glibc, systemd).
- Runs `.deb`/`apt` **and** our own `.mlpds` packages (AQA installer).
- **Turbo** mode + `deposit-turbo-fx` fade-in/out spinner overlay.
- **Thai**: fonts + `th_TH.UTF-8` locale (renders, but cannot yet *type* Thai).
- **Security**: AppArmor, ClamAV (`deposit-av`), `ufw` service.
- **Samsung-style quick menu** (`deposit-quickmenu`, Super+Q toggle) with
  Wi-Fi / Airplane / Turbo / LAN tiles, Brightness + Volume sliders, Scan + Files.
- **Drive file manager** `deposit-files` (C:/D: drive letters).
- Hybrid **BIOS/UEFI live ISO** + **USB installer** `deposit-install`
  (GPT partition, rsync, GRUB for BIOS + UEFI).
- `continuous` GitHub release (intended to carry `deposit-os.iso` + `deposit.os.mlpds`).
- README / LICENSE (GPL-3.0) / CONTRIBUTING / issue templates / docs/assets screenshots.

## Quick wins (small effort, high payoff)
1. **Thai input method** — add `ibus-libthai` and autostart IBus so Thai is
   both readable *and* typeable. Completes the stated "Thai" requirement.
2. **Power / session tile** in the quick menu — shutdown, restart, suspend,
   logout. A Samsung-style menu without power controls feels unfinished.
3. **Security Center tile** — one panel tying together AppArmor status,
   `ufw` on/off, and "Run AV scan" (we already have the pieces).

## Medium (the "this is a real OS" feeling)
4. **First-boot OOBE wizard** — language, keyboard, timezone, create your user,
   opt into updates. Today there is a single hardcoded `deposit`/`deposit` account.
5. **Software Center for `.mlpds`** — a graphical browser/installer for AQA
   packages. We built the format; a store makes it tangible.
6. **Updater / update notifier** — surface `apt` + `.mlpds` updates in the panel.
7. **Plymouth boot splash + GRUB theme + branded wallpaper** — visual polish.

## Bigger decisions
8. **Default web browser** — currently *intentionally* omitted (install Chrome
   via `aqa`). A desktop OS basically needs one (Firefox-ESR / Chromium, ~100 MB+).
9. **Bluetooth** — currently masked off in the image; enable if desired.

## ARM64 (parallel build target)
A whole separate architecture, not a tweak. The app layer (bash/Python/GTK
tools) is architecture-agnostic and reuses directly; the build pipeline needs
a second target:
- Cross-compile (or natively build) a `6.6.58` **arm64** kernel.
- `debootstrap --arch=arm64` Noble rootfs (reuse `build-rootfs.sh` with `ARCH=arm64`).
- Boot: `grub-efi-arm64` + UEFI — works on UEFI-capable ARM boards
  (Raspberry Pi 4/5 with UEFI firmware, Ampere, QEMU `virt`). BIOS/`grub-pc`
  does not apply; `deposit-install` already handles the UEFI path.
- Separate `arm64` CI job (kernel cache keyed per-arch) and a distinct
  `deposit-os-arm64.iso` artifact + release asset.

Sequencing: ship x86_64 first (release + quick wins), **then** add ARM64 as a
parallel target. Do not block the x86_64 release on it.

## Recommended next slice
Ship the three quick wins (Thai typing + power tile + security center) — they are
small, on-theme, and finish what is already started. Defer OOBE / App Store /
browser to a later iteration.

---
*Note: we are not famous, so this is mostly for ourselves — but writing it down
keeps the direction honest.*
