#!/bin/bash
# Registers the NotchHover approval hook with Claude Code.
# Usage: Scripts/install-claude-hook.sh [--uninstall]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PATH="$SCRIPT_DIR/claude-permission-hook.py"
SETTINGS="$HOME/.claude/settings.json"
MODE="install"
# Only tools that actually gate on permission; a "*" matcher would route every read
# through the notch, including calls your settings would have auto-allowed.
MATCHER="Bash|Write|Edit|MultiEdit|NotebookEdit|WebFetch"

while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall) MODE="uninstall" ;;
        --matcher) MATCHER="$2"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.notchhover-backup"

MODE="$MODE" HOOK_PATH="$HOOK_PATH" SETTINGS="$SETTINGS" MATCHER="$MATCHER" /usr/bin/python3 <<'PY'
import json, os

settings_path = os.environ["SETTINGS"]
hook_path = os.environ["HOOK_PATH"]
mode = os.environ["MODE"]

with open(settings_path) as handle:
    settings = json.load(handle)

hooks = settings.setdefault("hooks", {})
matchers = hooks.setdefault("PreToolUse", [])

# Drop any previous NotchHover entry so installing twice stays idempotent.
for matcher in list(matchers):
    entries = matcher.get("hooks", [])
    matcher["hooks"] = [h for h in entries if "claude-permission-hook" not in h.get("command", "")]
    if not matcher["hooks"]:
        matchers.remove(matcher)

if mode == "install":
    matchers.append({
        "matcher": os.environ["MATCHER"],
        "hooks": [{"type": "command", "command": hook_path, "timeout": 60}],
    })

if not matchers:
    hooks.pop("PreToolUse", None)
if not hooks:
    settings.pop("hooks", None)

with open(settings_path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")

print(("Installed" if mode == "install" else "Removed") + " the NotchHover approval hook in " + settings_path)
PY

echo "Backup written to $SETTINGS.notchhover-backup"
echo "Restart any running Claude Code sessions to pick up the change."
