#!/bin/bash
# verify-phase-3.sh — Single-shot validation harness for Phase 3 (Click-to-iTerm2).
#
# Skeleton modeled verbatim on scripts/verify-phase-2.sh (Wave 0 pattern):
#   - colors block, constants block, aggregation counters
#   - _record_pass / _record_fail / _record_skip / _record_manual / _summary
#   - _ensure_app_running helper
# Wave 0 (this plan, 03-00) ships smoke row 3-00-01 + downstream-row placeholders
# for plans 03-01..03-09. Each downstream plan grafts in its own verify_3_NN_NN
# functions in the slots reserved below.
#
# Sources:
#   - scripts/verify-phase-2.sh (lines 1-100 — header + colors + helpers; copied
#     byte-identical per CLAUDE.md "preserve original code")
#   - 03-CONTEXT.md D3-01..D3-25 (decisions defining row coverage)
#   - 03-PATTERNS.md (verifier patterns)

set -uo pipefail
# NOTE: deliberately NO `-e` — we want every check to run even when an earlier
# one fails, then aggregate.

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    DIM=''
    RESET=''
fi

# ---------------------------------------------------------------------------
# Constants — overridable via env for CI / alternate build dirs
# ---------------------------------------------------------------------------
APP_PATH="${APP_PATH:-build/export/ClaudeAlertBot.app}"
SOCK="$HOME/Library/Application Support/ClaudeAlertBot/sock"
LOG_FILE="$HOME/Library/Logs/ClaudeAlertBot/hook.log"
LOG_SUBSYS="com.claudealert.bot.hook"

# ─── Phase 3 constants ─────────────────────────────────────────────────────
SESSIONS_JSON="$HOME/Library/Application Support/ClaudeAlertBot/sessions.json"
LOG_CATEGORIES_PHASE3="widget|applescript|registry|listener"
# Phase 3 OSLog signature contract (D3-13): exactly 4 prefixes after Phase 3 ships.
JUMP_LOG_PREFIXES='\[jumped|\[jump-missed|\[jump-denied|\[jump-error'

# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
SKIP=0
RESULTS=()

_record_pass() {
    local id="$1" name="$2"
    PASS=$((PASS + 1))
    RESULTS+=("PASS|$id|$name|")
    printf "${GREEN}[PASS]${RESET} %s: %s\n" "$id" "$name"
}

_record_fail() {
    local id="$1" name="$2" reason="$3"
    FAIL=$((FAIL + 1))
    RESULTS+=("FAIL|$id|$name|$reason")
    printf "${RED}[FAIL]${RESET} %s: %s${DIM} — %s${RESET}\n" "$id" "$name" "$reason"
}

_record_skip() {
    local id="$1" name="$2" reason="$3"
    SKIP=$((SKIP + 1))
    RESULTS+=("SKIP|$id|$name|$reason")
    printf "${YELLOW}[SKIP]${RESET} %s: %s${DIM} — %s${RESET}\n" "$id" "$name" "$reason"
}

_record_manual() {
    local id="$1" name="$2" instructions="$3"
    RESULTS+=("MANUAL|$id|$name|$instructions")
    printf "${YELLOW}[MANUAL]${RESET} %s: %s\n${DIM}        %s${RESET}\n" "$id" "$name" "$instructions"
}

# ---------------------------------------------------------------------------
# Helper: bring the .app up cold so the IPC tier (3-*-* HookListener-dependent
# rows) sees a live listener. Idempotent — verbatim from verify-phase-2.sh.
# ---------------------------------------------------------------------------
_ensure_app_running() {
    if pgrep -f 'ClaudeAlertBot.app/Contents/MacOS/ClaudeAlertBot' >/dev/null 2>&1; then
        return 0
    fi
    if [[ ! -d "$APP_PATH" ]]; then
        return 1
    fi
    open "$APP_PATH" >/dev/null 2>&1
    sleep 2
}

# ---------------------------------------------------------------------------
# Wave 0 (03-00) — test scaffold rows
# ---------------------------------------------------------------------------

# 3-00-01: ClaudeAlertBotTests target builds (Phase 3 fixtures compile)
verify_3_00_01() {
    local id="3-00-01" name="ClaudeAlertBotTests target builds (Phase 3 fixtures compile)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/ClaudeAlertBotTests/test_targetCompilesAndLinks \
        > /tmp/cab-phase3-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-phase3-test-out.log"
    fi
}

# ---------------------------------------------------------------------------
# Downstream-row placeholders — executors of 03-01..03-09 graft their
# verify_3_NN_NN functions into the matching wave block below and add
# the matching call into main().
# ---------------------------------------------------------------------------

# ─── Wave 1 (03-01 contracts, 03-02 envelope) ─────────────────────────────
# verify_3_01_01 — iTermSessionID.uuid(fromRaw:) strips wXtYpZ: prefix (downstream)
# verify_3_01_02 — iTermSessionID.isValid(_:) accepts only Foundation-parseable UUIDs (downstream)
# verify_3_01_03 — TerminalJumper protocol present + JumpResult enum 6 cases (grep gate, downstream)
# verify_3_02_01 — Reporter envelope contains term_program when TERM_PROGRAM env set (downstream)
# verify_3_02_02 — HookEvent decodes envelope without term_program field (backward compat, downstream)

# ─── Wave 2 (03-03 normalize+migrate, 03-04 AppleScriptHelper extension) ──
# verify_3_03_01 — HookListener decode applies iTermSessionID.uuid (downstream)
# verify_3_03_02 — SessionStore.load migrates : prefix in-memory (downstream)
# verify_3_04_01 — AppleScriptHelper sources contain `with timeout of 3 seconds` (jump+focus, downstream)
# verify_3_04_02 — testConnection branch matrix unit (downstream)

# ─── Wave 3 (03-05 ITerm2Jumper) ──────────────────────────────────────────
# verify_3_05_01 — Pitfall #1: grep -v //. | grep -c NSApp.activate == 0 (downstream)
# verify_3_05_02 — ITerm2Jumper maps ScriptResult → JumpResult correctly (unit, downstream)

# ─── Wave 4 (03-06 PopoverRowView state machine) ──────────────────────────
# verify_3_06_01 — RowState transition normal→jumping→missing→cleared (downstream)
# verify_3_06_02 — Re-click during .jumping is a no-op (debounce, downstream)

# ─── Wave 5 (03-07 WidgetPopoverController, 03-08 SettingsView SET-05) ────
# verify_3_07_01 — onRowClick dispatches jumper.jump and emits [jumped (downstream, manual e2e)
# verify_3_07_02 — onRowClick missing path emits [jump-missed and triggers row collapse (downstream)
# verify_3_07_03 — onRowClick denied emits [jump-denied + opens deep-link (downstream)
# verify_3_07_04 — OSLog 4-prefix contract grep gate (downstream)
# verify_3_08_01 — SET-05 verbatim copy assertion (Korean button + EN status labels) (downstream)
# verify_3_08_02 — SET-05 button → testConnection branch dispatch (downstream)
# verify_3_08_03 — lastConnectionTestAt persists across @Published reload (downstream)

# ─── Wave 6 (03-09 e2e + sign-off) ────────────────────────────────────────
# verify_3_09_01 — Phase 1 regression chain (verify-phase-1.sh exit 0) (downstream)
# verify_3_09_02 — Phase 2 regression chain (verify-phase-2.sh — [would-jump row expected red post-Phase 3, doc'd) (downstream)
# verify_3_09_03 — Manual checkpoint marker for SC#1..5 (downstream — opens 03-VERIFICATION.md)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
_summary() {
    echo
    printf "Results: ${GREEN}%d pass${RESET}, ${RED}%d fail${RESET}" "$PASS" "$FAIL"
    if [[ "$SKIP" -gt 0 ]]; then
        printf ", ${YELLOW}%d skip${RESET}" "$SKIP"
    fi
    printf "\n"

    if [[ "$FAIL" -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

# ---------------------------------------------------------------------------
# Main — call every verify_3_*_* in order, then summary
# ---------------------------------------------------------------------------
main() {
    printf "${DIM}Phase 3 validation harness${RESET}\n"
    printf "${DIM}APP_PATH=%s${RESET}\n" "$APP_PATH"
    printf "${DIM}SOCK=%s${RESET}\n" "$SOCK"
    printf "${DIM}SESSIONS_JSON=%s${RESET}\n\n" "$SESSIONS_JSON"

    # Wave 0
    verify_3_00_01

    # Wave 1 — downstream (03-01, 03-02)
    # verify_3_01_01
    # verify_3_01_02
    # verify_3_01_03
    # verify_3_02_01
    # verify_3_02_02

    # Wave 2 — downstream (03-03, 03-04)
    # verify_3_03_01
    # verify_3_03_02
    # verify_3_04_01
    # verify_3_04_02

    # Wave 3 — downstream (03-05)
    # verify_3_05_01
    # verify_3_05_02

    # Wave 4 — downstream (03-06)
    # verify_3_06_01
    # verify_3_06_02

    # Wave 5 — downstream (03-07, 03-08)
    # verify_3_07_01
    # verify_3_07_02
    # verify_3_07_03
    # verify_3_07_04
    # verify_3_08_01
    # verify_3_08_02
    # verify_3_08_03

    # Wave 6 — downstream (03-09)
    # verify_3_09_01
    # verify_3_09_02
    # verify_3_09_03

    _summary
}

main "$@"
