#!/usr/bin/env bash
# inject-autologin.sh <mounted-root> <user>
#
# CI-ONLY: enable lightdm autologin so workflow screenshots reach the desktop.
# This is deliberately NEVER baked into the shipped rootfs / image / installer —
# a real computer must show a login screen. We edit files directly (no chroot)
# so it also works on a foreign-arch root (e.g. an arm64 image mounted on x86).
set -euo pipefail

MNT="${1:?mounted root path}"
USER="${2:?username}"

mkdir -p "$MNT/etc/lightdm/lightdm.conf.d"
cat > "$MNT/etc/lightdm/lightdm.conf.d/ci-autologin.conf" <<EOF
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

echo "[autologin] enabled for $USER at $MNT"
