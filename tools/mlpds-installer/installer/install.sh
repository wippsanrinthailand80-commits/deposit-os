#!/usr/bin/env bash
# ============================================================================
# Deposit OS .mlpds installer payload  (installer/install.sh)
# ----------------------------------------------------------------------------
# Runs with the extracted .mlpds archive as its working context.
#   install.sh --target <dir|device> --rootfs <path> [--kernel <dir>] [--boot]
#              [--hostname H] [--user U] [--locale L] [--timezone T]
#
# Designed to be offline / "airplane mode": everything it needs is already in
# the archive. Best-effort bootloader install via extlinux (lightweight, ideal
# for older hardware) or grub.
# ============================================================================
set -euo pipefail

TARGET="" ROOTFS="" KERNEL="" BOOT=0
HOSTNAME="deposit" USER="deposit" LOCALE="en_US.UTF-8" TIMEZONE="UTC"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)   TARGET="$2"; shift 2 ;;
    --rootfs)   ROOTFS="$2"; shift 2 ;;
    --kernel)   KERNEL="$2"; shift 2 ;;
    --boot)     BOOT=1; shift ;;
    --hostname) HOSTNAME="$2"; shift 2 ;;
    --user)     USER="$2"; shift 2 ;;
    --locale)   LOCALE="$2"; shift 2 ;;
    --timezone) TIMEZONE="$2"; shift 2 ;;
    *) echo "install.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TARGET" ]] || { echo "install.sh: --target is required" >&2; exit 2; }
[[ -d "$ROOTFS" ]] || { echo "install.sh: rootfs not found: $ROOTFS" >&2; exit 2; }

echo "[install] target = $TARGET"

# A block device target: we expect it pre-partitioned/formatted; mount it.
if [[ -b "$TARGET" ]]; then
  MNT="$(mktemp -d)"
  mount "$TARGET" "$MNT"
  TARGET="$MNT"
  CLEANMNT=1
else
  CLEANMNT=0
  mkdir -p "$TARGET"
fi
trap '[[ $CLEANMNT -eq 1 ]] && umount -l "$TARGET" 2>/dev/null; rm -rf "${MNT:-}" 2>/dev/null' EXIT

echo "[install] copying rootfs -> $TARGET"
# Preserve everything; overwrite is idempotent.
cp -a "$ROOTFS/." "$TARGET/"

# Identity
echo "$HOSTNAME" > "$TARGET/etc/hostname"
cat > "$TARGET/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME
::1       localhost
EOF

# Locale + timezone
mkdir -p "$TARGET/etc/default"
echo "LANG=$LOCALE" > "$TARGET/etc/default/locale"
echo "$TIMEZONE" > "$TARGET/etc/timezone"
if [[ -x "$TARGET/usr/sbin/dpkg-reconfigure" ]]; then
  chroot "$TARGET" /bin/bash -c "DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive locales 2>/dev/null || true"
fi

# fstab (generic; tune for real hardware / disk images as needed)
cat > "$TARGET/etc/fstab" <<EOF
# Deposit OS fstab — adjust the root device to match your disk.
# LABEL=deposit-root  /  ext4  defaults  0 1
proc           /proc  proc  defaults  0 0
sysfs          /sys   sysfs defaults  0 0
tmpfs          /tmp   tmpfs defaults  0 0
tmpfs          /run   tmpfs defaults  0 0
EOF

# Ensure default user exists (rootfs may already define it).
if [[ -x "$TARGET/usr/sbin/useradd" ]]; then
  chroot "$TARGET" /bin/bash -c "id '$USER' >/dev/null 2>&1 || useradd -m -s /bin/bash '$USER'"
fi

# Bootloader (best effort) -------------------------------------------------
if (( BOOT )); then
  echo "[install] setting up boot"
  mkdir -p "$TARGET/boot"
  if [[ -d "$KERNEL" ]]; then
    cp -a "$KERNEL/." "$TARGET/boot/" 2>/dev/null || true
  fi
  if command -v extlinux >/dev/null; then
    KIMG="$(ls "$TARGET/boot"/vmlinuz-* 2>/dev/null | head -1)"
    KREL="$(basename "$KIMG" | sed 's/vmlinuz-//')"
    cat > "$TARGET/boot/extlinux.conf" <<EOF
DEFAULT deposit
LABEL deposit
  KERNEL /boot/vmlinuz-$KREL
  APPEND root=/dev/sda1 ro quiet
EOF
    extlinux --install "$TARGET/boot" 2>/dev/null || true
    echo "[install] extlinux config written"
  elif command -v grub-install >/dev/null; then
    cat > "$TARGET/boot/grub.cfg" <<'EOF'
set timeout=5
set default=0
menuentry "Deposit OS" {
  linux /boot/vmlinuz-@KREL@ root=/dev/sda1 ro quiet
}
EOF
    echo "[install] grub config written (run grub-install separately)"
  else
    echo "[install] WARNING: no bootloader tool (extlinux/grub) on host; skipped."
  fi
fi

echo "[install] complete."
