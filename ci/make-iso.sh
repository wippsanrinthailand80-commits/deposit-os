#!/usr/bin/env bash
# ============================================================================
# make-iso.sh — build a bootable (BIOS + UEFI) live ISO for Deposit OS.
#
# Takes the built rootfs + kernel and produces a GRUB2 / live-boot / SquashFS
# hybrid ISO. Requires (on the build host): xorriso, grub-efi-amd64-bin,
# grub-pc-bin, squashfs-tools, initramfs-tools.
# ============================================================================
set -uo pipefail

ROOTFS="${1:-build/output/rootfs}"
KERNEL="${2:-build/output/kernel}"
OUT="${3:-build/output/deposit-os.iso}"

VER="$(ls "$KERNEL/lib/modules" 2>/dev/null | head -1)"
[ -n "$VER" ] || { echo "[iso] no kernel modules found in $KERNEL/lib/modules"; exit 1; }
echo "[iso] kernel version: $VER"

mount_chroot() {
  mount -t proc none "$ROOTFS/proc" 2>/dev/null || true
  mount -t sysfs none "$ROOTFS/sys" 2>/dev/null || true
  mount -o bind /dev "$ROOTFS/dev" 2>/dev/null || true
  mount -o bind /dev/pts "$ROOTFS/dev/pts" 2>/dev/null || true
}
umount_chroot() {
  umount "$ROOTFS/dev/pts" 2>/dev/null || true
  umount "$ROOTFS/dev" 2>/dev/null || true
  umount "$ROOTFS/sys" 2>/dev/null || true
  umount "$ROOTFS/proc" 2>/dev/null || true
}

# 1) place the kernel modules + vmlinuz into the rootfs (needed by live-boot)
mkdir -p "$ROOTFS/lib/modules"
rm -rf "$ROOTFS/lib/modules/$VER"
cp -a "$KERNEL/lib/modules/$VER" "$ROOTFS/lib/modules/$VER"
mkdir -p "$ROOTFS/boot"
cp "$KERNEL"/boot/vmlinuz-* "$ROOTFS/boot/" 2>/dev/null || true

# 2) install live-boot + initramfs tooling inside the rootfs, then build initrd
mount_chroot
chroot "$ROOTFS" /bin/bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends live-boot live-tools \
    initramfs-tools squashfs-tools || echo "[iso] WARN: live pkg install issue"
  mkinitramfs -o "/boot/initrd.img-$VER" "$VER" || echo "[iso] WARN: mkinitramfs issue"
'
umount_chroot

# 3) squash the rootfs (exclude /boot to keep ISO small; kernel/initrd copied separately)
WORK="$(mktemp -d)"
mkdir -p "$WORK/live"
echo "[iso] building squashfs…"
mksquashfs "$ROOTFS" "$WORK/live/filesystem.squashfs" -comp xz -e "/boot/*" \
  || mksquashfs "$ROOTFS" "$WORK/live/filesystem.squashfs" -comp xz
cp "$ROOTFS/boot/vmlinuz-$VER" "$WORK/live/vmlinuz" 2>/dev/null \
  || cp "$ROOTFS"/boot/vmlinuz-* "$WORK/live/vmlinuz"
cp "$ROOTFS/boot/initrd.img-$VER" "$WORK/live/initrd.img" 2>/dev/null || true

# 4) GRUB config (live-boot boots the squashfs)
mkdir -p "$WORK/boot/grub"
cat > "$WORK/boot/grub/grub.cfg" <<EOF
set timeout=5
insmod all_video
menuentry "Deposit OS (Live)" {
  linux /live/vmlinuz boot=live
  initrd /live/initrd.img
}
EOF

# 5) produce the hybrid ISO
echo "[iso] running grub-mkrescue…"
grub-mkrescue -o "$OUT" "$WORK" -- -volid "DepositOS" \
  || { echo "[iso] grub-mkrescue failed"; exit 1; }

echo "[iso] wrote $OUT ($(du -h "$OUT" | cut -f1))"
