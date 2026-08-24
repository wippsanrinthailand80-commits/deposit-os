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
