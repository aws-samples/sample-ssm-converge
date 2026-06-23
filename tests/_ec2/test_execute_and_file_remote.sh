#!/bin/bash
# Driver run on the EC2 instance to verify execute + file HTTPS+auth+checksum
# end-to-end. Intended to be invoked via SSM SendCommand from a workstation.
set +u
export DSC_LOCAL_DIR=/var/lib/ssm-converge
export DSC_PROFILE=execute-and-file-test
export DSC_MODE=enforce
export DSC_VERBOSE=true

source /opt/ssm-converge/lib.sh

echo "== ssm-converge version =="
echo "v$SSM_CONVERGE_VERSION"

# --- Test A: execute with creates, run-once-then-skip ----------------------
rm -f /tmp/ssmc-marker /tmp/ssmc-installed
execute 'mark-once' command 'echo HELLO > /tmp/ssmc-marker' creates '/tmp/ssmc-marker'
echo "first pass result: $(cat /tmp/ssmc-marker 2>/dev/null)"

execute 'mark-once' command 'echo SHOULD-NOT-RUN > /tmp/ssmc-marker' creates '/tmp/ssmc-marker'
echo "second pass content (must still be HELLO): $(cat /tmp/ssmc-marker 2>/dev/null)"

# --- Test B: execute with not_if --------------------------------------------
execute 'guarded' command 'touch /tmp/ssmc-installed' not_if 'test -f /tmp/ssmc-installed'

# --- Test C: file HTTPS download with checksum -----------------------------
URL='https://www.gnu.org/licenses/gpl-3.0.txt'
LOCAL='/tmp/ssmc-gpl.txt'
rm -f "$LOCAL"
file "$LOCAL" present source "$URL"
EXPECTED=$(sha256sum "$LOCAL" 2>/dev/null | awk '{print $1}')
echo "downloaded: $(stat -c%s "$LOCAL" 2>/dev/null) bytes, sha256=$EXPECTED"

# Re-run with correct checksum: should be no-op (compliant, not changed).
file "$LOCAL" present source "$URL" checksum "sha256:$EXPECTED"

# Wrong checksum: should fail.
rm -f "$LOCAL"
file "$LOCAL" present source "$URL" checksum 'sha256:0000000000000000000000000000000000000000000000000000000000000000'

# --- Test D: file with auth_basic via httpbin (rejects when wrong creds) ---
file '/tmp/ssmc-auth-ok.json' present \
  source     'https://httpbin.org/basic-auth/svc-deploy/S3cret' \
  auth_basic 'svc-deploy:S3cret'

file '/tmp/ssmc-auth-bad.json' present \
  source     'https://httpbin.org/basic-auth/svc-deploy/S3cret' \
  auth_basic 'wrong-user:wrong-pass'

# --- Test E: file with auth_bearer via httpbin /bearer ---------------------
file '/tmp/ssmc-bearer-ok.json' present \
  source      'https://httpbin.org/bearer' \
  auth_bearer 'sample-token-xyz'

# --- Test F: download + execute (full pattern) -----------------------------
file '/tmp/ssmc-payload.bin' present \
  source 'https://www.gnu.org/licenses/gpl-3.0.txt'

execute 'process-payload' \
  command 'wc -l /tmp/ssmc-payload.bin > /tmp/ssmc-payload.lines' \
  creates '/tmp/ssmc-payload.lines'

cat /tmp/ssmc-payload.lines

# --- Report ----------------------------------------------------------------
report_compliance

echo ""
echo "== Final report (filtered) =="
get_report_json | python3 -c '
import json, sys
r = json.load(sys.stdin)
print("summary:", r["summary"])
for x in r["resources"]:
    print(f"  {x[\"status\"]:13} changed={x[\"changed\"]!s:5} {x[\"resource\"]}")
'
