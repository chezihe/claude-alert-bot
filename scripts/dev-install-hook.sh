#!/bin/bash
# scripts/dev-install-hook.sh — developer hook installer.
# The app installs hooks on launch; this remains a manual development helper
# for checking or repairing ~/.claude/settings.json and, when present,
# ~/.codex hook configuration.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC_REPORTER="$REPO_ROOT/Reporter/cab-report.sh"
USER_DATA_DIR="$HOME/Library/Application Support/ClaudeAlertBot"
DEST_REPORTER="$USER_DATA_DIR/cab-report.sh"
SETTINGS="$HOME/.claude/settings.json"
CODEX_DIR="$HOME/.codex"
CODEX_HOOKS="$CODEX_DIR/hooks.json"
CODEX_CONFIG="$CODEX_DIR/config.toml"

usage() {
    cat <<EOF
Usage: $0 [--apply | --check | --help]

  (no flag)   Copy Reporter to user-data path and PRINT the JSON block to paste into $SETTINGS
  --apply     Same as default, plus merge hooks into $SETTINGS and Codex config when present
  --check     Pretty-print the current Claude hooks and Codex hooks when present
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

apply_codex() {
    if [ ! -d "$CODEX_DIR" ]; then
        return
    fi

    SNIPPET="$(snippet)" CODEX_HOOKS_PATH="$CODEX_HOOKS" CODEX_CONFIG_PATH="$CODEX_CONFIG" /usr/bin/python3 - <<'PY'
import json, os, sys

hooks_path = os.environ["CODEX_HOOKS_PATH"]
config_path = os.environ["CODEX_CONFIG_PATH"]
snippet = json.loads(os.environ["SNIPPET"])
cab_marker = "ClaudeAlertBot/cab-report.sh"

def strip_json_comments(text):
    result = []
    index = 0
    in_string = False
    escaping = False

    while index < len(text):
        char = text[index]
        if in_string:
            result.append(char)
            if escaping:
                escaping = False
            elif char == "\\":
                escaping = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
            result.append(char)
            index += 1
            continue

        if char == "/" and index + 1 < len(text):
            next_char = text[index + 1]
            if next_char == "/":
                index += 2
                while index < len(text) and text[index] not in "\r\n":
                    index += 1
                continue
            if next_char == "*":
                end = text.find("*/", index + 2)
                if end == -1:
                    raise ValueError("unterminated block comment")
                result.append(" ")
                result.extend(char for char in text[index + 2:end] if char in "\r\n")
                index = end + 2
                continue

        result.append(char)
        index += 1

    return "".join(result)

def load_hooks(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path) as f:
            text = f.read()
        cleaned = strip_json_comments(text)
        return json.loads(cleaned) if cleaned.strip() else {}
    except Exception as e:
        sys.stderr.write(
            f"warning: could not parse {path} ({e}); refusing to mutate Codex hooks.\n"
        )
        sys.exit(2)

def merge_event(settings, name):
    hooks = settings.setdefault("hooks", {})
    existing_entries = hooks.get(name, [])
    filtered = []
    for entry in existing_entries:
        entry_hooks = entry.get("hooks")
        if not isinstance(entry_hooks, list):
            filtered.append(entry)
            continue
        kept_hooks = [
            hook for hook in entry_hooks
            if cab_marker not in hook.get("command", "")
        ]
        if not kept_hooks:
            continue
        updated = dict(entry)
        updated["hooks"] = kept_hooks
        filtered.append(updated)
    hooks[name] = filtered + snippet["hooks"][name]

def config_lines(text):
    return text.replace("\r\n", "\n").replace("\r", "\n").split("\n")

def header_name(line):
    before_comment = line.split("#", 1)[0].strip()
    if before_comment.startswith("[[") and before_comment.endswith("]]"):
        return before_comment[2:-2].strip()
    if before_comment.startswith("[") and before_comment.endswith("]"):
        return before_comment[1:-1].strip()
    return None

def has_inline_hooks(text):
    return any(
        (name == "hooks" or name.startswith("hooks."))
        for name in (header_name(line) for line in config_lines(text))
        if name is not None
    )

def next_header_index(lines, after):
    index = after + 1
    while index < len(lines):
        if header_name(lines[index]) is not None:
            return index
        index += 1
    return len(lines)

def block_contains_cab_command(lines):
    for line in lines:
        trimmed = line.strip()
        key = trimmed.split("=", 1)[0].strip()
        if key == "command" and cab_marker in line:
            return True
    return False

def remove_cab_inline_hook_commands(lines, command_header):
    result = []
    index = 0
    while index < len(lines):
        if header_name(lines[index]) == command_header:
            end = next_header_index(lines, index)
            block = lines[index:end]
            if block_contains_cab_command(block):
                index = end
                continue
        result.append(lines[index])
        index += 1
    return result

def inline_hook_entry_end_index(lines, after, command_header):
    index = after + 1
    while index < len(lines):
        name = header_name(lines[index])
        if name is None:
            index += 1
            continue
        if name == command_header:
            index += 1
            continue
        break
    return index

def remove_empty_inline_hook_entries(lines, event):
    entry_header = f"hooks.{event}"
    command_header = f"hooks.{event}.hooks"
    result = []
    index = 0
    while index < len(lines):
        if header_name(lines[index]) != entry_header:
            result.append(lines[index])
            index += 1
            continue
        end = inline_hook_entry_end_index(lines, index, command_header)
        block = lines[index:end]
        if any(header_name(line) == command_header for line in block[1:]):
            result.extend(block)
        index = end
    return result

def remove_cab_inline_hooks(lines, event):
    command_header = f"hooks.{event}.hooks"
    without_cab_commands = remove_cab_inline_hook_commands(lines, command_header)
    return remove_empty_inline_hook_entries(without_cab_commands, event)

def enable_codex_hooks(text):
    lines = config_lines(text)
    if lines == [""]:
        lines = []
    lines = remove_cab_inline_hooks(lines, "Stop")
    lines = remove_cab_inline_hooks(lines, "UserPromptSubmit")
    in_features = False
    features_index = None
    did_set = False

    for index, line in enumerate(lines):
        name = header_name(line)
        if name is not None:
            in_features = name == "features"
            if in_features:
                features_index = index
            continue

        key = line.strip().split("=", 1)[0].strip()
        if in_features and key == "codex_hooks":
            indent = line[:len(line) - len(line.lstrip(" \t"))]
            lines[index] = f"{indent}codex_hooks = true"
            did_set = True
            break

    if not did_set:
        if features_index is not None:
            lines.insert(features_index + 1, "codex_hooks = true")
        else:
            if lines and lines[-1] != "":
                lines.append("")
            lines.extend(["[features]", "codex_hooks = true"])

    result = "\n".join(lines)
    if text.endswith("\n") and not result.endswith("\n"):
        result += "\n"
    if not result.endswith("\n"):
        result += "\n"
    return result

def append_inline_hooks(text):
    text = enable_codex_hooks(text).rstrip("\n")
    block = """

[[hooks.Stop]]
matcher = ""
[[hooks.Stop.hooks]]
type = "command"
command = '"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh" stop'
timeout = 5

[[hooks.UserPromptSubmit]]
matcher = ""
[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = '"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh" user_prompt_submit'
timeout = 5
"""
    return text + block

config_text = ""
if os.path.exists(config_path):
    with open(config_path) as f:
        config_text = f.read()

if not os.path.exists(hooks_path) and has_inline_hooks(config_text):
    updated_config = append_inline_hooks(config_text)
    with open(config_path, "w") as f:
        f.write(updated_config)
    os.chmod(config_path, 0o600)
    print(f"Updated {config_path} (inline Codex hooks)")
    sys.exit(0)

settings = load_hooks(hooks_path)
merge_event(settings, "Stop")
merge_event(settings, "UserPromptSubmit")
with open(hooks_path, "w") as f:
    json.dump(settings, f, indent=2, sort_keys=True)
    f.write("\n")
os.chmod(hooks_path, 0o600)

updated_config = enable_codex_hooks(config_text)
if updated_config != config_text:
    with open(config_path, "w") as f:
        f.write(updated_config)
    os.chmod(config_path, 0o600)

print(f"Updated {hooks_path} (idempotent merge)")
PY
}

check() {
    if [ ! -f "$SETTINGS" ]; then
        echo "$SETTINGS does not exist — no Claude hooks configured."
    else
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
    fi

    if [ -f "$CODEX_HOOKS" ]; then
        echo
        echo "--- Codex hooks from $CODEX_HOOKS ---"
        CODEX_HOOKS_PATH="$CODEX_HOOKS" /usr/bin/python3 - <<'PY'
import json, os, sys
hooks_path = os.environ["CODEX_HOOKS_PATH"]
try:
    with open(hooks_path) as f:
        j = json.load(f)
except Exception as e:
    sys.stderr.write(f"warning: could not parse {hooks_path} ({e})\n")
    sys.exit(2)
print(json.dumps(j.get("hooks", {}), indent=2))
PY
    fi
}

case "${1:-}" in
    ""|--print)   copy_reporter; echo; echo "--- paste into $SETTINGS ---"; snippet ;;
    --apply)      copy_reporter || exit $?; apply || exit $?; apply_codex || true ;;
    --check)      check ;;
    --help|-h)    usage ;;
    *)            usage; exit 2 ;;
esac
