#!/bin/sh
# Reporter/cab-report.sh — legacy shim for hooks registered before the Swift reporter.
# Claude Code snapshots hook config at session start, so sessions opened before the app
# re-registered hooks keep calling this path. Hand off to the compiled cab-report next to it.
# Hard contract: ALWAYS exit 0 (HOOK-03 / D-02). Never write to stdout/stderr (Pitfall #3).
BIN="$(dirname "$0")/cab-report"
[ -x "$BIN" ] && exec "$BIN" "$@"
exit 0
