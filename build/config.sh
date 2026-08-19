#!/usr/bin/env bash
# ============================================================================
# deposit-os build configuration
# ----------------------------------------------------------------------------
# deposit OS is a *new* distribution: we compile our own Linux kernel from
# upstream source and assemble a minimal userspace. To honour the requirement
# "supports Ubuntu installations" (run .deb / apt packages) the userspace is
# glibc + dpkg + apt compatible with the Debian/Ubuntu ABI, but it is
# *assembled* (debootstrap) rather than *cloned* from an Ubuntu install.
#
# Set any of these as environment variables to override at build time.
# ============================================================================

# --- Distro identity -------------------------------------------------------
DEPOSIT_NAME="deposit"
DEPOSIT_PRETTY="Deposit OS"
DEPOSIT_VERSION="0.1.0"
DEPOSIT_ID="deposit"
DEPOSIT_ID_LIKE="ubuntu debian"          # tells .deb tooling we are compatible
DEPOSIT_HOME_URL="https://example.invalid/deposit-os"
DEPOSIT_BUG_REPORT_URL="https://example.invalid/deposit-os/issues"
DEPOSIT_PRIVACY_POLICY_URL="https://example.invalid/deposit-os/privacy"

# --- Target architecture ---------------------------------------------------
# aarch64 (ARM64) or x86_64. Override with DEPOSIT_ARCH.
DEPOSIT_ARCH="${DEPOSIT_ARCH:-$(uname -m)}"

# --- Kernel (compiled from upstream source, NOT from any distro) ------------
DEPOSIT_KERNEL_VERSION="${DEPOSIT_KERNEL_VERSION:-6.6.58}"   # LTS, good on old HW
DEPOSIT_KERNEL_URL="${DEPOSIT_KERNEL_URL:-https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${DEPOSIT_KERNEL_VERSION}.tar.xz}"
DEPOSIT_KERNEL_TINY="${DEPOSIT_KERNEL_TINY:-1}"             # start from tinyconfig

# --- Userspace (Debian/Ubuntu pool, for .deb/apt compatibility) -------------
DEPOSIT_SUITE="${DEPOSIT_SUITE:-noble}"                     # Ubuntu 24.04
DEPOSIT_MIRROR="${DEPOSIT_MIRROR:-http://archive.ubuntu.com/ubuntu}"
DEPOSIT_PORTS_MIRROR="${DEPOSIT_PORTS_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}"
DEPOSIT_COMPONENTS="${DEPOSIT_COMPONENTS:-main,universe}"

# Minimal, apt-capable base. debootstrap --variant=minbase already pulls the
# essential toolchain; these are added on top.
DEPOSIT_EXTRA_BASE="${DEPOSIT_EXTRA_BASE:-apt-utils ca-certificates gpgv \
  gnupg netplan.io systemd systemd-sysv udev openssh-server vim-tiny}"

# Optional lightweight desktop (XFCE). Leave empty for a headless/CLI build.
DEPOSIT_DESKTOP_PKGS="${DEPOSIT_DESKTOP_PKGS:-xfce4 xfce4-terminal lightdm}"

# Kernel package is intentionally NOT installed in the rootfs because we build
# and supply our own kernel via build-kernel.sh.
DEPOSIT_INSTALL_KERNEL_IN_ROOTFS="${DEPOSIT_INSTALL_KERNEL_IN_ROOTFS:-0}"

# --- Default install settings (used by the .mlpds installer) ----------------
DEPOSIT_DEFAULT_HOSTNAME="${DEPOSIT_DEFAULT_HOSTNAME:-deposit}"
DEPOSIT_DEFAULT_USER="${DEPOSIT_DEFAULT_USER:-deposit}"
DEPOSIT_DEFAULT_USER_PASSWORD="${DEPOSIT_DEFAULT_USER_PASSWORD:-deposit}"
DEPOSIT_DEFAULT_LOCALE="${DEPOSIT_DEFAULT_LOCALE:-en_US.UTF-8}"
DEPOSIT_DEFAULT_TIMEZONE="${DEPOSIT_DEFAULT_TIMEZONE:-UTC}"

# --- Build output locations -------------------------------------------------
DEPOSIT_BUILD_DIR="${DEPOSIT_BUILD_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/output}"
DEPOSIT_KERNEL_OUT="${DEPOSIT_KERNEL_OUT:-$DEPOSIT_BUILD_DIR/kernel}"
DEPOSIT_ROOTFS_OUT="${DEPOSIT_ROOTFS_OUT:-$DEPOSIT_BUILD_DIR/rootfs}"

# Resolve the right debootstrap mirror for the arch.
deposit_mirror_for_arch() {
  case "$DEPOSIT_ARCH" in
    x86_64|amd64) echo "$DEPOSIT_MIRROR" ;;
    *)            echo "$DEPOSIT_PORTS_MIRROR" ;;
  esac
}

# Normalise arch for debootstrap / kernel build.
deposit_debootstrap_arch() {
  case "$DEPOSIT_ARCH" in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    armv7l|armhf) echo armhf ;;
    *) echo "$DEPOSIT_ARCH" ;;
  esac
}
