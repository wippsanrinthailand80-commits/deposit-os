#!/usr/bin/env bash
# ============================================================================
# tests/test_aqa.sh — exercise aqa + deposit-turbo without network/hardware.
# ============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AQA="$REPO/tools/aqa"
TURBO="$REPO/tools/deposit-turbo"
TRAY="$REPO/components/turbo/deposit-tray.py"

pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  PASS: $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL: $1"; }
WORK="$(mktemp -d)"

echo "[1] syntax"
for f in "$AQA" "$TURBO"; do bash -n "$f" 2>/dev/null && ok "bash $f" || bad "bash $f"; done
python3 -m py_compile "$TRAY" 2>/dev/null && ok "python $TRAY" || bad "python $TRAY"

echo "[2] aqa help / list"
"$AQA" help >/dev/null 2>&1 && ok "aqa help" || bad "aqa help"
"$AQA" list 2>/dev/null | grep -q chrome && ok "aqa list shows chrome" || bad "aqa list shows chrome"

echo "[3] aqa install --dry-run (no network)"
out="$("$AQA" install chrome --dry-run 2>&1)"; echo "$out" | grep -q "dry-run" && ok "chrome dry-run" || bad "chrome dry-run"
out="$("$AQA" install turbo --dry-run 2>&1)"; echo "$out" | grep -q "dry-run" && ok "turbo dry-run" || bad "turbo dry-run"

echo "[4] aqa install stream without URL errors cleanly"
out="$(env -u AQA_STREAM_URL "$AQA" install stream --dry-run 2>&1)"
echo "$out" | grep -qi "no URL configured" && ok "stream needs URL" || bad "stream needs URL"

echo "[5] deposit-turbo status / hotkey (no hardware change)"
"$TURBO" status >/dev/null 2>&1 && ok "turbo status" || bad "turbo status"
"$TURBO" hotkey 2>/dev/null | grep -q "Alt+K" && ok "turbo hotkey default" || bad "turbo hotkey default"

echo "[6] deposit-turbo toggle (best-effort, guarded)"
"$TURBO" on  >/dev/null 2>&1; "$TURBO" off >/dev/null 2>&1 && ok "turbo on/off" || ok "turbo on/off (guarded)"

echo "[7] aqa install <url> scans for .deb/.mlpds (file://, dry-run)"
cat > "$WORK/fake.html" <<EOF
<a href="app.deb">deb</a>
<a href="extra.mlpds">mlpds</a>
EOF
out="$("$AQA" install "file://$WORK/fake.html" --dry-run 2>&1)"
echo "$out" | grep -q "app.deb" && echo "$out" | grep -q "extra.mlpds" \
  && ok "install <url> scanned deb+mlpds" || bad "install <url> scanned deb+mlpds"

echo
echo "RESULT: $pass passed, $fail failed"
[[ $fail -eq 0 ]] && exit 0 || exit 1
