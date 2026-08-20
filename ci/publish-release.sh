#!/usr/bin/env bash
# ============================================================================
# publish-release.sh — attach the built ISO to a rolling "continuous" GitHub
# Release. Deletes and recreates the release each run so the latest ISO is
# always available. Non-fatal if the ISO wasn't produced.
# ============================================================================
set -uo pipefail

ISO="${1:-build/output/deposit-os.iso}"
[ -f "$ISO" ] || { echo "[release] no ISO at $ISO; skipping"; exit 0; }

API="https://api.github.com/repos/$GITHUB_REPOSITORY"
TOKEN="$GITHUB_TOKEN"
TAG="continuous"
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

curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @"$ISO" \
  "$API/releases/$REL_ID/assets?name=deposit-os.iso" >/dev/null
echo "[release] published ISO to continuous release (id $REL_ID)"
