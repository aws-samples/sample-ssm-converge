#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Reporter: SSM Compliance API
#
# Reports compliance items to AWS Systems Manager Compliance API
# (PutComplianceItems). Results appear in the SSM Console under Compliance and
# can be queried via the AWS CLI or integrated with AWS Config.
#
# Usage:
#   source /opt/ssm-converge/lib.sh
#   source /opt/ssm-converge/reporters/ssm_compliance.sh
#   _report_to_ssm_compliance "$(get_report_json)"
#
# Notes:
#   - The AWS:ComplianceItem inventory schema has FLAT Details (a string map),
#     not the nested 'string' wrapper that some older examples show.
#   - Compliance type must match regex [A-Za-z0-9_-]\\w+ or Custom:[a-zA-Z0-9_-]\\w+
#     Hyphens are only allowed as the *first* char, so we sanitise profile names
#     by replacing - with _ before composing the type.
# ═══════════════════════════════════════════════════════════════════════════════

_report_to_ssm_compliance() {
  local report="$1"
  local instance_id
  instance_id=$(_get_instance_id)

  # Convert the SSM Converge report into the AWS:ComplianceItem shape.
  # Report is passed as argv[1] to avoid the heredoc-stdin conflict.
  local items
  items=$(python3 - "$report" <<'PY'
import json, sys

try:
    report = json.loads(sys.argv[1])
except Exception:
    print('[]')
    sys.exit(0)

items = []
for r in report.get('resources', []):
    status   = 'COMPLIANT' if r.get('status') == 'compliant' else 'NON_COMPLIANT'
    severity = 'MEDIUM' if 'file' in r.get('resource', '') else 'HIGH'

    # Id must match the regex too — alphanumerics, hyphens, underscores only.
    item_id = r['resource']
    for bad in ('/', '.', '[', ']', ' ', ':', '@'):
        item_id = item_id.replace(bad, '_')
    # No consecutive underscores (cleaner) and no trailing underscore.
    while '__' in item_id:
        item_id = item_id.replace('__', '_')
    item_id = item_id.strip('_')

    items.append({
        'Id':       item_id[:100],   # API limit
        'Title':    r['resource'],
        'Severity': severity,
        'Status':   status,
        'Details': {
            'DetailedText': r.get('detail', '') or r.get('status', ''),
        },
    })

print(json.dumps(items))
PY
  )

  if [ -z "$items" ] || [ "$items" = "[]" ]; then
    _log "  ⚠ SSM Compliance: no items to report"
    return 1
  fi

  # Compose a valid compliance type.
  # Rules (discovered empirically against the live API):
  #   - Regex: Custom:[a-zA-Z0-9_\-]\w+  (dashes only as first char, so avoid)
  #   - Underscores ALSO fail with "sub type name is missing from item Context"
  #     because Foo_bar is parsed as type=Foo / subtype=bar.
  #   - Alphanumeric only is the safe choice.
  local profile_clean
  profile_clean=$(printf '%s' "${DSC_PROFILE:-default}" | tr -cd '[:alnum:]')
  [ -z "$profile_clean" ] && profile_clean="default"
  # Capitalize first letter for readability (Default, SmokeTest, etc.).
  local compliance_type="Custom:SSMConverge$(echo "$profile_clean" | sed 's/./\U&/')"

  # Write items to a temp file — avoids shell-escaping of nested JSON on the cmdline.
  local items_file
  items_file=$(mktemp /tmp/ssm-converge-items-XXXXXX.json)
  printf '%s' "$items" > "$items_file"

  if aws ssm put-compliance-items \
       --resource-id "$instance_id" \
       --resource-type "ManagedInstance" \
       --compliance-type "$compliance_type" \
       --execution-summary "ExecutionTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --items "file://${items_file}" 2>/dev/null; then
    _log "  ✓ Reported to SSM Compliance (type: $compliance_type)"
    rm -f "$items_file"
    return 0
  else
    _log "  ⚠ SSM Compliance reporting failed (non-fatal)"
    rm -f "$items_file"
    return 1
  fi
}
