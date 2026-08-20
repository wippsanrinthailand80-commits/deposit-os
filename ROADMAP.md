# Deposit OS — Roadmap

A living plan for what Deposit OS still needs to feel like a complete,
genuinely-new Linux distribution. Nothing here is set in stone; it is a
prioritized wish-list so we do not forget the gaps.

## What already exists
- Custom 6.6.58 kernel + debootstrapped Ubuntu Noble userspace (glibc, systemd).
- Runs `.deb`/`apt` **and** our own `.mlpds` packages (AQA installer).
- **Turbo** mode + `deposit-turbo-fx` fade-in/out spinner overlay.
- **Thai**: fonts, `th_TH.UTF-8` locale, **and** IBus typing (`ibus-libthai`, Super+Space).
- **Security**: AppArmor, ClamAV (`deposit-av`), `ufw` service, `deposit-security` panel.
- **Samsung-style quick menu** (`deposit-quickmenu`, Super+Q toggle) with
  Wi-Fi / Airplane / Turbo / LAN / Scan / Files / **Power** / **Security** /
  **Store** / **Updates** tiles, Brightness + Volume sliders.
- **Drive file manager** `deposit-files` (C:/D: drive letters).
- **First-boot OOBE wizard** `deposit-oobe` (timezone, locale, keyboard, password).
- **Software Center** `deposit-store` (browse/install AQA apps).
- **Updater** `deposit-updater` (apt + AQA update check/upgrade).
- **Plymouth boot splash** (spinner theme) + branded wallpaper.
- **Default browser**: Firefox-ESR baked into the image.
- **Bluetooth** enabled (bluez) instead of masked off.
- Hybrid **BIOS/UEFI live ISO** + **USB installer** `deposit-install`
  (GPT partition, rsync, GRUB for BIOS + UEFI).
- `continuous` GitHub release (carries `deposit-os.iso` + `deposit.os.mlpds`).
- README / LICENSE (GPL-3.0) / CONTRIBUTING / issue templates / docs/assets screenshots.

## Quick wins (small effort, high payoff) — DONE
1. ✅ **Thai input method** — `ibus-libthai` + IBus autostart (Super+Space).
2. ✅ **Power / session tile** — shutdown, restart, suspend, logout dialog.
3. ✅ **Security Center tile** — AppArmor status, `ufw` toggle, "Run AV scan".

## Medium (the "this is a real OS" feeling) — DONE
4. ✅ **First-boot OOBE wizard** — `deposit-oobe` (timezone/locale/keyboard/password).
5. ✅ **Software Center for `.mlpds`** — `deposit-store`.
6. ✅ **Updater / update notifier** — `deposit-updater`.
7. ✅ **Plymouth boot splash + branded wallpaper** — spinner theme + `splash` boot param.

## Bigger decisions — DONE
8. ✅ **Default web browser** — Firefox-ESR baked into the image.
9. ✅ **Bluetooth** — enabled (`bluez`), no longer masked.

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
x86_64 road-map (quick wins + medium + browser + Bluetooth) is complete. Next:
ship/locks the x86_64 `continuous` release, **then** start the **ARM64** parallel
target (kernel + debootstrap `--arch=arm64` + UEFI boot + arm64 CI job).

---
*Note: we are not famous, so this is mostly for ourselves — but writing it down
keeps the direction honest.*
