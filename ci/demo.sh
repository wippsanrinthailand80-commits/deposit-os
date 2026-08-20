#!/usr/bin/env bash
# Demo of the Deposit OS tooling, captured as a "screenshot" in CI.
set +e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
export PATH="$REPO/tools:$PATH"

# Ephemeral signing key so the demo exercises the real GPG trust chain
# (create signs -> install verifies). Not used for any real release.
if command -v gpg >/dev/null 2>&1; then
  KG="$(mktemp -d)"; chmod 700 "$KG"
  printf '%%no-protection\nKey-Type: eddsa\nKey-Curve: ed25519\nKey-Usage: sign\nName-Real: demo\nName-Email: demo@deposit\nExpire-Date: 0\n%%commit\n' > "$KG/kg"
  gpg --homedir "$KG" --batch --gen-key "$KG/kg" >/dev/null 2>&1
  gpg --homedir "$KG" --armor --export-secret-keys demo@deposit > "$KG/sec.asc" 2>/dev/null
  gpg --homedir "$KG" --armor --export demo@deposit > "$KG/pub.asc" 2>/dev/null
  export DEPOSIT_GPG_PRIVATE_FILE="$KG/sec.asc"
  export DEPOSIT_PUBKEY="$KG/pub.asc"
fi

mkdir -p /tmp/shots
exec > >(tee /tmp/shots/demo.log) 2>&1

echo "=================================================="
echo " Deposit OS - tool demo (.mlpds + AQA installer)"
echo "=================================================="
echo
echo "## [1] mlpds create  -> build a sample .mlpds (os type)"
rm -rf /tmp/demo-root /tmp/demo.mlpds
mkdir -p /tmp/demo-root/usr/bin /tmp/demo-root/etc
printf '#!/bin/sh\necho "hello from a Deposit app"\n' > /tmp/demo-root/usr/bin/hello
chmod +x /tmp/demo-root/usr/bin/hello
mlpds create --rootfs /tmp/demo-root --type os --out /tmp/demo.mlpds
echo "    -> $(ls -lh /tmp/demo.mlpds | awk '{print $5}')"
echo
echo "## [2] mlpds info    -> inspect the .mlpds manifest"
mlpds info /tmp/demo.mlpds
echo
echo "## [3] mlpds install -> unpack into /tmp/installed"
rm -rf /tmp/installed
mlpds install /tmp/demo.mlpds --target /tmp/installed
echo "--- installed tree ---"
ls -R /tmp/installed 2>/dev/null | head -20
echo
echo "## [4] aqa list      -> show installable apps"
aqa list
echo
echo "## [5] aqa install --dry-run chrome  -> AQA fetch plan"
aqa install --dry-run chrome
echo
echo "## [6] aqa install --dry-run turbo   -> AQA component plan"
aqa install --dry-run turbo
echo
echo "=================================================="
echo " demo complete"
echo "=================================================="
sleep 5
