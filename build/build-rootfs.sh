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

# --- Cross-build detection (host arch vs target debootstrap arch) ------------
qemu_arch() { case "$1" in arm64) echo aarch64;; amd64) echo x86_64;; armhf) echo arm;; *) echo "$1";; esac; }
QA="$(qemu_arch "$BOOT_ARCH")"
CROSS=0
case "$BOOT_ARCH" in
  arm64) [[ "$(uname -m)" != "aarch64" ]] && CROSS=1 ;;
  armhf) [[ "$(uname -m)" != "armv7l"  ]] && CROSS=1 ;;
  amd64) [[ "$(uname -m)" != "x86_64"  ]] && CROSS=1 ;;
esac
if (( CROSS )); then
  echo "[rootfs] CROSS build: host=$(uname -m) target=$BOOT_ARCH (needs qemu-user-static + binfmt)"
  QEMU_STATIC="$(command -v "qemu-${QA}-static" 2>/dev/null || true)"
  if [[ -z "$QEMU_STATIC" ]]; then
    echo "[rootfs] installing qemu-user-static + binfmt-support"
    (apt-get update -qq && apt-get install -y -qq qemu-user-static binfmt-support) 2>/dev/null \
      || echo "WARN: could not install qemu-user-static (cross build may fail)"
    QEMU_STATIC="$(command -v "qemu-${QA}-static" 2>/dev/null || true)"
  fi
  if [[ ! -d /proc/sys/fs/binfmt_misc ]]; then
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
  fi
  if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-"$QA" ]]; then
    update-binfmts --enable "qemu-$QA" 2>/dev/null || systemctl restart systemd-binfmt 2>/dev/null || true
  fi
  # Last-resort: register the interpreter manually if it is still missing.
  if [[ ! -e /proc/sys/fs/binfmt_misc/qemu-"$QA" && -n "${QEMU_STATIC:-}" ]]; then
    echo "[rootfs] manually registering binfmt for qemu-$QA"
    printf ':qemu-%s:M::\\x7fELF\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\xb7\\x00:\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xfc\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xfe\\xff\\xff:%s:OCF\n' \
      "$QA" "$QEMU_STATIC" > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
  fi
fi

# --- Stage 1: debootstrap minbase -------------------------------------------
if [[ -d "$ROOTFS" && -f "$ROOTFS/debootstrap/debootstrap.log" ]]; then
  echo "[rootfs] reusing existing debootstrap at $ROOTFS (remove to rebuild)"
elif (( CROSS )); then
  rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"
  echo "[rootfs] running debootstrap --foreign (minbase, $BOOT_ARCH)..."
  debootstrap --foreign --variant=minbase --components="$DEPOSIT_COMPONENTS" \
    --arch="$BOOT_ARCH" "$DEPOSIT_SUITE" "$ROOTFS" "$MIRROR"
  echo "[rootfs] second-stage (under qemu-user)..."
  chroot "$ROOTFS" /debootstrap/debootstrap --second-stage
  # Keep the static interpreter in the rootfs so later chroot apt steps work
  # even with a non-fix-binary binfmt registration; removed before we finish.
  [[ -n "${QEMU_STATIC:-}" ]] && cp "$QEMU_STATIC" "$ROOTFS/usr/bin/" 2>/dev/null || true
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
  for u in snapd.service cups.service cups-browsed.service \
           ModemManager.service whoopsie.service apport.service kerneloops.service \
           apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service \
           fwupd.service avahi-daemon.service; do
    systemctl mask "$u" 2>/dev/null || true
  done
  apt-get clean
  rm -rf /var/lib/apt/lists/*
'

# --- Stage 5: default user --------------------------------------------------
# Generate a RANDOM initial password and force a change on first login, so the
# shipped image never carries a known/default credential (closes the OOBE audit
# gap: SSH and any other auth are unusable until the user sets their own).
RPW="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
if ! chroot "$ROOTFS" id "$DEPOSIT_DEFAULT_USER" >/dev/null 2>&1; then
  chroot "$ROOTFS" useradd -m -s /bin/bash "$DEPOSIT_DEFAULT_USER"
fi
# Pipe the random password on stdin (never via an env var / command line).
printf '%s:%s\n' "$DEPOSIT_DEFAULT_USER" "$RPW" | chroot "$ROOTFS" chpasswd
chroot "$ROOTFS" usermod -aG sudo "$DEPOSIT_DEFAULT_USER" 2>/dev/null || true
chroot "$ROOTFS" chage -d 0 "$DEPOSIT_DEFAULT_USER" 2>/dev/null || true
echo "[rootfs] user '$DEPOSIT_DEFAULT_USER': random password set, force-change on first login (set it via OOBE)"

# --- Stage 6: Deposit OS tooling (aqa installer + turbo engine) ------------
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$ROOTFS/usr/local/bin" "$ROOTFS/etc/deposit" "$ROOTFS/usr/share/deposit"
cp "$REPO_ROOT/tools/aqa"        "$ROOTFS/usr/local/bin/aqa"
cp "$REPO_ROOT/tools/deposit-turbo" "$ROOTFS/usr/local/bin/deposit-turbo"
chmod +x "$ROOTFS/usr/local/bin/aqa" "$ROOTFS/usr/local/bin/deposit-turbo"

# Trusted public key used to verify GPG signatures on .mlpds packages.
cp "$REPO_ROOT/assets/deposit-signing-key.pub.asc" "$ROOTFS/usr/share/deposit/deposit-signing-key.pub.asc" 2>/dev/null \
  || echo "WARN: signing public key not found (packages will be unverifiable)"

# Default turbo config (hotkey is configurable here).
cat > "$ROOTFS/etc/deposit/turbo.conf" <<EOF
# Deposit Turbo configuration
# HOTKEY is the global shortcut that toggles turbo. Change to e.g. "<Super>K".
HOTKEY="Alt+K"
EOF

# Default AQA app registry (override by editing this file on the installed OS).
cat > "$ROOTFS/etc/deposit/aqa.apps" <<EOF
# name|type|url   — add your own lines. Stream has no fixed public URL; set
# AQA_STREAM_URL in the environment, or replace __STREAM_URL__ below.
chrome|deb|https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
stream|deb|__STREAM_URL__
EOF

# --- Stage 5b: rounded theme, Thai language, curated apps/services ----------
cat > "$ROOTFS/tmp/deposit-extra.sh" <<EOF
#!/usr/bin/env bash
# Non-fatal: an unavailable optional package must not break the whole image.
export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Acquire::Retries=3 -o Acquire::http::Timeout=30"
apt-get \$APT_OPTS install -y --no-install-recommends $DEPOSIT_THEME_PKGS \
  || echo "WARN: theme install issue"
apt-get \$APT_OPTS install -y --no-install-recommends $DEPOSIT_APPS \
  || echo "WARN: apps install issue"
apt-get \$APT_OPTS install -y --no-install-recommends $DEPOSIT_SERVICES \
  || echo "WARN: services install issue"
if [ "$DEPOSIT_ENABLE_THAI" = "1" ]; then
  apt-get \$APT_OPTS install -y --no-install-recommends $DEPOSIT_THAI_FONTS locales \
    || echo "WARN: thai install issue"
  for L in $DEPOSIT_LOCALES; do
    sed -i "s|^#\? *\$L UTF-8|\$L UTF-8|" /etc/locale.gen
  done
  locale-gen || echo "WARN: locale-gen issue"
  update-locale LANG=$DEPOSIT_DEFAULT_LOCALE || true
fi
EOF
chmod +x "$ROOTFS/tmp/deposit-extra.sh"
  chroot "$ROOTFS" /tmp/deposit-extra.sh
  rm -f "$ROOTFS/tmp/deposit-extra.sh"

# --- Stage 5b.5: IBus + Thai input (ROADMAP #1) -------------------------------
# Fonts already render Thai; this makes it *typeable* via IBus (Super+Space to
# switch to the Thai engine). Set the IM modules globally and autostart ibus.
{
  echo "GTK_IM_MODULE=ibus"
  echo "QT_IM_MODULE=ibus"
  echo "XMODIFIERS=@im=ibus"
  echo "CLUTTER_IM_MODULE=ibus"
} >> "$ROOTFS/etc/environment"
printf 'run_im ibus\n' > "$ROOTFS/etc/skel/.xinputrc"
mkdir -p "$ROOTFS/etc/xdg/autostart"
cat > "$ROOTFS/etc/xdg/autostart/ibus-daemon.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=IBus
Exec=ibus-daemon -drx
X-GNOME-Autostart-enabled=true
EOF

# --- Stage 5c: quick menu + virus scanner + OS security features ----------
DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 update -qq
DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 install -y --no-install-recommends \
  clamav clamav-freshclam apparmor apparmor-utils brightnessctl rfkill \
  python3-gi gir1.2-gtk-3.0 wpasupplicant || echo "WARN: security install issue"
# Deposit tooling: bottom-right quick menu + AV wrapper (launchable in terminal).
cp "$REPO_ROOT/tools/deposit-quickmenu"      "$ROOTFS/usr/local/bin/deposit-quickmenu"
cp "$REPO_ROOT/tools/deposit-quickmenu-toggle" "$ROOTFS/usr/local/bin/deposit-quickmenu-toggle"
cp "$REPO_ROOT/tools/deposit-av"            "$ROOTFS/usr/local/bin/deposit-av"
cp "$REPO_ROOT/tools/deposit-turbo-fx"      "$ROOTFS/usr/local/bin/deposit-turbo-fx"
cp "$REPO_ROOT/tools/deposit-files"         "$ROOTFS/usr/local/bin/deposit-files"
cp "$REPO_ROOT/tools/deposit-install"       "$ROOTFS/usr/local/bin/deposit-install"
cp "$REPO_ROOT/tools/deposit-security"      "$ROOTFS/usr/local/bin/deposit-security"
cp "$REPO_ROOT/tools/deposit-updater"       "$ROOTFS/usr/local/bin/deposit-updater"
cp "$REPO_ROOT/tools/deposit-store"         "$ROOTFS/usr/local/bin/deposit-store"
cp "$REPO_ROOT/tools/deposit-oobe"          "$ROOTFS/usr/local/bin/deposit-oobe"
cp "$REPO_ROOT/tools/deposit-settings"       "$ROOTFS/usr/local/bin/deposit-settings"
chmod +x "$ROOTFS/usr/local/bin/deposit-quickmenu" "$ROOTFS/usr/local/bin/deposit-quickmenu-toggle" \
         "$ROOTFS/usr/local/bin/deposit-av" "$ROOTFS/usr/local/bin/deposit-turbo-fx" \
         "$ROOTFS/usr/local/bin/deposit-files" "$ROOTFS/usr/local/bin/deposit-install" \
         "$ROOTFS/usr/local/bin/deposit-security" "$ROOTFS/usr/local/bin/deposit-updater" \
         "$ROOTFS/usr/local/bin/deposit-store" "$ROOTFS/usr/local/bin/deposit-oobe" \
         "$ROOTFS/usr/local/bin/deposit-settings"

# Desktop entry for the file manager.
mkdir -p "$ROOTFS/usr/share/applications"
cat > "$ROOTFS/usr/share/applications/deposit-files.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Deposit Files
Exec=deposit-files
Terminal=false
Categories=System;FileTools;
EOF

# Desktop entries for the Store + Updates tools.
cat > "$ROOTFS/usr/share/applications/deposit-store.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Deposit Store
Exec=deposit-store
Terminal=false
Categories=System;PackageManager;
EOF
cat > "$ROOTFS/usr/share/applications/deposit-updater.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Deposit Updates
Exec=deposit-updater
Terminal=false
Categories=System;PackageManager;
EOF

# Desktop entry for the OS installer (used from the live ISO).
cat > "$ROOTFS/usr/share/applications/deposit-install.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install Deposit OS
Comment=Install Deposit OS to a disk from the live USB
Exec=pkexec deposit-install
Terminal=true
Categories=System;
EOF
# Show it on the live user's desktop.
mkdir -p "$ROOTFS/etc/skel/Desktop"
cp "$ROOTFS/usr/share/applications/deposit-install.desktop" "$ROOTFS/etc/skel/Desktop/"

# Desktop entry for the Settings hub (Samsung One UI / Android-hybrid).
cat > "$ROOTFS/usr/share/applications/deposit-settings.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Deposit Settings
Comment=Samsung-style settings hub (gear)
Exec=deposit-settings
Terminal=false
Icon=deposit-gear
Categories=Settings;System;
EOF

# Autostart the quick menu in the XFCE session.
mkdir -p "$ROOTFS/etc/xdg/autostart"
cat > "$ROOTFS/etc/xdg/autostart/deposit-quickmenu.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Deposit Quick Menu
Exec=deposit-quickmenu
X-GNOME-Autostart-enabled=true
EOF
# Autostart the Turbo transition spinner overlay (reacts to deposit-turbo).
cat > "$ROOTFS/etc/xdg/autostart/deposit-turbo-fx.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Deposit Turbo FX
Exec=deposit-turbo-fx
X-GNOME-Autostart-enabled=true
EOF

# Autostart the first-boot OOBE wizard (it self-skips on the live ISO and once
# the sentinel /var/lib/deposit/oobe-done exists).
cat > "$ROOTFS/etc/xdg/autostart/deposit-oobe.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Deposit First Boot Setup
Exec=deposit-oobe
X-GNOME-Autostart-enabled=true
EOF

# Bind Super+Q to toggle the quick menu (applies to the default user's session).
mkdir -p "$ROOTFS/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
cat > "$ROOTFS/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty">
    <property name="custom" type="empty">
      <property name="&lt;Super&gt;q" type="string" value="deposit-quickmenu-toggle"/>
    </property>
  </property>
  <property name="providers" type="empty">
    <property name="&lt;Super&gt;q" type="string" value="deposit-quickmenu-toggle"/>
  </property>
</channel>
EOF
# Best-effort: enforce shipped AppArmor profiles (no-op if kernel lacks AA).
chroot "$ROOTFS" /bin/bash -c 'aa-enforce /etc/apparmor.d/* 2>/dev/null || true'

umount_chroot
trap - EXIT

# --- Stage 7: rounded aesthetic (XFCE theme) + brand logo -------------------
XCONF="$ROOTFS/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XCONF" "$ROOTFS/usr/share/pixmaps" \
         "$ROOTFS/usr/share/icons/hicolor/scalable/apps"
cat > "$XCONF/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Materia"/>
    <property name="IconThemeName" type="string" value="Papirus"/>
    <property name="DoubleClickTime" type="int" value="400"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans 11"/>
    <property name="MonospaceFontName" type="string" value="Noto Sans Mono 11"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorSize" type="int" value="0"/>
    <property name="DecorationLayout" type="string" value="menu:minimize,maximize,close"/>
  </property>
</channel>
EOF
cat > "$XCONF/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Materia"/>
    <property name="title_font" type="string" value="Noto Sans Bold 11"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="round_edges" type="bool" value="true"/>
    <property name="titleless_maximize" type="bool" value="true"/>
  </property>
</channel>
EOF
# Brand assets
cp "$REPO_ROOT/assets/logo.svg"         "$ROOTFS/usr/share/pixmaps/deposit-logo.svg"
cp "$REPO_ROOT/assets/gear.svg"          "$ROOTFS/usr/share/pixmaps/deposit-gear.svg"
cp "$REPO_ROOT/assets/deposit-turbo.svg" "$ROOTFS/usr/share/icons/hicolor/scalable/apps/deposit-turbo.svg"
cp "$REPO_ROOT/assets/logo.svg"         "$ROOTFS/usr/share/icons/hicolor/scalable/apps/deposit-logo.svg"

# Plymouth boot splash theme (ROADMAP #7). Sets the theme so the initramfs built
# later in make-iso picks it up; `splash` is added to the boot cmdline there.
chroot "$ROOTFS" /bin/bash -c 'plymouth-set-default-theme spinner 2>/dev/null || true' || true
# Ensure a framebuffer is available in the initramfs for the splash.
mkdir -p "$ROOTFS/etc/initramfs-tools/conf.d"
echo "FRAMEBUFFER=y" > "$ROOTFS/etc/initramfs-tools/conf.d/splash"

# --- Stage 8: graphical first-boot (autologin straight into XFCE) ------------
# This is what makes "boot the OS" land on the Deposit OS desktop.
chroot "$ROOTFS" /bin/bash -c '
  set -e
  systemctl set-default graphical.target 2>/dev/null || true
  systemctl enable lightdm 2>/dev/null || true
  systemctl enable bluetooth 2>/dev/null || true
'
mkdir -p "$ROOTFS/etc/lightdm/lightdm.conf.d"
cat > "$ROOTFS/etc/lightdm/lightdm.conf.d/50-deposit-autologin.conf" <<EOF
[Seat:*]
autologin-user=$DEPOSIT_DEFAULT_USER
autologin-user-timeout=0
autologin-session=xfce
EOF

# Branded desktop wallpaper (XFCE) — show the Deposit logo on first boot.
cat > "$XCONF/xfce4-desktop.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/pixmaps/deposit-logo.svg"/>
        <property name="image-style" type="int" value="5"/>
      </property>
    </property>
  </property>
</channel>
EOF

# Strip the cross-build interpreter so the shipped image stays clean.
if (( CROSS )); then
  rm -f "$ROOTFS/usr/bin/qemu-${QA}-static" 2>/dev/null || true
fi
echo "[rootfs] done -> $ROOTFS"
echo "[rootfs] next: build the kernel (./build/build-kernel.sh) then pack with: mlpds build"
