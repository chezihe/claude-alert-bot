#!/bin/bash
# verify-phase-2.sh — Single-shot validation harness for Phase 2 (Alert Loop).
#
# Skeleton modeled verbatim on scripts/verify-phase-1.sh (header + record helpers
# + _ensure_app_running + main aggregator). Wave 0 ships rows 2-00-01 (test
# target compiles + sentinel passes) and 2-00-02 (cab-test argv → ingress
# event=user_prompt_submit). Every other wave's rows are reserved as comment
# placeholders below; downstream plan executors uncomment + implement.
#
# Sources:
#   - 02-VALIDATION.md (per-row commands once written)
#   - 02-PATTERNS.md §verify-phase-2.sh (verbatim copy from Phase 1)
#   - 02-CONTEXT.md D2-31, D2-37 (OSLog categories)

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

# Phase 2 additions
SESSIONS_JSON="$HOME/Library/Application Support/ClaudeAlertBot/sessions.json"
LOG_CATEGORIES_PHASE2="registry|notification|widget|settings|applescript"

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
# Helper: bring the .app up cold so the IPC tier (2-*-* HookListener-dependent
# rows) sees a live listener. Idempotent — verbatim from verify-phase-1.sh.
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
# Wave 0 (02-00) — test scaffold rows
# ---------------------------------------------------------------------------

# 2-00-01: ClaudeAlertBotTests target builds and sentinel test passes
verify_2_00_01() {
    local id="2-00-01" name="ClaudeAlertBotTests target builds and sentinel test passes"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/ClaudeAlertBotTests/test_targetCompilesAndLinks \
        > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

# 2-00-02: cab-test --event=user_prompt_submit fires user_prompt_submit envelope
verify_2_00_02() {
    local id="2-00-02" name="cab-test --event=user_prompt_submit fires user_prompt_submit envelope"
    local cab_test="${APP_PATH}/Contents/MacOS/cab-test"
    if [[ ! -x "$cab_test" ]]; then
        _record_skip "$id" "$name" "cab-test helper missing at $cab_test (build needed)"
        return
    fi
    # Detect Phase-1-era cab-test (no --event= argv). The Phase 2 binary
    # contains the literal "--event=" prefix string; the Phase 1 one does not.
    # Skip cleanly so a stale build doesn't masquerade as a real regression.
    if ! strings "$cab_test" 2>/dev/null | grep -q -- '--event='; then
        _record_skip "$id" "$name" "cab-test predates --event= argv (rebuild needed)"
        return
    fi
    if ! _ensure_app_running; then
        _record_skip "$id" "$name" "App not running ($APP_PATH not launchable)"
        return
    fi
    "$cab_test" --event=user_prompt_submit > /dev/null 2>&1 || true
    sleep 1
    if log show --last 5s --predicate "subsystem == \"$LOG_SUBSYS\" AND category == \"ingress\"" 2>/dev/null \
        | grep -q 'event=user_prompt_submit'; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "no ingress line with event=user_prompt_submit in last 5s"
    fi
}

# ---------------------------------------------------------------------------
# Reserved placeholders for downstream waves. Executors of subsequent plans
# uncomment + implement these as their `<verify><automated>` rows ship.
# ---------------------------------------------------------------------------
# ─── Wave 1 (02-03 domain contracts) ──────────────────────────────────────
# verify_2_03_01 — SessionRecord Codable round-trip (downstream)
# ─── Wave 2 (02-04 SessionRegistry, 02-05 AppleScriptHelper) ─────────────
# verify_2_04_01 — start→stop elapsed seconds (downstream)
# verify_2_04_02 — sessions.json atomic save (downstream)
# verify_2_04_03 — THR-01 5s task → no widget; 31s task → widget (downstream)
# verify_2_04_04 — THR-02 orphan stop → alert with `?` (downstream)
# verify_2_05_01 — AppleScriptHelper compile + denial classification (downstream)
# ─── Wave 3 (02-06 NotificationOrchestrator+SoundPlayer, 02-07 widget) ───
# verify_2_06_01 — sound dedupe (AUD-01, downstream)
# verify_2_06_02 — sound toggle off → no playback (AUD-02, downstream)
# verify_2_07_01 — NSPanel collectionBehavior 3-flag (downstream)
# ─── Wave 4 (02-08 popover, 02-09 observers+GC) ──────────────────────────
# verify_2_08_01 — popover row click dispatches clearOne (downstream)
# verify_2_09_01 — 6h GC after wake (downstream)
# ─── Wave 5 (02-10 SettingsView) ─────────────────────────────────────────
# verify_2_10_01 — @AppStorage persists across restart (downstream)
# verify_2_10_02 — Test notification injection (SET-04, downstream)
# ─── Wave 6 (02-11 AppDelegate integration) ──────────────────────────────
# verify_2_11_01 — boot order (Pitfall #11): listener does not bind before registry restore (downstream)
# verify_2_11_02 — sessions.json restore on launch (SC#5, downstream)
# verify_2_11_03 — full e2e: cab-test user_prompt_submit + 31s + stop → widget OSLog (SC#1, downstream)

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
# Main — call every verify_2_*_* in order, then summary
# ---------------------------------------------------------------------------
main() {
    printf "${DIM}Phase 2 validation harness (Wave 0 skeleton)${RESET}\n"
    printf "${DIM}APP_PATH=%s${RESET}\n" "$APP_PATH"
    printf "${DIM}SOCK=%s${RESET}\n" "$SOCK"
    printf "${DIM}SESSIONS_JSON=%s${RESET}\n\n" "$SESSIONS_JSON"

    # Wave 0
    verify_2_00_01
    verify_2_00_02

    # Downstream waves' rows are inserted here as plans 02-03..02-11 ship.

    _summary
}

main "$@"
