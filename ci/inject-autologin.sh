#!/usr/bin/env bash
# inject-autologin.sh <mounted-root> <user> [conf-name] [--skip-oobe]
#
# CI/live-boot-channel helper: enable lightdm autologin.
#   default conf "ci-autologin.conf"        -> CI screenshots only (throwaway
#                                              copies; shipped media untouched)
#   conf "50-deposit-autologin.conf"        -> LIVE-BOOT CHANNEL media: boots
#                                              straight to the desktop, and
#                                              deposit-oobe REMOVES this exact
#                                              file once first-boot setup
#                                              completes, so an installed
#                                              system self-heals back to the
#                                              audited login screen (#15).
# --skip-oobe: ALSO pre-create /var/lib/deposit/oobe-done so deposit-oobe
#              self-skips and screenshots show the full desktop instead of
#              the setup wizard. FOR THROWAWAY CI COPIES ONLY — never pass
#              this when mutating shipped media (an installed system would
#              then skip OOBE and keep passwordless autologin = #15 hole).
# We edit files directly (no chroot) so it also works on a foreign-arch root.
set -euo pipefail

MNT="${1:?mounted root path}"
USER="${2:?username}"
CONF="ci-autologin.conf"
SKIP_OOBE=0
for a in "${@:3}"; do
  case "$a" in
    --skip-oobe) SKIP_OOBE=1 ;;
    *) CONF="$a" ;;
  esac
done

mkdir -p "$MNT/etc/lightdm/lightdm.conf.d"
cat > "$MNT/etc/lightdm/lightdm.conf.d/$CONF" <<EOF
[Seat:*]
autologin-user=$USER
autologin-user-timeout=0
autologin-session=xfce
EOF

# Unlock the account and clear the "must change password on first login" flag
# (set by the rootfs build) so autologin lands straight on the desktop.
SP="$MNT/etc/shadow"
if [[ -f "$SP" ]]; then
  python3 - "$SP" "$USER" <<'PY'
import sys
p, user = sys.argv[1], sys.argv[2]
out = []
for ln in open(p).read().splitlines():
    f = ln.split(":")
    if f and f[0] == user:
        f[1] = ""       # clear password (unlock)
        f[2] = "20000"  # last-change != 0 -> not "must change"
    out.append(":".join(f))
open(p, "w").write("\n".join(out) + "\n")
PY
fi

if (( SKIP_OOBE )); then
  mkdir -p "$MNT/var/lib/deposit"
  : > "$MNT/var/lib/deposit/oobe-done"
  echo "[autologin] OOBE sentinel set — setup wizard will self-skip (CI copy only)"
fi

echo "[autologin] enabled for $USER at $MNT"
