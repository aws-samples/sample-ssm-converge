#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Reporter: S3 Audit Lake
#
# Stores compliance reports in S3 for long-term retention and analytics.
# Partitioned by account/region/instance/date for efficient Athena queries.
#
# S3 path structure:
#   s3://bucket/ssm-converge/{account_id}/{region}/{instance_id}/{date}/{run_id}.json
# ═══════════════════════════════════════════════════════════════════════════════

_report_to_s3() {
  local report="$1"

  if [ -z "$DSC_S3_BUCKET" ]; then
    return 0  # S3 reporting not configured, skip silently
  fi

  local instance_id=$(_get_instance_id)
  local account_id=$(_get_account_id)
  local region=$(_get_region)
  local date_partition=$(date -u +%Y/%m/%d)

  # Build S3 path with partitioning
  local s3_path="${DSC_S3_BUCKET}/${account_id}/${region}/${instance_id}/${date_partition}/${DSC_RUN_ID}.json"

  echo "$report" | aws s3 cp - "$s3_path" \
    --content-type "application/json" \
    --metadata "profile=${DSC_PROFILE},mode=${DSC_MODE}" \
    2>/dev/null

  if [ $? -eq 0 ]; then
    _log "  ✓ Reported to S3 ($s3_path)"
  else
    _log "  ⚠ S3 reporting failed (non-fatal)"
  fi
}
