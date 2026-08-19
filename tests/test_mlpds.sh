#!/usr/bin/env bash
# ============================================================================
# tests/test_mlpds.sh — exercise the mlpds tool end-to-end with a synthetic
# rootfs (no network / no real debootstrap / no kernel compile needed).
# ============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MLPDS="$REPO/tools/mlpds"

pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  PASS: $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL: $1"; }

# --- syntax check all scripts ----------------------------------------------
echo "[1] syntax check"
for f in "$REPO/tools/mlpds" "$REPO/build/build-kernel.sh" "$REPO/build/build-rootfs.sh" "$REPO/tools/mlpds-installer/installer/install.sh"; do
  if bash -n "$f" 2>/dev/null; then ok "syntax $f"; else bad "syntax $f"; fi
done

# --- build a synthetic rootfs ----------------------------------------------
echo "[2] synthetic rootfs + dpkg db"
WORK="$(mktemp -d)"; trap "rm -rf '$WORK'" EXIT
ROOT="$WORK/rootfs"; mkdir -p "$ROOT/bin" "$ROOT/etc" "$ROOT/var/lib/dpkg"
echo "deposit" > "$ROOT/etc/hostname"
echo "#!/bin/true" > "$ROOT/bin/true"; chmod +x "$ROOT/bin/true"
cat > "$ROOT/var/lib/dpkg/status" <<'EOF'
Package: bash
Status: install ok installed

Package: dpkg
Status: install ok installed

Package: apt
Status: install ok installed
EOF

# --- create (os) -----------------------------------------------------------
echo "[3] mlpds create (type=os)"
OUT="$WORK/deposit.os.mlpds"
if "$MLPDS" create --rootfs "$ROOT" --out "$OUT" --type os >/dev/null 2>&1; then ok "create os"; else bad "create os"; fi
[[ -f "$OUT" ]] || bad "create produced no file"

# --- info ------------------------------------------------------------------
echo "[4] mlpds info"
MANIFEST="$("$MLPDS" info "$OUT" 2>/dev/null)" || bad "info failed"
grep -q '"format": "mlpds"' <<<"$MANIFEST" && ok "info format" || bad "info format"
grep -q '"type": "os"'        <<<"$MANIFEST" && ok "info type"   || bad "info type"
grep -q '"kind": "tree"'      <<<"$MANIFEST" && ok "info rootfs kind" || bad "info rootfs kind"
grep -q '"apt"'               <<<"$MANIFEST" && ok "info packages list" || bad "info packages list"

# --- extract ---------------------------------------------------------------
echo "[5] mlpds extract"
EXT="$WORK/extracted"; "$MLPDS" extract "$OUT" -d "$EXT" >/dev/null 2>&1 || bad "extract failed"
[[ -f "$EXT/manifest.json" ]] && ok "extract manifest" || bad "extract manifest"
[[ -d "$EXT/rootfs/bin" ]] && ok "extract rootfs" || bad "extract rootfs"

# --- install (into a dir) --------------------------------------------------
echo "[6] mlpds install (dir target)"
TGT="$WORK/target"; "$MLPDS" install "$OUT" --target "$TGT" >/dev/null 2>&1 || bad "install failed"
[[ -f "$TGT/etc/hostname" ]] && ok "install copied rootfs" || bad "install copied rootfs"
[[ "$(cat "$TGT/etc/hostname")" == "deposit" ]] && ok "install kept hostname" || bad "install kept hostname"
[[ -x "$TGT/bin/true" ]] && ok "install preserved exec bits" || bad "install preserved exec bits"
[[ -f "$TGT/etc/fstab" ]] && ok "install wrote fstab" || bad "install wrote fstab"

# --- install with custom hostname -----------------------------------------
echo "[7] mlpds install (--hostname)"
TGT2="$WORK/target2"; "$MLPDS" install "$OUT" --target "$TGT2" --hostname mybox >/dev/null 2>&1 || bad "install hostname failed"
[[ "$(cat "$TGT2/etc/hostname")" == "mybox" ]] && ok "custom hostname" || bad "custom hostname"

# --- create (app bundle, no rootfs) ----------------------------------------
echo "[8] mlpds create (type=app, --files)"
APPFILES="$WORK/appfiles"; mkdir -p "$APPFILES/opt/hello"
echo "echo hi" > "$APPFILES/opt/hello/run.sh"; chmod +x "$APPFILES/opt/hello/run.sh"
APPOUT="$WORK/hello.app.mlpds"
if "$MLPDS" create --out "$APPOUT" --type app --files "$APPFILES" >/dev/null 2>&1; then ok "create app"; else bad "create app"; fi
APPMAN="$("$MLPDS" info "$APPOUT" 2>/dev/null)"
grep -q '"type": "app"' <<<"$APPMAN" && ok "app type" || bad "app type"
grep -q '"kind": "none"' <<<"$APPMAN" && ok "app rootfs none" || bad "app rootfs none"

# --- extract app + verify bundled file -------------------------------------
echo "[9] mlpds extract app + files present"
APPEXT="$WORK/appext"; "$MLPDS" extract "$APPOUT" -d "$APPEXT" >/dev/null 2>&1 || bad "app extract failed"
[[ -x "$APPEXT/opt/hello/run.sh" ]] && ok "app bundled file" || bad "app bundled file"

# --- summary ---------------------------------------------------------------
echo
echo "RESULT: $pass passed, $fail failed"
[[ $fail -eq 0 ]] && exit 0 || exit 1
