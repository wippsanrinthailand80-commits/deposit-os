#!/usr/bin/env bash
# ============================================================================
# publish-release.sh — attach the built ISO to a rolling "continuous" GitHub
# Release. Deletes and recreates the release each run so the latest ISO is
# always available. Non-fatal if the ISO wasn't produced.
# ============================================================================
set -uo pipefail

ISO="${1:-build/output/deposit-os.iso}"
[ -f "$ISO" ] || { echo "[release] no ISO at $ISO; skipping"; exit 0; }
# Asset filename inside the release (3rd arg). Defaults to the classic name.
ASSET="${3:-deposit-os.iso}"

API="https://api.github.com/repos/$GITHUB_REPOSITORY"
TOKEN="$GITHUB_TOKEN"
# Channel override: main publishes to "continuous"; the LIVE-BOOT channel
# (same run, same pipeline) sets DEPOSIT_RELEASE_TAG=continuous-liveboot.
TAG="${DEPOSIT_RELEASE_TAG:-continuous}"
RUN="${RUN:-unknown}"

# remove any previous continuous release + tag
REL_ID=$(curl -s -H "Authorization: Bearer $TOKEN" "$API/releases/tags/$TAG" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('id',''))" 2>/dev/null)
if [ -n "$REL_ID" ]; then
  curl -s -X DELETE -H "Authorization: Bearer $TOKEN" "$API/releases/$REL_ID" >/dev/null
  curl -s -X DELETE -H "Authorization: Bearer $TOKEN" "$API/git/refs/tags/$TAG" >/dev/null || true
fi

BODY="Automated continuous build from run $RUN. Hybrid BIOS/UEFI live ISO — boot it in a VM or write it to a USB stick."
REL=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"tag_name\":\"$TAG\",\"name\":\"Deposit OS (continuous)\",\"body\":$(python3 -c "import json,sys;print(json.dumps('$BODY'))"),\"prerelease\":true}" \
  "$API/releases")
REL_ID=$(echo "$REL" | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
if [ -z "$REL_ID" ]; then echo "[release] failed to create release"; exit 1; fi
# upload_url already points at uploads.github.com (no redirect needed).
UP=$(echo "$REL" | python3 -c "import sys,json;print(json.load(sys.stdin).get('upload_url','').replace('{?name,label}',''))" 2>/dev/null)
[ -n "$UP" ] || UP="$API/releases/$REL_ID/assets"

RESP=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$ISO" \
  "$UP?name=$ASSET")
echo "$RESP" | python3 -c "import sys,json;d=json.load(sys.stdin);print('[release] iso ->',d.get('browser_download_url') or d.get('message'))" 2>/dev/null \
  || echo "[release] iso upload http error"
# also publish the .mlpds package if present
MLPDS="${2:-deposit.os.mlpds}"
if [ -f "$MLPDS" ]; then
  RESP=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$MLPDS" \
    "$UP?name=deposit.os.mlpds")
  echo "$RESP" | python3 -c "import sys,json;d=json.load(sys.stdin);print('[release] mlpds ->',d.get('browser_download_url') or d.get('message'))" 2>/dev/null \
    || echo "[release] mlpds upload http error"
fi
echo "[release] published to continuous release (id $REL_ID)"
