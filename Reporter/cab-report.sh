#!/bin/sh
# Reporter/cab-report.sh — Claude Alert Bot Phase 1
# Triggered as Claude Code Stop hook (and UserPromptSubmit hook in Phase 2).
# Hard contract: ALWAYS exit 0 (HOOK-03 / D-02). Never write to stdout/stderr (Pitfall #3).

set -u                                  # error on unset vars
trap 'exit 0' EXIT INT TERM HUP         # belt-and-suspenders: even on signal, exit 0

# Paths (D-04, D-10)
APP_DIR="$HOME/Library/Application Support/ClaudeAlertBot"
SOCK="$APP_DIR/sock"
LOG_DIR="$HOME/Library/Logs/ClaudeAlertBot"
LOG="$LOG_DIR/hook.log"

# Event name from $1 (callers pass "stop" or "user_prompt_submit"); default "stop"
EVENT="${1:-stop}"

# Ensure log dir (Pitfall #7)
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Capture context BEFORE consuming stdin
ITERM_SESSION_ID_VAL="${ITERM_SESSION_ID:-}"
CLAUDE_PROJECT_DIR_VAL="${CLAUDE_PROJECT_DIR:-}"
CWD_FALLBACK="$PWD"
PPID_VAL="$PPID"
TS=$(/bin/date -u "+%Y-%m-%dT%H:%M:%SZ")
TTY_VAL=$(/usr/bin/tty 2>/dev/null) || TTY_VAL=""
case "$TTY_VAL" in /dev/*) ;; *) TTY_VAL="" ;; esac

# Read Claude Code hook stdin JSON
STDIN_JSON=$(cat 2>/dev/null) || STDIN_JSON=""

# Build D-08 envelope via python3 with env-var injection (the only safe escape strategy — Pitfall #3)
JSON=$(STDIN_JSON="$STDIN_JSON" \
       EVENT="$EVENT" \
       ITERM="$ITERM_SESSION_ID_VAL" \
       CLAUDE_DIR="$CLAUDE_PROJECT_DIR_VAL" \
       CWD_FALLBACK="$CWD_FALLBACK" \
       TTY_VAL="$TTY_VAL" \
       TS="$TS" \
       PPID_VAL="$PPID_VAL" \
       /usr/bin/python3 -S -c '
import json, os, sys

raw = os.environ.get("STDIN_JSON", "")
parsed = {}
if raw.strip():
    try:
        parsed = json.loads(raw)
    except Exception:
        parsed = {"raw": raw}

env = os.environ.get
def nz(v): return v if v else None

envelope = {
    "schema_version": 1,
    "event": env("EVENT") or "stop",
    "session_id": parsed.get("session_id"),
    "transcript_path": parsed.get("transcript_path"),
    "cwd": parsed.get("cwd") or nz(env("CWD_FALLBACK")),
    "iterm_session_id": nz(env("ITERM")),
    "tty": nz(env("TTY_VAL")),
    "ppid": int(env("PPID_VAL", "0")) or None,
    "claude_project_dir": nz(env("CLAUDE_DIR")),
    "ts": env("TS"),
}
print(json.dumps(envelope, ensure_ascii=False))
' 2>/dev/null) || JSON=""

# Debug log FIRST (HOOK-06): record envelope + ppid chain BEFORE network
{
    printf '{"ts":"%s","entry":"hook_fire","envelope":%s,"ppid_chain":"%s","cwd":"%s"}\n' \
        "$TS" \
        "${JSON:-null}" \
        "$(/bin/ps -o pid=,ppid=,comm= -p "$PPID_VAL" 2>/dev/null | /usr/bin/head -1 | /usr/bin/tr -d '\n')" \
        "$CWD_FALLBACK"
} >> "$LOG" 2>/dev/null || true

# Forward to App (HOOK-01). Silently no-op if socket missing (HOOK-05).
if [ -n "$JSON" ] && [ -S "$SOCK" ]; then
    printf '%s\n' "$JSON" | /usr/bin/nc -U -w 1 "$SOCK" >/dev/null 2>&1 || true
fi

exit 0
