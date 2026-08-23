#!/usr/bin/env bash
# ============================================================================
# tests/test_deposit_updater.sh — exercise tools/deposit-updater without
# network, root, or a display. Mirrors the style of tests/test_aqa.sh.
#
# The updater imports PyGObject (gi + Gtk). On systems without the GTK
# Python bindings installed (e.g. minimal CI images), the GUI-related
# checks are reported as SKIP rather than FAIL. py_compile always runs.
# ============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$REPO/tools/deposit-updater"

pass=0; fail=0; skip=0
ok()  { pass=$((pass+1)); echo "  PASS: $1"; }
bad() { fail=$((fail+1)); echo "  FAIL: $1"; }
skp() { skip=$((skip+1)); echo "  SKIP: $1"; }

# --- [1] python compile (always runs, never skipped) -----------------------
echo "[1] python compile"
if python3 -m py_compile "$UPDATER" 2>/dev/null; then
  ok "py_compile deposit-updater"
else
  bad "py_compile deposit-updater"
fi

# --- preflight: do we have gi / Gtk bindings? ------------------------------
have_gi=0
if python3 -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gtk" 2>/dev/null; then
  have_gi=1
fi

if [[ $have_gi -eq 0 ]]; then
  skp "PyGObject/Gtk bindings not available (install python3-gi + gir1.3-gtk-3.0)"
  echo
  echo "RESULT: $pass passed, $fail failed, $skip skipped"
  [[ $fail -eq 0 ]] && exit 0 || exit 1
fi

# --- [2] --self-check exits 0 with a clear message -------------------------
echo "[2] --self-check exit code"
out="$(python3 "$UPDATER" --self-check 2>&1)"; rc=$?
if [[ $rc -eq 0 ]]; then
  ok "self-check exits 0"
else
  bad "self-check exits 0 (rc=$rc out=$out)"
fi

# --- [3] --self-check output is non-empty and human-readable ---------------
echo "[3] --self-check output shape"
echo "$out" | grep -qi "ok" && ok "self-check reports status" \
  || bad "self-check reports status (out=$out)"

# --- [4] no Python traceback in any self-check path ------------------------
echo "[4] no traceback"
if echo "$out" | grep -qi "traceback"; then
  bad "self-check leaked a traceback"
else
  ok "self-check no traceback"
fi

# --- [5] unknown arg does not crash with a Python traceback ----------------
echo "[5] unknown flag handled gracefully"
out2="$(python3 "$UPDATER" --definitely-not-a-flag 2>&1)" &
pid=$!
# Give it a moment; --definitely-not-a-flag should fall through to
# Updater() + Gtk.main() which will block forever without a display.
# We only care that no traceback has been emitted so far.
sleep 1
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  ok "unknown flag falls into GUI (no early crash)"
else
  if echo "$out2" | grep -qi "traceback"; then
    bad "unknown flag leaked a traceback (out=$out2)"
  else
    ok "unknown flag exited cleanly (no traceback)"
  fi
fi

# --- [6] importable as a module via runpy ----------------------------------
echo "[6] importable (best-effort)"
import_out="$(
  python3 - "$UPDATER" <<'PY' 2>&1
import sys, runpy
ns = runpy.run_path(sys.argv[1], run_name="deposit_updater")
assert "Updater" in ns, "Updater class missing"
assert "run" in ns, "run() helper missing"
assert "self_check" in ns, "self_check() missing"
print("import ok")
PY
)"
import_rc=$?
if [[ $import_rc -eq 0 ]] && echo "$import_out" | grep -q "import ok"; then
  ok "runpy import exposes Updater/run/self_check"
else
  bad "runpy import (rc=$import_rc out=$import_out)"
fi

# --- summary ---------------------------------------------------------------
echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
[[ $fail -eq 0 ]] && exit 0 || exit 1
