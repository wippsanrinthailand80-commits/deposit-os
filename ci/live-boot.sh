#!/usr/bin/env bash
# ============================================================================
# live-boot.sh — boot the built Deposit OS under QEMU with login bypassed
# (autologin) and capture:
#   - the DESKTOP with its Sagittarius A* black-hole wallpaper
#   - Firefox opening YouTube and TYPING a Thai query ("เพลงไทย") into the
#     search box via xdotool/XTEST — a real Thai input test
# Frames come from QMP screendumps (ground truth; see pick_brightest note).
#
# Requires: qemu-system-x86_64, python3-pil, and artifacts deposit-kernel /
# deposit-rootfs already extracted into build/output.
# ============================================================================
set -euo pipefail

REPO="$PWD"
KERNEL="$REPO/build/output/kernel"
ROOTFS="$REPO/build/output/rootfs"
OUT="$REPO/build/output/deposit-disk.img"

mkdir -p /tmp/shots

VMLINUZ="$(ls "$KERNEL"/boot/vmlinuz-* 2>/dev/null | head -1)"
[[ -n "$VMLINUZ" ]] || { echo "[live] no vmlinuz found"; exit 1; }

launch_qemu() {
  echo "[live] launching QEMU (TCG, VNC :0, QMP 4444, serial -> /tmp/serial.log)"
  : > /tmp/serial.log
  qemu-system-x86_64 \
    -name "Deposit OS" \
    -m 3072 -smp 2 -cpu max \
    -kernel "$VMLINUZ" \
    -append "root=/dev/sda rw rootfstype=ext4 console=tty0 console=ttyS0,115200n8 consoleblank=0" \
    -drive file="$OUT",format=raw,if=ide \
    -netdev user,id=n0 -device e1000,netdev=n0 \
    -vga std \
    -vnc :0 \
    -serial file:/tmp/serial.log \
    -qmp tcp:127.0.0.1:4444,server,nowait \
    -daemonize
}

capture_series() { # <prefix> <t1> [t2] ...
  local prefix="$1"; shift
  local prev=0 t i=1
  for t in "$@"; do
    sleep $((t - prev))
    prev=$t
    python3 ci/qmp_screendump.py "/tmp/shots/$prefix-$i.png" 127.0.0.1 4444 --vnc-poke 5900 || \
      echo "[live] screendump $prefix-$i failed (vm may still be booting)"
    cp /tmp/serial.log "/tmp/shots/serial-up-to-${prefix}-${t}s.log" 2>/dev/null || true
    echo "[live] captured $prefix-$i.png at ${t}s"
    i=$((i + 1))
  done
}

powerdown_and_wait() {
  echo "[live] sending ACPI powerdown"
  python3 ci/qmp_cmd.py 127.0.0.1 4444 system_powerdown >/dev/null 2>&1 || true
  local i
  for i in $(seq 1 30); do
    pgrep -f qemu-system-x86_64 >/dev/null || break
    sleep 2
  done
  pgrep -f qemu-system-x86_64 >/dev/null && { echo "[live] qemu still up — killing"; pkill -f qemu-system-x86_64 || true; sleep 3; }
  sleep 2
}

mount_rw() {
  MNT_RW="$(mktemp -d)"
  sudo mount -o loop "$OUT" "$MNT_RW"
}

enable_unit() { # <service-name>
  sudo mkdir -p "$MNT_RW/etc/systemd/system/graphical.target.wants"
  sudo ln -sf "/etc/systemd/system/$1" "$MNT_RW/etc/systemd/system/graphical.target.wants/$1"
}

# Pick the BRIGHTEST frame as the phase hero. Rationale: /dev/fb0 reads go
# black once modeset Xorg flips KMS surfaces (fbdev emulation keeps mapping
# the original, abandoned buffer) — so QMP screendumps are ground truth, and
# early dumps may still be boot-console black. Brightness = content here.
pick_brightest() { # <output.png> <input.png>...
  python3 - "$@" <<'PYP'
import sys
from PIL import Image, ImageStat
args = sys.argv[1:]
dst, cands = args[0], args[1:]
best, best_b = None, -1.0
for p in cands:
    try:
        b = sum(ImageStat.Stat(Image.open(p).convert("L")).mean)
        if b > best_b:
            best, best_b = p, b
    except Exception as e:
        print(f"[live] skip {p}: {e}")
if best:
    import shutil
    shutil.copyfile(best, dst)
    print(f"[live] hero {dst} <- {best} (brightness {best_b:.1f})")
else:
    print(f"[live] WARNING: no usable candidate for {dst}")
PYP
}

harvest_probes() {
  echo "[live] harvesting probe outputs from image"
  local MNT2 LOOP f
  MNT2="$(mktemp -d)"
  LOOP="$(sudo losetup -f --show -r "$OUT" 2>/dev/null)" || LOOP=""
  if [[ -n "$LOOP" ]] && sudo mount -o ro,norecovery "$LOOP" "$MNT2"; then
    for f in deposit-metrics.txt deposit-gfxdiag.txt deposit-web.log; do
      if sudo test -s "$MNT2/var/log/$f"; then
        sudo cp "$MNT2/var/log/$f" "/tmp/$f"
        sudo chown "$(id -u):$(id -g)" "/tmp/$f"
        echo "[live] harvested $f ✓"
      else
        echo "[live] WARNING: /var/log/$f missing or empty inside image"
      fi
    done
    # fb0 truth-camera frames (per-phase PPMs written by deposit-shot@)
    for ppm in $(sudo ls "$MNT2/var/log/" 2>/dev/null | grep '^deposit-fb0.*\.ppm$' || true); do
      sudo cp "$MNT2/var/log/$ppm" "/tmp/$ppm"
      sudo chown "$(id -u):$(id -g)" "/tmp/$ppm"
      echo "[live] harvested $ppm ✓"
    done
    sudo umount "$MNT2"
  else
    echo "[live] ERROR: could not loop-mount image read-only for harvest"
  fi
  [[ -n "$LOOP" ]] && sudo losetup -d "$LOOP" 2>/dev/null || true
  rmdir "$MNT2" 2>/dev/null || true
}

# ============================================================================
# Probe installation (CI-only, throwaway copy). Logic lives in script FILES:
# systemd unit quoting cannot survive nested shell+python heredocs (run #97).
# ============================================================================
echo "[live] building disk image"
bash ci/make-disk.sh "$ROOTFS" "$KERNEL" "$OUT" 8192
echo "[live] installing probes into disk image"
mount_rw

# --- resource metrics -------------------------------------------------------
sudo tee "$MNT_RW/usr/local/sbin/deposit-metrics-probe.sh" >/dev/null <<'PROBE'
#!/bin/sh
sleep 75
{
  echo "=== Deposit OS idle metrics ==="; date -u
  echo "-- free -m --"; free -m
  echo "-- df -h / --"; df -h /
  echo "-- du -sx MB --"; du -sxm /usr /var /etc 2>/dev/null
  echo; echo "=== boot diagnostics ==="
  systemctl is-active lightdm
  systemctl status lightdm --no-pager 2>&1 | tail -8
  echo "-- journal (lightdm/X/fatal) --"
  journalctl -b --no-pager 2>/dev/null | grep -iE "lightdm|xorg|fatal|failed" | tail -25
  [ -f /var/log/Xorg.0.log ] && { echo "-- Xorg.0.log tail --"; tail -15 /var/log/Xorg.0.log; }
} > /var/log/deposit-metrics.txt 2>&1
PROBE
sudo tee "$MNT_RW/etc/systemd/system/deposit-metrics.service" >/dev/null <<'UNIT'
[Unit]
Description=Deposit OS idle resource measurement
After=graphical.target lightdm.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/deposit-metrics-probe.sh

[Install]
WantedBy=graphical.target
UNIT
sudo chmod +x "$MNT_RW/usr/local/sbin/deposit-metrics-probe.sh"

# --- graphics diagnostics + generic fb0 truth camera ------------------------
sudo tee "$MNT_RW/usr/local/sbin/deposit-gfxdiag.sh" >/dev/null <<'GFX'
#!/bin/sh
sleep 150
{
  echo "=== Deposit OS graphics diagnostics ==="; date -u
  echo "-- modules dir --"; ls /lib/modules/$(uname -r)/ 2>&1 | head -6
  echo "-- drm/tiny modules present? --"; ls /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/tiny/ 2>&1
  echo "-- modprobe bochs --"; modprobe bochs 2>&1; echo "rc=$?"
  echo "-- sysfs --"; ls /sys/class/drm/ 2>&1; ls /sys/class/graphics/ 2>&1
  echo "-- lsmod (gpu) --"; lsmod | grep -E "bochs|cirrus|drm|ttm" || echo none
  echo "-- dmesg drm --"; dmesg 2>/dev/null | grep -iE "drm|bochs|fbcon|framebuffer" | tail -15
  echo "-- udevadm info VGA --"; udevadm info -q all -n /dev/dri/card0 2>&1 | head -5
  udevadm info /sys/devices/pci0000:00/0000:00:02.0 2>&1 | grep -E "MODALIAS|DRIVER"
  echo "-- lightdm/X status --"; systemctl is-active lightdm
  pgrep -a Xorg || echo "no Xorg process"
  pgrep -a firefox || echo "no firefox process"
  [ -f /var/log/Xorg.0.log ] && tail -20 /var/log/Xorg.0.log
  echo "-- greeter/desktop log tail --"
  journalctl -u lightdm -b --no-pager 2>/dev/null | tail -10
  echo "-- backdrop proof (user xfconf after autostart enforcer) --"
  echo "-- resolved property list --"
  runuser -u deposit -- env DISPLAY=:0 \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u deposit)/bus" \
    xfconf-query -c xfce4-desktop -l -v 2>&1 | grep -iE "last-image|image-style" || echo none
  echo "-- full user channel xml --"
  cat /home/deposit/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml 2>/dev/null
  echo "-- wallpaper assets + enforcer --"
  ls -la /usr/share/backgrounds/deposit/ 2>&1
  file /usr/share/backgrounds/deposit/*.jpg 2>&1
  ls /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders/ 2>&1
  ls -la /usr/local/sbin/deposit-set-wallpaper.sh /etc/xdg/autostart/deposit-wallpaper.desktop 2>&1
  pgrep -a -f "xfconfd|xfdesktop|deposit-set-wallpaper" || true
} > /var/log/deposit-gfxdiag.txt 2>&1
GFX
sudo tee "$MNT_RW/etc/systemd/system/deposit-gfxdiag.service" >/dev/null <<'UNIT'
[Unit]
Description=Deposit OS graphics stack diagnostics
After=graphical.target lightdm.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/deposit-gfxdiag.sh

[Install]
WantedBy=graphical.target
UNIT
sudo chmod +x "$MNT_RW/usr/local/sbin/deposit-gfxdiag.sh"

# fb0 truth camera: takes a suffix (login|desktop|web); sleeps per phase so
# the capture lands after the relevant screen state settles.
sudo tee "$MNT_RW/usr/local/sbin/deposit-shot.sh" >/dev/null <<'SHOT'
#!/bin/sh
SUF="${1:-x}"
case "$SUF" in
  desktop) sleep 115 ;;  # wallpaper visible right after autologin lands
  web)     sleep 240 ;;  # typed Thai @~185s, results loaded by ~200s
  *)       sleep 30 ;;
esac
python3 - "$SUF" <<'PYEOF'
import sys
suf = sys.argv[1]
try:
    vs = open('/sys/class/graphics/fb0/virtual_size').read().split(',')
    w, h = int(vs[0]), int(vs[1])
    bpp = int(open('/sys/class/graphics/fb0/bits_per_pixel').read())
    print('fb0 %dx%d %dbpp (%s)' % (w, h, bpp, suf))
    if bpp != 32:
        print('skipping capture: need 32bpp'); raise SystemExit(0)
    try:
        stride = int(open('/sys/class/graphics/fb0/stride').read())
    except Exception:
        stride = w * 4
    need = stride * h
    f = open('/dev/fb0', 'rb')
    parts = []
    got = 0
    while got < need:
        c = f.read(need - got)
        if not c:
            break
        parts.append(c)
        got += len(c)
    d = b''.join(parts)
    print('read %d of %d bytes from /dev/fb0' % (len(d), need))
    o = open('/var/log/deposit-fb0-%s.ppm' % suf, 'wb')
    o.write(b'P6\n%d %d\n255\n' % (w, h))
    rowbuf = bytearray(w * 3)
    rows_ok = 0
    for y in range(h):
        r = d[y*stride:y*stride + w*4]
        if len(r) < w*4:
            break
        rowbuf[0::3] = r[2::4]   # BGRA/X in memory -> RGB out
        rowbuf[1::3] = r[1::4]
        rowbuf[2::3] = r[0::4]
        o.write(rowbuf)
        rows_ok += 1
    o.close()
    print('wrote /var/log/deposit-fb0-%s.ppm (%d/%d rows)' % (suf, rows_ok, h))
except SystemExit:
    raise
except Exception as e:
    print('fb0 capture failed:', e)
PYEOF
SHOT
sudo tee "$MNT_RW/etc/systemd/system/deposit-shot@.service" >/dev/null <<'UNIT'
[Unit]
Description=Deposit OS fb0 screenshot (%i)
After=graphical.target lightdm.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/deposit-shot.sh %i

[Install]
WantedBy=graphical.target
UNIT
sudo chmod +x "$MNT_RW/usr/local/sbin/deposit-shot.sh"

# --- browser choreography (YouTube -> Thai Wikipedia tab) --------------------
sudo tee "$MNT_RW/usr/local/sbin/deposit-web-open.sh" >/dev/null <<'WEB'
#!/bin/sh
# Wait for the graphical session (TCG boots slowly; fixed sleeps are fragile)
i=0
while [ $i -lt 100 ]; do
  if pgrep -x Xorg >/dev/null 2>&1 && [ -S /tmp/.X11-unix/X0 ]; then
    break
  fi
  sleep 3
  i=$((i+1))
done
sleep 10
export HOME=/home/deposit USER=deposit LOGNAME=deposit DISPLAY=:0
[ -r /home/deposit/.Xauthority ] && export XAUTHORITY=/home/deposit/.Xauthority
ENV="env HOME=$HOME USER=$USER LOGNAME=$USER DISPLAY=:0"
[ -n "${XAUTHORITY:-}" ] && ENV="$ENV XAUTHORITY=$XAUTHORITY"
XDO="$ENV xdotool"
echo "opening youtube ($ENV)"
runuser -u deposit -- sh -c "$ENV firefox-esr --new-window https://www.youtube.com >/tmp/firefox-yt.log 2>&1 &"
# Let it render, bring it forward, then TYPE a Thai query into the search
# box ('/' is YouTube's focus-search shortcut). xdotool types unicode via
# XTEST — a real end-to-end test of Thai glyph entry, not just display.
sleep 50
WID="$(runuser -u deposit -- sh -c "$XDO search --onlyvisible --name 'YouTube' 2>/dev/null | head -1")"
if [ -n "$WID" ]; then
  runuser -u deposit -- sh -c "$XDO windowactivate --sync $WID" || true
fi
runuser -u deposit -- sh -c "$XDO key --delay 80 slash" || true
sleep 1
runuser -u deposit -- sh -c "$XDO type --delay 140 'เพลงไทย'" || true
sleep 3
runuser -u deposit -- sh -c "$XDO key --delay 80 Return" || true
{ echo "wid=$WID"; pgrep -a firefox; } > /var/log/deposit-web.log 2>&1
WEB
sudo tee "$MNT_RW/etc/systemd/system/deposit-web.service" >/dev/null <<'UNIT'
[Unit]
Description=Deposit OS web smoke test (YouTube + Thai Wikipedia)
After=graphical.target lightdm.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=HOME=/root
ExecStart=/usr/local/sbin/deposit-web-open.sh

[Install]
WantedBy=graphical.target
UNIT
sudo chmod +x "$MNT_RW/usr/local/sbin/deposit-web-open.sh"

# ============================================================================
# SINGLE BOOT — login bypassed (autologin): straight to the Sgr A* desktop,
# then Firefox opens YouTube and types a Thai query.
# ============================================================================
echo "[live] injecting CI autologin (login-screen bypass) + enabling probes"
sudo bash ci/inject-autologin.sh "$MNT_RW" deposit --skip-oobe
enable_unit deposit-metrics.service
enable_unit deposit-gfxdiag.service
enable_unit "deposit-shot@desktop.service"
enable_unit "deposit-shot@web.service"
enable_unit deposit-web.service
sudo umount "$MNT_RW"; rmdir "$MNT_RW"

launch_qemu
capture_series live 40 100 160 220 280
powerdown_and_wait
cp /tmp/serial.log /tmp/shots/serial-final.log 2>/dev/null || \
  echo "[live] WARNING: no serial log — guest produced no serial output"
rm -f /tmp/deposit-fb0-*.ppm /tmp/deposit-metrics.txt /tmp/deposit-gfxdiag.txt
harvest_probes
# Heroes from QMP ground truth: guest-desktop = best pre-browser frame
# (live-1/2 @40/100s), thai-web = live-5 (@280s, Thai query results shown).
pick_brightest /tmp/shots/guest-desktop.png /tmp/shots/live-1.png /tmp/shots/live-2.png \
  || [ -s /tmp/shots/live-2.png ] && cp /tmp/shots/live-2.png /tmp/shots/guest-desktop.png
[ -s /tmp/shots/live-5.png ] && cp /tmp/shots/live-5.png /tmp/shots/thai-web.png
[ -s /tmp/deposit-metrics.txt ] && { echo "---- idle metrics ----"; cat /tmp/deposit-metrics.txt; } \
  || echo "[live] no metrics (see warnings above)"
echo "[live] done"
