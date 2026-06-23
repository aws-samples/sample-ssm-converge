#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge Configuration: Download a vendor installer and install it
#
# Demonstrates the canonical "download + unattended install" pattern using
# only built-in resources:
#
#   1. `file` downloads the artifact (S3 or HTTPS, authenticated or public,
#      with checksum verification).
#   2. `execute` runs the installer with a guard so it only runs once.
#   3. `service` starts the resulting service and ensures it stays enabled.
#
# Three concrete scenarios are shown:
#
#   A. Public HTTPS download (Amazon CloudWatch Agent .deb) - no auth
#   B. Authenticated HTTPS download (token-based, Artifactory-style)
#   C. S3 download (instance-role credentials)
#
# Pick whichever matches your delivery model. The pattern is the same.
#
# Run:
#   sudo DSC_MODE=enforce  DSC_PROFILE=install-vendor bash install-vendor-package.sh
#   sudo DSC_MODE=audit    DSC_PROFILE=install-vendor bash install-vendor-package.sh
# ═══════════════════════════════════════════════════════════════════════════════

source /opt/ssm-converge/lib.sh

# ─── Detect distro family (deb vs rpm) ────────────────────────────────────────

if   command -v dpkg  &>/dev/null; then DISTRO_FAMILY="deb"
elif command -v rpm   &>/dev/null; then DISTRO_FAMILY="rpm"
else
  echo "Unsupported distro (neither dpkg nor rpm found)" >&2
  exit 1
fi

# ─── Scenario A: Public HTTPS download — Amazon CloudWatch Agent ─────────────
#
# Public S3-fronted URL, no auth. Using `checksum` is recommended; if you
# don't pin one, drift won't be detected once the file is on disk.

if [ "$DISTRO_FAMILY" = "deb" ]; then
  CW_URL="https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
  CW_LOCAL="/tmp/amazon-cloudwatch-agent.deb"
  CW_INSTALL_CMD="dpkg -i $CW_LOCAL"
else
  CW_URL="https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"
  CW_LOCAL="/tmp/amazon-cloudwatch-agent.rpm"
  CW_INSTALL_CMD="rpm -U --force $CW_LOCAL"
fi

# Pin a checksum if you have one. Pick one approach:
#   1. Hardcode below if you control the artifact and pin its hash.
#   2. Resolve the expected hash from a sidecar file or SSM parameter at runtime.
#   3. Omit it (cheapest, but no integrity check or drift detection).
# CW_SHA256="sha256:abcd1234..."

file "$CW_LOCAL" present \
  source "$CW_URL" \
  mode '0644' \
  ${CW_SHA256:+checksum "$CW_SHA256"}

execute 'install-cloudwatch-agent' \
  command "$CW_INSTALL_CMD" \
  creates '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl'

# Make sure it's running (won't run on first install until configured;
# we leave that for a separate configuration that ships agent config too).
service 'amazon-cloudwatch-agent' enabled

# ─── Scenario B: Authenticated HTTPS download from a private artifact repo ──
#
# Token comes from the environment. In practice, fetch it from Secrets Manager
# or SSM Parameter Store before invoking this configuration. We're showing the
# call shape here, not the secret-fetch.
#
# The artifact in this example is a hypothetical "myco-agent" package.

if [ -n "${MYCO_TOKEN:-}" ] && [ -n "${MYCO_VERSION:-}" ]; then
  if [ "$DISTRO_FAMILY" = "deb" ]; then
    MYCO_URL="https://artifactory.corp/repos/agents/myco-agent_${MYCO_VERSION}_amd64.deb"
    MYCO_LOCAL="/tmp/myco-agent.deb"
    MYCO_INSTALL="dpkg -i $MYCO_LOCAL"
    MYCO_QUERY="dpkg -l myco-agent | grep -q '^ii'"
  else
    MYCO_URL="https://artifactory.corp/repos/agents/myco-agent-${MYCO_VERSION}.x86_64.rpm"
    MYCO_LOCAL="/tmp/myco-agent.rpm"
    MYCO_INSTALL="rpm -U --force $MYCO_LOCAL"
    MYCO_QUERY="rpm -q myco-agent"
  fi

  file "$MYCO_LOCAL" present \
    source      "$MYCO_URL" \
    auth_bearer "$MYCO_TOKEN" \
    header      'Accept: application/octet-stream' \
    mode '0644' \
    ${MYCO_SHA256:+checksum "$MYCO_SHA256"}

  execute 'install-myco-agent' \
    command "$MYCO_INSTALL" \
    not_if  "$MYCO_QUERY"

  service 'myco-agent' running enabled
fi

# ─── Scenario C: S3 download with instance-role credentials ─────────────────
#
# Standard pattern when you control the artifact and ship it via S3.
# `aws s3 cp` runs under the instance profile - no token plumbing needed.

if [ -n "${S3_AGENT_BUCKET:-}" ]; then
  if [ "$DISTRO_FAMILY" = "deb" ]; then
    AGENT_LOCAL="/tmp/internal-agent.deb"
    AGENT_INSTALL="dpkg -i $AGENT_LOCAL"
    AGENT_QUERY="dpkg -l internal-agent | grep -q '^ii'"
  else
    AGENT_LOCAL="/tmp/internal-agent.rpm"
    AGENT_INSTALL="rpm -U --force $AGENT_LOCAL"
    AGENT_QUERY="rpm -q internal-agent"
  fi

  file "$AGENT_LOCAL" present \
    source "s3://${S3_AGENT_BUCKET}/$(basename "$AGENT_LOCAL")" \
    mode '0644'

  execute 'install-internal-agent' \
    command "$AGENT_INSTALL" \
    not_if  "$AGENT_QUERY"

  service 'internal-agent' running enabled
fi

# ─── Report ───────────────────────────────────────────────────────────────────
report_compliance
