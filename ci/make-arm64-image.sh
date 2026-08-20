#!/usr/bin/env bash
# make-arm64-image.sh — assemble a GENERAL-PURPOSE ARM64 UEFI OS image.
#
# The result is a portable UEFI/ACPI GPT disk image (ESP + ext4 root) that
# boots on anything that speaks ARM64 UEFI:
#   * QEMU  -M virt   (qemu-system-aarch64 -drive file=...,if=virtio)
#   * Raspberry Pi 4/5 (UEFI firmware)
#   * Rockchip / Snapdragon X / NVIDIA DGX Spark / Apple Silicon (Asahi boot)
#
# It is intentionally board-agnostic: no board-specific DT or bootloader;
# GRUB arm64-efi + ACPI does the right thing on all of the above.
#
# Usage: $0 <rootfs> <kernel-dir> <out.img> [size_MB]
set -euo pipefail

ROOTFS="${1:?usage: $0 <rootfs> <kernel> <out.img> [size_MB]}"
KERNEL="${2:?}"
OUT="${3:?}"
SIZE="${4:-4096}"

command -v sgdisk >/dev/null || command -v parted >/dev/null || { echo "need sgdisk/parted"; exit 1; }
command -v mkfs.vfat >/dev/null || { echo "need dosfstools"; exit 1; }
command -v mkfs.ext4 >/dev/null || { echo "need e2fsprogs"; exit 1; }

QA=aarch64
CROSS=0
[[ "$(uname -m)" != "aarch64" ]] && CROSS=1

# On a non-ARM host we need qemu-user-static so we can chroot the arm64 root
# to install + run GRUB and build the initramfs.
if (( CROSS )); then
  QEMU_STATIC="$(command -v "qemu-${QA}-static" 2>/dev/null || true)"
  if [[ -z "$QEMU_STATIC" ]]; then
    apt-get update -qq 2>/dev/null; apt-get install -y -qq qemu-user-static binfmt-support 2>/dev/null || true
    QEMU_STATIC="$(command -v "qemu-${QA}-static" 2>/dev/null || true)"
  fi
  [[ -d /proc/sys/fs/binfmt_misc ]] || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
  [[ -e /proc/sys/fs/binfmt_misc/qemu-"$QA" ]] || update-binfmts --enable "qemu-$QA" 2>/dev/null || systemctl restart systemd-binfmt 2>/dev/null || true
  [[ -n "$QEMU_STATIC" ]] && cp "$QEMU_STATIC" "$ROOTFS/usr/bin/" 2>/dev/null || true
fi

VER="$(ls "$KERNEL"/lib/modules 2>/dev/null | head -1)"
echo "[arm64-img] kernel version: ${VER:-<none>}"

echo "[arm64-img] creating $OUT (${SIZE} MB)"
rm -f "$OUT"
truncate -s "${SIZE}M" "$OUT"

sgdisk "$OUT" \
  --new=1::+200M --typecode=1:ef00 --change-name=1:ESP \
  --new=2:::     --typecode=2:8300 --change-name=2:root >/dev/null

DEV="$(losetup --find --show --partscan "$OUT")"
cleanup(){ losetup -d "$DEV" 2>/dev/null || true; }
trap cleanup EXIT

ESP="${DEV}p1"; ROOT="${DEV}p2"
mkfs.vfat -F 32 -n ESP "$ESP" >/dev/null
mkfs.ext4 -F -L deposit-root "$ROOT" >/dev/null

TMP="$(mktemp -d)"
mount "$ROOT" "$TMP"
mkdir -p "$TMP/boot/efi"
mount "$ESP" "$TMP/boot/efi"

echo "[arm64-img] copying rootfs..."
cp -a "$ROOTFS/." "$TMP/"

echo "[arm64-img] copying kernel modules + vmlinuz..."
if [[ -n "$VER" ]]; then
  mkdir -p "$TMP/lib/modules"
  rm -rf "$TMP/lib/modules/$VER"
  cp -a "$KERNEL/lib/modules/$VER" "$TMP/lib/modules/$VER"
fi
VMLINUZ="$(ls "$KERNEL"/boot/vmlinuz-* 2>/dev/null | head -1)"
[[ -n "$VMLINUZ" ]] && cp "$VMLINUZ" "$TMP/boot/vmlinuz"

cat > "$TMP/etc/fstab" <<EOF
PARTLABEL=root  /          ext4  defaults,noatime  0 1
PARTLABEL=ESP   /boot/efi  vfat  umask=0077        0 2
EOF

# Install GRUB (arm64-efi) + initramfs tooling and assemble the image,
# running inside the arm64 root via qemu-user when on a non-ARM host.
echo "[arm64-img] installing grub-efi-arm64 + initramfs-tools, writing ESP..."
mount -o bind /dev "$TMP/dev" 2>/dev/null || true
mount -t proc proc "$TMP/proc" 2>/dev/null || true
mount -o bind /sys "$TMP/sys" 2>/dev/null || true
chroot "$TMP" /bin/bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends grub-efi-arm64 linux-base initramfs-tools
  if [ -d /lib/modules/* ]; then
    VER="$(ls /lib/modules | head -1)"
    update-initramfs -c -k "$VER" -o /boot/initrd.img 2>/dev/null \
      || mkinitramfs -o /boot/initrd.img "$VER" 2>/dev/null || echo "[arm64-img] WARN: initramfs build issue"
  fi
  grub-install --target=arm64-efi --efi-directory=/boot/efi --boot-directory=/boot --removable
'
umount "$TMP/dev" 2>/dev/null || true
umount "$TMP/proc" 2>/dev/null || true
umount "$TMP/sys" 2>/dev/null || true

cat > "$TMP/boot/grub/grub.cfg" <<'EOF'
set timeout=5
set default=0
menuentry "Deposit OS" {
  linux /boot/vmlinuz root=PARTLABEL=root rw rootwait
  initrd /boot/initrd.img
}
EOF

# Remove the cross-build interpreter so the shipped image stays clean.
if (( CROSS )); then
  rm -f "$TMP/usr/bin/qemu-${QA}-static" 2>/dev/null || true
  rm -f "$ROOTFS/usr/bin/qemu-${QA}-static" 2>/dev/null || true
fi

umount "$TMP/boot/efi" 2>/dev/null || true
umount "$TMP" 2>/dev/null || true
rmdir "$TMP" 2>/dev/null || true

echo "[arm64-img] done -> $OUT"
echo "[arm64-img] test boot with: qemu-system-aarch64 -M virt -cpu max -m 2G -drive file=$OUT,if=virtio,format=raw -nographic"
