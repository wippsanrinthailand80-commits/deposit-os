#!/usr/bin/env bash
# ============================================================================
# Turbo applet installer (run by `aqa install turbo`).
# Installs the Deposit Turbo tray applet + desktop autostart, and binds the
# configurable hotkey (default Alt+K) in XFCE.
# ============================================================================
set -uo pipefail

DEST_BIN="/usr/local/bin"
APP_DIR="/usr/share/deposit-turbo"
SUDO=""; [[ "$(id -u)" -eq 0 ]] || SUDO="sudo"
HOTKEY="Alt+K"
[[ -f /etc/deposit/turbo.conf ]] && source /etc/deposit/turbo.conf

echo "turbo: installing applet..."

$SUDO DEBIAN_FRONTEND=noninteractive apt-get update -o Acquire::Retries=3 -qq
$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  python3-gi gir1.2-gtk-3.0 gir1.2-appindicator3-0.1 libnotify4

$SUDO mkdir -p "$APP_DIR" "$DEST_BIN"
$SUDO cp deposit-tray.py "$APP_DIR/deposit-tray.py"
$SUDO chmod +x "$APP_DIR/deposit-tray.py"
$SUDO ln -sf "$APP_DIR/deposit-tray.py" "$DEST_BIN/deposit-tray"

# rounded brand icon for the tray
$SUDO mkdir -p /usr/share/icons/hicolor/scalable/apps
$SUDO cp deposit-turbo.svg /usr/share/icons/hicolor/scalable/apps/deposit-turbo.svg
$SUDO gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true

# autostart (XFCE / any XDG autostart-aware DE)
$SUDO mkdir -p /etc/xdg/autostart
$SUDO cp deposit-turbo.desktop /etc/xdg/autostart/

# bind the hotkey in XFCE if present (best effort, configurable)
if command -v xfconf-query >/dev/null 2>&1; then
  xfconf-query -c xfce4-keyboard-shortcuts \
    -p "/commands/custom/$HOTKEY" -s "deposit-turbo toggle" 2>/dev/null || true
  echo "turbo: bound hotkey $HOTKEY (XFCE)"
else
  echo "turbo: XFCE not detected; bind '$HOTKEY' to 'deposit-turbo toggle' in your DE."
fi

echo "turbo: installed. Run 'deposit-tray' (or log out/in) to start the applet."
