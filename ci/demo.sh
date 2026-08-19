#!/usr/bin/env bash
# Demo of the Deposit OS tooling, captured as a "screenshot" in CI.
set +e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
export PATH="$REPO/tools:$PATH"
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
