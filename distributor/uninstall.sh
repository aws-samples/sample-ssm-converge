#!/bin/bash
# SSM Distributor uninstall script for ssm-converge.
# Removes library + CLI. Keeps /var/lib/ssm-converge (compliance history)
# intact so you don't lose audit data on upgrade.

set +e

INSTALL_PATH="${INSTALL_PATH:-/opt/ssm-converge}"
BIN_PATH="/usr/local/bin/ssm-converge"

echo "[ssm-converge] Removing $INSTALL_PATH"
rm -rf "$INSTALL_PATH"

echo "[ssm-converge] Removing $BIN_PATH"
rm -f "$BIN_PATH"

echo "[ssm-converge] Compliance history left at /var/lib/ssm-converge/ (delete manually if needed)"
echo "[ssm-converge] Uninstall complete."
