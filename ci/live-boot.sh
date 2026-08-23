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

# Harvest the metrics the probe wrote into the image (persistent ext4).
echo "[live] harvesting resource metrics from image"
MNT2="$(mktemp -d)"
if sudo mount -o loop,ro "$OUT" "$MNT2"; then
  if sudo ls -la "$MNT2/var/log/deposit-metrics.txt" 2>/dev/null; then
    sudo cp "$MNT2/var/log/deposit-metrics.txt" /tmp/deposit-metrics.txt
    sudo chown "$(id -u):$(id -g)" /tmp/deposit-metrics.txt
    echo "[live] metrics harvested ✓"
  else
    echo "[live] WARNING: probe file missing inside image:"
    sudo ls -la "$MNT2/var/log/" | tail -5 || true
  fi
  sudo ls -la "$MNT2/etc/systemd/system/graphical.target.wants/" 2>/dev/null | head -8 || true
  sudo umount "$MNT2"
else
  echo "[live] ERROR: could not loop-mount image for harvest"
fi
rmdir "$MNT2" 2>/dev/null || true
[ -s /tmp/deposit-metrics.txt ] && { echo "---- idle metrics ----"; cat /tmp/deposit-metrics.txt; } \
  || echo "[live] no metrics file (probe did not run? see warnings above)"
echo "[live] done"
