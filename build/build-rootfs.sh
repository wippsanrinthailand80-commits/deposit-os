#!/usr/bin/env bash
# ============================================================================
# build-rootfs.sh — assemble the Deposit OS userspace (apt/.deb compatible).
# ----------------------------------------------------------------------------
# We *assemble* a minimal Ubuntu/Debian userspace with debootstrap rather than
# cloning an installed Ubuntu system. dpkg + apt are included so Ubuntu .deb
# packages install and run. The kernel is supplied separately by build-kernel.sh.
#
#   ./build-rootfs.sh [ROOTFS_DIR]
#
# Requires: debootstrap, apt (root). On a mismatched host arch you also need
# qemu-<arch>-static + binfmt_misc (cross-rootfs build) — native builds are fine.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

ROOTFS="${1:-$DEPOSIT_ROOTFS_OUT}"
MIRROR="$(deposit_mirror_for_arch)"
BOOT_ARCH="$(deposit_debootstrap_arch)"

echo "[rootfs] target : $ROOTFS"
echo "[rootfs] suite  : $DEPOSIT_SUITE ($BOOT_ARCH)"
echo "[rootfs] mirror : $MIRROR"

# --- Prereqs ----------------------------------------------------------------
need() { command -v "$1" >/dev/null || { echo "missing required tool: $1" >&2; exit 1; }; }
need debootstrap
need tar

# --- Stage 1: debootstrap minbase -------------------------------------------
if [[ -d "$ROOTFS" && -f "$ROOTFS/debootstrap/debootstrap.log" ]]; then
  echo "[rootfs] reusing existing debootstrap at $ROOTFS (remove to rebuild)"
else
  rm -rf "$ROOTFS"
  mkdir -p "$ROOTFS"
  echo "[rootfs] running debootstrap (minbase)..."
  debootstrap --variant=minbase --components="$DEPOSIT_COMPONENTS" \
    --arch="$BOOT_ARCH" "$DEPOSIT_SUITE" "$ROOTFS" "$MIRROR"
fi

# --- chroot helpers ---------------------------------------------------------
mount_chroot() {
  mount -t proc proc "$ROOTFS/proc"
  mount -t sysfs sys "$ROOTFS/sys"
  mount -o bind /dev "$ROOTFS/dev"
  mount -o bind /dev/pts "$ROOTFS/dev/pts"
}
umount_chroot() {
  umount -l "$ROOTFS/dev/pts" 2>/dev/null || true
  umount -l "$ROOTFS/dev" 2>/dev/null || true
  umount -l "$ROOTFS/sys" 2>/dev/null || true
  umount -l "$ROOTFS/proc" 2>/dev/null || true
}
trap umount_chroot EXIT

# --- Stage 2: apt sources + identity ----------------------------------------
cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb $MIRROR $DEPOSIT_SUITE main universe
deb $MIRROR $DEPOSIT_SUITE-updates main universe
deb $MIRROR $DEPOSIT_SUITE-security main universe
EOF

# Deposit OS identity (kept Debian/Ubuntu-ABI compatible via ID_LIKE).
cat > "$ROOTFS/etc/os-release" <<EOF
PRETTY_NAME="$DEPOSIT_PRETTY $DEPOSIT_VERSION"
NAME="$DEPOSIT_PRETTY"
VERSION_ID="$DEPOSIT_VERSION"
VERSION="$DEPOSIT_PRETTY $DEPOSIT_VERSION"
ID=$DEPOSIT_ID
ID_LIKE=$DEPOSIT_ID_LIKE
HOME_URL="$DEPOSIT_HOME_URL"
BUG_REPORT_URL="$DEPOSIT_BUG_REPORT_URL"
PRIVACY_POLICY_URL="$DEPOSIT_BUG_REPORT_URL"
SUPPORTED_ARCH="$BOOT_ARCH"
EOF
echo "$DEPOSIT_VERSION" > "$ROOTFS/etc/deposit-release"

echo "$DEPOSIT_DEFAULT_HOSTNAME" > "$ROOTFS/etc/hostname"

# --- Stage 3: install extra base + optional desktop -------------------------
mount_chroot
chroot "$ROOTFS" /bin/bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  export APT_OPTS="-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"
  apt-get $APT_OPTS update -qq
  apt-get $APT_OPTS install -y --no-install-recommends '"$DEPOSIT_EXTRA_BASE"'
'
if [[ -n "${DEPOSIT_DESKTOP_PKGS:-}" ]]; then
  chroot "$ROOTFS" /bin/bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    export APT_OPTS="-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"
    apt-get $APT_OPTS install -y --no-install-recommends '"$DEPOSIT_DESKTOP_PKGS"'
  '
fi

# --- Stage 4: light first-boot setup (no systemd bloat on old HW) -----------
# Provide a simple, fast getty + network-online target. Keep services minimal.
chroot "$ROOTFS" /bin/bash -c '
  set -e
  systemctl set-default multi-user.target 2>/dev/null || true
  # Disable heavy/unneeded units on older hardware (mirrors dietpex philosophy).
  for u in snapd.service bluetooth.service cups.service cups-browsed.service \
           ModemManager.service whoopsie.service apport.service kerneloops.service \
           apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service \
           fwupd.service avahi-daemon.service; do
    systemctl mask "$u" 2>/dev/null || true
  done
  apt-get clean
  rm -rf /var/lib/apt/lists/*
'

# --- Stage 5: default user --------------------------------------------------
chroot "$ROOTFS" /bin/bash -c '
  id '"$DEPOSIT_DEFAULT_USER"' >/dev/null 2>&1 || useradd -m -s /bin/bash '"$DEPOSIT_DEFAULT_USER"'
  echo "'"$DEPOSIT_DEFAULT_USER"':$DEPOSIT_DEFAULT_USER_PASSWORD" | chpasswd
  usermod -aG sudo '"$DEPOSIT_DEFAULT_USER"' 2>/dev/null || true
'

umount_chroot
trap - EXIT

echo "[rootfs] done -> $ROOTFS"
echo "[rootfs] next: build the kernel (./build/build-kernel.sh) then pack with: mlpds build"
