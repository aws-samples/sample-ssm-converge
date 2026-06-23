#!/bin/bash
# Build an SSM Distributor package for ssm-converge.
#
# Reads from:
#   src/linux/            -> Linux zip (bash + Linux resources + reporters)
#   src/windows/          -> Windows zip (PowerShell + Windows resources) (when present)
#   cli/ssm-converge      -> Linux CLI
#   cli/ssm-converge.ps1  -> Windows CLI (when present)
#
# Produces under distributor/dist/:
#   ssm-converge-<VERSION>-linux-amd64.zip
#   ssm-converge-<VERSION>-linux-arm64.zip    (same bytes; bash is arch-neutral)
#   ssm-converge-<VERSION>-windows-amd64.zip  (when src/windows exists)
#   manifest.json
#
# After building, upload everything under dist/ to S3 and register with
# `aws ssm create-document --document-type Package --content <manifest>`.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/distributor/dist"
VERSION=$(grep '^SSM_CONVERGE_VERSION=' "$ROOT/src/linux/lib.sh" | head -1 | cut -d'"' -f2)

if [ -z "$VERSION" ]; then
  echo "ERROR: could not extract version from src/linux/lib.sh" >&2
  exit 1
fi

echo "Building ssm-converge $VERSION Distributor package"

rm -rf "$DIST"
mkdir -p "$DIST"

# --- Linux zip ---------------------------------------------------------------

STAGE_LINUX=$(mktemp -d)
trap "rm -rf $STAGE_LINUX $STAGE_WIN" EXIT

mkdir -p "$STAGE_LINUX/src" "$STAGE_LINUX/cli"
cp -r "$ROOT/src/linux/."                "$STAGE_LINUX/src/"
cp    "$ROOT/cli/ssm-converge"           "$STAGE_LINUX/cli/"
cp    "$ROOT/distributor/install.sh"     "$STAGE_LINUX/install.sh"
cp    "$ROOT/distributor/uninstall.sh"   "$STAGE_LINUX/uninstall.sh"
chmod +x "$STAGE_LINUX/install.sh" "$STAGE_LINUX/uninstall.sh" "$STAGE_LINUX/cli/ssm-converge"

LINUX_ZIP="ssm-converge-${VERSION}-linux.zip"
( cd "$STAGE_LINUX" && zip -qr "$DIST/$LINUX_ZIP" . )

# SSM Distributor wants one archive per (platform, architecture) pair; the
# content can be identical for arch-neutral software.
cp "$DIST/$LINUX_ZIP" "$DIST/ssm-converge-${VERSION}-linux-amd64.zip"
cp "$DIST/$LINUX_ZIP" "$DIST/ssm-converge-${VERSION}-linux-arm64.zip"
rm  "$DIST/$LINUX_ZIP"

sha_linux_amd64=$(sha256sum "$DIST/ssm-converge-${VERSION}-linux-amd64.zip" | awk '{print $1}')
sha_linux_arm64=$(sha256sum "$DIST/ssm-converge-${VERSION}-linux-arm64.zip" | awk '{print $1}')
bytes_linux_amd64=$(stat -f%z "$DIST/ssm-converge-${VERSION}-linux-amd64.zip" 2>/dev/null || stat -c%s "$DIST/ssm-converge-${VERSION}-linux-amd64.zip")

# --- Windows zip (only if src/windows/ exists and install.ps1 exists) --------

HAS_WINDOWS=false
STAGE_WIN=""
if [ -d "$ROOT/src/windows" ] && [ -f "$ROOT/distributor/install.ps1" ]; then
  HAS_WINDOWS=true
  STAGE_WIN=$(mktemp -d)
  mkdir -p "$STAGE_WIN/src" "$STAGE_WIN/cli"
  cp -r "$ROOT/src/windows/."                "$STAGE_WIN/src/"
  [ -f "$ROOT/cli/ssm-converge.ps1" ] && cp "$ROOT/cli/ssm-converge.ps1" "$STAGE_WIN/cli/"
  cp    "$ROOT/distributor/install.ps1"      "$STAGE_WIN/install.ps1"
  cp    "$ROOT/distributor/uninstall.ps1"    "$STAGE_WIN/uninstall.ps1"

  WIN_ZIP="ssm-converge-${VERSION}-windows-amd64.zip"
  ( cd "$STAGE_WIN" && zip -qr "$DIST/$WIN_ZIP" . )

  sha_win_amd64=$(sha256sum "$DIST/$WIN_ZIP" | awk '{print $1}')
  bytes_win_amd64=$(stat -f%z "$DIST/$WIN_ZIP" 2>/dev/null || stat -c%s "$DIST/$WIN_ZIP")
fi

# --- Manifest ----------------------------------------------------------------
#
# Platform names from:
#   https://docs.aws.amazon.com/systems-manager/latest/userguide/distributor-package-create.html
# 'linux' family names: amazon, redhat, ubuntu, debian, suse.

{
  cat <<EOF
{
  "schemaVersion": "2.0",
  "publisher": "ssm-converge",
  "name": "ssm-converge",
  "version": "${VERSION}",
  "packages": {
    "amazon":  { "_any": {
        "x86_64": { "file": "ssm-converge-${VERSION}-linux-amd64.zip" },
        "arm64":  { "file": "ssm-converge-${VERSION}-linux-arm64.zip" } } },
    "redhat":  { "_any": {
        "x86_64": { "file": "ssm-converge-${VERSION}-linux-amd64.zip" },
        "arm64":  { "file": "ssm-converge-${VERSION}-linux-arm64.zip" } } },
    "ubuntu":  { "_any": {
        "x86_64": { "file": "ssm-converge-${VERSION}-linux-amd64.zip" },
        "arm64":  { "file": "ssm-converge-${VERSION}-linux-arm64.zip" } } },
    "debian":  { "_any": {
        "x86_64": { "file": "ssm-converge-${VERSION}-linux-amd64.zip" },
        "arm64":  { "file": "ssm-converge-${VERSION}-linux-arm64.zip" } } }$($HAS_WINDOWS && echo ',')
EOF

  if $HAS_WINDOWS; then
    cat <<EOF
    "windows": { "_any": {
        "x86_64": { "file": "ssm-converge-${VERSION}-windows-amd64.zip" } } }
EOF
  fi

  cat <<EOF
  },
  "files": {
    "ssm-converge-${VERSION}-linux-amd64.zip": {
      "checksums": { "sha256": "${sha_linux_amd64}" },
      "size": ${bytes_linux_amd64}
    },
    "ssm-converge-${VERSION}-linux-arm64.zip": {
      "checksums": { "sha256": "${sha_linux_arm64}" },
      "size": ${bytes_linux_amd64}
    }$($HAS_WINDOWS && echo ',')
EOF

  if $HAS_WINDOWS; then
    cat <<EOF
    "ssm-converge-${VERSION}-windows-amd64.zip": {
      "checksums": { "sha256": "${sha_win_amd64}" },
      "size": ${bytes_win_amd64}
    }
EOF
  fi

  cat <<EOF
  }
}
EOF
} > "$DIST/manifest.json"

echo "Built:"
ls -la "$DIST"
echo ""
echo "Manifest:"
cat "$DIST/manifest.json"
