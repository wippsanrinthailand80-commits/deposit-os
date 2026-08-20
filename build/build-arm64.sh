#!/usr/bin/env bash
# build-arm64.sh — build the GENERAL-PURPOSE ARM64 Deposit OS from scratch.
#
# Produces a portable UEFI/ACPI ARM64 image (boots on QEMU -M virt, Pi 4/5 UEFI,
# Rockchip, Snapdragon X, NVIDIA DGX Spark) instead of an x86 PC ISO.
#
# On an x86_64 CI host this cross-builds via qemu-user-static; on an ARM64
# host it builds natively.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${DEPOSIT_OUT:-$SCRIPT_DIR/../build/output}"
SIZE="${DEPOSIT_ARM64_SIZE:-4096}"

export DEPOSIT_ARCH=aarch64

mkdir -p "$OUT"

echo "==> building ARM64 kernel"
bash "$SCRIPT_DIR/build-kernel.sh"

echo "==> building ARM64 rootfs (debootstrap arm64)"
bash "$SCRIPT_DIR/build-rootfs.sh"

echo "==> assembling general ARM64 UEFI image"
bash "$SCRIPT_DIR/../ci/make-arm64-image.sh" \
  "$OUT/rootfs" \
  "$OUT/kernel" \
  "$OUT/deposit-arm64.img" \
  "$SIZE"

echo "==> done: $OUT/deposit-arm64.img"
