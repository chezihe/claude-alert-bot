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
#     byte-identical per repository guidance "preserve original code")
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
verify_3_01_01() {
    local id="3-01-01" name="iTermSessionID extractor + 7 unit tests"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/iTermSessionIDTests \
        > /tmp/cab-3-01-01.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-3-01-01.log"
    fi
}

verify_3_01_02() {
    local id="3-01-02" name="TerminalJumper protocol + JumpResult enum (6 cases)"
    local cases
    cases=$(grep -cE '^\s+case [a-zA-Z]' App/TerminalJumper.swift)
    [[ "$cases" == "6" ]] && _record_pass "$id" "$name" || _record_fail "$id" "$name" "expected 6 JumpResult cases, found $cases"
}

verify_3_02_01() {
    local id="3-02-01" name="Reporter envelope contains term_program (after Reporter run with TERM_PROGRAM set)"
    local hits
    hits=$(grep -c TERM_PROGRAM Reporter/cab-report.sh)
    [[ "$hits" -ge 3 ]] && _record_pass "$id" "$name" || _record_fail "$id" "$name" "expected ≥3 TERM_PROGRAM occurrences, found $hits"
}

verify_3_02_02() {
    local id="3-02-02" name="HookEvent.term_program field declared (Decodable optional)"
    grep -q "let term_program" App/HookEvent.swift && _record_pass "$id" "$name" || _record_fail "$id" "$name" "field declaration not found"
}

# ─── Wave 2 (03-03 normalize+migrate, 03-04 AppleScriptHelper extension) ──
verify_3_03_01() {
    local id="3-03-01" name="HookListener applies iTermSessionID.uuid normalization"
    grep -q 'iTermSessionID.uuid' App/HookListener.swift && _record_pass "$id" "$name" || _record_fail "$id" "$name" "normalization call not found in HookListener"
}

verify_3_03_02() {
    local id="3-03-02" name="SessionStore.load migrates : prefix + 3 regression tests"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SessionStoreTests \
        > /tmp/cab-3-03-02.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-3-03-02.log"
    fi
}

verify_3_04_01() {
    local id="3-04-01" name="AppleScriptHelper has 3-second timeout in jump+focus scripts"
    local hits
    hits=$(grep -c 'with timeout of 3 seconds' App/AppleScriptHelper.swift)
    [[ "$hits" -eq 2 ]] && _record_pass "$id" "$name" || _record_fail "$id" "$name" "expected exactly 2 occurrences (jump+focus), found $hits"
}

verify_3_04_02() {
    local id="3-04-02" name="AppleScriptHelper test branches (jump-by-uuid + testConnection + whitelist)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/AppleScriptHelperTests \
        > /tmp/cab-3-04-02.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-3-04-02.log"
    fi
}

# ─── Wave 3 (03-05 ITerm2Jumper) ──────────────────────────────────────────
verify_3_05_01() {
    local id="3-05-01" name="Pitfall #1 regression guard — NSApp.activate count == 0 (comment-stripped)"
    local hits
    hits=$(grep -v '^[[:space:]]*//' App/ITerm2Jumper.swift App/AppleScriptHelper.swift | grep -c 'NSApp\.activate' || true)
    [[ "$hits" == "0" ]] && _record_pass "$id" "$name" || _record_fail "$id" "$name" "found $hits NSApp.activate occurrences in jump path (excluding comment lines)"
}

verify_3_05_02() {
    local id="3-05-02" name="ITerm2Jumper unit tests (nil/invalid/envelope-format paths)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/ITerm2JumperTests \
        > /tmp/cab-3-05-02.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-3-05-02.log"
    fi
}

# ─── Wave 4 (03-06 PopoverRowView state machine) ──────────────────────────
verify_3_06_01() {
    local id="3-06-01" name="PopoverRowView state machine — RowState + JUMP-05 guard + onMissingComplete dispatch"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/PopoverRowStateTests \
        > /tmp/cab-3-06-01.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-3-06-01.log"
    fi
}

verify_3_06_02() {
    local id="3-06-02" name="PopoverRowView reduced-motion fallback present"
    grep -q 'accessibilityDisplayShouldReduceMotion' App/PopoverRowView.swift && _record_pass "$id" "$name" || _record_fail "$id" "$name" "no reduced-motion guard in PopoverRowView.swift"
}

# ─── Wave 5 (03-07 WidgetPopoverController, 03-08 SettingsView SET-05) ────
verify_3_07_01() {
    local id="3-07-01" name="WidgetPopoverController dispatches via TerminalJumper (D2-08 [would-jump] removed)"
    local oldHits newHits
    oldHits=$(grep -c '\[would-jump' App/WidgetPopoverController.swift || true)
    newHits=$(grep -c 'jumper.jump' App/WidgetPopoverController.swift || true)
    if [[ "$oldHits" == "0" ]] && [[ "$newHits" -ge 1 ]]; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "old [would-jump]: $oldHits (expected 0); new jumper.jump: $newHits (expected ≥1)"
    fi
}

verify_3_07_02() {
    local id="3-07-02" name="OSLog 4-prefix contract — [jumped, [jump-missed, [jump-denied, [jump-error all present in source"
    local prefixes=("\[jumped" "\[jump-missed" "\[jump-denied" "\[jump-error")
    local missing=""
    for p in "${prefixes[@]}"; do
        if ! grep -qE "$p" App/ITerm2Jumper.swift App/WidgetPopoverController.swift; then
            missing="$missing $p"
        fi
    done
    [[ -z "$missing" ]] && _record_pass "$id" "$name" || _record_fail "$id" "$name" "missing prefixes:$missing"
}

verify_3_07_03() {
    local id="3-07-03" name="WidgetPopoverController calls PermissionDeepLink on .permissionDenied"
    grep -q 'PermissionDeepLink.openAutomationPreferences' App/WidgetPopoverController.swift && _record_pass "$id" "$name" || _record_fail "$id" "$name" "ONB-03 deep-link not wired in WidgetPopoverController"
}

verify_3_08_01() {
    local id="3-08-01" name="SET-05 verbatim copy lock (T-COPY-DRIFT-01)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SettingsViewTests \
        > /tmp/cab-3-08-01.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-3-08-01.log"
    fi
}

verify_3_08_02() {
    local id="3-08-02" name="SettingsView SET-05 wiring — testConnection call + auto-deep-link on denied"
    grep -q 'AppleScriptHelper.shared.testConnection' App/SettingsView.swift && \
        grep -q 'PermissionDeepLink.openAutomationPreferences' App/SettingsView.swift && \
        _record_pass "$id" "$name" || _record_fail "$id" "$name" "missing testConnection or denied auto-deeplink wiring"
}

verify_3_08_03() {
    local id="3-08-03" name="SettingsStore lastConnectionTestAt with UserDefaults bridge"
    grep -q 'lastConnectionTestAt' App/SettingsStore.swift && \
        grep -q '"last_connection_test_at"' App/SettingsStore.swift && \
        _record_pass "$id" "$name" || _record_fail "$id" "$name" "lastConnectionTestAt or its UserDefaults key missing"
}

# ─── Wave 6 (03-09 e2e + sign-off) ────────────────────────────────────────
verify_3_09_01() {
    local id="3-09-01" name="Phase 1 regression chain (verify-phase-1.sh exit 0)"
    if bash scripts/verify-phase-1.sh > /tmp/cab-3-09-01.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "Phase 1 verifier failed — see /tmp/cab-3-09-01.log"
    fi
}

verify_3_09_02() {
    local id="3-09-02" name="Phase 2 regression chain (allow-list: 2-08-02 D3-13 + 2-11-02 V-7)"
    if bash scripts/verify-phase-2.sh > /tmp/cab-3-09-02.log 2>&1; then
        _record_pass "$id" "$name (no Phase 2 failures)"
        return
    fi
    # Phase 2 has exactly two documented expected-red rows post-Phase-3:
    #   2-08-02 — D3-13 contract change: Phase 3 03-07 deletes [would-jump session=]
    #             literal from WidgetPopoverController in favor of
    #             [jumped]/[jump-missed]/[jump-denied]/[jump-error].
    #             (Plan 03-09 referenced row 2-08-01, but the actual `[would-jump]`
    #             grep is inside verify_2_08_02 per scripts/verify-phase-2.sh — corrected.)
    #   2-11-02 — V-7 carry-over: Phase 2 cab-test UUID-per-invocation tooling
    #             artifact, deferred at Phase 2 close (02-VERIFICATION.md;
    #             STATE.md "23 PASS / 1 FAIL* / 2 SKIP").
    # Pass iff every FAIL line matches one of those two row IDs. Any other
    # FAIL = real Phase 2 regression introduced by Phase 3 → fail this row.
    local unexpected
    unexpected=$(grep -E '^\[FAIL\]|^FAIL' /tmp/cab-3-09-02.log | grep -vE '2-08-02|2-11-02' || true)
    if [[ -z "$unexpected" ]]; then
        _record_pass "$id" "$name (expected reds present, no surprises)"
    else
        _record_fail "$id" "$name" "Phase 2 had unexpected failures beyond allow-list — see /tmp/cab-3-09-02.log"
    fi
}

verify_3_09_03() {
    local id="3-09-03" name="Manual checkpoint marker — open 03-VERIFICATION.md and verify SC#1..5 by hand"
    _record_skip "$id" "$name" "Manual checkpoint required — see .planning/phases/03-click-to-iterm2/03-VERIFICATION.md"
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
# Main — call every verify_3_*_* in order, then summary
# ---------------------------------------------------------------------------
main() {
    printf "${DIM}Phase 3 validation harness${RESET}\n"
    printf "${DIM}APP_PATH=%s${RESET}\n" "$APP_PATH"
    printf "${DIM}SOCK=%s${RESET}\n" "$SOCK"
    printf "${DIM}SESSIONS_JSON=%s${RESET}\n\n" "$SESSIONS_JSON"

    # Wave 0
    verify_3_00_01

    # Wave 1 (03-01, 03-02)
    verify_3_01_01
    verify_3_01_02
    verify_3_02_01
    verify_3_02_02

    # Wave 2 (03-03, 03-04)
    verify_3_03_01
    verify_3_03_02
    verify_3_04_01
    verify_3_04_02

    # Wave 3 (03-05)
    verify_3_05_01
    verify_3_05_02

    # Wave 4 (03-06)
    verify_3_06_01
    verify_3_06_02

    # Wave 5 (03-07, 03-08)
    verify_3_07_01
    verify_3_07_02
    verify_3_07_03
    verify_3_08_01
    verify_3_08_02
    verify_3_08_03

    # Wave 6 (03-09)
    verify_3_09_01
    verify_3_09_02
    verify_3_09_03

    _summary
}

main "$@"
