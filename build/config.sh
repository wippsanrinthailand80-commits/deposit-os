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
DEPOSIT_PRETTY_BETA="Deposit OS Beta"
DEPOSIT_VERSION="0.1.1"
DEPOSIT_VERSION_CODENAME="beta"
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
DEPOSIT_KERNEL_TINY="${DEPOSIT_KERNEL_TINY:-0}"             # 0 = defconfig (broad), 1 = tinyconfig
# Build parallelism. Lower = less RAM, slower build. Default: all host cores.
DEPOSIT_KERNEL_JOBS="${DEPOSIT_KERNEL_JOBS:-$(nproc)}"

# --- Userspace (Debian/Ubuntu pool, for .deb/apt compatibility) -------------
DEPOSIT_SUITE="${DEPOSIT_SUITE:-noble}"                     # Ubuntu 24.04
DEPOSIT_MIRROR="${DEPOSIT_MIRROR:-http://archive.ubuntu.com/ubuntu}"
DEPOSIT_PORTS_MIRROR="${DEPOSIT_PORTS_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}"
DEPOSIT_COMPONENTS="${DEPOSIT_COMPONENTS:-main,universe}"

# --- Ubuntu compat (Path 1: single noble ISO runs jammy/focal .debs) --------
# Noble (glibc 2.39) is forward-compatible with binaries linked against older
# suites. Installing the older sonames alongside noble lets jammy/focal debs
# run without a separate ISO. Keep this minimal; extend via DEPOSIT_COMPAT_*.
DEPOSIT_ENABLE_COMPAT="${DEPOSIT_ENABLE_COMPAT:-1}"
# Jammy (22.04 LTS, supported to 2027): libicu70 is the main soname bump.
DEPOSIT_COMPAT_JAMMY_PKGS="${DEPOSIT_COMPAT_JAMMY_PKGS:-libicu70}"
# Focal (20.04 LTS, ESM to 2030): openssl 1.1 + icu66 + libffi7 cover most
# binary compat failures. These coexist with noble's libssl3/libicu74/libffi8.
DEPOSIT_COMPAT_FOCAL_PKGS="${DEPOSIT_COMPAT_FOCAL_PKGS:-libssl1.1 libicu66 libffi7}"

# Minimal, apt-capable base. debootstrap --variant=minbase already pulls the
# essential toolchain; these are added on top.
# linux-firmware: WITHOUT these blobs, AMD/NVIDIA/Wi-Fi/BT devices stay dead
# on real hardware (the #1 "boots but nothing works" gap).
# microcodes: CPU stability/security fixes for both vendors.
DEPOSIT_EXTRA_BASE="${DEPOSIT_EXTRA_BASE:-apt-utils ca-certificates gpgv \
  gnupg netplan.io systemd systemd-sysv udev openssh-server vim-tiny curl \
  linux-firmware amd64-microcode intel-microcode}"

# Optional lightweight desktop (XFCE). Leave empty for a headless/CLI build.
# xorg + video/input driver metas are required for the GUI to actually start
# (they are not pulled in by --no-install-recommends elsewhere).
# whiskermenu = the "Start" button for Windows-style mode (deposit-winmode).
DEPOSIT_DESKTOP_PKGS="${DEPOSIT_DESKTOP_PKGS:-xfce4 xfce4-terminal lightdm lightdm-gtk-greeter xfce4-goodies xorg xserver-xorg-video-all xserver-xorg-input-all xfce4-whiskermenu-plugin \
  breeze-gtk-theme breeze-cursor-theme}"

# --- Windows-friendly layer (Beta 0.1.0.8+) ---------------------------------
# Wine lets users run Windows installers (.exe/.msi) directly; ntfs-3g gives
# reliable read/write on Windows drives (kernel ntfs3 module also present);
# fonts-wine ships the core Windows-metric fonts many installers expect.
# bubblewrap/firejail sandbox the execution (SANDBOX=auto in win.conf);
# carlito is metric-compatible with Calibri (Segoe-like UI text in winmode).
# Runs entirely as the user (never root). Set 0 for a lean build.
DEPOSIT_WIN_SUPPORT="${DEPOSIT_WIN_SUPPORT:-1}"
DEPOSIT_WIN_PKGS="${DEPOSIT_WIN_PKGS:-wine wine64 winetricks fonts-wine ntfs-3g \
  bubblewrap firejail fonts-crosextra-carlito}"

# --- Android layer (Beta 0.1.0.9): run .apk apps via Waydroid ---------------
# Waydroid needs the waydroid repo (not in Ubuntu archive) + kernel Binder
# (enabled in deposit-80m.cfg). adb covers sideloading to physical phones.
DEPOSIT_ANDROID_SUPPORT="${DEPOSIT_ANDROID_SUPPORT:-1}"
DEPOSIT_ANDROID_PKGS="${DEPOSIT_ANDROID_PKGS:-waydroid adb}"

# --- Bluetooth audio: A2DP profile support (AirPods/headsets work fully) ----
DEPOSIT_BT_PKGS="${DEPOSIT_BT_PKGS:-pulseaudio-module-bluetooth bluez-obexd}"

# --- Foreign Linux packages (.rpm Fedora/RHEL, Arch .pkg.tar.zst) -----------
# Extracted into isolated prefixes (~/.deposit/rpm, ~/.deposit/arch) by
# tools/deposit-pkg — no dependency resolution, transparently documented.
DEPOSIT_FOREIGN_SUPPORT="${DEPOSIT_FOREIGN_SUPPORT:-1}"

# --- Rounded aesthetic (kept light: theme + icon set, no heavy DE extras) ---
DEPOSIT_THEME_PKGS="${DEPOSIT_THEME_PKGS:-materia-gtk-theme papirus-icon-theme \
  fonts-noto-color-emoji librsvg2-common}"

# --- Thai language support (fonts + locale). On by default. -----------------
DEPOSIT_ENABLE_THAI="${DEPOSIT_ENABLE_THAI:-1}"
DEPOSIT_THAI_FONTS="${DEPOSIT_THAI_FONTS:-fonts-thai-tlwg fonts-noto-color-emoji \
  fonts-noto-extra}"
# Locales to generate in the image (Thai + English both present).
DEPOSIT_LOCALES="${DEPOSIT_LOCALES:-en_US.UTF-8 th_TH.UTF-8}"

# --- Curated "necessary" apps/services for a usable desktop (still light) ----
# A default browser (Firefox ESR) IS baked in now; heavy apps like Chrome can
# still be added later via `aqa install chrome` without bloating the base.
DEPOSIT_APPS="${DEPOSIT_APPS:-network-manager-gnome pavucontrol pulseaudio \
  udisks2 xfce4-screenshooter xarchiver gnome-font-viewer \
  ibus ibus-libthai im-config \
  bluez bluez-tools \
  plymouth plymouth-themes \
  network-manager epiphany-browser}"
# Services: firewall present but not auto-enabled (so SSH isn't locked out).
DEPOSIT_SERVICES="${DEPOSIT_SERVICES:-ufw}"

# Kernel package is intentionally NOT installed in the rootfs because we build
# and supply our own kernel via build-kernel.sh.
DEPOSIT_INSTALL_KERNEL_IN_ROOTFS="${DEPOSIT_INSTALL_KERNEL_IN_ROOTFS:-0}"

# --- Default install settings (used by the .mlpds installer) ----------------
DEPOSIT_DEFAULT_HOSTNAME="${DEPOSIT_DEFAULT_HOSTNAME:-deposit}"
DEPOSIT_DEFAULT_USER="${DEPOSIT_DEFAULT_USER:-deposit}"
# NOTE: the build does NOT ship this value. build-rootfs.sh generates a RANDOM
# password and forces a change on first login (chage -d 0); the OOBE wizard sets
# the real one. This avoids a known/default credential in the shipped image.
DEPOSIT_DEFAULT_USER_PASSWORD="${DEPOSIT_DEFAULT_USER_PASSWORD:-}"
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
