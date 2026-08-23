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
# Beta channel: PRETTY_NAME shows "Deposit OS Beta 0.1.0.7" when codename=beta.
PRETTY_BETA="$DEPOSIT_PRETTY"
if [[ "${DEPOSIT_VERSION_CODENAME:-}" == "beta" ]]; then PRETTY_BETA="$DEPOSIT_PRETTY_BETA"; fi
cat > "$ROOTFS/etc/os-release" <<EOF
PRETTY_NAME="$PRETTY_BETA $DEPOSIT_VERSION"
NAME="$DEPOSIT_PRETTY"
VERSION_ID="$DEPOSIT_VERSION"
VERSION="$PRETTY_BETA $DEPOSIT_VERSION"
VERSION_CODENAME="$DEPOSIT_VERSION_CODENAME"
ID=$DEPOSIT_ID
ID_LIKE=$DEPOSIT_ID_LIKE
HOME_URL="$DEPOSIT_HOME_URL"
BUG_REPORT_URL="$DEPOSIT_BUG_REPORT_URL"
PRIVACY_POLICY_URL="$DEPOSIT_BUG_REPORT_URL"
SUPPORTED_ARCH="$BOOT_ARCH"
EOF
echo "$DEPOSIT_VERSION" > "$ROOTFS/etc/deposit-release"
echo "$DEPOSIT_VERSION_CODENAME" > "$ROOTFS/etc/deposit-channel" 2>/dev/null || true
# MOTD / issue for a nice first impression (nice UI: branded login banner)
cat > "$ROOTFS/etc/update-motd.d/00-deposit-beta" <<MOTD
#!/bin/sh
echo ""
echo "  ◆ Deposit OS Beta $DEPOSIT_VERSION — Andromeda (purple-blue) · x86_64 + arm64"
echo "  ◆ Windows-friendly: double-click .exe/.msi (Wine) · 'deposit-winmode on' for the taskbar look"
echo "  ◆ Packages: .deb .mlpds · .apk (Android+Alpine) · .rpm/.pkg.tar.zst (deposit-pkg)"
echo "  ◆ Kernel ~80MB • Ubuntu compat (jammy/focal) • Samsung One UI inspired"
echo ""
MOTD
chmod +x "$ROOTFS/etc/update-motd.d/00-deposit-beta" 2>/dev/null || true
echo "Deposit OS Beta $DEPOSIT_VERSION (\\l) — \\d \\t" > "$ROOTFS/etc/issue"
echo "Deposit OS Beta $DEPOSIT_VERSION" > "$ROOTFS/etc/issue.net"

echo "$DEPOSIT_DEFAULT_HOSTNAME" > "$ROOTFS/etc/hostname"

# --- Stage 3: install extra base + optional desktop -------------------------
mount_chroot
chroot "$ROOTFS" /bin/bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  export APT_OPTS="-o Acquire::Retries=5 -o Acquire::http::Timeout=180 -o Acquire::https::Timeout=180"
  apt-get $APT_OPTS update -qq
  apt-get $APT_OPTS install -y --no-install-recommends '"$DEPOSIT_EXTRA_BASE"'
'
if [[ -n "${DEPOSIT_DESKTOP_PKGS:-}" ]]; then
  # Firefox comes from Mozilla's official APT repo: Ubuntu noble only offers
  # the snap transitional package, which cannot work in our rootfs layout.
  # Repo setup is best-effort — if the keyring fetch fails, apt simply skips
  # firefox and the build continues (browser is a nicety, not a hard dep).
  if mkdir -p "$ROOTFS/etc/apt/keyrings" "$ROOTFS/etc/apt/sources.list.d" "$ROOTFS/etc/apt/preferences.d" && \
     wget -q --timeout=60 https://packages.mozilla.org/apt/repo-signing-key.gpg \
       -O "$ROOTFS/etc/apt/keyrings/packages.mozilla.org.asc" 2>/dev/null; then
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
      > "$ROOTFS/etc/apt/sources.list.d/mozilla.list"
    cat > "$ROOTFS/etc/apt/preferences.d/mozilla" <<'PIN'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
PIN
    echo "mozilla apt repo staged for firefox install"
  else
    echo "WARNING: could not fetch Mozilla signing key — no browser this build"
  fi
  chroot "$ROOTFS" /bin/bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    export APT_OPTS="-o Acquire::Retries=5 -o Acquire::http::Timeout=180 -o Acquire::https::Timeout=180"
    apt-get $APT_OPTS update -qq
    apt-get $APT_OPTS install -y --no-install-recommends '"$DEPOSIT_DESKTOP_PKGS"'
  '
fi

# --- Stage 3b: Ubuntu compat libs (jammy/focal .debs on noble) ---------------
# Path 1 delivers "almost 100% installer compat" for runtime: jammy/focal
# binaries linked against older sonames (libicu70/66, libssl1.1, libffi7)
# run on noble's newer toolchain because we ship the older libs alongside.
# We use apt pinning so noble stays 900, jammy/focal are 100 — only the
# explicitly listed compat libs are pulled, not a full downgrade.
if [[ "${DEPOSIT_ENABLE_COMPAT:-1}" == "1" ]]; then
  echo "[rootfs] enabling Ubuntu compat (jammy/focal) -> $ROOTFS"
  cat > "$ROOTFS/etc/apt/sources.list.d/jammy-compat.list" <<EOF
deb $MIRROR jammy main universe
deb $MIRROR jammy-updates main universe
deb $MIRROR jammy-security main universe
EOF
  cat > "$ROOTFS/etc/apt/sources.list.d/focal-compat.list" <<EOF
deb $MIRROR focal main universe
deb $MIRROR focal-updates main universe
deb $MIRROR focal-security main universe
EOF
  cat > "$ROOTFS/etc/apt/preferences.d/99-compat-pin" <<EOF
Package: *
Pin: release n=$DEPOSIT_SUITE
Pin-Priority: 900

Package: *
Pin: release n=jammy
Pin-Priority: 100

Package: *
Pin: release n=focal
Pin-Priority: 100
EOF
  cat > "$ROOTFS/tmp/setup-compat.sh" <<EOF
#!/usr/bin/env bash
set -e
export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Acquire::Retries=5 -o Acquire::http::Timeout=180 -o Acquire::https::Timeout=180"
apt-get \$APT_OPTS update -qq || echo "WARN: compat apt update issue"
if [ -n "$DEPOSIT_COMPAT_JAMMY_PKGS" ]; then
  apt-get \$APT_OPTS install -y --no-install-recommends $DEPOSIT_COMPAT_JAMMY_PKGS || echo "WARN: jammy compat install issue"
fi
if [ -n "$DEPOSIT_COMPAT_FOCAL_PKGS" ]; then
  apt-get \$APT_OPTS install -y --no-install-recommends $DEPOSIT_COMPAT_FOCAL_PKGS || echo "WARN: focal compat install issue"
fi
ldconfig 2>/dev/null || true
EOF
  chmod +x "$ROOTFS/tmp/setup-compat.sh"
  chroot "$ROOTFS" /tmp/setup-compat.sh || echo "WARN: compat script issue"
  rm -f "$ROOTFS/tmp/setup-compat.sh"
else
  echo "[rootfs] compat disabled (DEPOSIT_ENABLE_COMPAT=0)"
  rm -f "$ROOTFS/etc/apt/sources.list.d/jammy-compat.list" "$ROOTFS/etc/apt/sources.list.d/focal-compat.list" "$ROOTFS/etc/apt/preferences.d/99-compat-pin" 2>/dev/null || true
fi

# --- Stage 4: light first-boot setup (no systemd bloat on old HW) -----------
# Provide a simple, fast getty + network-online target. Keep services minimal.
# NOTE: do NOT clean apt lists here — later stages (5b/5c) still install
# packages; wiping /var/lib/apt/lists made every one of those installs fail
# with "Unable to locate package" and the || WARN guards hid it for months.
# The cleanup moved to the very end of this script.
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
'

# --- Stage 5: default user --------------------------------------------------
# Generate a RANDOM initial password and force a change on first login, so the
# shipped image never carries a known/default credential (closes the OOBE audit
# gap: SSH and any other auth are unusable until the user sets their own).
# NOTE: do NOT write this as 'tr ... | head -c N'. head exits early -> tr dies
# of SIGPIPE -> with pipefail the whole build aborts right here (this exact
# line silently truncated every CI rootfs for months). Read a bounded chunk
# first so every process terminates cleanly.
_RAND_SRC="$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | LC_ALL=C tr -dc 'A-Za-z0-9' || true)"
RPW="${_RAND_SRC:0:16}"
while [[ ${#RPW} -lt 16 ]]; do   # astronomically unlikely; belt & braces
  _RAND_SRC="$RPW$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | LC_ALL=C tr -dc 'A-Za-z0-9' || true)"
  RPW="${_RAND_SRC:0:16}"
done
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
APT_OPTS="-o Acquire::Retries=5 -o Acquire::http::Timeout=180"
# Stage 4 no longer wipes lists, but re-update anyway (belt & braces):
apt-get \$APT_OPTS update -qq || true
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
# Windows-friendly layer (Beta 0.1.0.8): Wine + winetricks + ntfs-3g.
# Non-fatal: an unavailable package must not break the whole image build.
if [ "$DEPOSIT_WIN_SUPPORT" = "1" ]; then
  apt-get \$APT_OPTS install -y --no-install-recommends $DEPOSIT_WIN_PKGS \
    || echo "WARN: windows-support install issue (wine/ntfs)"
fi
# Android layer (Beta 0.1.0.9): Waydroid repo is outside the Ubuntu archive;
# add key+source best-effort, then install waydroid+adb (non-fatal).
# Requires kernel Binder (CONFIG_ANDROID_BINDERFS=y in deposit-80m.cfg).
if [ "$DEPOSIT_ANDROID_SUPPORT" = "1" ]; then
  curl -fsSL --max-time 30 https://repo.waydro.id/waydroid.gpg \
    -o /usr/share/keyrings/waydroid.gpg 2>/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/waydroid.gpg] https://repo.waydro.id/ $DEPOSIT_SUITE main" \
       > /etc/apt/sources.list.d/waydroid.list \
    || echo "WARN: could not add waydroid repo"
  apt-get \$APT_OPTS install -y --no-install-recommends adb \
    || echo "WARN: adb install issue"
  apt-get \$APT_OPTS install -y --no-install-recommends waydroid \
    || echo "WARN: waydroid unavailable (repo unreachable?) - Android apps degrade to adb-only"
fi
# Bluetooth A2DP audio (AirPods/headsets) — non-fatal.
apt-get \$APT_OPTS install -y --no-install-recommends $DEPOSIT_BT_PKGS \
  || echo "WARN: bluetooth-audio install issue"
# Foreign-package extraction (.rpm / Arch .pkg.tar.zst) for deposit-pkg.
if [ "$DEPOSIT_FOREIGN_SUPPORT" = "1" ]; then
  apt-get \$APT_OPTS install -y --no-install-recommends rpm2cpio cpio zstd \
    || echo "WARN: foreign-pkg tools install issue"
fi
EOF
chmod +x "$ROOTFS/tmp/deposit-extra.sh"
  chroot "$ROOTFS" /tmp/deposit-extra.sh
  rm -f "$ROOTFS/tmp/deposit-extra.sh"

# --- Alpine .apk support: ship a static apk-tools (Alpine Package Keeper) ----
# NOTE: ".apk" is TWO different formats. Android APK = zip with
# AndroidManifest.xml. Alpine apk = signed tar.gz installed by apk-tools.
# deposit-apk detects the kind and routes accordingly. This block fetches the
# official static binary from dl-cdn.alpinelinux.org at BUILD time (runtime
# stays offline-friendly) and strips its two signature header lines.
if [[ "${DEPOSIT_ALPINE_SUPPORT:-1}" == "1" ]]; then
  case "$(deposit_debootstrap_arch)" in
    amd64)  ALP_ARCH="x86_64"  ;;
    arm64)  ALP_ARCH="aarch64" ;;
    armhf)  ALP_ARCH="armv7"   ;;
    *)      ALP_ARCH="x86_64"  ;;
  esac
  ALP_MIRROR="${DEPOSIT_ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
  ALP_BRANCH="${DEPOSIT_ALPINE_BRANCH:-latest-stable}"
  echo "[rootfs] fetching apk-tools-static ($ALP_ARCH) for Alpine .apk support"
  IDX="$(mktemp)"
  if curl -fsSL --max-time 45 "$ALP_MIRROR/$ALP_BRANCH/main/$ALP_ARCH/" -o "$IDX"; then
    APKF="$(grep -o 'apk-tools-static-[^"]*\.apk' "$IDX" | head -1 || true)"
    if [[ -n "$APKF" ]] && curl -fsSL --max-time 90 "$ALP_MIRROR/$ALP_BRANCH/main/$ALP_ARCH/$APKF" -o /tmp/apks.apk; then
      # Parser must NEVER kill the build: Alpine may ship v2 (Q1/Q2 sig header)
      # or v3 (plain concatenated gzip tars). Auto-detect. Non-fatal on failure.
      if python3 - /tmp/apks.apk "$ROOTFS/usr/local/libexec/apk.static" <<'PYEOF'
import io, sys, tarfile, zlib
raw = open(sys.argv[1], "rb").read()
i = 0
if raw[:2] == b"Q1":                       # v2: skip signature header
    i = raw.index(b"\n") + 1
    if raw[i:i+2] != b"Q2":
        sys.exit("unexpected apk-tools-static header")
    L = int.from_bytes(raw[i+2:i+6], "big")
    i += 6 + L
rest, chunks = raw[i:], []
while rest[:2] == b"\x1f\x8b":             # gzip magic, member by member
    dobj = zlib.decompressobj(31)
    try:
        chunks.append(dobj.decompress(rest))
    except zlib.error:
        break
    rest = dobj.unused_data.lstrip(b"\x00")
if not chunks:
    sys.exit("no gzip members in apk-tools-static")
for data in chunks:                        # control & data are separate tars
    with tarfile.open(fileobj=io.BytesIO(data)) as tf:
        for m in tf.getmembers():
            if m.name == "sbin/apk.static":
                open(sys.argv[2], "wb").write(tf.extractfile(m).read())
                print(f"[rootfs] apk.static extracted ({m.size} bytes)")
                sys.exit(0)
sys.exit("apk.static not found in package")
PYEOF
      then
        chmod 755 "$ROOTFS/usr/local/libexec/apk.static" 2>/dev/null || true
      else
        echo "WARN: apk-tools-static parse failed (Alpine format change?) - Alpine .apk support degraded, continuing"
      fi
    else
      echo "WARN: could not download apk-tools-static - continuing"
    fi
  else
    echo "WARN: alpine CDN unreachable (apk support degraded) - continuing"
  fi
  rm -f "$IDX" /tmp/apks.apk
fi

# .apk double-click handler — deposit-apk sniffs Android vs Alpine format.
cat > "$ROOTFS/usr/share/applications/deposit-apk-open.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=APK Installer (Deposit)
Exec=deposit-apk %f
Terminal=false
NoDisplay=true
MimeType=application/vnd.android.package-archive;application/gzip;application/octet-stream;application/x-archive;
Categories=System;
EOF
# .rpm / Arch package handler — deposit-pkg extracts into isolated prefixes.
cat > "$ROOTFS/usr/share/applications/deposit-pkg-open.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=RPM/Arch Package Installer (Deposit)
Exec=deposit-pkg %f
Terminal=false
NoDisplay=true
MimeType=application/x-rpm;application/x-zstd-compressed-tar;application/x-compressed-tar;
Categories=System;
EOF
chroot "$ROOTFS" update-desktop-database /usr/share/applications 2>/dev/null || true

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
DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=180 update -qq
DEBIAN_FRONTEND=noninteractive chroot "$ROOTFS" apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=180 install -y --no-install-recommends \
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
cp "$REPO_ROOT/tools/deposit-compat"         "$ROOTFS/usr/local/bin/deposit-compat"
cp "$REPO_ROOT/tools/deposit-win"            "$ROOTFS/usr/local/bin/deposit-win"
cp "$REPO_ROOT/tools/deposit-winmode"        "$ROOTFS/usr/local/bin/deposit-winmode"
cp "$REPO_ROOT/tools/deposit-apk"            "$ROOTFS/usr/local/bin/deposit-apk"
cp "$REPO_ROOT/tools/deposit-pkg"            "$ROOTFS/usr/local/bin/deposit-pkg"
chmod +x "$ROOTFS/usr/local/bin/deposit-quickmenu" "$ROOTFS/usr/local/bin/deposit-quickmenu-toggle" \
         "$ROOTFS/usr/local/bin/deposit-av" "$ROOTFS/usr/local/bin/deposit-turbo-fx" \
         "$ROOTFS/usr/local/bin/deposit-files" "$ROOTFS/usr/local/bin/deposit-install" \
         "$ROOTFS/usr/local/bin/deposit-security" "$ROOTFS/usr/local/bin/deposit-updater" \
         "$ROOTFS/usr/local/bin/deposit-store" "$ROOTFS/usr/local/bin/deposit-oobe" \
         "$ROOTFS/usr/local/bin/deposit-settings" "$ROOTFS/usr/local/bin/deposit-compat" \
         "$ROOTFS/usr/local/bin/deposit-win" "$ROOTFS/usr/local/bin/deposit-winmode"

# Windows installer handler: .exe / .msi open with deposit-win (Wine, as user).
cat > "$ROOTFS/usr/share/applications/deposit-win-open.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Windows Installer (Deposit)
Exec=deposit-win %f
Terminal=false
NoDisplay=true
MimeType=application/vnd.microsoft.portable-executable;application/x-ms-dos-executable;application/x-msi;
Categories=System;
EOF
chroot "$ROOTFS" update-desktop-database /usr/share/applications 2>/dev/null || true

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
    <property name="ThemeName" type="string" value="Materia-dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="DoubleClickTime" type="int" value="400"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans 11"/>
    <property name="MonospaceFontName" type="string" value="Noto Sans Mono 11"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorSize" type="int" value="24"/>
    <property name="DecorationLayout" type="string" value="menu:minimize,maximize,close"/>
    <property name="DialogsUseHeader" type="bool" value="true"/>
  </property>
</channel>
EOF
cat > "$XCONF/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Materia-dark"/>
    <property name="title_font" type="string" value="Noto Sans Bold 11"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="round_edges" type="bool" value="true"/>
    <property name="titleless_maximize" type="bool" value="true"/>
    <!-- smooth like commercial distros: compositing + subtle shadows/animations -->
    <property name="use_compositing" type="bool" value="true"/>
    <property name="shadow_opacity" type="uint" value="50"/>
    <property name="show_popup_shadow" type="bool" value="true"/>
    <property name="wrap_cycle" type="bool" value="true"/>
    <property name="cycle_draw_frame" type="bool" value="false"/>
  </property>
</channel>
EOF
# NOTE: xsettings is written exactly once here (Materia-dark + Papirus-Dark to match
# the Andromeda purple-blue theme). Do not add a second writer below.
# Brand assets — nice UI: wallpapers + icons + Plymouth
mkdir -p "$ROOTFS/usr/share/backgrounds/deposit" "$ROOTFS/usr/share/pixmaps" \
         "$ROOTFS/usr/share/icons/hicolor/scalable/apps"
cp "$REPO_ROOT/assets/logo.svg"              "$ROOTFS/usr/share/pixmaps/deposit-logo.svg"
cp "$REPO_ROOT/assets/gear.svg"               "$ROOTFS/usr/share/pixmaps/deposit-gear.svg"
cp "$REPO_ROOT/assets/deposit-turbo.svg"      "$ROOTFS/usr/share/icons/hicolor/scalable/apps/deposit-turbo.svg"
cp "$REPO_ROOT/assets/logo.svg"               "$ROOTFS/usr/share/icons/hicolor/scalable/apps/deposit-logo.svg"
# Beta wallpapers — Andromeda (hero), light/dark/abstract alternates
for wp in wallpaper-andromeda.svg wallpaper-light.svg wallpaper-dark.svg wallpaper-abstract.svg; do
  if [[ -f "$REPO_ROOT/assets/$wp" ]]; then
    cp "$REPO_ROOT/assets/$wp" "$ROOTFS/usr/share/backgrounds/deposit/$wp"
  fi
done
# Also install as pixmaps for greeter fallback (Andromeda is the hero art)
cp "$REPO_ROOT/assets/wallpaper-andromeda.svg" "$ROOTFS/usr/share/pixmaps/deposit-wallpaper.svg" 2>/dev/null || true
# THE hero wallpaper (login): real Andromeda galaxy photograph (Adam Evans,
# CC BY 2.0 — see assets/ATTRIBUTIONS.md).
HERO_JPG="/usr/share/backgrounds/deposit/andromeda-galaxy.jpg"
if [[ -f "$REPO_ROOT/assets/wallpaper-andromeda-galaxy.jpg" ]]; then
  cp "$REPO_ROOT/assets/wallpaper-andromeda-galaxy.jpg" "$ROOTFS$HERO_JPG"
fi
# THE desktop wallpaper: Sagittarius A* — the black hole at the center of
# the Milky Way (Event Horizon Telescope Collaboration, CC BY 4.0).
DESK_JPG="/usr/share/backgrounds/deposit/sagittarius-a.jpg"
if [[ -f "$REPO_ROOT/assets/wallpaper-sagittarius-a.jpg" ]]; then
  cp "$REPO_ROOT/assets/wallpaper-sagittarius-a.jpg" "$ROOTFS$DESK_JPG"
fi
# Pre-render the vector wallpaper to PNG as fallback. lightdm-gtk-greeter
# loads images via gdk-pixbuf and CRASHES on SVG when librsvg's loader isn't
# installed — so we rasterize at build time instead of shipping raw SVG.
if command -v rsvg-convert >/dev/null 2>&1 && [[ -f "$ROOTFS/usr/share/pixmaps/deposit-wallpaper.svg" ]]; then
  rsvg-convert -w 1920 -h 1080 -b '#0b1020' \
    "$ROOTFS/usr/share/pixmaps/deposit-wallpaper.svg" \
    -o "$ROOTFS/usr/share/backgrounds/deposit/wallpaper-andromeda.png" || true
fi
# Plymouth boot splash theme — spinner with Deposit branding on framebuffer
chroot "$ROOTFS" /bin/bash -c 'plymouth-set-default-theme spinner 2>/dev/null || true' || true
# Plymouth text + logo (nice UI during boot: show Beta version)
mkdir -p "$ROOTFS/usr/share/plymouth/themes/spinner"
if [[ -f "$REPO_ROOT/assets/logo.svg" ]]; then
  cp "$REPO_ROOT/assets/logo.svg" "$ROOTFS/usr/share/plymouth/themes/spinner/watermark.png" 2>/dev/null || true
fi
mkdir -p "$ROOTFS/etc/initramfs-tools/conf.d"
echo "FRAMEBUFFER=y" > "$ROOTFS/etc/initramfs-tools/conf.d/splash"
# LightDM greeter (Andromeda galaxy login, Breeze-Dark, centered)
# Background: the real galaxy photo when shipped, else pre-rendered vector
# PNG, else the solid deep-space color. Never a raw SVG (see note above).
GREETER_BG="/usr/share/backgrounds/deposit/andromeda-galaxy.jpg"
[[ -f "$ROOTFS$GREETER_BG" ]] || GREETER_BG="/usr/share/backgrounds/deposit/wallpaper-andromeda.png"
[[ -f "$ROOTFS$GREETER_BG" ]] || GREETER_BG="#0b1020"
mkdir -p "$ROOTFS/etc/lightdm"
cat > "$ROOTFS/etc/lightdm/lightdm-gtk-greeter.conf" <<GREETER
[greeter]
background=$GREETER_BG
theme-name=Breeze-Dark
font-name=DejaVu Sans 11
xft-antialias=true
xft-hintstyle=hintslight
position=center 45%,center
clock-format=%a, %d %b  %H:%M
indicators=~host;~spacer;~clock;~spacer;~session;~language;~power
GREETER
# NOTE: background is a pre-rendered PNG on purpose (never an SVG).
# lightdm-gtk-greeter loads images via gdk-pixbuf; pointing it at an SVG
# crashed greeters on installs where librsvg's loader wasn't pulled in.
# The XFCE desktop uses the same galaxy photo via xfconf defaults below.

# System-wide XFCE desktop wallpaper for EVERY new user: Sagittarius A*,
# the Milky Way's central black hole (zoomed). Login keeps Andromeda.
mkdir -p "$ROOTFS/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
cat > "$ROOTFS/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" <<XFD
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="single-workspace-number" type="int" value="0">
      <property name="last-image" type="string" value="$DESK_JPG"/>
      <property name="image-style" type="int" value="5"/>
    </property>
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-style" type="int" value="5"/>
        <property name="last-image" type="string" value="$DESK_JPG"/>
      </property>
    </property>
  </property>
</channel>
XFD

# Plymouth watermark: rasterize the galaxy logo properly (the old build
# copied raw SVG bytes into a .png filename, which plymouth can't render).
if command -v rsvg-convert >/dev/null 2>&1 && [[ -f "$ROOTFS/usr/share/pixmaps/deposit-logo.svg" ]]; then
  rsvg-convert -w 256 -h 256 "$ROOTFS/usr/share/pixmaps/deposit-logo.svg" \
    -o "$ROOTFS/usr/share/plymouth/themes/spinner/watermark.png" || true
fi

# Boot splash "deposit": clone the upstream spinner theme, rename it, and
# paint a deep-space purple gradient behind the galaxy watermark + progress
# dots. Falls back to plain spinner automatically if anything above failed.
SP_PLY="$ROOTFS/usr/share/plymouth/themes/spinner"
DP_PLY="$ROOTFS/usr/share/plymouth/themes/deposit"
if [[ -f "$SP_PLY/spinner.plymouth" ]]; then
  rm -rf "$DP_PLY"
  mkdir -p "$DP_PLY"
  cp -a "$SP_PLY/." "$DP_PLY/"
  mv "$DP_PLY/spinner.plymouth" "$DP_PLY/deposit.plymouth"
  sed -i 's/^Name=.*/Name=Deposit OS/' "$DP_PLY/deposit.plymouth"
  grep -q '^BackgroundStartColor=' "$DP_PLY/deposit.plymouth" || \
    printf 'BackgroundStartColor=0x0a0630\nBackgroundEndColor=0x1b1040\n' >> "$DP_PLY/deposit.plymouth"
  chroot "$ROOTFS" plymouth-set-default-theme deposit 2>/dev/null || true
fi

# --- Windows-style mode templates (Beta 0.1.0.8, deposit-winmode) -----------
# Two full xfce4-panel layouts shipped read-only; deposit-winmode copies the
# chosen one into the user's xfconf and restarts the panel. No root needed
# at runtime.
mkdir -p "$ROOTFS/usr/share/deposit/winmode"
cat > "$ROOTFS/usr/share/deposit/winmode/deposit-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=960;y=1040"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="false"/>
      <property name="size" type="uint" value="36"/>
      <property name="background-style" type="uint" value="0"/>
      <property name="background-color" type="array">
        <value type="uint" value="18"/><value type="uint" value="14"/><value type="uint" value="42"/><value type="uint" value="235"/>
      </property>
      <property name="background-rgba" type="array">
        <value type="double" value="0.07"/><value type="double" value="0.055"/><value type="double" value="0.165"/><value type="double" value="0.88"/>
      </property>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/><value type="int" value="2"/><value type="int" value="3"/><value type="int" value="4"/>
      </property>
    </property>
  </property>
</channel>
EOF
cat > "$ROOTFS/usr/share/deposit/winmode/windows-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=960;y=1059"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="42"/>
      <property name="background-style" type="uint" value="0"/>
      <property name="background-color" type="array">
        <value type="uint" value="18"/><value type="uint" value="14"/><value type="uint" value="42"/><value type="uint" value="242"/>
      </property>
      <property name="background-rgba" type="array">
        <value type="double" value="0.07"/><value type="double" value="0.055"/><value type="double" value="0.165"/><value type="double" value="0.95"/>
      </property>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/><value type="int" value="2"/><value type="int" value="3"/><value type="int" value="4"/><value type="int" value="5"/>
      </property>
      <property name="plugins" type="empty">
        <property name="plugin-1" type="string" value="whiskermenu">
          <property name="button-title" type="string" value="Start"/>
          <property name="button-icon" type="string" value="deposit-logo"/>
        </property>
        <property name="plugin-2" type="string" value="separator">
          <property name="expand" type="bool" value="true"/>
        </property>
        <property name="plugin-3" type="string" value="tasklist">
          <property name="grouping" type="uint" value="1"/>
        </property>
        <property name="plugin-4" type="string" value="systray">
          <property name="show-frame" type="bool" value="false"/>
        </property>
        <property name="plugin-5" type="string" value="clock">
          <property name="format" type="string" value="%a %H:%M   %d/%m"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF

# Windows-mode GTK look: Breeze-dark widgets + Breeze cursors (closest
# packaged stack to Windows' flat UI); Deposit mode restores Materia-dark.
cat > "$ROOTFS/usr/share/deposit/winmode/windows-xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Breeze-dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="DoubleClickTime" type="int" value="400"/>
    <property name="CursorThemeName" type="string" value="breeze_cursors"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Carlito 10"/>
    <property name="MonospaceFontName" type="string" value="Noto Sans Mono 10"/>
    <property name="DecorationLayout" type="string" value=":minimize,maximize,close"/>
    <property name="DialogsUseHeader" type="bool" value="true"/>
  </property>
</channel>
EOF
cat > "$ROOTFS/usr/share/deposit/winmode/deposit-xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Materia-dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="DoubleClickTime" type="int" value="400"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans 11"/>
    <property name="MonospaceFontName" type="string" value="Noto Sans Mono 11"/>
    <property name="DecorationLayout" type="string" value="menu:minimize,maximize,close"/>
    <property name="DialogsUseHeader" type="bool" value="true"/>
  </property>
</channel>
EOF

# Wine execution policy for deposit-win (sandbox + sha256 allowlist).
mkdir -p "$ROOTFS/etc/deposit"
cat > "$ROOTFS/etc/deposit/win.conf" <<EOF
# deposit-win policy — user override: ~/.config/deposit/win.conf
# SANDBOX: auto | firejail | bwrap | none   (auto = firejail, else bwrap)
SANDBOX="auto"
# HASH_POLICY: block | warn
# block = refuse installers whose sha256 is not whitelisted (no CLI bypass).
# warn  = loud warning only.
HASH_POLICY="block"
EOF
cat > "$ROOTFS/etc/deposit/win-hash-whitelist" <<'EOF'
# /etc/deposit/win-hash-whitelist — one sha256 per line.
# Lines starting with '#' are comments; an optional label may follow the hash.
# Users can whitelist their own installers in:
#   ~/.config/deposit/win-hash-whitelist
# Example:
# 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08  ubuntu-installer-test.exe
EOF

# Foreign-package policy for deposit-pkg (.rpm / .pkg.tar.zst) — same model
# as win.conf: sandboxed run + sha256 allowlist, no CLI bypass.
cat > "$ROOTFS/etc/deposit/pkg.conf" <<EOF
# deposit-pkg policy — user override: ~/.config/deposit/pkg.conf
# SANDBOX: auto | bwrap | none   (auto = bwrap when available)
SANDBOX="auto"
# HASH_POLICY: block | warn
# block = refuse packages whose sha256 is not whitelisted (no CLI bypass).
# warn  = loud warning only.
HASH_POLICY="block"
EOF
cat > "$ROOTFS/etc/deposit/pkg-hash-whitelist" <<'EOF'
# /etc/deposit/pkg-hash-whitelist — one sha256 per line.
# Lines starting with '#' are comments; an optional label may follow the hash.
# Users can whitelist their own .rpm/.pkg.tar.zst files in:
#   ~/.config/deposit/pkg-hash-whitelist   (or: deposit-pkg allow FILE)
# Example:
# 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08  hello-2.12.rpm
EOF

# Alpine .apk policy — gates deposit-apk --insecure (signature bypass).
cat > "$ROOTFS/etc/deposit/apk.conf" <<EOF
# deposit-apk policy — user override: ~/.config/deposit/apk.conf
# ALLOW_INSECURE controls 'deposit-apk --insecure' (skips signature checks):
#   ask    = interactive confirmation required (type ALLOW); scripts refused
#   always = allowed without prompt (for CI/scripted builds)
#   never  = --insecure refused entirely
ALLOW_INSECURE="ask"
EOF

# Force-load the QEMU/Bochs KMS driver at boot so VMs and machines with
# std-VGA-class adapters get a real framebuffer (fbcon + X modesetting).
# Harmless on other hardware: the driver simply doesn't bind.
mkdir -p "$ROOTFS/etc/modules-load.d"
printf '# Deposit OS: display stack for QEMU/std-VGA-class hardware\nbochs\ncirrus\n' \
  > "$ROOTFS/etc/modules-load.d/deposit-gpu.conf"

# --- Stage 8: graphical first-boot (autologin straight into XFCE) ------------
# This is what makes "boot the OS" land on the Deposit OS desktop.
chroot "$ROOTFS" /bin/bash -c '
  set -e
  systemctl set-default graphical.target 2>/dev/null || true
  systemctl enable lightdm 2>/dev/null || true
  systemctl enable bluetooth 2>/dev/null || true
'
# Belt & braces: some chroot environments fail `systemctl set-default`
# silently (swallowed above), shipping images that boot to a CONSOLE login
# instead of the desktop. Force the symlink directly — idempotent.
ln -sfn /lib/systemd/system/graphical.target "$ROOTFS/etc/systemd/system/default.target"
[[ "$(basename "$(readlink "$ROOTFS/etc/systemd/system/default.target")")" == "graphical.target" ]] \
  || { echo "[rootfs] FATAL: default.target not graphical"; exit 1; }
# NOTE: autologin is intentionally NOT baked here. The shipped image/installer
# must show a real login screen on a regular computer. CI enables autologin for
# screenshots only (ci/inject-autologin.sh), on a throwaway copy of the media.

# Branded desktop wallpaper (XFCE) — Andromeda hero art, purple-blue theme
cat > "$XCONF/xfce4-desktop.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/deposit/wallpaper-andromeda.svg"/>
        <property name="image-style" type="int" value="5"/>
        <property name="color-style" type="int" value="0"/>
        <property name="color1" type="array">
          <value type="uint" value="11"/><value type="uint" value="7"/><value type="uint" value="36"/><value type="uint" value="255"/>
        </property>
      </property>
      <property name="monitor1" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/deposit/wallpaper-andromeda.svg"/>
        <property name="image-style" type="int" value="5"/>
      </property>
    </property>
    <property name="desktop-icons" type="empty">
      <property name="icon-size" type="uint" value="48"/>
      <property name="show-tooltips" type="bool" value="true"/>
    </property>
  </property>
</channel>
EOF
# XFCE panel — nice UI: translucent deep-purple glass over the galaxy
mkdir -p "$ROOTFS/etc/xdg/xfce4/panel" "$ROOTFS/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
cat > "$XCONF/xfce4-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=960;y=1040"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="false"/>
      <property name="size" type="uint" value="36"/>
      <property name="background-style" type="uint" value="0"/>
      <property name="background-color" type="array">
        <value type="uint" value="18"/><value type="uint" value="14"/><value type="uint" value="42"/><value type="uint" value="235"/>
      </property>
      <property name="background-rgba" type="array">
        <value type="double" value="0.07"/><value type="double" value="0.055"/><value type="double" value="0.165"/><value type="double" value="0.88"/>
      </property>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/><value type="int" value="2"/><value type="int" value="3"/><value type="int" value="4"/>
      </property>
    </property>
  </property>
</channel>
EOF
# Version watermark on the desktop (nice touch for Beta)
mkdir -p "$ROOTFS/etc/skel/Desktop"
cat > "$ROOTFS/etc/skel/Desktop/README-Beta.desktop" <<DESK
[Desktop Entry]
Type=Link
Name=Welcome to Deposit OS Beta 0.1.0.7 — Andromeda
Comment=Beta 0.1.0.7 — Andromeda purple-blue theme, 80MB kernel, x86_64 + arm64, Ubuntu compat
URL=https://example.invalid/deposit-os
Icon=deposit-logo
DESK

# --- Final integrity gate: a truncated build must FAIL loudly ----------------
# (The silent-truncation bug: a mid-script death used to still produce a
# "green" artifact missing greeter/tools/firmware. Never again.)
echo "[rootfs] integrity gate:"
FAILED=0
for f in usr/bin/Xorg usr/bin/startxfce4 usr/sbin/lightdm \
         usr/sbin/NetworkManager usr/bin/pulseaudio /usr/local/bin/aqa; do
  if [[ ! -e "$ROOTFS/$f" ]]; then echo "  MISSING: $f"; FAILED=1; fi
done
if [[ -z "$(ls -A "$ROOTFS/usr/lib/firmware" 2>/dev/null)" ]]; then
  echo "  MISSING: /usr/lib/firmware is empty"; FAILED=1
fi
if [[ "$(basename "$(readlink "$ROOTFS/etc/systemd/system/default.target" 2>/dev/null)")" != "graphical.target" ]]; then
  echo "  MISSING: default.target -> graphical"; FAILED=1; fi
# lightdm-gtk-greeter lives in /usr/sbin on Debian/Ubuntu (not libexec):
if [[ ! -e "$ROOTFS/usr/sbin/lightdm-gtk-greeter" && ! -e "$ROOTFS/usr/libexec/lightdm-gtk-greeter" ]]; then
  echo "  MISSING: lightdm gtk greeter (sbin|libexec)"; FAILED=1
fi
(( FAILED )) && { echo "[rootfs] FATAL: integrity gate failed"; exit 1; }
echo "[rootfs] integrity gate: OK"

# Space-saving cleanup LAST — after every apt consumer has finished.
chroot "$ROOTFS" /bin/bash -c 'apt-get clean; rm -rf /var/lib/apt/lists/*' || true

# Strip the cross-build interpreter so the shipped image stays clean.
if (( CROSS )); then
  rm -f "$ROOTFS/usr/bin/qemu-${QA}-static" 2>/dev/null || true
fi
echo "[rootfs] done -> $ROOTFS"
echo "[rootfs] next: build the kernel (./build/build-kernel.sh) then pack with: mlpds build"
