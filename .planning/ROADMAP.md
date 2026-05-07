# Roadmap: Claude Alert Bot

**Defined:** 2026-05-07
**Granularity:** standard (target 5-8 phases)
**Total v1 requirements:** 53
**Coverage:** 53/53 (100%)

## Core Value Anchor

Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다. **알림이 떠도 어느 세션 것인지 헷갈리거나 클릭이 잘못된 터미널을 여는 순간 가치가 무너진다.**

## Phase Ordering Rationale

- **Spine before face before punchline.** Hook→App pipeline (Phase 1) is the spine; the floating widget + alert loop (Phase 2) is the face; the iTerm2 jump (Phase 3) is the punchline.
- **Risk concentration in Phase 3.** Apple Events permission, AppleScript correctness, and session-identity edge cases (Pitfall #2, #4, #10) sit in one phase, after a working alert loop exists to test against.
- **Concurrency gate in Phase 4.** Actor discipline is established in Phase 2; the 10-hooks-in-100ms stress test gates Phase 4 when multi-session UI exists to verify against (Pitfall #9).
- **Hook installer + onboarding (Phase 5) before distribution (Phase 6).** The README's macOS 15+ "Open Anyway" flow can only be written correctly once the actual user-facing path has been tested end-to-end on a fresh account.
- **Ad-hoc signing and `exit 0` are non-negotiable from Phase 1.** Apple Silicon refuses to launch unsigned binaries (Pitfall #2 / DIST-01). A Stop hook with `exit 2` puts Claude into an infinite loop (Pitfall #1 / HOOK-03). Both must be locked at the foundation.

## Phases

- [ ] **Phase 1: Foundation** — Hook script + AF_UNIX IPC + headless app skeleton + ad-hoc-sign build pipeline; a Stop event lands as a structured log line in the running app.
- [ ] **Phase 2: Alert Loop** — UserPromptSubmit/Stop correlation, threshold filter, persistent floating NSPanel widget, sound, Settings window. A 31-second Claude turn produces a clickable widget showing the project name (no jump yet).
- [ ] **Phase 3: Click-to-iTerm2** — UUID-based AppleScript jump, TTY fallback, Automation permission flow, click debounce, 3-second hard timeout. Clicking the widget lands on the exact originating tab.
- [ ] **Phase 4: Multi-Session UX** — Counter-badge widget, expandable session list popover, batching window, sound dedupe, concurrency stress hardening. Five near-simultaneous completions produce one badge that opens a list and jumps each to its correct tab.
- [ ] **Phase 5: Hook Installer & Onboarding** — Idempotent JSON5-tolerant patch of `~/.claude/settings.json` with manual fallback, 3-screen first-run wizard, clean uninstall. A new user reaches a working notifier without touching their terminal.
- [ ] **Phase 6: Distribution** — `.dmg` packaging, README with macOS 14/15+ Gatekeeper paths, `bypass-gatekeeper.command` helper, fresh-account validation. Another macOS user installs from `.dmg` and reaches a working notifier in under five minutes.

## Phase Details

### Phase 1: Foundation
**Goal:** A Claude Code Stop hook lands as a structured log entry in a running, invisible Swift app. The build pipeline is correct from the first commit (ad-hoc-signed, headless, single-instance), and the hook never breaks Claude Code.
**Depends on:** Nothing (first phase)
**Requirements:** HOOK-01, HOOK-03, HOOK-04, HOOK-05, HOOK-06, IPC-01, IPC-02, IPC-03, DIST-01, DIST-05
**Success Criteria** (what must be TRUE):
  1. Running Claude Code in iTerm2 and ending a turn produces a JSON line in the app's OSLog containing `session_id`, `cwd`, `ITERM_SESSION_ID`, `tty`, `ppid`, `CLAUDE_PROJECT_DIR`, and a timestamp.
  2. With the app not running, the same Stop event leaves Claude Code unaffected — the user sees no error, no infinite loop, and the hook script exits 0 within 50ms.
  3. The built `.app` bundle reports `Signature=adhoc` under `codesign -dv --verbose=4` and launches without `cs_invalid_page` errors on Apple Silicon.
  4. After launch the app shows no Dock icon, no menu-bar item, no Cmd-Tab entry; a second launch attempt is blocked because the Unix-domain socket is already held.
  5. The file `~/Library/Logs/ClaudeAlertBot/hook.log` accumulates a debug record for every hook fire (env snapshot, PPID chain, tty), including fires that happened while the app was down.
**Plans:** 7 plans
Plans:
**Wave 1**
- [x] 01-00-PLAN.md — Wave 0: scripts/verify-phase-1.sh validation harness scaffold
- [x] 01-01-PLAN.md — Wave 1: Xcode project skeleton (App + cab-test targets, Info.plist with LSUIElement)
- [x] 01-02-PLAN.md — Wave 1: Reporter shell script (POSIX sh, exit 0 always, AF_UNIX nc transport, hook.log debug)

**Wave 2** *(blocked on Wave 1 completion)*
- [ ] 01-03-PLAN.md — Wave 2: App listener (NWListener AF_UNIX, HookEvent schema, AppDelegate, cab-test CLI)
- [ ] 01-04-PLAN.md — Wave 2: scripts/dev-install-hook.sh (D-04 user-data copy + idempotent ~/.claude/settings.json merge)

**Wave 3** *(blocked on Wave 2 completion)*
- [ ] 01-05-PLAN.md — Wave 3: scripts/build.sh (xcodebuild archive + per-Mach-O ad-hoc codesign + verification)
- [ ] 01-06-PLAN.md — Wave 3: e2e verify-phase-1.sh wiring + 01-VERIFICATION.md sign-off (with manual checkpoint)

### Phase 2: Alert Loop
**Goal:** Long Claude turns produce a persistent, focus-safe floating widget that survives until clicked. Settings persist, sound plays once, and the start/stop correlation is robust enough to compute elapsed time against a configurable threshold.
**Depends on:** Phase 1
**Requirements:** HOOK-02, SESS-01, SESS-02, SESS-03, SESS-04, THR-01, THR-02, WIDG-01, WIDG-02, WIDG-03, WIDG-04, WIDG-05, WIDG-06, WIDG-07, AUD-01, AUD-02, SET-01, SET-02, SET-03, SET-04
**Success Criteria** (what must be TRUE):
  1. A 31-second Claude turn produces a floating Claude-icon widget showing the project folder name; the widget appears above all Spaces, full-screen apps, and Stage Manager, and does not steal keyboard focus from the foreground app.
  2. A 5-second Claude turn produces no widget and plays no sound (threshold filter holds at the default 30 s).
  3. The widget remains on screen until the user clicks it — across Space switches, sleep/wake, and lid close/open — and is invisible whenever no completion is pending.
  4. Settings (threshold seconds, sound on/off, widget corner + offset) change behavior immediately, persist across app restart, and the "Test notification" button surfaces the widget and plays the sound on demand.
  5. Killing and restarting the app while a completed-but-unclicked alert is pending re-renders that alert from `sessions.json`; an in-flight session older than 6 hours does not.
  6. When a Stop event has no matching UserPromptSubmit (start lost), the configured fallback policy (default: alert with "?" duration) is applied — never silently dropped.
**Plans:** TBD
**UI hint:** yes

### Phase 3: Click-to-iTerm2
**Goal:** Clicking the widget lands the user on the exact iTerm2 tab where the work happened, or shows a friendly "session no longer exists" error — never the wrong tab. Apple Events permission is granted deterministically during a known UI moment, with a documented recovery path on denial.
**Depends on:** Phase 2
**Requirements:** JUMP-01, JUMP-02, JUMP-03, JUMP-04, JUMP-05, SET-05, ONB-02, ONB-03
**Success Criteria** (what must be TRUE):
  1. With three concurrent Claude sessions in three iTerm2 tabs, clicking the widget for any one of them brings exactly that tab to the front (verified via `unique ID` UUID match), never a sibling pane.
  2. After the user closes the originating tab, clicking the widget produces a non-blocking "That terminal is gone" message instead of focusing a different tab; the entry leaves the queue cleanly.
  3. The "iTerm2 connection test" Settings button triggers the macOS Automation permission dialog the first time it is pressed (with a specific, user-trustworthy `NSAppleEventsUsageDescription`); subsequent presses execute a real focus operation against a chosen tab.
  4. When Automation permission is denied, the next click surfaces a recovery banner with a button that deep-links to System Settings → Privacy & Security → Automation; the app does not silently no-op.
  5. AppleScript calls run on a background queue with a 3-second hard timeout and a 500ms click debounce; the main thread never beachballs even when iTerm2 is busy.
  6. When `ITERM_SESSION_ID` was unavailable at hook time (e.g., shell-integration-disabled environment), TTY-based fallback lookup still focuses the correct pane.
**Plans:** TBD
**UI hint:** yes

### Phase 4: Multi-Session UX
**Goal:** Five near-simultaneous Claude completions produce one widget — not five — that expands into a list, plays one sound, and routes each list item to its own correct tab. Concurrency races cannot corrupt the queue under stress.
**Depends on:** Phase 3
**Requirements:** AGG-01, AGG-02, AGG-03, AGG-04, AGG-05, AUD-03
**Success Criteria** (what must be TRUE):
  1. Five Stop events arriving within a 500ms-2s batching window produce a single counter-badge widget showing "5", not five stacked widgets; the sound plays exactly once.
  2. Clicking the counter widget opens a popover listing all five sessions with their project names and elapsed times in arrival order; selecting any item jumps to that exact iTerm2 tab and decrements the badge.
  3. Stress test — 10 fake Stop events fired within 100ms — produces a badge of 10, ten distinct list rows, and ten correct jumps with no missing or duplicated entries (composite dedupe key `(session_id, transcript_path, timestamp-rounded)` holds).
  4. A Stop event arriving for a session already in the completed-unclicked queue is ignored (no double-counting, no double-sound).
  5. While the popover is open, a new completion appears in the list without dismissing the popover or stealing focus.
**Plans:** TBD
**UI hint:** yes

### Phase 5: Hook Installer & Onboarding
**Goal:** A new user goes from "fresh app launched" to "first test notification clicked through to iTerm2" without ever opening their `~/.claude/settings.json`. Uninstall is reversible — only this app's hook entries are touched.
**Depends on:** Phase 4
**Requirements:** INST-01, INST-02, INST-03, INST-04, ONB-01, ONB-04
**Success Criteria** (what must be TRUE):
  1. Installing the hook through the in-app onboarding wizard adds exactly one Stop entry and one UserPromptSubmit entry to `~/.claude/settings.json`; running the install a second time changes nothing (idempotent).
  2. When `~/.claude/settings.json` already contains user-authored hooks (including JSON5 comments), the installer preserves all of them and only appends the two new entries; comments and formatting outside the modified section survive.
  3. The 3-screen first-run wizard (install hook → grant Automation → fire test notification) runs to completion on first launch; the test notification produces a real widget that focuses iTerm2 when clicked.
  4. The "Copy hook JSON" manual-fallback button produces a string the user can paste into their settings.json and reach a working notifier without the auto-installer.
  5. The "Uninstall hook" action removes only the entries this app added, leaving every other user hook untouched (verified by snapshot diff).
  6. README troubleshooting includes the `tccutil reset AppleEvents <bundle-id>` command for users who clicked "Don't Allow" and now need to retry.
**Plans:** TBD
**UI hint:** yes

### Phase 6: Distribution
**Goal:** Another macOS user — on a fresh user account, with no developer tools — downloads a `.dmg`, drags the app to /Applications, follows the README, and reaches a working notifier in under five minutes. The README reflects the actual macOS 14 and macOS 15+ Gatekeeper paths the user will see.
**Depends on:** Phase 5
**Requirements:** DIST-02, DIST-03, DIST-04, DIST-06
**Success Criteria** (what must be TRUE):
  1. A single `scripts/release.sh` (or equivalent) produces an ad-hoc-signed `.app` inside a `create-dmg`-built `.dmg`; the artifact is reproducible from a clean checkout.
  2. The README documents two distinct first-run paths — macOS 14 (right-click → Open) and macOS 15+ (System Settings → Privacy & Security → Open Anyway) — with screenshots that match what the user actually sees.
  3. The DMG includes a `bypass-gatekeeper.command` helper that, when double-clicked, runs `xattr -cr` against `/Applications/ClaudeAlertBot.app` and explains what it just did.
  4. End-to-end validation on a fresh macOS user account (or VM): download `.dmg` from a real URL → drag to /Applications → follow the documented path → onboarding wizard runs → test notification fires → click jumps to iTerm2 — no developer assistance required.
**Plans:** TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 3/7 | Executing | - |
| 2. Alert Loop | 0/0 | Not started | - |
| 3. Click-to-iTerm2 | 0/0 | Not started | - |
| 4. Multi-Session UX | 0/0 | Not started | - |
| 5. Hook Installer & Onboarding | 0/0 | Not started | - |
| 6. Distribution | 0/0 | Not started | - |

## Research Flags

Phases that should run `/gsd-research-phase` before planning:

- **Phase 3 (Click-to-iTerm2):** Open questions — (a) `ITERM_SESSION_ID` reliability under tmux/screen/nix-shell/zellij/containerized shells; (b) AppleScript `unique ID` lookup latency under typical pane counts (Phase 1's hook log will provide the test data); (c) recovery UX for `errAEEventNotPermitted (-1743)` deep-link reliability across macOS 14/15/26.
- **Phase 6 (Distribution):** Validate — (a) exact dialog text on macOS 14/15/26 when launching an ad-hoc-signed-but-quarantined app; (b) whether shipping `bypass-gatekeeper.command` itself triggers extra Gatekeeper friction.

Phases with standard patterns (no research-phase recommended):
- Phase 1 (Foundation), Phase 2 (Alert Loop), Phase 4 (Multi-Session UX), Phase 5 (Hook Installer & Onboarding).

## Locked Architectural Decisions (from research)

These decisions are locked by the research and must hold across all phases:

- **Hook script always exits 0** (Pitfall #1 / HOOK-03). Reserve non-zero only for "configuration is broken." Drives the thin-shell-hook + fat-daemon split.
- **Two hooks installed, not one.** Both `Stop` and `UserPromptSubmit` are required for elapsed-time correlation. Affects HOOK-01/02 and INST-01.
- **Ad-hoc signing in build pipeline from Phase 1** (DIST-01). Apple Silicon will not launch unsigned binaries; this is a load-time block, not a Gatekeeper block.
- **AppleScript by UUID, never by tab/window/pane index** (Pitfall #4 / JUMP-02). Indices shift on tab reorder; UUIDs are stable for the life of a pane.
- **Session matching multi-strategy with explicit failure** (Pitfall #4 / JUMP-02). UUID first, TTY fallback, friendly "session no longer exists" last — never wrong-jump.
- **Swift `actor` for SessionRegistry** (Pitfall #9 / SESS-01). Established Phase 2 in single-session form; stress-test gate at Phase 4.
- **`NSPanel` with `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` + `.canJoinAllSpaces` + `.fullScreenAuxiliary` + `.stationary`** (Pitfall #1 / WIDG-01, WIDG-02). SwiftUI `Window` cannot pin above all Spaces.
- **`NSAppleEventsUsageDescription` with specific user-trustworthy text** (Pitfall #3 / ONB-02). Generic strings make users decline; missing key = silent denial.
- **AppleScript on background queue with 3-second hard timeout + click debounce** (Pitfall #10 / JUMP-03, JUMP-04, JUMP-05). Main thread never blocks on iTerm2.
- **AF_UNIX socket for IPC, not HTTP/XPC/URL-scheme** (chosen Phase 1 / IPC-01). No port management, no entitlements, survives concurrent fires.
- **Min OS macOS 14 Sonoma.** `MenuBarExtra`, `SMAppService.mainApp`, and `NWEndpoint.unix` all stable from 14.

## Out of Scope (v2+)

Tracked in REQUIREMENTS.md under v2: Multi-Terminal (MTERM-*), Per-Project Customization (PPC-*), Quiet Hours/Focus (QH-*), History/Notification (HIST-*, NOTI-*), Distribution Polish (DPOL-*). Not in this roadmap.

---
*Roadmap created: 2026-05-07*
*Next: `/gsd-plan-phase 1`*
