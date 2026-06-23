#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Local test for `execute` + HTTPS `file` download
#
# Verifies:
#   1. `execute` with `creates` guard runs once, second pass is no-op
#   2. `execute` with `not_if` guard skips when test passes
#   3. `execute` failure is reported as `error`
#   4. `file` source 'https://...' downloads (uses example.com if reachable)
#   5. `file` checksum mismatch is caught
#
# Runs without root and without network for #1-#3. #4-#5 only run if curl can
# reach https://www.gnu.org/licenses/gpl-3.0.txt (skipped otherwise).
# ═══════════════════════════════════════════════════════════════════════════════

export SSM_CONVERGE_HOME="$(cd "$(dirname "$0")/../../src/linux" && pwd)"
export DSC_MODE="enforce"
export DSC_PROFILE="execute-test"
export DSC_LOCAL_DIR="/tmp/ssm-converge-execute-test"
export DSC_VERBOSE="true"

rm -rf /tmp/ssm-converge-execute-test
rm -rf /tmp/ssm-converge-execute-fixtures
mkdir -p /tmp/ssm-converge-execute-fixtures

source "${SSM_CONVERGE_HOME}/lib.sh"

PASS=0
FAIL=0

assert_compliant() {
  local name="$1"
  local count
  count=$(get_report_json | python3 -c '
import json,sys
r = json.load(sys.stdin)
hits = [x for x in r["resources"] if x["resource"] == "'"$name"'" and x["status"] == "compliant"]
print(len(hits))
')
  if [ "$count" -ge 1 ]; then
    echo "  [PASS] $name reported compliant"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $name not reported compliant"
    FAIL=$((FAIL + 1))
  fi
}

assert_changed() {
  local name="$1" expected="$2"
  local got
  got=$(get_report_json | python3 -c '
import json,sys
r = json.load(sys.stdin)
hits = [x for x in r["resources"] if x["resource"] == "'"$name"'"]
if hits: print(hits[-1]["changed"])
else:    print("missing")
')
  if [ "$got" = "$expected" ]; then
    echo "  [PASS] $name changed=$expected"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $name changed=$got (expected $expected)"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "── Test 1: execute with creates guard (first pass) ────────────"
execute 'first-boot' \
  command 'touch /tmp/ssm-converge-execute-fixtures/.first-boot-done' \
  creates '/tmp/ssm-converge-execute-fixtures/.first-boot-done'
assert_compliant 'execute/first-boot'
assert_changed   'execute/first-boot' 'True'

echo ""
echo "── Test 2: execute with creates guard (second pass — no-op) ───"
execute 'first-boot' \
  command 'echo SHOULD-NOT-RUN' \
  creates '/tmp/ssm-converge-execute-fixtures/.first-boot-done'
assert_compliant 'execute/first-boot'
assert_changed   'execute/first-boot' 'False'

echo ""
echo "── Test 3: execute with not_if guard (skip when test passes) ──"
echo 'sentinel' > /tmp/ssm-converge-execute-fixtures/sentinel
execute 'guarded-by-not-if' \
  command 'echo SHOULD-NOT-RUN' \
  not_if  'test -f /tmp/ssm-converge-execute-fixtures/sentinel'
assert_compliant 'execute/guarded-by-not-if'
assert_changed   'execute/guarded-by-not-if' 'False'

echo ""
echo "── Test 4: execute with only_if guard (run when test passes) ──"
execute 'guarded-by-only-if' \
  command 'touch /tmp/ssm-converge-execute-fixtures/only-if-ran' \
  only_if 'test -f /tmp/ssm-converge-execute-fixtures/sentinel'
assert_compliant 'execute/guarded-by-only-if'
assert_changed   'execute/guarded-by-only-if' 'True'
[ -f /tmp/ssm-converge-execute-fixtures/only-if-ran ] && echo "  [PASS] only_if command actually ran" && PASS=$((PASS + 1)) || { echo "  [FAIL] only_if command did not run"; FAIL=$((FAIL + 1)); }

echo ""
echo "── Test 5: execute with failing command reports error ─────────"
execute 'will-fail' command 'exit 7'
got=$(get_report_json | python3 -c '
import json,sys
r = json.load(sys.stdin)
hits = [x for x in r["resources"] if x["resource"] == "execute/will-fail"]
print(hits[-1]["status"] if hits else "missing")
')
if [ "$got" = "error" ]; then echo "  [PASS] execute/will-fail status=error"; PASS=$((PASS + 1)); else echo "  [FAIL] expected error, got $got"; FAIL=$((FAIL + 1)); fi

echo ""
echo "── Test 6: file with checksum mismatch is rejected ────────────"
# Pre-create a file whose hash does NOT match what we'll claim.
echo "wrong content" > /tmp/ssm-converge-execute-fixtures/bad.txt
# Use file:// to avoid network. Provide a checksum that won't match.
file '/tmp/ssm-converge-execute-fixtures/bad-managed.txt' present \
  source 'file:///tmp/ssm-converge-execute-fixtures/bad.txt' \
  checksum 'sha256:0000000000000000000000000000000000000000000000000000000000000000'
got=$(get_report_json | python3 -c '
import json,sys
r = json.load(sys.stdin)
hits = [x for x in r["resources"] if x["resource"] == "file/tmp/ssm-converge-execute-fixtures/bad-managed.txt"]
print(hits[-1]["status"] if hits else "missing")
')
if [ "$got" = "error" ]; then echo "  [PASS] checksum mismatch -> error"; PASS=$((PASS + 1)); else echo "  [FAIL] expected error, got $got"; FAIL=$((FAIL + 1)); fi

echo ""
echo "── Test 7: file with correct checksum from local file:// ──────"
echo "hello" > /tmp/ssm-converge-execute-fixtures/good.txt
expected_hash=$(sha256sum /tmp/ssm-converge-execute-fixtures/good.txt | cut -d' ' -f1)
file '/tmp/ssm-converge-execute-fixtures/good-managed.txt' present \
  source "file:///tmp/ssm-converge-execute-fixtures/good.txt" \
  checksum "sha256:$expected_hash"
got=$(get_report_json | python3 -c '
import json,sys
r = json.load(sys.stdin)
hits = [x for x in r["resources"] if x["resource"] == "file/tmp/ssm-converge-execute-fixtures/good-managed.txt"]
print(hits[-1]["status"] if hits else "missing")
')
if [ "$got" = "compliant" ]; then echo "  [PASS] checksum match -> compliant"; PASS=$((PASS + 1)); else echo "  [FAIL] expected compliant, got $got"; FAIL=$((FAIL + 1)); fi

echo ""
echo "── Test 8: file with HTTPS source (network optional) ──────────"
if curl -fsSL --max-time 10 -o /dev/null https://www.gnu.org/licenses/gpl-3.0.txt; then
  file '/tmp/ssm-converge-execute-fixtures/gpl.txt' present \
    source 'https://www.gnu.org/licenses/gpl-3.0.txt'
  got=$(get_report_json | python3 -c '
import json,sys
r = json.load(sys.stdin)
hits = [x for x in r["resources"] if x["resource"] == "file/tmp/ssm-converge-execute-fixtures/gpl.txt"]
print(hits[-1]["status"] if hits else "missing")
')
  if [ "$got" = "compliant" ]; then
    echo "  [PASS] HTTPS download succeeded"
    PASS=$((PASS + 1))
    [ -s /tmp/ssm-converge-execute-fixtures/gpl.txt ] && echo "  [PASS] file is non-empty" && PASS=$((PASS + 1)) || { echo "  [FAIL] file empty"; FAIL=$((FAIL + 1)); }
  else
    echo "  [FAIL] expected compliant, got $got"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  [SKIP] no network"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Tests:  $((PASS + FAIL))"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "═══════════════════════════════════════════════════"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
