#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
MONITOR_DIR="$HOME/.claude-monitor"
SETTINGS_FILE="$HOME/.claude/settings.json"
PLIST_NAME="com.launchmgr.agent-watch"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"
LOG_DIR="$HOME/Library/Logs/launchmgr"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}==> $1${NC}"; }
warn()  { echo -e "${YELLOW}==> $1${NC}"; }
error() { echo -e "${RED}==> $1${NC}"; exit 1; }

# ── Prerequisites ──────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    error "jq is required. Install it with: brew install jq"
fi

if ! command -v swift &>/dev/null; then
    error "Swift is required. Install Xcode Command Line Tools."
fi

# ── 1. Install hook script ─────────────────────────────────────────

info "Installing hook script to $MONITOR_DIR/"
mkdir -p "$MONITOR_DIR"
cp "$REPO_DIR/update-state.sh" "$MONITOR_DIR/"
chmod +x "$MONITOR_DIR/update-state.sh"
mkdir -p "$MONITOR_DIR/sessions"

# ── 2. Merge hooks into Claude Code settings ───────────────────────

info "Configuring Claude Code hooks..."
mkdir -p "$(dirname "$SETTINGS_FILE")"

HOOKS_JSON=$(cat <<'HOOKS'
{
  "UserPromptSubmit": [
    {"matcher": "", "hooks": [{"type": "command", "command": "$HOME/.claude-monitor/update-state.sh running"}]}
  ],
  "Stop": [
    {"matcher": "", "hooks": [{"type": "command", "command": "$HOME/.claude-monitor/update-state.sh idle"}]}
  ],
  "SessionStart": [
    {"matcher": "", "hooks": [{"type": "command", "command": "$HOME/.claude-monitor/update-state.sh started"}]}
  ],
  "SessionEnd": [
    {"matcher": "", "hooks": [{"type": "command", "command": "$HOME/.claude-monitor/update-state.sh ended"}]}
  ]
}
HOOKS
)

if [ -f "$SETTINGS_FILE" ]; then
    # Merge hooks into existing settings
    EXISTING_HOOKS=$(jq -r '.hooks // {}' "$SETTINGS_FILE")

    # Check if our hooks are already installed
    if echo "$EXISTING_HOOKS" | jq -e '.UserPromptSubmit' &>/dev/null && \
       echo "$EXISTING_HOOKS" | jq -e '.Stop' &>/dev/null && \
       echo "$EXISTING_HOOKS" | jq -e '.SessionStart' &>/dev/null && \
       echo "$EXISTING_HOOKS" | jq -e '.SessionEnd' &>/dev/null; then
        warn "Hooks already configured in $SETTINGS_FILE, skipping."
    else
        TMPFILE=$(mktemp)
        jq --argjson new_hooks "$HOOKS_JSON" '.hooks = ((.hooks // {}) * $new_hooks)' "$SETTINGS_FILE" > "$TMPFILE"
        mv "$TMPFILE" "$SETTINGS_FILE"
        info "Hooks merged into $SETTINGS_FILE"
    fi
else
    echo "{\"hooks\": $HOOKS_JSON}" | jq . > "$SETTINGS_FILE"
    info "Created $SETTINGS_FILE with hooks"
fi

# ── 3. Build release binary ────────────────────────────────────────

info "Building Agent Watch (release)..."
cd "$REPO_DIR"
swift build -c release --product AgentWatch 2>&1 | tail -3

BINARY="$REPO_DIR/.build/arm64-apple-macosx/release/AgentWatch"
if [ ! -f "$BINARY" ]; then
    # Try alternate path
    BINARY=$(find "$REPO_DIR/.build" -path "*/release/AgentWatch" -not -path "*/dSYM/*" -type f | head -1)
fi

if [ ! -f "$BINARY" ]; then
    error "Build failed — could not find release binary."
fi

info "Binary built at $BINARY"

# ── 4. Install launch agent ────────────────────────────────────────

info "Installing launch agent..."
mkdir -p "$LOG_DIR"

# Unload existing if present
if launchctl list "$PLIST_NAME" &>/dev/null 2>&1; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$PLIST_NAME</string>
	<key>ProgramArguments</key>
	<array>
		<string>$BINARY</string>
	</array>
	<key>WorkingDirectory</key>
	<string>$REPO_DIR</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$LOG_DIR/$PLIST_NAME.log</string>
	<key>StandardErrorPath</key>
	<string>$LOG_DIR/$PLIST_NAME.log</string>
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
	</dict>
</dict>
</plist>
PLIST

# ── 5. Start the service ──────────────────────────────────────────

info "Starting Agent Watch..."
launchctl load "$PLIST_PATH"

if launchctl list "$PLIST_NAME" &>/dev/null 2>&1; then
    info "Agent Watch is running!"
else
    error "Failed to start Agent Watch. Check $LOG_DIR/$PLIST_NAME.log"
fi

echo ""
info "Installation complete!"
echo ""
echo "  Agent Watch is now running in your menubar."
echo "  It will start automatically on login."
echo ""
echo "  Global shortcut: Ctrl+Option+Shift+Cmd+'"
echo "  Or click the hexagon cluster in the menubar."
echo ""
echo "  To uninstall:  bash $(basename "$0") --uninstall"
echo "  To rebuild:    swift build -c release --product AgentWatch"
echo "  Logs:          $LOG_DIR/$PLIST_NAME.log"
