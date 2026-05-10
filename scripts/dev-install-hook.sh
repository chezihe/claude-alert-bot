#!/bin/bash
# scripts/dev-install-hook.sh — developer hook installer.
# The app installs hooks on launch; this remains a manual development helper
# for checking or repairing ~/.claude/settings.json.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC_REPORTER="$REPO_ROOT/Reporter/cab-report.sh"
USER_DATA_DIR="$HOME/Library/Application Support/ClaudeAlertBot"
DEST_REPORTER="$USER_DATA_DIR/cab-report.sh"
SETTINGS="$HOME/.claude/settings.json"

usage() {
    cat <<EOF
Usage: $0 [--apply | --check | --help]

  (no flag)   Copy Reporter to user-data path and PRINT the JSON block to paste into $SETTINGS
  --apply     Same as default, plus merge the JSON block into $SETTINGS idempotently
  --check     Pretty-print the current hooks section from $SETTINGS
  --help      This help
EOF
}

copy_reporter() {
    if [ ! -f "$SRC_REPORTER" ]; then
        echo "error: $SRC_REPORTER missing — Plan 02 not yet shipped?" >&2
        exit 1
    fi
    mkdir -p "$USER_DATA_DIR"
    cp "$SRC_REPORTER" "$DEST_REPORTER"
    chmod +x "$DEST_REPORTER"
    echo "Copied Reporter to: $DEST_REPORTER"
}

snippet() {
    # The exact block from RESEARCH Pitfall #10 + extended for UserPromptSubmit.
    # Note: \$HOME is escaped so the JSON contains the literal string "$HOME/...".
    # Claude Code's hook runner expands $HOME itself per code.claude.com/docs/en/hooks.
    cat <<JSON
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "\"\$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" stop", "timeout": 5 }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "\"\$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" user_prompt_submit", "timeout": 5 }
        ]
      }
    ]
  }
}
JSON
}

apply() {
    mkdir -p "$(dirname "$SETTINGS")"
    if [ ! -f "$SETTINGS" ]; then
        snippet > "$SETTINGS"
        echo "Created $SETTINGS"
        return
    fi
    # Idempotent merge — only replace OUR Stop / UserPromptSubmit entries; preserve other user hooks.
    # Use python3 for safe JSON manipulation.
    SNIPPET="$(snippet)" SETTINGS_PATH="$SETTINGS" /usr/bin/python3 - <<'PY'
import json, os, sys, re

settings_path = os.environ["SETTINGS_PATH"]
snippet = json.loads(os.environ["SNIPPET"])

try:
    with open(settings_path) as f:
        text = f.read()
    # Strip JSON5-style line/block comments before parsing.
    # The in-app installer uses the canonical Swift implementation.
    cleaned = re.sub(r'^\s*//.*$', '', text, flags=re.MULTILINE)
    cleaned = re.sub(r'/\*.*?\*/', '', cleaned, flags=re.DOTALL)
    existing = json.loads(cleaned) if cleaned.strip() else {}
except Exception as e:
    sys.stderr.write(
        f"warning: could not parse {settings_path} ({e}); refusing to mutate. "
        f"Use default mode and hand-merge.\n"
    )
    sys.exit(2)

existing.setdefault("hooks", {})

cab_marker = "ClaudeAlertBot/cab-report.sh"

def merge_event(name):
    new_entries = snippet["hooks"][name]
    existing_entries = existing["hooks"].get(name, [])
    # Drop any prior cab-report registrations
    filtered = []
    for entry in existing_entries:
        keep = True
        for h in entry.get("hooks", []):
            if cab_marker in h.get("command", ""):
                keep = False
                break
        if keep:
            filtered.append(entry)
    existing["hooks"][name] = filtered + new_entries

merge_event("Stop")
merge_event("UserPromptSubmit")

with open(settings_path, "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\n")
print(f"Updated {settings_path} (idempotent merge)")
PY
}

check() {
    if [ ! -f "$SETTINGS" ]; then
        echo "$SETTINGS does not exist — no hooks configured."
        exit 0
    fi
    SETTINGS_PATH="$SETTINGS" /usr/bin/python3 - <<'PY'
import json, os, re, sys
settings_path = os.environ["SETTINGS_PATH"]
with open(settings_path) as f:
    t = f.read()
cleaned = re.sub(r'^\s*//.*$', '', t, flags=re.MULTILINE)
cleaned = re.sub(r'/\*.*?\*/', '', cleaned, flags=re.DOTALL)
try:
    j = json.loads(cleaned) if cleaned.strip() else {}
except Exception as e:
    sys.stderr.write(f"warning: could not parse {settings_path} ({e})\n")
    sys.exit(2)
print(json.dumps(j.get("hooks", {}), indent=2))
PY
}

case "${1:-}" in
    ""|--print)   copy_reporter; echo; echo "--- paste into $SETTINGS ---"; snippet ;;
    --apply)      copy_reporter; apply ;;
    --check)      check ;;
    --help|-h)    usage ;;
    *)            usage; exit 2 ;;
esac
