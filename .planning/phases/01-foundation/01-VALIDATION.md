---
phase: 1
slug: foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-07
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: 01-RESEARCH.md `## Validation Architecture` section.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell scripts + `xcodebuild test` (XCTest); manual smoke via `cab-test` CLI |
| **Config file** | `scripts/verify-phase-1.sh` (Wave 0 deliverable) |
| **Quick run command** | `bash scripts/verify-phase-1.sh --quick` |
| **Full suite command** | `bash scripts/verify-phase-1.sh` |
| **Estimated runtime** | ~10–20 seconds (full); ~3–5s (quick) |

---

## Sampling Rate

- **After every task commit:** `bash scripts/verify-phase-1.sh --quick` (file existence + codesign + LSUIElement)
- **After every plan wave:** Full `scripts/verify-phase-1.sh` (build + launch + hook fire + OSLog grep + single-instance + hook-down resilience)
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 20 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 1-00-01 | 00 (W0) | 0 | DIST-01 | — | Build pipeline works locally | smoke | `bash scripts/build.sh && test -d build/Release/ClaudeAlertBot.app` | ❌ W0 | ⬜ pending |
| 1-00-02 | 00 (W0) | 0 | DIST-05 | — | Ad-hoc signature applied | smoke | `codesign -dv --verbose=4 build/Release/ClaudeAlertBot.app 2>&1 \| grep -q 'Signature=adhoc'` | ❌ W0 | ⬜ pending |
| 1-01-01 | 01 | 1 | DIST-01 | — | Xcode project + two targets present | unit | `test -f ClaudeAlertBot.xcodeproj/project.pbxproj && grep -q 'cab-test' ClaudeAlertBot.xcodeproj/project.pbxproj` | ✅ | ⬜ pending |
| 1-01-02 | 01 | 1 | DIST-05 | — | LSUIElement=true in Info.plist | unit | `/usr/libexec/PlistBuddy -c "Print :LSUIElement" App/Info.plist \| grep -q true` | ✅ | ⬜ pending |
| 1-02-01 | 02 | 1 | IPC-01, IPC-02 | T-IPC-01 | NWListener binds AF_UNIX socket | integration | `pgrep -f ClaudeAlertBot && test -S "$HOME/Library/Application Support/ClaudeAlertBot/sock"` | ✅ | ⬜ pending |
| 1-02-02 | 02 | 1 | IPC-03 | — | OSLog subsystem registered | integration | `log show --last 30s --predicate 'subsystem == "com.claudealert.bot.hook"' \| grep -q "listener bound"` | ✅ | ⬜ pending |
| 1-03-01 | 03 | 2 | HOOK-01, HOOK-04 | T-HOOK-01 | Reporter writes valid JSON line | unit | `printf '{"session_id":"x","cwd":"/tmp"}' \| bash Reporter/cab-report.sh \| python3 -c "import sys,json; json.loads(sys.stdin.read())"` | ✅ | ⬜ pending |
| 1-03-02 | 03 | 2 | HOOK-03 | T-HOOK-03 | Reporter exits 0 with no socket (app down) | unit | `rm -f "$HOME/Library/Application Support/ClaudeAlertBot/sock"; printf '{}' \| bash Reporter/cab-report.sh; echo $?` (must be 0) | ✅ | ⬜ pending |
| 1-03-03 | 03 | 2 | HOOK-03 | — | Reporter ≤ 50ms when socket missing | perf | `time bash Reporter/cab-report.sh </dev/null` (real ≤ 0.050s) | ✅ | ⬜ pending |
| 1-03-04 | 03 | 2 | HOOK-06 | — | Hook debug log accumulates entries | unit | `test -f "$HOME/Library/Logs/ClaudeAlertBot/hook.log" && [ $(wc -l <"$HOME/Library/Logs/ClaudeAlertBot/hook.log") -ge 1 ]` | ✅ | ⬜ pending |
| 1-04-01 | 04 | 2 | HOOK-01, HOOK-05 | — | End-to-end: hook → socket → OSLog | integration | `bash CabTest/.../cab-test --synthetic && log show --last 5s --predicate 'subsystem == "com.claudealert.bot.hook"' \| grep -q session_id` | ✅ | ⬜ pending |
| 1-05-01 | 05 | 2 | IPC-01 | T-IPC-01 | Single-instance lock — second launch exits | integration | `open build/Release/ClaudeAlertBot.app; sleep 1; open build/Release/ClaudeAlertBot.app; sleep 1; [ $(pgrep -fc ClaudeAlertBot) -eq 1 ]` | ✅ | ⬜ pending |
| 1-06-01 | 06 | 3 | DIST-01 | — | App is invisible (no Dock/menubar/Cmd-Tab) | manual | See Manual-Only Verifications | ⚠️ manual | ⬜ pending |
| 1-07-01 | 07 (W0) | 0 | All 9 reqs | — | `verify-phase-1.sh` exists & exits 0 | smoke | `test -x scripts/verify-phase-1.sh && bash scripts/verify-phase-1.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky · 🟡 manual*

---

## Wave 0 Requirements

- [ ] `scripts/build.sh` — `xcodebuild archive` + per-Mach-O `codesign --force --sign -` + bundle seal
- [ ] `scripts/verify-phase-1.sh` — single-shot validation harness automating all 14 rows above
- [ ] `scripts/dev-install-hook.sh` — copies `cab-report.sh` to user-data path + patches `~/.claude/settings.json` (manual JSON merge OK for Phase 1)
- [ ] Xcode project skeleton with App + CabTest targets and LSUIElement=true Info.plist
- [ ] `Reporter/cab-report.sh` shebang + `python3 -c json.dumps` JSON construction stub

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| App invisibility (no Dock icon, no menu-bar item, no Cmd-Tab entry) | DIST-01 | Visual UI inspection — automatable but flaky from headless CI | 1) `open build/Release/ClaudeAlertBot.app` 2) Confirm no Dock bounce/icon 3) Press Cmd-Tab — app must not appear 4) Open menu bar — no app icon 5) `pgrep -f ClaudeAlertBot` returns a PID (proves it IS running) |
| First-run permission dialogs | (Phase 1 should have NONE — sanity check) | Phase 1 must not require Automation/Accessibility permissions | Run app fresh; confirm zero TCC dialogs appear (those come in Phase 3) |
| 100× hook-with-app-down resilience | HOOK-03 | Stress test for `exit 0` discipline | `for i in {1..100}; do bash Reporter/cab-report.sh </dev/null; echo $? ; done \| sort -u` must print only `0` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (build.sh, verify-phase-1.sh, project skeleton, Reporter stub)
- [ ] No watch-mode flags
- [ ] Feedback latency < 20s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
