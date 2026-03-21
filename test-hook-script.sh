#!/bin/bash
# Test suite for update-state.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/update-state.sh"
PASS=0
FAIL=0
TESTS=0

# Setup: create a temp directory for test session files
TEST_DIR=$(mktemp -d)
export CLAUDE_MONITOR_DIR="$TEST_DIR"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

pass() {
  PASS=$((PASS + 1))
  TESTS=$((TESTS + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  TESTS=$((TESTS + 1))
  echo "  FAIL: $1"
}

assert_file_exists() {
  if [ -f "$1" ]; then
    pass "$2"
  else
    fail "$2 (file not found: $1)"
  fi
}

assert_file_not_exists() {
  if [ ! -f "$1" ]; then
    pass "$2"
  else
    fail "$2 (file still exists: $1)"
  fi
}

assert_json_field() {
  local file="$1" field="$2" expected="$3" label="$4"
  local actual
  actual=$(jq -r ".$field" "$file" 2>/dev/null)
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

mock_input() {
  local session_id="$1" cwd="$2"
  echo "{\"session_id\":\"$session_id\",\"cwd\":\"$cwd\"}"
}

# =====================================================================
echo "=== Test 1: Basic lifecycle — SessionStart creates file ==="

echo '{"session_id":"test-session-1","cwd":"/tmp"}' | bash "$SCRIPT" started

assert_file_exists "$TEST_DIR/test-session-1.json" "session file created"
assert_json_field "$TEST_DIR/test-session-1.json" "status" "started" "status is 'started'"
assert_json_field "$TEST_DIR/test-session-1.json" "session_id" "test-session-1" "session_id matches"

# =====================================================================
echo ""
echo "=== Test 2: Status transitions — running then idle ==="

echo '{"session_id":"test-session-2","cwd":"/tmp"}' | bash "$SCRIPT" started
assert_json_field "$TEST_DIR/test-session-2.json" "status" "started" "initial status is 'started'"

echo '{"session_id":"test-session-2","cwd":"/tmp"}' | bash "$SCRIPT" running
assert_json_field "$TEST_DIR/test-session-2.json" "status" "running" "status changed to 'running'"

echo '{"session_id":"test-session-2","cwd":"/tmp"}' | bash "$SCRIPT" idle
assert_json_field "$TEST_DIR/test-session-2.json" "status" "idle" "status changed to 'idle'"

# =====================================================================
echo ""
echo "=== Test 3: Session end — file deleted ==="

echo '{"session_id":"test-session-3","cwd":"/tmp"}' | bash "$SCRIPT" started
assert_file_exists "$TEST_DIR/test-session-3.json" "session file exists before end"

echo '{"session_id":"test-session-3","cwd":"/tmp"}' | bash "$SCRIPT" ended
assert_file_not_exists "$TEST_DIR/test-session-3.json" "session file deleted on end"

# =====================================================================
echo ""
echo "=== Test 4: Short-circuit — same status skips write ==="

echo '{"session_id":"test-session-4","cwd":"/tmp"}' | bash "$SCRIPT" running
assert_file_exists "$TEST_DIR/test-session-4.json" "session file exists"

# Record the mtime
if stat -f %m "$TEST_DIR/test-session-4.json" >/dev/null 2>&1; then
  MTIME_BEFORE=$(stat -f %m "$TEST_DIR/test-session-4.json")
else
  MTIME_BEFORE=$(stat -c %Y "$TEST_DIR/test-session-4.json")
fi

# Small delay to ensure mtime would differ if file were rewritten
sleep 1

echo '{"session_id":"test-session-4","cwd":"/tmp"}' | bash "$SCRIPT" running

if stat -f %m "$TEST_DIR/test-session-4.json" >/dev/null 2>&1; then
  MTIME_AFTER=$(stat -f %m "$TEST_DIR/test-session-4.json")
else
  MTIME_AFTER=$(stat -c %Y "$TEST_DIR/test-session-4.json")
fi

if [ "$MTIME_BEFORE" = "$MTIME_AFTER" ]; then
  pass "file not rewritten when status unchanged"
else
  fail "file was rewritten despite same status (mtime $MTIME_BEFORE -> $MTIME_AFTER)"
fi

# =====================================================================
echo ""
echo "=== Test 5: Atomic writes — no temp files linger ==="

echo '{"session_id":"test-session-5","cwd":"/tmp"}' | bash "$SCRIPT" started

TMPFILES=$(find "$TEST_DIR" -name '.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$TMPFILES" = "0" ]; then
  pass "no .tmp files remain after write"
else
  fail "$TMPFILES .tmp file(s) found after write"
fi

# =====================================================================
echo ""
echo "=== Test 6: Git root derivation ==="

# This test uses the AgentWatch repo itself as the git repo
echo "{\"session_id\":\"test-session-6\",\"cwd\":\"$SCRIPT_DIR\"}" | bash "$SCRIPT" started
assert_json_field "$TEST_DIR/test-session-6.json" "project" "AgentWatch" "project derived from git root"

# =====================================================================
echo ""
echo "=== Test 7: Non-git fallback ==="

NOGIT_DIR=$(mktemp -d)
echo "{\"session_id\":\"test-session-7\",\"cwd\":\"$NOGIT_DIR\"}" | bash "$SCRIPT" started
EXPECTED_PROJECT=$(basename "$NOGIT_DIR")
assert_json_field "$TEST_DIR/test-session-7.json" "project" "$EXPECTED_PROJECT" "project falls back to directory basename"
rm -rf "$NOGIT_DIR"

# =====================================================================
echo ""
echo "=== Test 8: Custom CLAUDE_MONITOR_DIR ==="

CUSTOM_DIR=$(mktemp -d)
CLAUDE_MONITOR_DIR="$CUSTOM_DIR" bash -c "echo '{\"session_id\":\"test-session-8\",\"cwd\":\"/tmp\"}' | bash '$SCRIPT' started"
assert_file_exists "$CUSTOM_DIR/test-session-8.json" "file written to custom CLAUDE_MONITOR_DIR"
assert_json_field "$CUSTOM_DIR/test-session-8.json" "status" "started" "correct status in custom dir"
rm -rf "$CUSTOM_DIR"

# =====================================================================
echo ""
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed out of $TESTS tests"
echo "==========================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
