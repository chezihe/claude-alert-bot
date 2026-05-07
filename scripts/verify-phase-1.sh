#!/bin/bash
# verify-phase-1.sh — Single-shot validation harness for Phase 1 (Foundation).
#
# Mirrors `.planning/phases/01-foundation/01-VALIDATION.md` Per-Task Verification
# Map. Every row (1-00-01 through 1-07-01) maps to a `verify_X_YY_ZZ` function
# below. Run with no args for the full suite (~10–20s). Run with `--quick` for a
# fast post-task-commit sampling subset (~3–5s).
#
# Wave 0 reality: when this script is first introduced, most checks will FAIL —
# the artifacts they test do not exist yet. That is expected. The script itself
# must run to a "Results: N pass, M fail" summary line without bash errors.
#
# Sources:
#   - 01-VALIDATION.md  (verbatim commands)
#   - 01-CONTEXT.md     (D-07 OSLog subsystem, D-10 socket path)
#   - 01-RESEARCH.md    (Validation Architecture)

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
# Verify functions — 14 rows, one per VALIDATION map entry
# Each function is callable independently. Wave 0 deps (build/launch) are
# skipped automatically in --quick mode.
# ---------------------------------------------------------------------------

# 1-00-01: Build pipeline produces .app (Wave 3 dep)
verify_1_00_01() {
    local id="1-00-01" name="Build pipeline works locally (build.sh → .app)"
    if [[ ! -f scripts/build.sh ]]; then
        _record_fail "$id" "$name" "scripts/build.sh missing (Wave 3 deliverable)"
        return
    fi
    if bash scripts/build.sh >/dev/null 2>&1 && [[ -d "$APP_PATH" ]]; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "build failed or $APP_PATH not produced"
    fi
}

# 1-00-02: Ad-hoc signature applied to .app (Wave 3 dep)
verify_1_00_02() {
    local id="1-00-02" name="Ad-hoc signature applied"
    if [[ ! -d "$APP_PATH" ]]; then
        _record_fail "$id" "$name" "$APP_PATH not built yet"
        return
    fi
    if codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -q 'Signature=adhoc'; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "codesign output does not contain 'Signature=adhoc'"
    fi
}

# 1-01-01: Xcode project + cab-test target present
verify_1_01_01() {
    local id="1-01-01" name="Xcode project skeleton + two targets"
    if [[ -f ClaudeAlertBot.xcodeproj/project.pbxproj ]] \
       && grep -q 'cab-test' ClaudeAlertBot.xcodeproj/project.pbxproj; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "ClaudeAlertBot.xcodeproj/project.pbxproj missing or no 'cab-test' target"
    fi
}

# 1-01-02: LSUIElement=true in Info.plist
verify_1_01_02() {
    local id="1-01-02" name="LSUIElement=true in App/Info.plist"
    if [[ ! -f App/Info.plist ]]; then
        _record_fail "$id" "$name" "App/Info.plist missing"
        return
    fi
    if /usr/libexec/PlistBuddy -c "Print :LSUIElement" App/Info.plist 2>/dev/null | grep -qi true; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "LSUIElement key not true in App/Info.plist"
    fi
}

# 1-02-01: NWListener binds AF_UNIX socket (full only)
verify_1_02_01() {
    local id="1-02-01" name="NWListener binds AF_UNIX socket"
    if ! pgrep -f ClaudeAlertBot >/dev/null 2>&1; then
        _record_fail "$id" "$name" "ClaudeAlertBot not running"
        return
    fi
    if [[ -S "$SOCK" ]]; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "$SOCK not a socket"
    fi
}

# 1-02-02: OSLog subsystem registered (full only)
verify_1_02_02() {
    local id="1-02-02" name="OSLog subsystem registered (listener bound)"
    if log show --last 30s --predicate "subsystem == \"$LOG_SUBSYS\"" 2>&1 | grep -q "listener bound"; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "no 'listener bound' line in OSLog subsystem $LOG_SUBSYS in last 30s"
    fi
}

# 1-03-01: Reporter writes valid JSON envelope
verify_1_03_01() {
    local id="1-03-01" name="Reporter writes valid JSON line"
    if [[ ! -f Reporter/cab-report.sh ]]; then
        _record_fail "$id" "$name" "Reporter/cab-report.sh missing"
        return
    fi
    # Fire reporter; then validate the last line of hook.log is JSON containing 'envelope'.
    printf '{"session_id":"x","cwd":"/tmp"}' | bash Reporter/cab-report.sh >/dev/null 2>&1 || true
    if [[ ! -f "$LOG_FILE" ]]; then
        _record_fail "$id" "$name" "$LOG_FILE not written"
        return
    fi
    if tail -1 "$LOG_FILE" | python3 -c "import sys,json; obj=json.loads(sys.stdin.read()); assert 'envelope' in obj" 2>/dev/null; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "last line of $LOG_FILE not JSON with 'envelope' key"
    fi
}

# 1-03-02: Reporter exits 0 with no socket (app down)
# Threat-mitigation T-VRFY-01: always restore $SOCK on exit/interrupt.
verify_1_03_02() {
    local id="1-03-02" name="Reporter exits 0 with no socket"
    if [[ ! -f Reporter/cab-report.sh ]]; then
        _record_fail "$id" "$name" "Reporter/cab-report.sh missing"
        return
    fi
    local restored=0
    _restore_sock() {
        if [[ "$restored" -eq 0 && -e "$SOCK.bak" ]]; then
            mv "$SOCK.bak" "$SOCK" 2>/dev/null || true
            restored=1
        fi
    }
    trap _restore_sock EXIT INT TERM
    mv "$SOCK" "$SOCK.bak" 2>/dev/null || true
    printf '{}' | bash Reporter/cab-report.sh >/dev/null 2>&1
    local rc=$?
    _restore_sock
    trap - EXIT INT TERM
    if [[ "$rc" -eq 0 ]]; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "Reporter exited rc=$rc (must be 0)"
    fi
}

# 1-03-03: Reporter ≤ 50ms when socket missing
verify_1_03_03() {
    local id="1-03-03" name="Reporter ≤ 50ms (socket missing)"
    if [[ ! -f Reporter/cab-report.sh ]]; then
        _record_fail "$id" "$name" "Reporter/cab-report.sh missing"
        return
    fi
    local restored=0
    _restore_sock() {
        if [[ "$restored" -eq 0 && -e "$SOCK.bak" ]]; then
            mv "$SOCK.bak" "$SOCK" 2>/dev/null || true
            restored=1
        fi
    }
    trap _restore_sock EXIT INT TERM
    mv "$SOCK" "$SOCK.bak" 2>/dev/null || true
    # Use python for sub-ms timing portability across macOS bash 3.2.
    local elapsed
    elapsed=$(python3 - <<'PY' 2>/dev/null || echo "999"
import subprocess, time
t = time.perf_counter()
subprocess.run(["bash", "Reporter/cab-report.sh"],
               input=b"", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(f"{time.perf_counter()-t:.4f}")
PY
)
    _restore_sock
    trap - EXIT INT TERM
    # Compare via awk; bash can't do float compare directly.
    if awk -v e="$elapsed" 'BEGIN { exit !(e+0 <= 0.050) }'; then
        _record_pass "$id" "$name (${elapsed}s)"
    else
        _record_fail "$id" "$name" "elapsed ${elapsed}s exceeds 0.050s budget"
    fi
}

# 1-03-04: hook.log accumulates entries
verify_1_03_04() {
    local id="1-03-04" name="hook.log accumulates entries"
    if [[ ! -f "$LOG_FILE" ]]; then
        _record_fail "$id" "$name" "$LOG_FILE missing"
        return
    fi
    local lines
    lines=$(wc -l <"$LOG_FILE" 2>/dev/null | tr -d ' ')
    if [[ -n "$lines" && "$lines" -ge 1 ]]; then
        _record_pass "$id" "$name ($lines lines)"
    else
        _record_fail "$id" "$name" "$LOG_FILE has 0 lines"
    fi
}

# 1-04-01: cab-test → OSLog end-to-end (full only)
verify_1_04_01() {
    local id="1-04-01" name="cab-test → socket → OSLog end-to-end"
    local cab_test_bin="$APP_PATH/Contents/MacOS/cab-test"
    if [[ ! -x "$cab_test_bin" ]]; then
        _record_fail "$id" "$name" "$cab_test_bin not built / not executable"
        return
    fi
    "$cab_test_bin" --synthetic >/dev/null 2>&1 || true
    sleep 1
    if log show --last 5s --predicate "subsystem == \"$LOG_SUBSYS\"" 2>&1 | grep -q session_id; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "no session_id in OSLog $LOG_SUBSYS in last 5s"
    fi
}

# 1-05-01: Single-instance lock (full only)
# Threat-mitigation T-VRFY-02: clean up stray ClaudeAlertBot processes on exit
# so a failed run does not leak a running app.
verify_1_05_01() {
    local id="1-05-01" name="Single-instance lock (second launch blocked)"
    if [[ ! -d "$APP_PATH" ]]; then
        _record_fail "$id" "$name" "$APP_PATH not built"
        return
    fi
    _kill_stray_cab() {
        # Only kill if exactly one PID and it was launched fresh by us.
        pgrep -fx ClaudeAlertBot 2>/dev/null | xargs -r kill 2>/dev/null || true
    }
    trap _kill_stray_cab EXIT INT TERM
    open "$APP_PATH" >/dev/null 2>&1
    sleep 1
    open "$APP_PATH" >/dev/null 2>&1
    sleep 1
    local count
    count=$(pgrep -fc ClaudeAlertBot 2>/dev/null || echo 0)
    _kill_stray_cab
    trap - EXIT INT TERM
    if [[ "$count" -eq 1 ]]; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "expected 1 ClaudeAlertBot process, found $count"
    fi
}

# 1-06-01: App invisibility — manual check only
verify_1_06_01() {
    local id="1-06-01" name="App is invisible (Dock/menubar/Cmd-Tab)"
    _record_manual "$id" "$name" "MANUAL CHECK REQUIRED — see 01-VALIDATION.md Manual-Only Verifications row 1: open the app, confirm no Dock/menubar/Cmd-Tab presence, but pgrep -f ClaudeAlertBot returns a PID."
}

# 1-07-01: Self-check — harness exists & is executable
verify_1_07_01() {
    local id="1-07-01" name="verify-phase-1.sh exists & exits 0"
    if [[ -x scripts/verify-phase-1.sh ]]; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "scripts/verify-phase-1.sh not executable"
    fi
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------
usage() {
    cat <<USAGE
Usage: $(basename "$0") [--quick | --help]

  (no args)   Run the full Phase 1 verification suite (~10–20s). Includes
              Wave 3 build/launch checks; expect failures until Wave 3 lands.

  --quick     Run a fast subset for post-task-commit sampling (~3–5s).
              Skips build, app-launch, IPC, and OSLog checks.

  --help      Show this help.

Environment:
  APP_PATH    Override path to the .app bundle (default: build/export/ClaudeAlertBot.app)
USAGE
}

main() {
    local mode="full"
    case "${1:-}" in
        --quick) mode="quick" ;;
        --help|-h) usage; exit 0 ;;
        "") mode="full" ;;
        *) printf "Unknown arg: %s\n\n" "$1"; usage; exit 2 ;;
    esac

    printf "${DIM}Phase 1 validation harness — mode=%s${RESET}\n" "$mode"
    printf "${DIM}APP_PATH=%s${RESET}\n" "$APP_PATH"
    printf "${DIM}SOCK=%s${RESET}\n" "$SOCK"
    printf "${DIM}LOG_FILE=%s${RESET}\n\n" "$LOG_FILE"

    if [[ "$mode" == "quick" ]]; then
        # Fast subset: file-existence + LSUIElement + log-presence + self-check.
        verify_1_01_01
        verify_1_01_02
        verify_1_03_04
        verify_1_07_01
    else
        # Full suite — dependency order: project skeleton → build/sign →
        # IPC/OSLog → reporter → e2e → single-instance → manual → self.
        verify_1_01_01
        verify_1_01_02
        verify_1_00_01
        verify_1_00_02
        verify_1_02_01
        verify_1_02_02
        verify_1_03_01
        verify_1_03_02
        verify_1_03_03
        verify_1_03_04
        verify_1_04_01
        verify_1_05_01
        verify_1_06_01
        verify_1_07_01
    fi

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

main "$@"
