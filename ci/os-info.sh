#!/usr/bin/env bash
# Show info about the built OS .mlpds (captured as a screenshot in CI).
set +e
cd "${GITHUB_WORKSPACE:-.}"
tools/mlpds info deposit.os.mlpds | tee /tmp/os-shot/os.log
echo
echo "[screenshot in 5s]"
sleep 5
