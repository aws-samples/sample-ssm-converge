#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Reporter: EventBridge
#
# Emits drift events to EventBridge. Only fires when drift is detected so
# compliant runs don't generate noise.
#
# Event structure:
#   Source:      ssm-converge
#   DetailType:  SSM Converge Drift Detected
#   Detail:      compact JSON with run metadata + drifted resources
#
# Usage:
#   source /opt/ssm-converge/reporters/eventbridge.sh
#   _report_to_eventbridge "$(get_report_json)"
# ═══════════════════════════════════════════════════════════════════════════════

_report_to_eventbridge() {
  local report="$1"
  local bus="${DSC_EVENTBRIDGE_BUS:-default}"

  # Build a compact event detail (or an empty JSON "skip" marker if no drift).
  # Report is passed as argv[1] to avoid the heredoc-stdin conflict.
  local detail
  detail=$(python3 - "$report" <<'PY'
import json, sys

try:
    r = json.loads(sys.argv[1])
except Exception:
    print('')
    sys.exit(0)

drifted = [x for x in r.get('resources', []) if x.get('status') == 'non_compliant']
if not drifted:
    print('')
    sys.exit(0)

event = {
    'run_id':            r.get('run_id'),
    'instance_id':       r.get('instance_id'),
    'account_id':        r.get('account_id'),
    'region':            r.get('region'),
    'profile':           r.get('profile'),
    'mode':              r.get('mode'),
    'drift_count':       len(drifted),
    'total_resources':   r.get('summary', {}).get('total', 0),
    'compliance_pct':    r.get('summary', {}).get('compliance_pct', 0),
    'drifted_resources': [
        {'resource': d['resource'], 'detail': d.get('detail', '')}
        for d in drifted
    ],
}

print(json.dumps(event))
PY
  )

  # Skip silently if no drift.
  [ -z "$detail" ] && return 0

  # put-events' Detail field must be a JSON *string*, so encode the compact
  # detail a second time.
  local detail_string
  detail_string=$(python3 - "$detail" <<'PY'
import json, sys
print(json.dumps(sys.argv[1]))
PY
  )

  local drift_count
  drift_count=$(python3 - "$detail" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get('drift_count', 0))
PY
  )

  local entries
  entries=$(cat <<EOF
[{"Source":"ssm-converge","DetailType":"SSM Converge Drift Detected","Detail":$detail_string,"EventBusName":"$bus"}]
EOF
  )

  if aws events put-events --entries "$entries" 2>/dev/null; then
    _log "  ✓ EventBridge: drift event emitted ($drift_count resources)"
  else
    _log "  ⚠ EventBridge reporting failed (non-fatal)"
  fi
}
