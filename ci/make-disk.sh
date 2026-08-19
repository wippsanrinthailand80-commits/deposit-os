#!/usr/bin/env bash
# ============================================================================
# make-disk.sh — build a raw, bootable Deposit OS disk image from a rootfs
# directory + a compiled kernel directory. Used by the CI live-boot job to
# actually *boot* Deposit OS under QEMU and screenshot it.
#
#   ./make-disk.sh <rootfs-dir> <kernel-dir> <out.img> [size-mb]
#
# The image is a single ext4 filesystem on /dev/sda (no partition table, so
# the kernel cmdline is just root=/dev/sda). A demo-only autostart drops a
# terminal running the AQA installer so the live screenshot shows it.
# ============================================================================
set -euo pipefail

ROOTFS="${1:?usage: make-disk.sh <rootfs> <kernel> <out.img> [size_mb]}"
KERNEL="${2:?missing kernel dir}"
OUT="${3:?missing out img}"
SIZE="${4:-4096}"

KVER="$(cat "$KERNEL/boot/kernel-release" 2>/dev/null || echo 6.6.58)"

echo "[disk] creating $OUT (${SIZE}M)"
rm -f "$OUT"
dd if=/dev/zero of="$OUT" bs=1M count="$SIZE" status=none
mkfs.ext4 -F -L deposit "$OUT" >/dev/null

MNT="$(mktemp -d)"
cleanup() { sudo umount "$MNT" 2>/dev/null || true; rm -rf "$MNT"; }
trap cleanup EXIT

# Mount via loop (fall back to explicit losetup if needed).
if ! sudo mount -o loop "$OUT" "$MNT" 2>/dev/null; then
  LP="$(sudo losetup -f --show "$OUT")"
  sudo mount "$LP" "$MNT"
fi

echo "[disk] copying rootfs -> image"
sudo cp -a "$ROOTFS/." "$MNT/"

# Install the matching kernel modules into the image.
if [[ -d "$KERNEL/lib/modules" ]]; then
  echo "[disk] installing kernel modules ($KVER)"
  sudo mkdir -p "$MNT/lib/modules"
  sudo cp -a "$KERNEL/lib/modules/." "$MNT/lib/modules/"
fi

# Single ext4 root on /dev/sda.
sudo tee "$MNT/etc/fstab" >/dev/null <<FSTAB
# Deposit OS
/dev/sda  /  ext4  defaults  0  1
FSTAB

# --- Demo-only autostart: a terminal that runs the AQA installer -----------
sudo mkdir -p "$MNT/etc/xdg/autostart" "$MNT/usr/local/bin"
sudo tee "$MNT/usr/local/bin/deposit-aqa-demo.sh" >/dev/null <<'DEMO'
#!/bin/bash
sleep 3
clear
echo "====================================================="
echo "  Deposit OS — AQA installer demo (live boot)"
echo "====================================================="
echo
aqa list
echo
echo ">>> aqa install --dry-run chrome"
aqa install --dry-run chrome
echo
echo ">>> aqa install --dry-run turbo"
aqa install --dry-run turbo
echo
echo "[Deposit OS] AQA demo complete. Terminal left open."
sleep infinity
DEMO
sudo chmod +x "$MNT/usr/local/bin/deposit-aqa-demo.sh"

sudo tee "$MNT/etc/xdg/autostart/deposit-aqa-demo.desktop" >/dev/null <<'AUT'
[Desktop Entry]
Type=Application
Name=Deposit AQA demo
Exec=xfce4-terminal -e "bash /usr/local/bin/deposit-aqa-demo.sh"
X-GNOME-Autostart-enabled=true
AUT

echo "[disk] done -> $OUT"
