#!/bin/sh
# Reporter/cab-report.sh — Claude Alert Bot Phase 1
# Triggered as Claude Code Stop, UserPromptSubmit, and Notification hooks.
# Hard contract: ALWAYS exit 0 (HOOK-03 / D-02). Never write to stdout/stderr (Pitfall #3).

set -u                                  # error on unset vars
trap 'exit 0' EXIT INT TERM HUP         # belt-and-suspenders: even on signal, exit 0

# Paths (D-04, D-10)
APP_DIR="$HOME/Library/Application Support/ClaudeAlertBot"
SOCK="$APP_DIR/sock"
LOG_DIR="$HOME/Library/Logs/ClaudeAlertBot"
LOG="$LOG_DIR/hook.log"

# Event name from $1 (callers pass "stop", "user_prompt_submit", or "notification"); default "stop"
EVENT="${1:-stop}"

# Ensure log dir (Pitfall #7)
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Capture context BEFORE consuming stdin
ITERM_SESSION_ID_VAL="${ITERM_SESSION_ID:-}"
TERM_PROGRAM_VAL="${TERM_PROGRAM:-}"
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
       TERM_PROGRAM="$TERM_PROGRAM_VAL" \
       CLAUDE_DIR="$CLAUDE_PROJECT_DIR_VAL" \
       CWD_FALLBACK="$CWD_FALLBACK" \
       TTY_VAL="$TTY_VAL" \
       PPID_VAL="$PPID_VAL" \
       /usr/bin/python3 -S -c '
import json, os, sys, time
from datetime import datetime, timezone

captured_at = datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")

raw = os.environ.get("STDIN_JSON", "")
parsed = {}
if raw.strip():
    try:
        parsed = json.loads(raw)
    except Exception:
        parsed = {"raw": raw}

env = os.environ.get
def nz(v): return v if v else None
def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)
def cap_utf8(v):
    if not isinstance(v, str):
        return None
    data = v.encode("utf-8")[:4096]
    while True:
        try:
            return data.decode("utf-8")
        except UnicodeDecodeError as e:
            data = data[:e.start]
def epoch(v):
    if is_number(v):
        return v
    if isinstance(v, str):
        try:
            text = v.replace("Z", "+00:00")
            return datetime.fromisoformat(text).timestamp()
        except Exception:
            return None
    return None
def is_codex_memory_event(envelope):
    cwd = envelope.get("cwd")
    home = env("HOME")
    if not isinstance(cwd, str) or not home:
        return False
    memories = os.path.abspath(os.path.join(home, ".codex", "memories"))
    cwd = os.path.abspath(os.path.expanduser(cwd))
    return envelope.get("transcript_path") is None and (cwd == memories or cwd.startswith(memories + os.sep))
def transcript_tail_lines(path, max_bytes=2 * 1024 * 1024):
    # Long sessions grow the transcript to tens of MB and the stop hook re-reads it on a
    # retry loop — cap IO to the tail. Both consumers want the LATEST matching line,
    # which lives at the end of the JSONL file.
    if not isinstance(path, str) or not path:
        return []
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            start = max(0, size - max_bytes)
            f.seek(start)
            data = f.read()
        if start > 0:
            cut = data.find(b"\n")
            data = data[cut + 1:] if cut != -1 else b""
        return data.decode("utf-8", "replace").splitlines()
    except Exception:
        return []
def transcript_started_at(path):
    latest = None
    for line in transcript_tail_lines(path):
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("type") == "user":
            ts = epoch(obj.get("timestamp"))
            if ts is not None:
                latest = ts
    return latest
def content_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict) and isinstance(item.get("text"), str):
                parts.append(item.get("text"))
        return "\n".join(parts) if parts else None
    return None
def payload_text(payload):
    if not isinstance(payload, dict):
        return None
    for key in ("message", "output", "result", "summary", "text"):
        if isinstance(payload.get(key), str):
            return payload.get(key)
    return content_text(payload.get("content"))
def transcript_last_output(path):
    latest = None
    for line in transcript_tail_lines(path):
        try:
            obj = json.loads(line)
        except Exception:
            continue
        payload = obj.get("payload") if isinstance(obj.get("payload"), dict) else {}
        message = obj.get("message") if isinstance(obj.get("message"), dict) else {}
        candidate = None
        if message.get("role") == "assistant":
            candidate = content_text(message.get("content"))
        elif obj.get("type") == "assistant":
            candidate = payload_text(payload) or content_text(obj.get("content"))
        elif payload.get("type") == "message":
            candidate = payload_text(payload)
        elif obj.get("type") == "event_msg" and payload.get("type") == "agent_message":
            candidate = payload.get("message")
        if isinstance(candidate, str) and candidate.strip():
            latest = candidate
    return latest
def wait_transcript_last_output(path):
    for attempt in range(8):
        output = transcript_last_output(path)
        if isinstance(output, str) and output.strip():
            return output
        if attempt < 7:
            time.sleep(0.1)
    return None

envelope = {
    "schema_version": 1,
    "event": env("EVENT") or "stop",
    "session_id": parsed.get("session_id"),
    "transcript_path": parsed.get("transcript_path"),
    "cwd": parsed.get("cwd") or nz(env("CWD_FALLBACK")),
    "iterm_session_id": nz(env("ITERM")),
    "term_program": nz(env("TERM_PROGRAM")),
    "tty": nz(env("TTY_VAL")),
    "ppid": int(env("PPID_VAL", "0")) or None,
    "claude_project_dir": nz(env("CLAUDE_DIR")),
    "ts": captured_at,
}
tool_use = parsed.get("tool_use") if isinstance(parsed.get("tool_use"), dict) else {}
exit_code = parsed.get("exit_code")
if exit_code is None:
    exit_code = tool_use.get("exit_code")
if isinstance(exit_code, int) and not isinstance(exit_code, bool):
    envelope["exit_code"] = exit_code
started_at = epoch(parsed.get("started_at"))
if started_at is None:
    started_at = epoch(parsed.get("prompt_started_at"))
if started_at is None:
    started_at = transcript_started_at(parsed.get("transcript_path"))
if started_at is not None:
    envelope["started_at"] = started_at
kind = parsed.get("kind")
if not isinstance(kind, str) and env("EVENT") == "notification":
    kind = "waiting"
if isinstance(kind, str):
    envelope["kind"] = kind
event = env("EVENT")
last_output = None
if event == "stop":
    transcript_path = parsed.get("transcript_path")
    if isinstance(transcript_path, str) and transcript_path:
        last_output = wait_transcript_last_output(transcript_path)
    if not isinstance(last_output, str):
        last_output = parsed.get("last_output")
elif event == "notification":
    last_output = parsed.get("message")
    if not isinstance(last_output, str):
        last_output = parsed.get("last_output")
else:
    last_output = parsed.get("last_output")
last_output = cap_utf8(last_output)
if last_output is not None:
    envelope["last_output"] = last_output
if is_codex_memory_event(envelope):
    sys.exit(0)
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
