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
echo "[live] injecting CI autologin into disk image"
MNT="$(mktemp -d)"
sudo mount -o loop "$OUT" "$MNT"
sudo bash ci/inject-autologin.sh "$MNT" deposit
sudo umount "$MNT"; rmdir "$MNT"

VMLINUZ="$(ls "$KERNEL"/boot/vmlinuz-* 2>/dev/null | head -1)"
[[ -n "$VMLINUZ" ]] || { echo "[live] no vmlinuz found"; exit 1; }
echo "[live] kernel: $VMLINUZ"

echo "[live] launching QEMU (TCG, VNC on :0, QMP on 4444)"
qemu-system-x86_64 \
  -name "Deposit OS" \
  -m 3072 -smp 2 -cpu max \
  -kernel "$VMLINUZ" \
  -append "root=/dev/sda rw rootfstype=ext4 vga=791 console=tty0 console=ttyS0,115200n8" \
  -drive file="$OUT",format=raw,if=ide \
  -netdev user,id=n0 -device e1000,netdev=n0 \
  -vga std \
  -vnc :0 \
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
  echo "[live] captured live-$i.png at ${t}s"
  i=$((i + 1))
done

pkill -f qemu-system-x86_64 || true
echo "[live] done"
