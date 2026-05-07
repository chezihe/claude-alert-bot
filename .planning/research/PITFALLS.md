# Pitfalls Research

**Domain:** macOS native menu-bar/accessory app — floating notification companion for Claude Code, controlling iTerm2 via Apple Events, distributed unsigned via .dmg
**Researched:** 2026-05-07
**Confidence:** HIGH for distribution / NSPanel / Apple Events (multiple corroborating sources including Apple docs). MEDIUM for Claude Code hook edge cases (docs current but real-world race behavior under-documented). MEDIUM for DND/Focus sound behavior (long-standing Apple bug with imperfect public spec).

## Critical Pitfalls

### Pitfall 1: Floating widget steals focus from iTerm2 every time it appears

**What goes wrong:**
The widget pops up on Claude completion, becomes the key window, and yanks focus away from whatever app the user is in (often a different iTerm2 tab they're working in, a browser, or a code editor). Even worse: when the user clicks the widget to jump to iTerm2, they end up in your app first, then in iTerm2 — adding a flicker and breaking the "instant teleport" feel that is the product's Core Value.

**Why it happens:**
Default `NSWindow` (and even default `NSPanel` without the right style mask) becomes key on display and triggers `NSApplication.activate(...)`. SwiftUI's default `WindowGroup` is even worse — it activates the app fully. Developers who don't know about `.nonactivatingPanel` ship with the default and only notice in beta when their typing gets interrupted.

**How to avoid:**
- Set `LSUIElement = true` in Info.plist OR call `NSApp.setActivationPolicy(.accessory)` early in `applicationWillFinishLaunching` (before any window is shown).
- Use a custom `NSPanel` subclass with style mask including `.nonactivatingPanel`; override `canBecomeKey` to return `false` (or `true` only when the expanded session-list popover is shown and needs keyboard navigation).
- Set `becomesKeyOnlyIfNeeded = true`.
- Host SwiftUI inside `NSHostingView` attached to the panel — do NOT use `WindowGroup`/`Window` from SwiftUI's App lifecycle for the floating widget itself.
- When the user clicks the widget to jump to iTerm2, do NOT call `NSApp.activate` on self before `tell application "iTerm" to activate` — go straight to iTerm2's activation.

**Warning signs:**
- During development you notice your typing in another app gets eaten when the widget appears.
- The Dock shows your app icon when LSUIElement should hide it (means LSUIElement is being overridden — usually by SwiftUI Scene types).
- ⌘-Tab shows your app in the switcher.

**Phase to address:** Phase 1 (foundation / window plumbing). This decision compounds — if you build features on top of a focus-stealing window, every test feels broken in subtle ways.

---

### Pitfall 2: Unsigned app bundle ships with quarantine xattr → "app is damaged and cannot be opened" on Apple Silicon

**What goes wrong:**
You build the app, put it inside a .dmg, the user downloads it, drags to /Applications, double-clicks, and sees: **"'Claude Alert Bot' is damaged and can't be opened. You should move it to the Trash."** Note this is *different* from the more familiar "unidentified developer" message. There is **no right-click → Open workaround** for "is damaged" — that workaround only existed for the older Gatekeeper assessment. The user is stuck.

**Why it happens:**
Two stacked issues:
1. Since Apple Silicon (M1+), every executable must be at least ad-hoc code-signed (`codesign -s -`) to launch at all. An entirely unsigned binary built without `CODE_SIGN_IDENTITY` set won't run.
2. When Safari/Chrome download a .dmg, macOS attaches the `com.apple.quarantine` extended attribute. On a non-notarized, non-Developer-ID-signed app, Gatekeeper in Sonoma+ shows "is damaged" rather than "from unidentified developer."
3. macOS Sequoia 15.0+ removed the right-click-Open shortcut entirely; the workflow is now "double-click → dismiss → System Settings → Privacy & Security → Open Anyway." Users do NOT know this.

**How to avoid:**
- **Always ad-hoc sign** the .app before zipping/distributing: `codesign --force --deep --sign - YourApp.app`. Xcode default for "Sign to Run Locally" produces this; do not strip it.
- Verify with `codesign -dv --verbose=4 YourApp.app` — should show `Signature=adhoc`.
- Tell users in the README to either: (a) drag from .dmg to /Applications, then on first launch use **System Settings → Privacy & Security → "Open Anyway"** (Sequoia path), or (b) run `xattr -dr com.apple.quarantine /Applications/ClaudeAlertBot.app` in Terminal once after install.
- Provide a tiny shell installer script in the .dmg that strips quarantine on the dragged copy (with explicit consent — print what it does first).
- Test on a *fresh* macOS user account or a VM with no developer tools installed. Your dev machine has special trust state that hides this bug.

**Warning signs:**
- "Damaged" appears verbatim in the Gatekeeper dialog (not "unidentified developer").
- `spctl -a -vv YourApp.app` returns `rejected (the code is valid but does not seem to be signed with the required certificate)` — this is fine; what you don't want is `rejected: a sealed resource is missing or invalid`.
- Console.app shows `CODE SIGNING: process is exiting because cs_invalid_page(...)` for your bundle ID.

**Phase to address:** Phase 1 should make the build script ad-hoc sign by default. The user-facing Sequoia "Open Anyway" instructions should be locked into the README at the same time the .dmg target is added (likely later phase, but the constraint must be known up front).

---

### Pitfall 3: First-run Apple Events authorization flow that the user can't recover from if they decline

**What goes wrong:**
The first time the app sends an AppleScript event to iTerm2, macOS shows the TCC dialog: "Claude Alert Bot.app would like to control 'iTerm.app'." If the user clicks "Don't Allow" — by reflex, by mistake, or because the dialog appears unexpectedly mid-task — every subsequent AppleScript call fails silently with `errAEEventNotPermitted (-1743)`. There is no second prompt. The widget appears to work but clicking it does nothing — the iTerm2 jump is dead.

Worse: if `NSAppleEventsUsageDescription` is missing from Info.plist, on the 10.14+ SDK the AppleEvent returns `errAEEventNotPermitted` *without ever showing the prompt*. The user sees a broken app with no actionable error.

**Why it happens:**
- The Info.plist key `NSAppleEventsUsageDescription` is mandatory for Mojave+ to even attempt the prompt; missing it = silent denial.
- macOS only prompts once. After "Don't Allow," recovery requires the user to navigate **System Settings → Privacy & Security → Automation → Claude Alert Bot → toggle iTerm on**, OR the developer/user runs `tccutil reset AppleEvents <bundle-id>` from Terminal.
- Hooks fire from background processes — the prompt may appear when the user isn't expecting an automation dialog at all (they were just running Claude in another terminal), increasing the chance they click "Don't Allow" on impulse.

**How to avoid:**
- Put a clear, user-trustworthy string in `NSAppleEventsUsageDescription`: e.g. `"Claude Alert Bot needs to switch focus to your iTerm2 tab when a Claude Code task completes."` Generic strings like "for automation" make users decline.
- Trigger the prompt at a *known, expected* moment — during a first-run onboarding screen with a "Test connection to iTerm2" button, NOT on the first real notification.
- Detect `errAEEventNotPermitted` (-1743) in the AppleScript result and surface an actionable error UI: "iTerm2 control is disabled. Open System Settings → Privacy & Security → Automation to fix" with a button that opens that pane via `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.
- On startup, check the previously-remembered "we have control" state; if missing, run a no-op AppleScript (e.g., `tell application "iTerm" to count of windows`) inside the onboarding flow to drive the prompt deterministically.
- Document the `tccutil reset AppleEvents com.example.claudealertbot` command in the README's troubleshooting section.

**Warning signs:**
- During testing, you removed and reinstalled the app and the prompt didn't reappear → TCC remembers by bundle ID; reset with `tccutil reset AppleEvents <bundle-id>`.
- The app works for you but a tester reports "clicks do nothing" → almost always TCC denial.
- `osascript` returns immediately with a -1743 error code.

**Phase to address:** Phase containing first iTerm2 integration. Build the onboarding/permission-test screen before building the production click-to-jump path; otherwise denial is a guaranteed beta bug.

---

### Pitfall 4: Hook environment doesn't carry `ITERM_SESSION_ID` → wrong tab gets focused

**What goes wrong:**
You assume the `Stop` hook runs with the same environment as the shell where the user ran `claude`. You read `ITERM_SESSION_ID` from `getenv` to find the originating tab, store it, and at click time tell iTerm2 to focus that session. In practice it works on your dev machine but fails for some users — clicking the widget either does nothing or focuses a *different* tab than the one Claude ran in. In the worst case, this destroys the Core Value: "the click is wrong" is the failure mode the project explicitly cannot tolerate.

**Why it happens:**
- Hooks run in a non-interactive child process; environment is *inherited from Claude Code*, which itself inherited from the shell. Most user-set env vars that come from `.zshrc` are NOT exported because non-interactive shells don't source `.zshrc` by default. But `ITERM_SESSION_ID` is set by iTerm2 itself in the parent shell environment, so it IS usually inherited — *except* when the user runs Claude inside `tmux`, `screen`, `nix-shell`, `zellij`, a containerized shell, or any nested env that re-sanitizes environment.
- Even when present, `ITERM_SESSION_ID` corresponds to the iTerm2 session, but the user could have closed and reopened the tab. Session IDs do NOT persist across iTerm2 restarts.
- PPID-walking up to find iTerm2's PID and then asking iTerm2 "which session has this tty/pid as a child?" is more robust but has its own race conditions: the hook process, by the time AppleScript runs, may already have exited (zombie) or the shell may have re-spawned.
- The Claude Code main process is NOT necessarily a direct child of the iTerm2 shell — there may be wrappers, login shells, or the user may have started Claude via `&` or in a subshell.

**How to avoid:**
- **Capture session identity at hook time, not at click time.** When the Stop hook fires, it has access to the live process tree and live env. Walk parents (`ps -o ppid=,comm= -p $$`) until you find an `iTerm2` ancestor or a process whose `tty` matches an iTerm2 session's `tty` (queryable via AppleScript `tty of session`).
- Store both: `ITERM_SESSION_ID` (if set) AND the tty path (always available — `ttyname(0)` from the hook process or `tty` shell builtin). The tty path is iTerm2-restart-resilient within a single iTerm2 launch.
- At click time, ask iTerm2 via AppleScript: `tell application "iTerm" to repeat with w in windows ... if tty of t = "/dev/ttys004" then ...`. Match by tty first, then by session id, then by cwd as last fallback.
- If no match found, fall back to a *clear visual error*, not silently focusing a random tab. The widget should say "session no longer exists" rather than wrong-jump.
- Exclude tmux/screen sessions from MVP (document as known limitation) OR detect tmux via `$TMUX` and prompt user to register sessions manually.
- Test specifically: tmux, nested zsh, fish, sourcing a venv, running Claude after `cd`, running Claude in a split pane.

**Warning signs:**
- During testing, two iTerm2 tabs both show the widget jumping to the same one.
- `env | grep ITERM` from inside the hook (have it log to a file) sometimes shows nothing.
- The hook's working directory matches the project but the ancestor PIDs don't reach iTerm2.

**Phase to address:** Phase containing session→tab mapping. This is the single highest-risk piece of the product. Build a logging mode early that records `(timestamp, env-snapshot, ppid-chain, tty)` for every hook fire so beta data shows the failure modes before they bite production users.

---

### Pitfall 5: Hook with `exit 2` blocks Claude Code; long hook with non-zero exit confuses Claude

**What goes wrong:**
Your hook script does the right thing (records the event, sends to the daemon), but somewhere it has a syntax error or the daemon isn't running, so it exits non-zero. Claude Code interprets `exit 2` as "blocking error" and *does not stop* — it keeps generating, treating stderr as feedback. The user is in an infinite "Claude won't end its turn" loop caused by your notifier. Or: the hook takes 90 seconds because it's trying to AppleScript-query iTerm2 for the session list, and the user's Claude session feels frozen for that whole time.

**Why it happens:**
- Stop hook exit code 2 has a defined behavior: it tells Claude that stopping was *blocked* and feeds stderr back as a "you must continue" signal. This is the opposite of "notification successful, please proceed."
- Non-zero non-2 exits print stderr to the user's terminal but don't block — still ugly.
- Hooks run synchronously from Claude's perspective and have a default timeout, but a slow hook is felt as latency on every turn.
- The `stop_hook_active` field in the JSON input exists specifically to prevent loops; if you ignore it you can deadlock when your hook itself triggers conditions that re-trigger Stop.

**How to avoid:**
- Hook script must `exit 0` on success **and on most failures**. Reserve non-zero only for "configuration is broken and the user must know."
- Never use `exit 2` from this product unless you intentionally want Claude to keep working — which this product never does.
- Hook should be a *thin client*: read JSON from stdin, write a single JSON message to a Unix socket / named pipe / HTTP-on-localhost owned by the daemon, exit immediately. Target: <50ms of wall time. All AppleScript / iTerm2 querying happens in the long-running app, not the hook.
- If the daemon is not running, the hook should still `exit 0` silently (or log to a file). The user's Claude session must never break because the notifier is misconfigured.
- Read `stop_hook_active` from the input JSON and short-circuit if true.
- Set up the hook with a strict timeout in `settings.json` if available, AND have the hook self-timeout (e.g., wrap with `timeout 2` or use a Swift binary with its own deadline).
- Provide a debug-log file (`~/Library/Logs/ClaudeAlertBot/hook.log`) so users can diagnose without `print` to stderr (which Claude sees).

**Warning signs:**
- User reports "Claude won't stop after a task" — check for exit 2.
- User reports "Claude feels slow now after installing this" — check hook latency.
- Hook script tries to do AppleScript / network / heavy work directly.

**Phase to address:** Phase containing hook integration. The "thin hook → fat daemon" architectural decision must be locked in before any feature work; reversing it later means rewriting the hook contract.

---

### Pitfall 6: Widget hidden under the MacBook Pro notch or off-screen on multi-display

**What goes wrong:**
On a 14"/16" MacBook Pro, the user's chosen widget position (e.g., "top-center") puts the widget directly behind the notch, making it partially or fully invisible. On a multi-display setup, the widget appears on a screen the user isn't looking at. After unplugging an external display, the saved widget position is on a coordinate space that no longer exists and the widget renders at -1200,800 (off-screen).

**Why it happens:**
- `NSScreen.main` returns the screen with the key window — which for an LSUIElement app may be unpredictable.
- The notch occupies a region described by `NSScreen.safeAreaInsets` (top inset ~38pt) and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Naive code placing windows at `(screenWidth/2, screenHeight - widgetHeight)` lands behind the notch.
- macOS persists window positions per-screen-config; when the config changes, restored frames may be invalid.

**How to avoid:**
- Read `NSScreen.screens` and explicitly choose a target (saved by user setting: "main display," "display with mouse cursor," or "display where the iTerm2 tab lives").
- Subtract `NSScreen.safeAreaInsets.top` from any "top" anchor; never anchor to absolute screen Y.
- Validate restored positions against current `NSScreen.screens` frames; if invalid, snap back to a default safe corner.
- Test with: 16" MBP closed-clamshell + external, MBP open + external, single MBP, single external 4K, sidecar iPad.
- Provide a "Reset widget position" menu item — recovery valve when a user gets stuck.

**Warning signs:**
- User reports "I don't see the widget" but logs show it was shown.
- After display reconfig, widget appears at unusual coordinates.

**Phase to address:** Phase containing widget placement / user position settings. Multi-display testing in QA checklist.

---

### Pitfall 7: Sound plays during Do Not Disturb / Focus mode, defeating the user's quiet hours

**What goes wrong:**
The user enables Focus mode for "deep work" or DND for a meeting. They expect notifications to be muted. Your widget pops up silently (visually fine), but `NSSound("Glass").play()` ignores Focus state entirely — sound rings out in the meeting. The user uninstalls.

**Why it happens:**
- macOS's Focus/DND only suppresses *UserNotifications-framework* (UN/UNNotificationCenter) banners and their associated sounds. Direct `NSSound` / `AudioServicesPlaySystemSound` / `AVAudioPlayer` playback is unaffected — these are not "notifications," they're just audio.
- This is a *long-standing, documented* behavior gap; even some Apple system apps misbehave here.

**How to avoid:**
- Decision tree: prefer `UNUserNotificationCenter` for the *sound* delivery (with `sound = .default` or a custom .caf) and use the floating widget for the *visual*. UN sounds respect Focus.
- Alternatively: query Focus state via the (limited) `NSUserNotificationCenter` `Notification.Name("com.apple.donotdisturbActive")` darwin notifications, OR check `defaults read com.apple.controlcenter "NSStatusItem Visible FocusModes"` heuristics. Both are unreliable across versions.
- Cleanest path: use `UNNotificationSound` for audio, `NSPanel` for visual. Two layers, each respects the user's settings appropriately.
- Provide a user preference: "Mute sound during Focus" toggle as a backstop.
- Test explicitly with Focus on, Focus on + "Allow time-sensitive," and DND scheduled.

**Warning signs:**
- Sound plays even though notifications are showing as silenced elsewhere.
- User feedback uses words like "interrupted my meeting."

**Phase to address:** Phase containing notification + sound feature. Sound architecture decision should be made before implementing — not patched in after a beta complaint.

---

### Pitfall 8: SMAppService login-item registration succeeds but the helper bundle isn't there → silent failure

**What goes wrong:**
You add a "Launch at login" toggle. Calling `SMAppService.mainApp.register()` returns success on your dev machine. On a fresh user system, the call returns success too — but the app doesn't actually launch at login. The user toggles the setting, restarts, nothing happens, and there's no error.

**Why it happens:**
- `SMAppService` requires the *bundle structure to be correct*. For mainApp, the executable must be in `/Applications` (or another approved location); from `~/Downloads` or even from a custom path it may register-but-not-launch. The actual launchd service is registered against a path; if the path moves, the registration breaks silently.
- Status (`SMAppService.mainApp.status`) is the source of truth, NOT the return value of `register()`. Many implementations cache a local Bool and never re-check.
- macOS Ventura+ requires `SMAppService` (legacy `SMLoginItemSetEnabled` is deprecated and removed for SwiftUI-built apps); using legacy code on macOS 13+ is a slow-burn bug.
- The user can *also* disable login items globally in System Settings → General → Login Items; the app's UI must reflect that.

**How to avoid:**
- Always read `SMAppService.mainApp.status` to display the toggle's current state — never store a local Bool.
- Tell the user explicitly: "drag to /Applications first, then enable Launch at Login."
- Detect `.requiresApproval` status and surface a banner: "Approve in System Settings → General → Login Items."
- Defer this feature to a later phase; for MVP, manual launch is acceptable.

**Warning signs:**
- Toggle says "On" but the app doesn't appear in `launchctl list | grep <bundle-id>` after login.
- `SMAppService.mainApp.status` returns `.notRegistered` despite `register()` having succeeded earlier.

**Phase to address:** Whichever phase introduces "Launch at login" feature (likely later — this is non-essential for MVP).

---

### Pitfall 9: Concurrent Stop hooks from multiple sessions create race conditions in widget state

**What goes wrong:**
User has Claude running in three iTerm2 tabs simultaneously. Two of them finish within 200ms of each other. Hook A fires and starts updating the daemon's "completions" list. Hook B fires before A finishes. Without proper synchronization, you get: only one widget shows, or the badge counter says "1" when it should say "2," or worse, Hook B's session gets stored under Hook A's key. Click-to-jump goes to the wrong tab.

Even within a single session: if the user rapidly alternates turns (asks question, gets answer, asks again 3 seconds later), you may have Stop_n still being processed when Stop_n+1 fires. If the same `session_id` is reused for the new turn, in-flight state from n could collide with n+1.

**Why it happens:**
- Hook scripts are independent processes — no shared memory; they communicate to the daemon via socket/file. The daemon must serialize.
- Naive append-to-file logic without flock has classic interleaving bugs.
- SwiftUI `@Published` updates from background threads without `MainActor` cause publish-on-the-wrong-thread exceptions and dropped updates.
- A known Claude Code bug (anthropics/claude-code#9188) reports stale `session_id`/`transcript_path` after `/exit` and `--continue` — the schema isn't always trustworthy as a unique key across the session lifecycle.

**How to avoid:**
- The daemon owns a single serial queue (Swift `DispatchQueue` or actor) for all hook event ingestion. Hook clients write atomically (single `write()` of a length-prefixed JSON message), daemon reads and processes one at a time.
- Use `session_id` + `transcript_path` + `timestamp` as a composite key to deduplicate in case of retries.
- All UI state mutation goes through `@MainActor`.
- Define a maximum coalescing window (e.g., 500ms): if multiple completions arrive within window, they batch into the single widget+counter.
- Stress test: write a script that fires 10 fake hooks in 100ms and verify the badge says "10" and clicking shows all 10 in the list.

**Warning signs:**
- Counter sometimes shows fewer items than expected.
- Click-to-jump occasionally targets the wrong session under load.
- Logs show out-of-order processing.
- Crashes / "publishing changes from background thread" warnings in console.

**Phase to address:** Phase containing daemon IPC architecture + multi-session handling. Concurrency is the kind of thing you cannot reliably bolt on later.

---

### Pitfall 10: AppleScript blocking the main thread → spinning beachball when iTerm2 is busy

**What goes wrong:**
User clicks the widget. The app calls `NSAppleScript(source: ...).executeAndReturnError(...)` on the main thread to focus the iTerm2 tab. iTerm2 is in the middle of rendering a 5MB log file or running a slow tab-switching animation. The AppleScript call blocks for 4 seconds. The widget UI freezes; the cursor goes beachball. The user clicks the widget again, queueing another AppleScript event, making it worse.

**Why it happens:**
- `NSAppleScript.executeAndReturnError` is synchronous and runs the Apple Event RPC inline. The other end (iTerm2) handles events on its own loop and may be busy.
- A buggy iTerm2 state can cause AppleScript to hang for 30+ seconds.
- `osascript` via `Process` has the same issue when called with `waitUntilExit()`.
- SwiftUI button taps run on `MainActor`; sync work in the handler stalls the UI.

**How to avoid:**
- All AppleScript calls run on a background queue (`DispatchQueue.global(qos: .userInitiated)` or `Task.detached`).
- Wrap with a hard timeout (e.g., 2 seconds). If exceeded, surface a non-blocking error and don't retry.
- Debounce widget clicks — disable the tap target for 500ms after a click.
- Show a brief loading indicator on the widget while the focus operation is in flight.

**Warning signs:**
- Beachball after clicking widget.
- Multiple widget clicks queueing up multiple iTerm2 focus operations.

**Phase to address:** Phase containing iTerm2 control implementation.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Use `osascript` via `Process` instead of native `NSAppleScript` / `OSAKit` | Faster to prototype; easy to copy from shell | Process spawn overhead per call (~50-150ms); harder to handle structured errors; unbounded stdout parsing | MVP only; migrate to `NSAppleScript` once API surface is stable |
| Hardcode the `Stop` hook command path in README, ask user to copy-paste into `~/.claude/settings.json` | No installer code | Users mis-edit JSON, miss commas, break their entire Claude config | Acceptable for first preview release with sophisticated users; ship an installer/CLI by v0.2 |
| Ad-hoc sign only, don't document Sequoia "Open Anyway" path | One less README section | New macOS users completely blocked; "the app is broken" reports flood you | Never — the README must include this from day one |
| Single global widget position (no per-display, no per-resolution) | Simpler settings UI | Plug/unplug breaks, multi-monitor users see widget on wrong screen | MVP only if the README explicitly notes limitation |
| Skip `NSAppleEventsUsageDescription` because "it shows the prompt anyway" | Slightly cleaner Info.plist | On 10.14 SDK+, AppleEvents silently fail with -1743; users see broken app, no prompt | Never |
| Store widget click → tab mapping in-memory only (no persistence) | No file format to design | App restart loses all in-flight session mappings; the Claude session that was running becomes unjumpable | Acceptable iff app rarely restarts during use; revisit if users report lost sessions |
| Polling iTerm2 over AppleScript every N seconds for tab list | Simple "current state" model | Battery drain; AppleScript prompts users about constant access; iTerm2 perf hit | Never; use event-driven (hook fires → query once → cache) |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Claude Code `Stop` hook | Returning `exit 2` on hook script error | Always `exit 0` from notifier hooks; reserve non-zero for "this is a config bug user must see" |
| Claude Code `Stop` hook | Heavy work in hook script (AppleScript, network) | Hook = thin client, write JSON to socket, exit. Daemon does the work |
| Claude Code `Stop` hook | Not reading `stop_hook_active` from input JSON | Always read; short-circuit if true to prevent loops |
| Claude Code `Stop` hook | Trusting `session_id` is stable across `/exit --continue` | Treat as best-effort; use composite (session_id + transcript_path + timestamp) for dedupe |
| iTerm2 AppleScript | Sending events on main thread | Always background queue + timeout |
| iTerm2 AppleScript | Looking up tab by index after user reordered tabs | Look up by `tty` or session id, not by position |
| iTerm2 AppleScript | Assuming `current session` is the originating session | Do not rely on "current"; always pass the explicit identifier |
| iTerm2 Python API | Adding it as a dependency for MVP | Skip; AppleScript covers MVP needs and avoids the cookie-acquisition round-trip |
| macOS TCC (Automation) | Triggering the prompt from a hook fired in background | Force the prompt during onboarding via an explicit "Test connection" button in foreground |
| macOS TCC (Automation) | Generic `NSAppleEventsUsageDescription` text | Specific, user-trustworthy text mentioning iTerm2 and the action |
| Apple Silicon code signing | Shipping unsigned (no `codesign`) | Always ad-hoc sign at minimum |
| .dmg distribution | Letting Safari/Chrome attach quarantine xattr without instructions | README must explain "Open Anyway" Sequoia path or `xattr -dr` command |
| `LSUIElement` | Setting it but using SwiftUI `WindowGroup` | Use AppKit `NSPanel` directly for floating UI; LSUIElement + WindowGroup conflicts produce dock-icon flicker |
| `NSPanel` levels | Using `.floating` and expecting it to stay above fullscreen apps | `.floating` doesn't beat fullscreen; needs `.statusBar` or `.screenSaver` level + `.fullScreenAuxiliary` collection behavior |
| `NSPanel` collection behavior | Just `.canJoinAllSpaces` and stopping there | Add `.fullScreenAuxiliary` (display alongside fullscreen apps) and `.stationary` (don't move with Mission Control) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Hook script latency adds to every Claude turn | "Claude feels slow since I installed this" | Thin hook client: <50ms; offload to daemon | Felt at every turn; user notices around >200ms |
| Daemon polls iTerm2 for state every N seconds | Battery, CPU, AppleScript prompts | Event-driven only; query iTerm2 once per hook fire | Felt within hours of first install |
| In-memory list of completed sessions never bounded | Memory grows; old click targets become stale | Ring-buffer (last 50) or drop-on-click | Long-running app (>1 day uptime) |
| AppleScript on main thread | UI beachball during click | Background queue + timeout | Whenever iTerm2 is briefly busy (large logs, animations) |
| Spawning `osascript` for every hook fire | High RAM churn, slow first response | Use `NSAppleScript` (compiled once, reused) or daemon-owned long-lived script handle | At scale: rapid completions, e.g., a project with chained sub-agents |
| Custom NSPanel re-creation per notification | Window flicker, animation glitches | Reuse a single panel instance; update its content | Visible after 5-10 notifications |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Daemon listens on TCP port instead of Unix socket | Other users on the machine can spoof completion events | Use Unix domain socket in `~/Library/Application Support/<bundle>/` with 0600 perms |
| Hook accepts arbitrary `cwd` and renders it in the widget without sanitization | Malicious project name injects newlines / control codes into widget UI | Sanitize: max length, strip non-printable chars, render with text rendering not WebView |
| Storing iTerm2 session IDs / paths in a world-readable location | Other users see what projects are open | Store in user's Application Support, 0700 directory perms |
| Granting AppleScript automation permission and never asking again | TCC permission is per-bundle-id forever; if your bundle is later compromised it controls iTerm2 | Bundle id stable; sign with stable identity; document scope in usage description |
| Logging full `transcript_path` paths in user-visible places | Reveals project paths (privacy) | Log only basename in user-visible UI; full path in debug log only |
| Auto-update over HTTP without signing | MITM can replace .dmg | Defer auto-update entirely (already out-of-scope); when added, use signed manifest |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Showing the widget for every Claude reply (no time threshold) | Notification fatigue; user disables the app | Default 30s threshold (already specced); user-tunable |
| Widget that auto-dismisses after N seconds | User misses the notification — destroys core value | Persist until clicked (already specced); never time out |
| Multiple widgets stacking up across the screen | Visual clutter, blocks user's work | Single widget + counter badge (already specced); list expands on click |
| First-run with no onboarding — straight into "waiting for hook" | User doesn't know hook isn't installed; thinks app is broken | First-run wizard: install hook, test iTerm2 permission, fire test notification |
| Click on widget activates the app, then iTerm2 → flicker | Feels janky; perceived as buggy | Skip self-activation; jump directly to iTerm2 |
| Sound plays during Focus/DND | User uses app in shared spaces / meetings, gets embarrassed | Use UNNotificationCenter for sound (respects Focus) OR provide explicit Focus-aware mute toggle |
| Click on widget jumps to wrong tab, occasionally | Trust collapses; the entire product loses value | Multi-strategy lookup (tty, session_id, cwd) + visible "session not found" fallback |
| Unsigned-app first-run dialog with no in-app guidance | User abandons install before launch | README screenshot of exact Sequoia "Open Anyway" path + .dmg includes "READ FIRST.txt" |
| No way to test "would my widget fire right now?" | User can't validate setup; ghost installs | Menu bar (or hidden CLI) "Test notification" command |
| Hook installation requires hand-editing `~/.claude/settings.json` | High install friction; broken JSON | App-provided installer that merges hook entry safely or generates settings.json snippet to copy |

## "Looks Done But Isn't" Checklist

- [ ] **Floating widget appears:** Verify on a 16" MBP with notch, on an external 4K, after sleep/wake, after lid close/open, after switching Spaces, in fullscreen Safari, in Stage Manager.
- [ ] **Click-to-jump:** Verify with iTerm2 in: split panes, fullscreen, minimized window, on a different Space, after Cmd+W reopened the tab via Cmd+Shift+T.
- [ ] **Hook reliability:** Verify hook fires when Claude session ran inside tmux, inside a venv, with `cd` having been used, after `claude --continue`, after pressing Esc to interrupt.
- [ ] **Permissions flow:** Verify the FIRST install on a fresh user account triggers `NSAppleEventsUsageDescription` prompt and that recovery from "Don't Allow" is documented and reachable from the app.
- [ ] **Distribution:** Download the .dmg from a real URL via Safari on a fresh Mac → drag to /Applications → double-click → confirm the exact dialog the user sees and that the README path matches.
- [ ] **Quarantine:** Verify `xattr -l /Applications/ClaudeAlertBot.app` after fresh install shows `com.apple.quarantine` and the README workaround clears it.
- [ ] **Code sign:** `codesign -dv --verbose=4 /Applications/ClaudeAlertBot.app` shows at minimum `Signature=adhoc`.
- [ ] **Multi-session:** Fire 5 hooks within 100ms — confirm badge counter shows 5, list shows all 5 distinct sessions, click on each jumps to the correct tab.
- [ ] **No focus stealing:** Type in another app while the widget appears — typing must not be interrupted.
- [ ] **No Dock icon, no ⌘-Tab entry:** Verify after every login.
- [ ] **DND / Focus respect:** With Focus on, verify sound is silenced (or that the user's mute preference works).
- [ ] **Settings persistence:** After app restart, threshold/sound/position are preserved.
- [ ] **Hook exit code:** Trigger a forced hook script error → verify Claude Code does NOT enter a "must continue" loop.
- [ ] **Widget position validity:** Unplug external display while widget is positioned on it → confirm widget remains visible (snap back).
- [ ] **Onboarding survives uninstall/reinstall:** `tccutil reset AppleEvents <bundle-id>` then reinstall → permission prompt re-appears at the right time.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| User clicked "Don't Allow" on AppleEvents prompt | LOW | Surface in-app banner with deep link `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`. Document `tccutil reset AppleEvents <bundle-id>` in README. |
| "App is damaged" Gatekeeper error on user's machine | LOW–MEDIUM | README: System Settings → Privacy & Security → "Open Anyway" (Sequoia+). Backup: `xattr -dr com.apple.quarantine /Applications/ClaudeAlertBot.app` in Terminal. |
| Wrong tab focused on click | MEDIUM (trust damage) | Add diagnostic command "Show last hook env" — user copies output to a bug report. Implement multi-strategy lookup (tty, session id, cwd) before adding new features. |
| Hook script breaks Claude session (loops, crashes) | HIGH (user uninstalls) | Hook should `exit 0` even on internal failure. Provide single-command uninstall that strips hook entry from `~/.claude/settings.json`. |
| Widget invisible after display change | LOW | "Reset widget position" menu item / hotkey. Validate restored frame on every startup. |
| TCC permissions corrupted after major macOS update | LOW–MEDIUM | Document `tccutil reset AppleEvents` and `tccutil reset Accessibility` in troubleshooting README. |
| Daemon crashes mid-completion → state lost | LOW | Write completed events to `~/Library/Application Support/.../inbox/` as JSON files; daemon reads on startup. |
| User on macOS 12 (below SMAppService minimum) | MEDIUM | Either gate to macOS 13+ (recommended given Project doc says "현실적으로 13 또는 14 이상") or provide a manual `~/Library/LaunchAgents/*.plist` install script. |
| Concurrent hook race produces miscounted badge | MEDIUM | Daemon uses single-actor / serial queue; add invariant assertions that fire diagnostic logs. |

## Pitfall-to-Phase Mapping

These map to typical roadmap phase shapes. The roadmap planner should treat these as constraints on phase ordering and success criteria, not as the phase list itself.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| #1 Focus stealing | Phase 1 — Floating window foundation | UI test: type in TextEdit while triggering widget; typing not interrupted |
| #2 "App is damaged" / unsigned distribution | Phase 1 build pipeline (set ad-hoc sign) + later Phase that produces .dmg (README) | Download own .dmg from a temp URL on a fresh user account; succeeds with documented steps |
| #3 AppleEvents authorization | Phase that introduces iTerm2 control + onboarding phase | Fresh user account: prompt appears at intended moment; deny path has UI recovery |
| #4 Wrong tab on click | Phase containing session→tab mapping (highest-risk; consider its own phase or research spike) | Beta logging confirms ppid-chain + tty captured for 100% of fires; tmux/venv/nested-shell test matrix passes |
| #5 Hook breaks Claude | Phase containing hook integration | Fault-injection test: corrupt hook config; verify Claude Code still terminates turns normally |
| #6 Notch / multi-display | Phase containing widget placement settings | QA matrix across MBP14/16 + external; state persistence after display reconfig |
| #7 Sound during Focus/DND | Phase containing notification/sound feature | Manual: Focus on → trigger → sound silenced (or explicit mute setting works) |
| #8 SMAppService silent failure | Phase introducing "Launch at login" (likely later milestone) | After enable + reboot, app appears; toggle reflects `SMAppService.mainApp.status` |
| #9 Concurrent hook races | Phase containing daemon IPC + multi-session UX | Stress test: 10 hooks in 100ms; counter exact, all distinct, click order preserved |
| #10 AppleScript blocking main thread | Phase containing iTerm2 control | UI never beachballs; AppleScript timeout enforced |

## Sources

- [SwiftUI Floating Panel: NSPanel Patterns for macOS Apps — fazm.ai](https://fazm.ai/blog/swiftui-floating-panel)
- [Fine-Tuning macOS App Activation Behavior — artlasovsky.com](https://artlasovsky.com/fine-tuning-macos-app-activation-behavior)
- [SwiftUI Menu Bar App With a Floating Window: Best Practices — fazm.ai](https://fazm.ai/blog/swiftui-menu-bar-app-floating-window-best-practices)
- [Nailing the Activation Behavior of a Spotlight / Raycast-Like Command Palette — Multi blog](https://multi.app/blog/nailing-the-activation-behavior-of-a-spotlight-raycast-like-command-palette)
- [nonactivatingPanel — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
- [Hooks reference — Claude Code Docs](https://code.claude.com/docs/en/hooks)
- [Claude Code Hook Control Flow — Steve Kinney](https://stevekinney.com/courses/ai-development/claude-code-hook-control-flow)
- [Claude Code Hooks: Complete Guide to All 12 Lifecycle Events — claudefa.st](https://claudefa.st/blog/tools/hooks/hooks-guide)
- [BUG: Hooks receive stale session_id and transcript_path after /exit and --continue — anthropics/claude-code#9188](https://github.com/anthropics/claude-code/issues/9188)
- [claude-code-hooks-schemas.md (gist)](https://gist.github.com/FrancisBourre/50dca37124ecc43eaf08328cdcccdb34)
- [macOS 15.1 completely removes ability to launch unsigned applications — MacRumors Forums](https://forums.macrumors.com/threads/macos-15-1-completely-removes-ability-to-launch-unsigned-applications.2441792/)
- [Run xattr -r -d com.apple.quarantine on casks on Apple Silicon — Homebrew/brew#17979](https://github.com/Homebrew/brew/issues/17979)
- [Apple Forces The Signing Of Applications In MacOS Sequoia 15.1 — Hackaday](https://hackaday.com/2024/11/01/apple-forces-the-signing-of-applications-in-macos-sequoia-15-1/)
- [Gatekeeper and notarization in Sequoia — The Eclectic Light Company](https://eclecticlight.co/2024/08/10/gatekeeper-and-notarization-in-sequoia/)
- [macOS Sequoia: Bypassing Gatekeeper to install unsigned apps — TechBloat](https://www.techbloat.com/macos-sequoia-bypassing-gatekeeper-to-install-unsigned-apps.html)
- [Permissions on Mojave: Not authorized to send Apple events to iTerm — Hammerspoon/hammerspoon#2031](https://github.com/Hammerspoon/hammerspoon/issues/2031)
- [Avoiding AppleScript Security and Privacy Requests — Scripting OS X](https://scriptingosx.com/2020/09/avoiding-applescript-security-and-privacy-requests/)
- [iTerm2 Python API Security](https://iterm2.com/python-api-auth.html)
- [iTerm2 Scripting Documentation](https://iterm2.com/documentation-scripting.html)
- [iTerm2 Variables Documentation](https://iterm2.com/documentation-variables.html)
- [NSAppleEventsUsageDescription — Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)
- [Apple Events Usage Description — Michael Tsai](https://mjtsai.com/blog/2018/08/23/apple-events-usage-description/)
- [Executing AppleScript in a Mac app on macOS Mojave — Jesse Squires](https://www.jessesquires.com/blog/2018/11/17/executing-applescript-in-mac-app-on-macos-mojave/)
- [SMAppService — Apple Developer Documentation](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [macOS Service Management - The SMAppService API — theevilbit](https://theevilbit.github.io/posts/smappservice/)
- [Add launch at login setting to a macOS app — nilcoalescing.com](https://nilcoalescing.com/blog/LaunchAtLoginSetting/)
- [LaunchAtLogin-Legacy — sindresorhus](https://github.com/sindresorhus/LaunchAtLogin-Legacy)
- [How to fix Mac menu bar icons hidden by the MacBook notch — Jesse Squires](https://www.jessesquires.com/blog/2023/12/16/macbook-notch-and-menu-bar-fixes/)
- [Escaping the notch: Tailscale's new macOS home](https://tailscale.com/blog/macos-notch-escape)
- [safeAreaInsets — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets)
- [NSWindow.CollectionBehavior — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
- [stationary — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior/1419188-stationary)
- [fullScreenAuxiliary — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)
- [Notifications do not respect focus mode on macOS — Mailspring Community](https://community.getmailspring.com/t/notifications-do-not-respect-focus-mode-on-macos/9737)
- [Do not disturb/focus mode doesn't work — MacRumors Forums](https://forums.macrumors.com/threads/do-not-disturb-focus-mode-doesnt-work-still-getting-sound-notifications-why.2387717/)
- [Build a macOS menu bar utility in SwiftUI — nilcoalescing.com](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)
- [Claude Code Hooks + tmux pane auto-focus setup (gist)](https://gist.github.com/grmkris/85a9b8b0cbdffaa752d2fcc4ae619dcd)

---
*Pitfalls research for: macOS native floating-widget Claude Code companion (unsigned distribution, iTerm2 integration)*
*Researched: 2026-05-07*
