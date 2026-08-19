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
  DL_OK=0
  for U in "$DEPOSIT_KERNEL_URL" \
           "https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-${KVER}.tar.xz" \
           "https://ftp.yz.yamagata-u.ac.jp/pub/linux/kernel.org/pub/linux/kernel/v6.x/linux-${KVER}.tar.xz"; do
    echo "[kernel] trying $U"
    if wget --tries=3 --timeout=60 --waitretry=10 -qO "$DEPOSIT_BUILD_DIR/linux-$KVER.tar.xz" "$U"; then
      DL_OK=1; break
    fi
    echo "[kernel] download failed, trying next mirror"
  done
  (( DL_OK )) || { echo "[kernel] all download attempts failed"; exit 1; }
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

# --- Deposit OS kernel features (bootable on real x86_64 hardware) ---
# Core / platform
CONFIG_SMP=y
CONFIG_X86_MPPARSE=y
CONFIG_X86_LOCAL_APIC=y
CONFIG_X86_IO_APIC=y
CONFIG_PCI=y
CONFIG_PCI_MSI=y
CONFIG_PCI_QUIRKS=y
CONFIG_PCI_HOTPLUG=y
CONFIG_ACPI=y
CONFIG_ACPI_TABLES=y
CONFIG_ACPI_PROCESSOR=y
CONFIG_DMI=y
CONFIG_DMIID=y
CONFIG_EFI=y
CONFIG_EFI_STUB=y
CONFIG_PM=y

# Block layer + storage (NVMe / SATA / SCSI / USB disks)
CONFIG_BLOCK=y
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_BLK_DEV_RAM=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_SCSI=y
CONFIG_BLK_DEV_SD=y
CONFIG_BLK_DEV_SR=y
CONFIG_SCSI_LOWLEVEL=y
CONFIG_ATA=y
CONFIG_ATA_ACPI=y
CONFIG_ATA_GENERIC=y
CONFIG_ATA_PIIX=y
CONFIG_SATA_AHCI=y
CONFIG_BLK_DEV_NVME=y
CONFIG_USB_STORAGE=y

# Filesystems
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_USE_FOR_EXT2=y
CONFIG_FAT_FS=y
CONFIG_VFAT_FS=y
CONFIG_ISO9660_FS=y
CONFIG_OVERLAY_FS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_CONFIGFS_FS=y
CONFIG_FS_POSIX_ACL=y

# Namespaces + cgroups (systemd, containers, sandboxes)
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_PIDS=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CPUSETS=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_CGROUP_SCHED=y
CONFIG_CFS_BANDWIDTH=y
CONFIG_POSIX_MQUEUE=y
CONFIG_INOTIFY_USER=y

# Networking (virtual + common real NICs for older PCs)
CONFIG_INET=y
CONFIG_IPV6=y
CONFIG_PACKET=y
CONFIG_UNIX=y
CONFIG_NETDEVICES=y
CONFIG_NET_CORE=y
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_E1000=y
CONFIG_E1000E=y
CONFIG_R8169=y
CONFIG_8139TOO=y

# USB + input (keyboard / mouse on real hardware)
CONFIG_USB=y
CONFIG_USB_COMMON=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_OHCI_HCD=y
CONFIG_USB_HID=y
CONFIG_HID=y
CONFIG_HID_GENERIC=y
CONFIG_INPUT=y
CONFIG_INPUT_KEYBOARD=y
CONFIG_INPUT_MOUSE=y
CONFIG_INPUT_EVDEV=y
CONFIG_SERIO=y
CONFIG_SERIO_I8042=y
CONFIG_KEYBOARD_ATKBD=y
CONFIG_MOUSE_PS2=y

# Graphics + boot screen (framebuffer console + kernel logo)
CONFIG_DRM=y
CONFIG_DRM_FBDEV_EMULATION=y
CONFIG_DRM_SIMPLEDRM=y
CONFIG_DRM_BOCHS=y
CONFIG_FB=y
CONFIG_FB_CORE=y
CONFIG_FB_VESA=y
CONFIG_FB_EFI=y
CONFIG_BOOT_VESA_LFB=y
CONFIG_VGA_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y
CONFIG_LOGO=y
CONFIG_LOGO_LINUX_CLUT224=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_HW_CONSOLE=y

# Console / misc / debug
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_PCI=y
CONFIG_HW_RANDOM=y
CONFIG_RTC_CLASS=y
CONFIG_MAGIC_SYSRQ=y
CONFIG_PRINTK=y
CONFIG_EARLY_PRINTK=y
CONFIG_NLS_DEFAULT="utf8"
CONFIG_NLS_CODEPAGE_437=y
CONFIG_NLS_UTF8=y
CFG

  # Append the broad hardware-support fragment (distro-class driver set).
  cat "$SCRIPT_DIR/kernel-fragments/deposit-broad.cfg" >> .config

  echo "[kernel] olddefconfig"
  make "${MAKE_VARS[@]}" olddefconfig
fi

if (( MENU )); then
  make "${MAKE_VARS[@]}" menuconfig
fi

# --- Build ------------------------------------------------------------------
# Parallelism is capped by DEPOSIT_KERNEL_JOBS (default: all cores).
# Lower it (e.g. 1) to trade build time for a smaller RAM spike.
echo "[kernel] building with -j$DEPOSIT_KERNEL_JOBS (lower = less RAM, slower)"
make "${MAKE_VARS[@]}" -j"$DEPOSIT_KERNEL_JOBS"

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
