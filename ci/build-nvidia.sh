#!/usr/bin/env bash
# ============================================================================
# build-nvidia.sh — BETA NVIDIA support: compile NVIDIA's OPEN kernel modules
# against the freshly-built Deposit OS kernel and bundle the matching Ubuntu
# userspace (GL/X/Vulkan/NVENC/firmware) into a single .mlpds driver package.
#
#   Output: build/output/nvidia-beta.mlpds   (type=driver, GPG-signed when a
#           DEPOSIT_GPG_PRIVATE_FILE key is provided, unsigned dev pkg otherwise)
#
# This is the BETA channel: any failure here logs loudly and exits non-zero,
# but the CI job wrapping it uses continue-on-error — the main pipeline never
# breaks because of it.
#
# Requirements: the kernel job has already built build/output/linux-6.6.58
# (with Module.symvers), git, dpkg-dev, and access to Ubuntu multiverse.
# ============================================================================
set -uo pipefail

NV_VER="${DEPOSIT_NVIDIA_VERSION:-550.107.02}"     # open-gpu-kernel-modules tag
UBU_SERIES="550"                                   # matching userspace series
REPO="$PWD"
KDIR="$REPO/build/output/linux-6.6.58"
OUT="$REPO/build/output"

log(){ echo "[nvidia] $*"; }
fail(){ echo "[nvidia] FAIL: $*" >&2; exit 1; }

[[ -d "$KDIR" ]] || fail "kernel build tree not found: $KDIR"
[[ -f "$KDIR/Module.symvers" ]] || fail "Module.symvers missing — kernel not fully built?"
KREL="$(cat "$KDIR/include/config/kernel.release" 2>/dev/null)" || fail "kernel.release unreadable"
log "kernel release: $KREL"

# --- 1. Open GPU kernel modules ---------------------------------------------
log "cloning open-gpu-kernel-modules $NV_VER"
rm -rf ogkm
git clone -q --depth 1 --branch "$NV_VER" \
  https://github.com/NVIDIA/open-gpu-kernel-modules ogkm \
  || fail "could not clone tag $NV_VER (check DEPOSIT_NVIDIA_VERSION)"

log "building kernel modules (this takes a few minutes)"
make -j"$(nproc)" -C ogkm/kernel-open \
     SYSSRC="$KDIR" SYSOUT="$KDIR" modules \
  > /tmp/nvidia-kbuild.log 2>&1 || { tail -30 /tmp/nvidia-kbuild.log; fail "kbuild failed"; }

MODS=""
for m in nvidia nvidia-modeset nvidia-drm nvidia-uvm nvidia-peermem nvidia-nvswitch nvidia-vgpu; do
  [[ -f "ogkm/kernel-open/$m.ko" ]] && MODS="$MODS ogkm/kernel-open/$m.ko"
done
[[ -n "$MODS" ]] || { tail -30 /tmp/nvidia-kbuild.log; fail "no modules produced"; }
log "built modules:$MODS"

# --- 2. Userspace from Ubuntu multiverse (unmodified debs) -------------------
log "fetching Ubuntu userspace packages (series $UBU_SERIES)"
PKGS="libnvidia-gl-$UBU_SERIES xserver-xorg-video-nvidia-$UBU_SERIES \
      libnvidia-encode-$UBU_SERIES libnvidia-firmware-$UBU_SERIES \
      nvidia-utils-$UBU_SERIES libnvidia-cfg1-$UBU_SERIES"
DL="$(mktemp -d)"
( cd "$DL" && apt-get download $PKGS ) > /tmp/nvidia-dl.log 2>&1 \
  || { tail -20 /tmp/nvidia-dl.log; fail "userspace download failed"; }

# --- 3. Assemble payload (absolute-layout tree) -----------------------------
PAYLOAD="$DL/payload"
mkdir -p "$PAYLOAD"
for d in "$DL"/*.deb; do dpkg -x "$d" "$PAYLOAD"; done
mkdir -p "$PAYLOAD/lib/modules/$KREL/updates/drm"
for f in $MODS; do
  install -m 0644 "$REPO/$f" "$PAYLOAD/lib/modules/$KREL/updates/drm/"
done
echo "$KREL" > "$PAYLOAD/KERNEL_RELEASE"
mkdir -p "$PAYLOAD/etc/modules-load.d"
echo "# Deposit OS NVIDIA (beta) — load proprietary modules at boot
nvidia
nvidia-modeset
nvidia-drm
nvidia-uvm" > "$PAYLOAD/etc/modules-load.d/nvidia-deposit.conf"
# strip deb metadata dirs dpkg -x may have laid down
rm -rf "$PAYLOAD/DEBIAN" 2>/dev/null || true
log "payload staged ($(du -sh "$PAYLOAD" | cut -f1))"

# --- 4. Package --------------------------------------------------------------
cat > "$REPO/ci/nvidia-installer/install.sh" <<'INST'
#!/usr/bin/env bash
# NVIDIA beta driver installer payload — copies the staged tree onto the
# target root and regenerates module dependencies.
set -euo pipefail
T="${2:-}"
while [[ $# -gt 0 ]]; do case "$1" in
  --target) T="$2"; shift 2 ;;
  *) shift ;;
esac; done
[[ -n "$T" && -d "$T" ]] || { echo "install.sh: need --target DIR" >&2; exit 2; }
SRC="$(cd "$(dirname "$0")/.." && pwd)"
find "$SRC" -mindepth 1 -maxdepth 1 ! -name installer -exec cp -a {} "$T"/ \;
KREL="$(cat "$T/KERNEL_RELEASE")"
depmod -b "$T" "$KREL"
echo "[nvidia-installer] modules + userspace installed for $KREL"
echo "[nvidia-installer] reboot to activate; verify with: nvidia-smi"
INST

command -v squashfs-tools >/dev/null 2>&1 || true
log "packing .mlpds (driver)"
bash "$REPO/tools/mlpds" create \
  --type driver \
  --files "$PAYLOAD" \
  --installer "$REPO/ci/nvidia-installer" \
  --out "$OUT/nvidia-beta.mlpds" \
  || fail "mlpds create failed"
log "OK -> $OUT/nvidia-beta.mlpds ($(du -h "$OUT/nvidia-beta.mlpds" | cut -f1))"
