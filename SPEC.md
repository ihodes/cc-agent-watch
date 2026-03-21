# Agent Watch — Specification

macOS menubar app that monitors Claude Code sessions via hook-based IPC and displays per-project status as a hexagon cluster.

## Overview

Claude Code hooks write per-session JSON files to a watched directory. Agent Watch reads them, groups by project (git root basename), and renders a hex cluster in the menubar. A hexagon is grey when all sessions in that project are running, and lights up (green or custom color) when at least one session is idle/waiting for input.

## Architecture

```
Claude Code hooks  -->  ~/.claude-monitor/sessions/*.json  -->  Agent Watch (menubar app)
     (shell script)           (per-session files)                (FSEvents watcher)
```

No Emacs involvement. No buffer parsing. Hooks are the sole data source.

---

## 1. Claude Code Hooks

### 1.1 Hook Configuration (`~/.claude/settings.json`)

These hooks should be **merged** into the user's existing `settings.json`, not replace it. If a `hooks` key already exists, add these entries to it.

Hook commands use `$HOME` (not `~`) for reliable path expansion.

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [{ "type": "command", "command": "$HOME/.claude-monitor/update-state.sh idle" }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "$HOME/.claude-monitor/update-state.sh running" }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "$HOME/.claude-monitor/update-state.sh started" }]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "$HOME/.claude-monitor/update-state.sh ended" }]
      }
    ]
  }
}
```

### 1.2 State Update Script (`~/.claude-monitor/update-state.sh`)

Receives hook JSON on stdin. Writes/removes per-session files.

**Prerequisites**: Requires `jq` (`brew install jq`).

Must be made executable: `chmod +x ~/.claude-monitor/update-state.sh`

```bash
#!/bin/bash
STATUS="$1"
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')
PROJECT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null | xargs basename || basename "$CWD")
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
```

### 1.3 Session File Format

```json
{
  "session_id": "abc123",
  "project": "emacs.org",
  "cwd": "/Users/isaac/workspace/emacs.org",
  "status": "idle",
  "timestamp": 1742567890
}
```

- One file per session: `{session_id}.json`
- File removed on `SessionEnd`
- `status`: `"started"`, `"running"`, `"idle"`
- Writes are atomic (write to temp file, then `mv`) to prevent the Swift app from reading partial JSON

---

## 2. Menubar App — Agent Watch

### 2.1 Platform

- Swift / SwiftUI
- Minimum deployment: macOS 26 (Tahoe)
- `MenuBarExtra` for menubar presence
- SPM dependency: `HotKey` (https://github.com/soffes/HotKey) for global keyboard shortcut
- The app is a menubar-only app (no Dock icon). Set `LSUIElement = YES` in Info.plist.

### 2.2 Menubar Icon — Hexagon Cluster

- Each hexagon represents one **project** (grouped by `project` field from session files)
- Layout: honeycomb packing algorithm for N hexagons, fitting within ~22x22pt menubar space
- Colors:
  - **Light grey** (`#C0C0C0`): all sessions in project are `running` / `started`
  - **Project color** (default green `#34D058`, configurable per project): at least one session is `idle`
- Rendered via SwiftUI `Canvas` or composed `Path` shapes
- Cluster dynamically grows/shrinks as projects appear/disappear
- When zero projects are active, show a single grey hexagon outline as a placeholder

### 2.3 Config Window

Opened via:
- Global keyboard shortcut: `Cmd+Shift+Option+Ctrl+'` (requires Accessibility permission — macOS will prompt on first use)
- Clicking the menubar icon

#### Layout

```
+-----------------------------------------------+
|  Agent Watch                                   |
|-----------------------------------------------|
|  IPC Directory: ~/.claude-monitor/sessions     |
|  [Change...]  [Reveal in Finder]               |
|-----------------------------------------------|
|  # | Project      | Status    | Color | On/Off|
|  1 | emacs.org    | 2 idle    | [===] |  [x]  |
|  2 | my-api       | 1 running | [===] |  [x]  |
|  3 | frontend     | idle      | [===] |  [ ]  |
|-----------------------------------------------|
|  Cmd+1..9      Toggle project on/off           |
|  Shift+Cmd+1..9  Open color picker             |
+-----------------------------------------------+
```

#### Features

| Feature | Shortcut | Notes |
|---------|----------|-------|
| Toggle project monitoring | `Cmd+1` through `Cmd+9` | Only within config window. Disabled projects hide their hexagon from menubar |
| Open color picker | `Shift+Cmd+1` through `Shift+Cmd+9` | Native `ColorPicker`, saved per project |
| Change IPC directory | Click "Change..." | `NSOpenPanel` directory picker |
| Reveal IPC directory | Click "Reveal in Finder" | `NSWorkspace.shared.selectFile(...)` |
| Close window | `Escape` | Standard |

#### Project List Behavior

- Auto-populated from session files in the watched directory
- Projects persist in config even after all their sessions end (until manually removed or app restart)
- Newly discovered projects default to: enabled, green color
- Projects are sorted alphabetically by name

### 2.4 IPC Directory Watching

- Default directory: `~/.claude-monitor/sessions/`
- Configurable via the config window (persisted in UserDefaults)
- Uses `DispatchSource.makeFileSystemObjectSource` or `FSEvents` to watch for file creation, modification, and deletion
- On change: re-read all `.json` files in the directory (ignoring dotfiles/temp files), regroup by project, update state
- Ignore files starting with `.` (temp files from atomic writes)

### 2.5 Persistence (UserDefaults)

- IPC directory path (string, default `~/.claude-monitor/sessions`)
- Per-project settings: dictionary keyed by project name, value is `{ "enabled": Bool, "color": hex string }`
- Global hotkey binding (for future configurability; v1 is hardcoded)

### 2.6 State Aggregation Logic

```
For each project:
  sessions = all session files where project == this project
  if any session has status == "idle":
    project_status = idle  →  show project color
  else:
    project_status = running  →  show grey

  session_count = len(sessions)
  idle_count = count where status == "idle"
  display: "{idle_count} idle" or "{session_count} running" in config window
```

Only **enabled** projects are rendered as hexagons in the menubar. Disabled projects still appear in the config window but are greyed out and have no hexagon.

### 2.7 Staleness Handling

- If a session file's `timestamp` is older than 5 minutes and status is `running`, mark as `stale`
- Stale sessions are shown with a dimmed/hatched hexagon in the menubar and a "stale" badge in the config window
- This handles cases where Claude Code crashes or is killed without firing `SessionEnd`

---

## 3. Hex Cluster Layout Algorithm

For N hexagons in a ~22x22pt menubar space:

- **0**: single grey hexagon outline (placeholder)
- **1**: centered single hex
- **2**: side by side
- **3**: triangle (2 top, 1 bottom)
- **4**: 2x2 grid with hex offset
- **5-7**: classic honeycomb ring (1 center + up to 6 surrounding)
- **8+**: shrink hex size, nested rings (practical limit ~12 before illegibly small)

Each hex is a `Path` with 6 vertices (flat-top orientation), filled with the appropriate color. Hex size is computed as: `available_size / (2 * rings + 1)` where rings is the number of concentric rings needed.

---

## 4. File Structure

### 4.1 Swift Project

Location: `~/workspace/AgentWatch/` (standalone git repo)

```
AgentWatch/
  Package.swift              # SPM package (HotKey dependency)
  Sources/
    AgentWatchApp.swift       # @main, MenuBarExtra, LSUIElement
    Models/
      Session.swift           # Codable struct matching session JSON
      ProjectState.swift      # Aggregated project: name, sessions, idle status
      AppState.swift          # @Observable: projects, directory path, settings
    Views/
      HexClusterView.swift    # Menubar icon rendering (Canvas/Path)
      ConfigWindow.swift      # Settings panel with project list
      ProjectRowView.swift    # Single row: name, status, color picker, toggle
    Services/
      DirectoryWatcher.swift  # FSEvents/DispatchSource wrapper
      HotkeyManager.swift     # Global shortcut via HotKey library
    Utilities/
      HexLayout.swift         # Hex grid position calculation
  Tests/
    SessionTests.swift        # JSON parsing, malformed input handling
    ProjectStateTests.swift   # Aggregation logic, idle detection
    HexLayoutTests.swift      # Position calculations for N=0..12
    DirectoryWatcherTests.swift # Mock filesystem, file creation/deletion
    AppStateTests.swift       # Integration: files → projects → hex states
```

### 4.2 Hook Script

```
~/.claude-monitor/
  update-state.sh            # Hook script (chmod +x)
  sessions/                  # IPC directory (created by script)
    {session_id}.json         # One per active session
```

---

## 5. Testing Strategy

### 5.1 Shell Script Tests (bash, no app needed)

Create a test script `test-hook-script.sh` that:

1. **Basic lifecycle**: pipe mock SessionStart JSON → verify file created with `"started"` status
2. **Status transitions**: pipe PreToolUse JSON → verify `"running"`; pipe Notification JSON → verify `"idle"`
3. **Session end**: pipe SessionEnd JSON → verify file deleted
4. **Short-circuit**: write a `"running"` file, pipe another PreToolUse → verify file mtime unchanged
5. **Atomic writes**: verify no `.tmp.*` files linger after writes
6. **Git root derivation**: run from a known git repo → verify project name matches repo basename
7. **Non-git fallback**: run from `/tmp` → verify project name is `tmp`
8. **Custom CLAUDE_MONITOR_DIR**: set env var → verify files written to custom path

### 5.2 Swift Unit Tests (xcodebuild test, no GUI)

- **SessionTests**: parse valid JSON, handle missing fields, handle malformed JSON gracefully
- **ProjectStateTests**: given N sessions with mixed statuses, verify `isIdle` is true when any session is idle; verify counts
- **HexLayoutTests**: for N=0..12, verify all positions are unique and fit within bounds; verify hex vertex geometry
- **AppStateTests**: load mock directory of session files → verify correct number of projects with correct states; verify enabled/disabled filtering
- **StalenessTests**: session with timestamp > 5min ago and status `running` → marked stale

### 5.3 Integration Tests (shell + Swift model layer)

1. Run `update-state.sh` to create real session files in a temp directory
2. Point `AppState` at that directory
3. Verify project grouping and status detection end-to-end
4. Delete a session file → verify project updates

### 5.4 Manual Testing (requires human)

- Accessibility permission grant for global hotkey
- Visual verification of hex cluster at actual menubar scale
- Real Claude Code session firing actual hooks

---

## 6. Prerequisites & Manual Steps

These steps require human intervention and cannot be automated:

| Step | When | What to do |
|------|------|------------|
| Install `jq` | Before first use | `brew install jq` (skip if already installed) |
| Grant Accessibility permission | First app launch | macOS will prompt; approve in System Settings > Privacy > Accessibility |
| Trust unsigned app | First app launch | Right-click > Open, then approve in System Settings > Privacy > Security |
| Merge hooks into `settings.json` | Setup | Review the hook entries and merge into existing `~/.claude/settings.json` |

---

## 7. Future Roadmap

- **Per-session hexagons**: Option to show one hex per CC session instead of per project, labeled with session ID or index
- **Project name override**: `CLAUDE_MONITOR_PROJECT` env var checked by hook script before falling back to git root basename; or Emacs dir-locals per tabspace
- **Click hex to focus**: clicking a hexagon sends focus to the corresponding Emacs tabspace
- **Notification integration**: optional macOS notification when a project transitions to idle
- **Menu on click**: right-click/option-click the menubar icon shows a dropdown with project list and quick toggles
- **Auto-cleanup**: periodically remove stale session files older than N hours
- **Configurable global hotkey**: UI to rebind the hotkey (v1 is hardcoded to `Cmd+Shift+Option+Ctrl+'`)

---

## 8. Estimated Effort

| Component | Lines (est.) |
|-----------|-------------|
| Shell hook script | ~30 |
| Shell test script | ~80 |
| Swift: app entry + MenuBarExtra | ~60 |
| Swift: hex cluster rendering + layout | ~150 |
| Swift: app state model + session parsing | ~120 |
| Swift: config window + shortcuts + color pickers | ~200 |
| Swift: directory watcher | ~80 |
| Swift: global hotkey | ~50 |
| Swift: UserDefaults persistence | ~60 |
| Swift: unit tests | ~200 |
| **Total** | **~1030** |
