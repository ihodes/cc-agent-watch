#!/bin/bash
STATUS="$1"
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$GIT_ROOT" ]; then
  PROJECT=$(basename "$GIT_ROOT")
else
  PROJECT=$(basename "$CWD")
fi
MONITOR_DIR="${CLAUDE_MONITOR_DIR:-$HOME/.claude-monitor/sessions}"
mkdir -p "$MONITOR_DIR"

TARGET="$MONITOR_DIR/$SESSION_ID.json"

if [ "$STATUS" = "ended" ]; then
  rm -f "$TARGET"
  exit 0
fi

# Short-circuit: skip write if status unchanged (PreToolUse fires very frequently)
if [ -f "$TARGET" ]; then
  CURRENT=$(jq -r '.status' "$TARGET" 2>/dev/null)
  if [ "$CURRENT" = "$STATUS" ]; then
    exit 0
  fi
fi

# Atomic write via temp file to prevent partial reads
TMPFILE=$(mktemp "$MONITOR_DIR/.tmp.XXXXXX")
cat > "$TMPFILE" <<EOF
{"session_id":"$SESSION_ID","project":"$PROJECT","cwd":"$CWD","status":"$STATUS","timestamp":$(date +%s)}
EOF
mv -f "$TMPFILE" "$TARGET"
