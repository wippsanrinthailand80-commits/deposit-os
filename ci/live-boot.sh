#!/usr/bin/env bash
# ============================================================================
# live-boot.sh — boot the built Deposit OS under QEMU and capture screenshots
# of the boot screen, the GUI, and a terminal running the AQA installer.
#
# Requires: qemu-system-x86_64, python3, and artifacts deposit-kernel /
# deposit-rootfs already extracted into build/output.
# ============================================================================
set -euo pipefail

REPO="$PWD"
KERNEL="$REPO/build/output/kernel"
ROOTFS="$REPO/build/output/rootfs"
OUT="$REPO/build/output/deposit-disk.img"

echo "[live] building disk image"
bash ci/make-disk.sh "$ROOTFS" "$KERNEL" "$OUT" 4096

# CI-ONLY: enable autologin on a throwaway copy of the disk so the screenshot
# reaches the desktop. The shipped .mlpds installer keeps a real login screen.
# --skip-oobe also pre-sets the OOBE sentinel on THIS copy only, so captures
# show the full desktop instead of the first-boot setup wizard.
echo "[live] injecting CI autologin into disk image"
MNT="$(mktemp -d)"
sudo mount -o loop "$OUT" "$MNT"
sudo bash ci/inject-autologin.sh "$MNT" deposit --skip-oobe

# Resource-metrics probe: once the desktop settles, record REAL idle RAM +
# storage usage inside the running OS. Persisted into the image at
# /var/log/deposit-metrics.txt so the CI job can harvest it after shutdown
# (job *logs* may be unreadable, but artifacts are not).
echo "[live] installing resource-metrics probe"
sudo tee "$MNT/etc/systemd/system/deposit-metrics.service" >/dev/null <<'UNIT'
[Unit]
Description=Deposit OS idle resource measurement
After=graphical.target lightdm.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'sleep 75; { echo "=== Deposit OS idle metrics ==="; date -u; echo "-- free -m --"; free -m; echo "-- df -h / --"; df -h /; echo "-- du -sx MB --"; du -sxm /usr /var /etc 2>/dev/null; echo; echo "=== boot diagnostics ==="; systemctl is-active lightdm; systemctl status lightdm --no-pager 2>&1 | tail -8; echo "-- journal (lightdm/X/fatal) --"; journalctl -b --no-pager 2>/dev/null | grep -iE "lightdm|xorg|fatal|failed" | tail -25; [ -f /var/log/Xorg.0.log ] && { echo "-- Xorg.0.log tail --"; tail -15 /var/log/Xorg.0.log; }; } > /var/log/deposit-metrics.txt 2>&1'

[Install]
WantedBy=graphical.target
UNIT
sudo mkdir -p "$MNT/etc/systemd/system/graphical.target.wants"
sudo ln -sf /etc/systemd/system/deposit-metrics.service \
            "$MNT/etc/systemd/system/graphical.target.wants/deposit-metrics.service"

# Graphics diagnostics: WHY (if ever) the display stays black. Written into
# the image at /var/log/deposit-gfxdiag.txt and harvested with the metrics.
echo "[live] installing graphics-diagnostic probe"
sudo tee "$MNT/etc/systemd/system/deposit-gfxdiag.service" >/dev/null <<'UNIT'
[Unit]
Description=Deposit OS graphics stack diagnostics
After=graphical.target lightdm.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'sleep 90; { echo "=== Deposit OS graphics diagnostics ==="; date -u; echo "-- modules dir --"; ls /lib/modules/$(uname -r)/ 2>&1 | head -6; echo "-- drm/tiny modules present? --"; ls /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/tiny/ 2>&1; echo "-- modprobe bochs --"; modprobe bochs 2>&1; echo "rc=$?"; echo "-- sysfs --"; ls /sys/class/drm/ 2>&1; ls /sys/class/graphics/ 2>&1; echo "-- lsmod (gpu) --"; lsmod | grep -E "bochs|cirrus|drm|ttm" || echo none; echo "-- dmesg drm --"; dmesg 2>/dev/null | grep -iE "drm|bochs|fbcon|framebuffer" | tail -15; echo "-- udevadm info VGA --"; udevadm info -q all -n /dev/dri/card0 2>&1 | head -5; udevadm info /sys/devices/pci0000:00/0000:00:02.0 2>&1 | grep -E "MODALIAS|DRIVER" ; echo "-- lightdm/X status --"; systemctl is-active lightdm; pgrep -a Xorg || echo "no Xorg process"; [ -f /var/log/Xorg.0.log ] && tail -20 /var/log/Xorg.0.log; } > /var/log/deposit-gfxdiag.txt 2>&1'

[Install]
WantedBy=graphical.target
UNIT
sudo ln -sf /etc/systemd/system/deposit-gfxdiag.service \
            "$MNT/etc/systemd/system/graphical.target.wants/deposit-gfxdiag.service"

sudo umount "$MNT"; rmdir "$MNT"

VMLINUZ="$(ls "$KERNEL"/boot/vmlinuz-* 2>/dev/null | head -1)"
[[ -n "$VMLINUZ" ]] || { echo "[live] no vmlinuz found"; exit 1; }
echo "[live] kernel: $VMLINUZ"

echo "[live] launching QEMU (TCG, VNC on :0, QMP on 4444, serial -> /tmp/serial.log)"
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

# Give QEMU a moment, then capture frames at increasing intervals so the
# Actions Summary shows boot -> GUI -> AQA terminal progression.
mkdir -p /tmp/shots
times=(30 90 180 300 450 600)
prev=0
i=1
for t in "${times[@]}"; do
  sleep $((t - prev))
  prev=$t
  python3 ci/qmp_screendump.py "/tmp/shots/live-$i.png" 127.0.0.1 4444 || \
    echo "[live] screendump $i failed (vm may still be booting)"
  # Keep the serial log growing into the shots dir so each artifact carries
  # the full guest console up to this timestamp (diagnoses black frames).
  cp /tmp/serial.log "/tmp/shots/serial-up-to-${t}s.log" 2>/dev/null || true
  echo "[live] captured live-$i.png at ${t}s"
  i=$((i + 1))
done

pkill -f qemu-system-x86_64 || true
sleep 3
cp /tmp/serial.log /tmp/shots/serial-final.log 2>/dev/null || \
  echo "[live] WARNING: no serial log — guest produced no serial output"

# Harvest probe outputs from the image. ext4 refuses a plain ro mount when
# the journal needs replay after our SIGTERM'd QEMU, so attach a fresh
# READ-ONLY loop device and mount with norecovery.
echo "[live] harvesting probes from image"
MNT2="$(mktemp -d)"
LOOP="$(sudo losetup -f --show -r "$OUT" 2>/dev/null)" || LOOP=""
if [[ -n "$LOOP" ]] && sudo mount -o ro,norecovery "$LOOP" "$MNT2"; then
  for f in deposit-metrics.txt deposit-gfxdiag.txt; do
    if sudo test -s "$MNT2/var/log/$f"; then
      sudo cp "$MNT2/var/log/$f" "/tmp/$f"
      sudo chown "$(id -u):$(id -g)" "/tmp/$f"
      echo "[live] harvested $f ✓"
    else
      echo "[live] WARNING: /var/log/$f missing or empty inside image"
    fi
  done
  sudo umount "$MNT2"
else
  echo "[live] ERROR: could not loop-mount image read-only for harvest"
fi
[[ -n "$LOOP" ]] && sudo losetup -d "$LOOP" 2>/dev/null || true
rmdir "$MNT2" 2>/dev/null || true
[ -s /tmp/deposit-metrics.txt ] && { echo "---- idle metrics ----"; cat /tmp/deposit-metrics.txt; } \
  || echo "[live] no metrics (see warnings above)"
echo "[live] done"
