#!/usr/bin/env bash
# ============================================================================
# build-kernel.sh — compile the Deposit OS Linux kernel from upstream source.
# ----------------------------------------------------------------------------
# This is what makes Deposit OS a *new* OS rather than a respin: the kernel is
# downloaded from kernel.org and compiled here, not taken from Ubuntu.
#
#   ./build-kernel.sh                 # build (expects build deps present)
#   ./build-kernel.sh --deps         # install build dependencies (apt, root)
#   ./build-kernel.sh --menuconfig   # tweak the config interactively
#   DEPOSIT_ARCH=x86_64 ./build-kernel.sh
#
# Output: $DEPOSIT_KERNEL_OUT/boot/vmlinuz-<ver>  and  .../boot/initrd (if any)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

BUILD_DEPS=0
MENU=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --deps) BUILD_DEPS=1; shift ;;
    --menuconfig) MENU=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if (( BUILD_DEPS )); then
  echo "[kernel] installing build dependencies (needs root + apt)"
  command -v apt-get >/dev/null || { echo "apt-get required for --deps" >&2; exit 1; }
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    build-essential bc flex bison libelf-dev libssl-dev \
    wget xz-utils cpio kmod ccache \
    "gcc-$(gcc -dumpmachine)" 2>/dev/null || \
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    build-essential bc flex bison libelf-dev libssl-dev wget xz-utils cpio kmod ccache
fi

KVER="$DEPOSIT_KERNEL_VERSION"
SRC_DIR="$DEPOSIT_BUILD_DIR/linux-$KVER"
KOUT="$DEPOSIT_KERNEL_OUT"
mkdir -p "$DEPOSIT_BUILD_DIR" "$KOUT"

# --- Download + extract -----------------------------------------------------
if [[ ! -d "$SRC_DIR" ]]; then
  echo "[kernel] downloading linux-$KVER"
  wget -qO "$DEPOSIT_BUILD_DIR/linux-$KVER.tar.xz" "$DEPOSIT_KERNEL_URL"
  echo "[kernel] extracting"
  tar -C "$DEPOSIT_BUILD_DIR" -xf "$DEPOSIT_BUILD_DIR/linux-$KVER.tar.xz"
fi

cd "$SRC_DIR"

# Cross-compile support: set DEPOSIT_KERNEL_ARCH / CROSS_COMPILE if needed.
MAKE_VARS=()
if [[ -n "${DEPOSIT_KERNEL_ARCH:-}" ]]; then
  MAKE_VARS+=(ARCH="$DEPOSIT_KERNEL_ARCH")
  if [[ -n "${CROSS_COMPILE:-}" ]]; then MAKE_VARS+=(CROSS_COMPILE="$CROSS_COMPILE"); fi
fi

# --- Configure (start from a tiny kernel, then enable what we need) ----------
if [[ ! -f .config ]]; then
  if (( DEPOSIT_KERNEL_TINY )); then
    echo "[kernel] tinyconfig"
    make "${MAKE_VARS[@]}" tinyconfig
  else
    make "${MAKE_VARS[@]}" defconfig
  fi

  # Append a minimal-but-bootable feature set. Old/weak hardware still needs a
  # real block layer, a filesystem, and serial/console output.
  cat >> .config <<'CFG'

# --- Deposit OS base kernel features ---
CONFIG_BLOCK=y
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_USE_FOR_EXT2=y
CONFIG_VFAT_FS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_INET=y
CONFIG_NETDEVICES=y
CONFIG_NET_CORE=y
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_PCI=y
CONFIG_HW_RANDOM=y
CONFIG_PRINTK=y
CONFIG_EARLY_PRINTK=y
CONFIG_RTC_CLASS=y
CONFIG_FS_POSIX_ACL=y
CONFIG_BLK_DEV_INITRD=y
CFG

  echo "[kernel] olddefconfig"
  make "${MAKE_VARS[@]}" olddefconfig
fi

if (( MENU )); then
  make "${MAKE_VARS[@]}" menuconfig
fi

# --- Build ------------------------------------------------------------------
NPROC="$(nproc)"
echo "[kernel] building with -j$NPROC"
make "${MAKE_VARS[@]}" -j"$NPROC"

# --- Install artefacts -------------------------------------------------------
mkdir -p "$KOUT/boot"
cp "$(make "${MAKE_VARS[@]}" -s image_name)" "$KOUT/boot/vmlinuz-$KVER"
if [[ -f arch/x86/boot/bzImage ]]; then
  cp arch/x86/boot/bzImage "$KOUT/boot/vmlinuz-$KVER" 2>/dev/null || true
fi
# Modules (if any built)
if grep -q '^CONFIG_MODULES=y' .config; then
  make "${MAKE_VARS[@]}" INSTALL_MOD_PATH="$KOUT" modules_install
fi
echo "$KVER" > "$KOUT/boot/kernel-release"

echo "[kernel] done -> $KOUT/boot/vmlinuz-$KVER"
