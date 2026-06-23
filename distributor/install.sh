#!/bin/bash
# SSM Distributor install script for ssm-converge.
# The package is unpacked into the current working directory by the SSM agent.
# This script copies the library into place and installs the CLI.

set -e

INSTALL_PATH="${INSTALL_PATH:-/opt/ssm-converge}"
BIN_PATH="/usr/local/bin/ssm-converge"

echo "[ssm-converge] Installing to $INSTALL_PATH"

# Clean previous install so we don't leave stale files behind.
if [ -d "$INSTALL_PATH" ]; then
  rm -rf "$INSTALL_PATH"
fi
mkdir -p "$INSTALL_PATH"

# Copy the library tree. The unpacked package has src/ and cli/ at the root.
cp -r src/. "$INSTALL_PATH/"

# Install the CLI.
install -m 0755 cli/ssm-converge "$BIN_PATH"

# Seed the on-instance state directory.
mkdir -p /var/lib/ssm-converge/history

# Surface the installed version so Distributor's exit log shows something useful.
VERSION=$(grep '^SSM_CONVERGE_VERSION=' "$INSTALL_PATH/lib.sh" | head -1 | cut -d'"' -f2)
echo "[ssm-converge] Installed version: $VERSION"
echo "[ssm-converge] Library path:      $INSTALL_PATH"
echo "[ssm-converge] CLI path:          $BIN_PATH"
