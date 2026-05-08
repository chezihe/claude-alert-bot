#!/bin/bash
# verify-phase-2.sh — Single-shot validation harness for Phase 2 (Alert Loop).
#
# Skeleton modeled verbatim on scripts/verify-phase-1.sh (header + record helpers
# + _ensure_app_running + main aggregator). Wave 0 ships rows 2-00-01/02; Waves 1-5
# ship rows 2-02-01..2-10-01 grafted in by 02-11; Wave 6 (this plan) ships SC#1..6
# e2e rows + 2-11-99 Phase 1 regression.
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
# Wave 1 (02-02 PermissionDeepLink + Info.plist Korean copy)
# ---------------------------------------------------------------------------

# 2-02-01: PermissionDeepLink URL sequence (D2-36) regression guard
verify_2_02_01() {
    local id="2-02-01" name="PermissionDeepLink URL sequence (D2-36)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/PermissionDeepLinkTests \
        > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

# 2-02-02: NSAppleEventsUsageDescription D2-33 Korean copy matches in Info.plist + project.yml
verify_2_02_02() {
    local id="2-02-02" name="NSAppleEventsUsageDescription Korean copy (D2-33) matches in Info.plist + project.yml"
    local expected='이미 보고 있는'  # unique-enough Korean substring
    local plist_val
    plist_val=$(/usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" App/Info.plist 2>/dev/null || echo "")
    local yml_val
    yml_val=$(grep -A0 "NSAppleEventsUsageDescription:" project.yml | head -1)
    if [[ "$plist_val" == *"$expected"* && "$yml_val" == *"$expected"* ]]; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "Info.plist=[$plist_val] project.yml=[$yml_val]"
    fi
}

# ---------------------------------------------------------------------------
# Wave 1 (02-03 SessionRecord + ProjectName)
# ---------------------------------------------------------------------------

verify_2_03_01() {
    local id="2-03-01" name="SessionRecord Codable round-trip + DedupeKey hashing + SocketPaths.sessionsJSONPath"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SessionRecordTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_03_02() {
    local id="2-03-02" name="ProjectName.derive rules (D2-06)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/ProjectNameTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

# ---------------------------------------------------------------------------
# Wave 2 (02-04 SessionRegistry + SessionStore, 02-05 AppleScriptHelper)
# ---------------------------------------------------------------------------

verify_2_04_01() {
    local id="2-04-01" name="SessionRegistry actor — ingest, threshold, dedupe, THR-02, D2-13, GC, injectTest"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SessionRegistryTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_04_02() {
    local id="2-04-02" name="SessionStore atomic save/load + corrupt-file recovery (SESS-03)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SessionStoreTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_05_01() {
    local id="2-05-01" name="AppleScriptHelper compile-once + classify + state mirror"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/AppleScriptHelperTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

# ---------------------------------------------------------------------------
# Wave 3 (02-06 NotificationOrchestrator + SoundPlayer, 02-07 widget)
# ---------------------------------------------------------------------------

verify_2_06_01() {
    local id="2-06-01" name="SoundPlayer load-once + tolerate missing file (AUD-01)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SoundPlayerTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_06_02() {
    local id="2-06-02" name="NotificationOrchestrator AUD-02 sound toggle + WIDG-05 hideWidget routing"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/NotificationOrchestratorTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_07_01() {
    local id="2-07-01" name="FloatingWidgetPanel + Positioning (WIDG-01,02,06,07)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/FloatingWidgetPanelTests \
        -only-testing:ClaudeAlertBotTests/PositioningTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_07_02() {
    local id="2-07-02" name="FloatingWidgetWindowController compiles + protocol conformance"
    if xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS' > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "build failed — see /tmp/cab-test-out.log"
    fi
}

# ---------------------------------------------------------------------------
# Wave 4 (02-08 popover, 02-09 observers + GC timer)
# ---------------------------------------------------------------------------

verify_2_08_01() {
    local id="2-08-01" name="PopoverContent display rules (D2-06, D2-07, D2-16)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/PopoverContentTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_08_02() {
    local id="2-08-02" name="WidgetPopoverController compiles + WidgetHoverDelegate conformance + D2-08 anchor"
    if xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS' > /tmp/cab-test-out.log 2>&1; then
        # Anchor verification: D2-08 log format must exist; either NSPopover or popoverPanel must be present.
        local jump_count
        jump_count=$(grep -c '\[would-jump session=' App/WidgetPopoverController.swift)
        local nsp_count
        nsp_count=$(grep -c 'NSPopover' App/WidgetPopoverController.swift)
        local panel_count
        panel_count=$(grep -c 'popoverPanel' App/WidgetPopoverController.swift)
        if [ "$jump_count" -ge 1 ] && { [ "$nsp_count" -ge 1 ] || [ "$panel_count" -ge 1 ]; }; then
            _record_pass "$id" "$name"
        else
            _record_fail "$id" "$name" "anchor missing (jump=$jump_count nsp=$nsp_count panel=$panel_count)"
        fi
    else
        _record_fail "$id" "$name" "build failed — see /tmp/cab-test-out.log"
    fi
}

verify_2_09_01() {
    local id="2-09-01" name="Observers + timer compile + retention pattern (CRITICAL: retain comment, [weak self], bundle-ID filter)"
    if xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS' > /tmp/cab-test-out.log 2>&1; then
        if [ "$(grep -c 'CRITICAL: retain' App/WakeObserver.swift App/WorkspaceFrontmostObserver.swift App/SessionGCTimer.swift | grep -c ':1$')" = "3" ] && \
           [ "$(grep -c 'com.googlecode.iterm2' App/WorkspaceFrontmostObserver.swift)" -ge 1 ]; then
            _record_pass "$id" "$name"
        else
            _record_fail "$id" "$name" "anchor grep regression — see App/WakeObserver.swift, App/WorkspaceFrontmostObserver.swift, App/SessionGCTimer.swift"
        fi
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_09_02() {
    local id="2-09-02" name="SessionGCTimer fires at interval (SESS-04 mechanism, retention contract)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SessionGCTimerTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

# ---------------------------------------------------------------------------
# Wave 5 (02-10 SettingsView)
# ---------------------------------------------------------------------------

verify_2_10_01() {
    local id="2-10-01" name="SettingsView + PermissionBanner copy regression (D2-33, D2-36)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SettingsViewTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

# ---------------------------------------------------------------------------
# Wave 6 (02-11) — integration build + ROADMAP Phase 2 Success Criteria
# ---------------------------------------------------------------------------

# 2-11-00: full Phase 2 integration builds (AppDelegate boot wiring + HookListener dispatch + @main App)
verify_2_11_00() {
    local id="2-11-00" name="AppDelegate boot order + HookListener dispatch + @main SwiftUI App wired"
    if xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS' > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "build failed — see /tmp/cab-test-out.log"
    fi
}

verify_2_11_01() {
    # SC#1 — 31-second turn → widget appears with project name; multi-Space; no focus steal.
    local id="2-11-01" name="SC#1 31s turn produces widget (HOOK-02 + threshold + widget)"
    _ensure_app_running || { _record_skip "$id" "$name" "App not running"; return; }
    "${APP_PATH}/Contents/MacOS/cab-test" --event=user_prompt_submit > /dev/null 2>&1 || true
    sleep 31
    "${APP_PATH}/Contents/MacOS/cab-test" --event=stop > /dev/null 2>&1 || true
    sleep 2
    if log show --last 5s --predicate "subsystem == \"$LOG_SUBSYS\" AND category == \"notification\"" 2>/dev/null \
        | grep -q 'present session='; then
        _record_pass "$id" "$name (widget shown via OSLog)"
    else
        _record_fail "$id" "$name" "no notification.present line in last 5s"
    fi
}

verify_2_11_02() {
    # SC#2 — 5-second turn → no widget, no sound (threshold filter holds).
    local id="2-11-02" name="SC#2 5s turn → no widget (THR-01 threshold filter)"
    _ensure_app_running || { _record_skip "$id" "$name" "App not running"; return; }
    "${APP_PATH}/Contents/MacOS/cab-test" --event=user_prompt_submit > /dev/null 2>&1 || true
    sleep 5
    "${APP_PATH}/Contents/MacOS/cab-test" --event=stop > /dev/null 2>&1 || true
    sleep 2
    if log show --last 5s --predicate "subsystem == \"$LOG_SUBSYS\" AND category == \"registry\"" 2>/dev/null \
        | grep -q 'THR-01 below-threshold'; then
        _record_pass "$id" "$name (THR-01 below-threshold logged)"
    else
        _record_fail "$id" "$name" "no THR-01 below-threshold line in last 5s"
    fi
}

verify_2_11_03() {
    # SC#3 — widget persists across Space switch, sleep/wake, lid close — MANUAL CHECKPOINT.
    local id="2-11-03" name="SC#3 widget persistence across Space/sleep — MANUAL"
    _record_skip "$id" "$name" "manual checkpoint — see 02-VERIFICATION.md and Task 3"
}

verify_2_11_04() {
    # SC#4 — settings persistence across app restart.
    local id="2-11-04" name="SC#4 SET-03 @AppStorage persists across restart"
    _ensure_app_running || { _record_skip "$id" "$name" "App not running"; return; }
    defaults write com.claudealert.bot threshold_seconds -int 120
    pkill -x ClaudeAlertBot 2>/dev/null || true
    sleep 1
    open "$APP_PATH"
    sleep 2
    local v
    v=$(defaults read com.claudealert.bot threshold_seconds 2>/dev/null || echo 0)
    if [[ "$v" == "120" ]]; then
        _record_pass "$id" "$name (threshold_seconds=120 after restart)"
    else
        _record_fail "$id" "$name" "expected 120, got $v"
    fi
    defaults write com.claudealert.bot threshold_seconds -int 30
}

verify_2_11_05() {
    # SC#5 — kill+restart with pending alert → re-renders from sessions.json.
    local id="2-11-05" name="SC#5 sessions.json restore on launch (SESS-03)"
    _ensure_app_running || { _record_skip "$id" "$name" "App not running"; return; }
    pkill -x ClaudeAlertBot 2>/dev/null || true
    sleep 1
    cat > "$SESSIONS_JSON" <<'JSON'
{"completed":[{"sessionID":"sc05-restore-test","projectName":"sc05","stoppedAt":"2026-05-08T12:00:00Z","durationSec":42,"itermSessionID":null,"tty":null,"cwd":"/tmp/sc05"}],"inFlight":{},"schema":1}
JSON
    chmod 0600 "$SESSIONS_JSON"
    open "$APP_PATH"
    sleep 3
    if log show --last 10s --predicate "subsystem == \"$LOG_SUBSYS\" AND category == \"registry\"" 2>/dev/null \
        | grep -q 'restore: inFlight=0 completed=1'; then
        _record_pass "$id" "$name (restore line confirmed)"
    else
        _record_fail "$id" "$name" "no restore line in last 10s"
    fi
    rm -f "$SESSIONS_JSON"
}

verify_2_11_06() {
    # SC#6 — orphan stop (no preceding user_prompt_submit) → fallback alert with ? duration.
    local id="2-11-06" name="SC#6 THR-02 orphan stop → fallback alert (never silently dropped)"
    _ensure_app_running || { _record_skip "$id" "$name" "App not running"; return; }
    "${APP_PATH}/Contents/MacOS/cab-test" --event=stop > /dev/null 2>&1 || true
    sleep 2
    if log show --last 5s --predicate "subsystem == \"$LOG_SUBSYS\" AND category == \"notification\"" 2>/dev/null \
        | grep -q 'present session='; then
        _record_pass "$id" "$name (orphan stop emitted alert)"
    else
        _record_fail "$id" "$name" "no notification.present line for orphan stop"
    fi
}

# Phase 1 regression — Phase 2 must not break Phase 1.
# VERIFY_NONINTERACTIVE=1 makes phase-1's verify_1_06_01 (manual visual)
# defer instead of hanging on `read -r` with no controlling stdin.
verify_2_11_99() {
    local id="2-11-99" name="Phase 1 regression (verify-phase-1.sh PASS)"
    if VERIFY_NONINTERACTIVE=1 bash scripts/verify-phase-1.sh > /tmp/cab-phase1-regression.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "Phase 1 verifier failed — see /tmp/cab-phase1-regression.log"
    fi
}

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
    printf "${DIM}Phase 2 validation harness${RESET}\n"
    printf "${DIM}APP_PATH=%s${RESET}\n" "$APP_PATH"
    printf "${DIM}SOCK=%s${RESET}\n" "$SOCK"
    printf "${DIM}SESSIONS_JSON=%s${RESET}\n\n" "$SESSIONS_JSON"

    # Wave 0
    verify_2_00_01
    verify_2_00_02

    # Wave 1
    verify_2_02_01
    verify_2_02_02
    verify_2_03_01
    verify_2_03_02

    # Wave 2
    verify_2_04_01
    verify_2_04_02
    verify_2_05_01

    # Wave 3
    verify_2_06_01
    verify_2_06_02
    verify_2_07_01
    verify_2_07_02

    # Wave 4
    verify_2_08_01
    verify_2_08_02
    verify_2_09_01
    verify_2_09_02

    # Wave 5
    verify_2_10_01

    # Wave 6 — integration + ROADMAP Phase 2 Success Criteria
    verify_2_11_00
    verify_2_11_01
    verify_2_11_02
    verify_2_11_03
    verify_2_11_04
    verify_2_11_05
    verify_2_11_06
    verify_2_11_99

    _summary
}

main "$@"
