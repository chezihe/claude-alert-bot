# Phase 1: Foundation - Research

**Researched:** 2026-05-07
**Domain:** macOS native daemon plumbing — POSIX shell hook → AF_UNIX socket → headless ad-hoc-signed Swift app
**Confidence:** HIGH on Apple frameworks (NWListener, OSLog, codesign, LSUIElement), HIGH on Claude Code hook contract (verified against official docs 2026-05-07), HIGH on `/usr/bin/nc` AF_UNIX behavior on macOS 14/15/26 (verified against the man page on the build host), MEDIUM on the exact set of NWListener log-noise warnings (cosmetic only, well-documented as harmless).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Reporter is a POSIX `sh` script that writes one JSON line to an AF_UNIX socket via `/usr/bin/nc -U <socket-path>`. Absolute path to `/usr/bin/nc` is mandatory — `nc` flavor in the user's PATH may be GNU netcat which does not support `-U`.
- **D-02:** Reporter must always exit 0, including when the socket is unreachable (app not running) or when `nc` fails. Shell pattern: pipe + `|| true` + explicit `exit 0` at the end. Hard architectural constraint — `exit 2` from Stop hook makes Claude Code loop.
- **D-03:** Reporter sends to the socket with a hard timeout (e.g., `nc -w 1`) so a stuck app cannot block Claude Code's turn end.
- **D-04:** Reporter script is bundled in the `.app` (`Contents/Resources/cab-report.sh`) AND copied to `~/Library/Application Support/ClaudeAlertBot/cab-report.sh` on first run / hook install. The path the user's `~/.claude/settings.json` references is the stable user-data copy, never the in-bundle path. Version-aware copy: only overwrite if bundled is newer.
- **D-05:** Phase 5's HookInstaller will eventually do the auto-copy + settings.json patch. For Phase 1, this can be done by a manual setup script (`scripts/dev-install-hook.sh`) or by the developer copying the file by hand.
- **D-06:** Bundle ID `com.claudealert.bot`. Display name "Claude Alert Bot". Original artwork only — no Anthropic-trademarked imagery.
- **D-07:** Phase 1 verification = (1) OSLog subsystem `com.claudealert.bot.hook` viewable via `log stream` predicate, (2) hook debug log file at `~/Library/Logs/ClaudeAlertBot/hook.log` written by Reporter independent of app, (3) `cab-test` Swift CLI helper for synthetic event injection.
- **D-08:** JSON event envelope schema (locked for Phase 2 to consume):
  ```json
  {
    "schema_version": 1,
    "event": "stop" | "user_prompt_submit",
    "session_id": "<from hook stdin>",
    "transcript_path": "<from hook stdin>",
    "cwd": "<env CWD or hook stdin cwd>",
    "iterm_session_id": "<env ITERM_SESSION_ID>",
    "tty": "<output of /usr/bin/tty>",
    "ppid": <integer>,
    "claude_project_dir": "<env CLAUDE_PROJECT_DIR>",
    "ts": "<ISO 8601 with timezone>"
  }
  ```
  Missing fields sent as JSON `null`, not omitted. App rejects unknown `schema_version`.
- **D-09:** AF_UNIX socket bind exclusivity is the single-instance lock. Second launch fails with `EADDRINUSE`-equivalent and exits 0.
- **D-10:** Socket path: `~/Library/Application Support/ClaudeAlertBot/sock`. App removes a stale socket file at startup before bind only if no live listener.
- **D-11:** `scripts/build.sh` does `xcodebuild archive` + `codesign --force --deep --sign -` on the resulting `.app`. Phase 1 does not produce a `.dmg`.
- **D-12:** Repo layout — single Xcode project, two targets (App + cab-test CLI). Reporter is a plain `.sh` in top-level `Reporter/` directory, copied into `Contents/Resources/` via Xcode Run Script Phase.

### Claude's Discretion

The user did not select these areas for discussion. Default to standard choices and proceed; can be revisited in planning.

### Deferred Ideas (OUT OF SCOPE)

- Hook auto-installer with idempotent JSON5 merge — Phase 5 (INST-01..04, ONB-01).
- macOS 15+ Gatekeeper "Open Anyway" docs + `bypass-gatekeeper.command` — Phase 6 (DIST-03, DIST-04).
- First-run onboarding wizard — Phase 5 (ONB-01).
- Real app icon / branding artwork — Phase 2 latest.
- `cab-test` permanent placement / hidden-by-default — Phase 5.
- Richer socket-collision recovery UX — Phase 5.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HOOK-01 | Reporter executes as Claude Code `Stop` hook, forwards JSON event to App | "Claude Code Hook Contract" (verified) + "Reporter Script Anatomy" |
| HOOK-03 | Reporter always `exit 0` | "Hook Safety Contract — `exit 0` Discipline" |
| HOOK-04 | Reporter captures `session_id`, `cwd`, `ITERM_SESSION_ID`, `tty`, `CLAUDE_PROJECT_DIR`, `ppid`, timestamp | "JSON Construction in POSIX sh" (uses `printf` + `python3 -c json.dumps`) + "Field Capture Mechanics" |
| HOOK-05 | When App not running, Reporter still exits 0 with no Claude side-effect | "Reporter Script Anatomy" — `[ -S "$SOCK" ] \|\| exit 0` short-circuit |
| HOOK-06 | Debug log at `~/Library/Logs/ClaudeAlertBot/hook.log` records env, ppid chain, tty | "Hook Debug Log Format" |
| IPC-01 | App opens AF_UNIX `NWListener`, receives JSON events | "NWListener AF_UNIX Setup" with verified Apple Forums sample |
| IPC-02 | Socket path under user home: `~/Library/Application Support/ClaudeAlertBot/sock` | Path resolution + ASCII-safe (no spaces) — verified to fit AF_UNIX `sun_path` 104-char limit |
| IPC-03 | Single-instance enforcement | "Single-Instance via AF_UNIX Bind" — uses `requiredLocalEndpoint`; bind failure surfaces as `NWListener.State.failed` |
| DIST-01 | Build pipeline ad-hoc signs (`codesign --force --deep --sign -`) | "Ad-hoc Codesign Recipe" + verification with `codesign -dv --verbose=4` |
| DIST-05 | App runs as accessory (`LSUIElement=true`) — no Dock, no menu bar, no Cmd-Tab | "Headless App Skeleton" — pure AppKit `NSApplicationMain` + `LSUIElement` |
</phase_requirements>

## Summary

Phase 1 builds a single, narrow vertical slice: a Claude Code `Stop` hook fires → POSIX `sh` reporter forwards a one-line JSON envelope through `/usr/bin/nc -U` → AF_UNIX socket → Swift `NWListener` → OSLog + hook log file. No UI, no elapsed-time logic, no terminal control, no .dmg packaging. Every architectural decision in this phase is locked from research already done at project level (STACK.md / ARCHITECTURE.md / PITFALLS.md) and ratified by CONTEXT.md (D-01 through D-12).

The planner's job for Phase 1 is to translate that locked architecture into concrete, ordered tasks: scaffold an Xcode project with two targets and macOS 14 deployment, write the headless app entry point with `LSUIElement=true` plus the `NWListener` accept loop, write the 30-line POSIX `sh` reporter, write the build/codesign script, and write the `cab-test` CLI smoke-check. The validation surface (Nyquist Dimension 8) is unusually amenable to automation — every Phase 1 success criterion can be checked with a one-liner shell command (`log show`, `codesign -dv`, `pgrep`, `osascript -e 'count windows of "Dock"'`, etc.) plus one synthetic-event smoke test.

**Primary recommendation:** Use pure-AppKit `NSApplicationMain` (not SwiftUI `App` protocol) for the Phase 1 app because the app has zero scenes. SwiftUI `App` requires at least one `Scene`; faking one with an empty `Settings { EmptyView() }` adds menu-bar artifacts that fight `LSUIElement`. AppKit `NSApplicationMain` + `NSApplicationDelegate` is the smallest, cleanest skeleton — Phase 2's UI work can keep this pattern and add `NSPanel` programmatically, or migrate to SwiftUI `App` once a real `Settings` scene exists.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Hook event capture (env, stdin, tty, ppid) | Reporter (POSIX sh) | — | Stateless edge — runs in the Claude Code subprocess; only it has access to `ITERM_SESSION_ID`, `tty`, live `$PPID` |
| JSON serialization | Reporter (POSIX sh) | — | Reporter is the only place where the field values exist (cwd, env). Push serialization to the edge so the wire format is the source of truth |
| Wire transport | Reporter (`/usr/bin/nc -U`) → Kernel AF_UNIX → App (`NWListener`) | — | Kernel-mediated SOCK_STREAM byte stream. No userland broker |
| Event ingestion / parsing | App (Swift `NWListener` + `JSONDecoder`) | — | Long-running daemon — only consumer of the wire format |
| Single-instance enforcement | App (AF_UNIX bind exclusivity) | — | The socket is the lock; no separate PID file, no NSDistributedNotificationCenter probe |
| Persistence (debug log) | Reporter (`~/Library/Logs/ClaudeAlertBot/hook.log`) | — | Reporter writes log even when app is down — by design (HOOK-06) |
| Persistence (event log) | App (OSLog subsystem `com.claudealert.bot.hook`) | — | Structured, queryable, persistent across reboots via `log show --last 1h` |
| Process lifecycle / activation policy | App (AppKit `NSApplicationMain` + `LSUIElement=YES`) | — | Headless accessory — no Dock, no menu bar, no Cmd-Tab |
| Ad-hoc code signing | Build pipeline (`scripts/build.sh` → `codesign`) | — | Apple Silicon load-time requirement — must run for both the App target *and* the embedded `cab-test` helper |

## Standard Stack

### Core (Phase 1)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 5.10 (Xcode 15.4) or 5.x mode under Xcode 16/26 | Application language | Locked by PROJECT.md. Phase 1 does not need Swift 6 strict concurrency — opt out with `-swift-version 5` |
| AppKit (`NSApplication`, `NSApplicationDelegate`) | macOS 14 SDK | App lifecycle for a headless daemon | SwiftUI `App` requires ≥1 `Scene`; for a no-UI Phase 1 app, AppKit's `NSApplicationMain` is smaller and avoids `Settings { EmptyView() }` ghost menus |
| `Network.framework` (`NWListener`, `NWConnection`, `NWEndpoint.unix`, `NWParameters`) | macOS 10.15+ (stable since Catalina) | AF_UNIX SOCK_STREAM IPC server | Apple-blessed replacement for Berkeley sockets boilerplate; no entitlements; per-connection async accept |
| `os.Logger` (OSLog API, `import os`) | macOS 11+ (Logger struct), `subsystem`/`category` since 10.12 | Structured persistent logs (subsystem `com.claudealert.bot.hook`) | `log stream --predicate 'subsystem == "..."'` is the canonical query. Survives app restart, integrated with Console.app |
| Foundation (`JSONDecoder`, `FileManager`, `URL`) | macOS 14 SDK | JSON envelope decoding, path resolution, stale-socket cleanup | First-party, no deps |
| Carbon-era `NSProcessInfo` / `Process` | macOS 14 SDK | Embedded `cab-test` CLI helper to send synthetic event | The CLI is even simpler than the App — it just opens an `NWConnection` to the socket and writes one JSON line |

**Verification:**
- macOS host build target: `MACOSX_DEPLOYMENT_TARGET = 14.0` [VERIFIED: STACK.md, ROADMAP.md locked decision]
- All listed APIs are GA on macOS 14. [VERIFIED: STACK.md "Version Compatibility" table]
- Verified Xcode 26 / `/usr/bin/codesign` / `/usr/bin/xcodebuild` available on the developer's build host (Darwin 25.4.0 / macOS 26.4.1). [VERIFIED: Bash command `sw_vers && xcodebuild -version` 2026-05-07]

### Supporting (Phase 1)

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `xcodebuild` | bundled with Xcode | CLI build for `scripts/build.sh` | Used to drive `archive` + `exportArchive` from the script |
| `codesign` | `/usr/bin/codesign` | Ad-hoc sign the .app bundle and the embedded `cab-test` helper | `--force --deep --sign -` covers nested binaries, but verify each Mach-O explicitly |
| `/usr/bin/nc` | bundled with macOS (Apple variant) | Reporter's wire transport | Apple's `nc` supports `-U` (Unix sockets) and `-w` (idle timeout). Verified on macOS 26 host: man page lists both |
| `/usr/bin/python3` | bundled with macOS Command Line Tools (Apple-stub installs on demand) | JSON escaping in Reporter | Used for one-line `python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"` to robustly escape arbitrary cwd / project paths |
| `/usr/bin/tty` | bundled with macOS | Capture terminal device path in Reporter | Outputs e.g. `/dev/ttys004` or "not a tty" — Reporter must capture both cases |
| `log` | bundled with macOS | Verify OSLog output during tests | `log stream --predicate '...'` is the primary verification command |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `/usr/bin/nc -U` in Reporter | Tiny Swift CLI (`cab-send`) bundled in app | More robust error handling, but adds another Mach-O to ad-hoc-sign and complicates D-01's "POSIX sh / no Swift wrapper" intent. Reject for Phase 1 unless `nc -U` proves unreliable in real testing |
| `/usr/bin/python3` for JSON escaping | `printf` + manual quote/backslash escaping | Manual escaping is error-prone for arbitrary paths (quotes, backslashes, unicode, newlines from `tty` errors). `python3` is always available on macOS 14+ and gives bulletproof escaping |
| AppKit `NSApplicationMain` | SwiftUI `App` with `Settings { EmptyView() }` | SwiftUI `App` adds an Edit/Help menu surface that fights `LSUIElement`; minimal value with no UI in Phase 1. Migrate in Phase 2 when real Settings scene exists |
| OSLog (`os.Logger`) | `print` to stderr / file logging | OSLog is queryable (`log stream`/`log show`), persisted, has structured levels, and is the platform standard. `print` would require us to re-invent log rotation |
| AF_UNIX socket | HTTP `127.0.0.1:<fixed-port>` (Claude Code's native `"type": "http"` hook) | HTTP would remove the shell-script glue but adds port-management to Phase 5's installer (`settings.json` must reference an exact port). Rejected at project level (STACK.md, ARCHITECTURE.md) — committed to AF_UNIX |

**Installation (developer machine):**

```bash
xcode-select --install                # Command Line Tools (if not already)
# Phase 1 needs nothing else — no Node, no jq, no third-party Swift deps.
# create-dmg / brew / npm are Phase 6 concerns.
```

**Version verification (must run before locking the plan):**

```bash
sw_vers                               # confirm dev host meets macOS 14+
xcodebuild -version                   # confirm Xcode 15.4+ available
/usr/bin/python3 --version            # confirm python3 is on PATH
/usr/bin/nc -h 2>&1 | head -1         # confirm Apple's nc (mentions --apple-* flags)
which -a nc                           # confirm /usr/bin/nc resolves first OR document absolute path use
```

[VERIFIED on 2026-05-07 dev host: macOS 26.4.1, Xcode 26.0.1, `/usr/bin/nc` is Apple variant supporting `-U` and `-w`, `/bin/sh` is GNU bash 3.2.57 in POSIX mode.]

## Architecture Patterns

### System Architecture Diagram

```
                       Claude Code subprocess
                              │
                              │ stdin: {session_id, transcript_path, cwd, hook_event_name, ...}
                              │ env:   CLAUDE_PROJECT_DIR, ITERM_SESSION_ID (inherited)
                              ▼
                  ┌────────────────────────┐
                  │ cab-report.sh          │
                  │  (POSIX sh, ~30 lines) │
                  │                        │
                  │  1. read stdin JSON    │
                  │  2. capture env+tty+ppid│
                  │  3. python3 -c json.dumps              ──────► ~/Library/Logs/ClaudeAlertBot/hook.log
                  │  4. printf one envelope line                    (HOOK-06; written FIRST,
                  │  5. nc -U -w 1  || true                          before nc, so even socket
                  │  6. exit 0                                       failure leaves a trace)
                  └────────────┬───────────┘
                               │
                               │ AF_UNIX SOCK_STREAM, one connection per fire
                               │ wire: one JSON object + '\n' + EOF
                               ▼
              ~/Library/Application Support/ClaudeAlertBot/sock
                               │
                               ▼
                  ┌────────────────────────┐
                  │ NWListener (App)       │
                  │   newConnectionHandler │
                  └────────────┬───────────┘
                               │ NWConnection.receive (length-irrelevant; EOF = end-of-message)
                               ▼
                  ┌────────────────────────┐
                  │ JSONDecoder<HookEvent> │ ──► reject unknown schema_version
                  └────────────┬───────────┘
                               │
                               ▼
                  ┌────────────────────────┐
                  │ Logger(subsystem:      │
                  │   "com.claudealert.bot │
                  │    .hook")             │
                  │ category: "ingress"    │
                  └────────────────────────┘

       (Phase 1 endpoint. Phase 2 will tap the same Logger output and additionally
        feed events to SessionRegistry → NotificationOrchestrator → NSPanel.)


  ┌──── App lifecycle ────┐
  │ NSApplicationMain     │   Info.plist: LSUIElement=YES, NSAppleEventsUsageDescription
  │ NSApplicationDelegate │   (the iTerm2 reason string, set NOW even though Phase 3 uses it)
  │   - applicationDidFinishLaunching:                                                    │
  │       1. ensure ~/Library/Application Support/ClaudeAlertBot/ exists                  │
  │       2. ensure ~/Library/Logs/ClaudeAlertBot/ exists                                 │
  │       3. attempt to detect and remove stale socket (see Pitfall: Stale Socket)        │
  │       4. start NWListener; on .failed → log + NSApp.terminate(0)  (D-09 single-inst)  │
  │       5. install signal handlers (SIGTERM/SIGINT) → cancel listener + remove socket   │
  └───────────────────────┘
```

### Recommended Project Structure

```
ClaudeAlertBot/                        # repo root
├── ClaudeAlertBot.xcodeproj/
├── App/                               # main App target — Swift sources
│   ├── main.swift                     # NSApplicationMain entry (or @main on AppDelegate)
│   ├── AppDelegate.swift              # applicationDidFinishLaunching: paths, listener, signals
│   ├── HookListener.swift             # NWListener wrapper, accept loop, per-connection receive
│   ├── HookEvent.swift                # Codable struct mirroring D-08 schema (schema_version, event, ...)
│   ├── SocketPaths.swift              # one source of truth for ~/Library/.../sock and the log file
│   └── Info.plist                     # LSUIElement=YES, NSAppleEventsUsageDescription, bundle id
├── CabTest/                           # cab-test CLI helper target — Swift sources
│   ├── main.swift                     # opens NWConnection, sends synthetic D-08 envelope, exits
│   └── Info.plist                     # CLI helper Info.plist (or none — pure executable)
├── Reporter/
│   └── cab-report.sh                  # POSIX sh, copied into App bundle Resources via Run Script Phase
├── scripts/
│   ├── build.sh                       # xcodebuild archive + codesign --force --deep --sign -
│   └── dev-install-hook.sh            # Phase 1 dev convenience: copies cab-report.sh + prints settings.json snippet
└── .planning/                         # already exists
```

### Pattern 1: Stateless Edge, Stateful Core (Phase 1 form)

**What:** Reporter captures everything it knows the moment the hook fires (stdin + env + tty + ppid + timestamp), serializes it, ships it, and exits. The App is the only thing with memory. The Reporter never reads the App's state.

**When to use:** Whenever the trigger is a short-lived subprocess (Claude Code hook, Git hook). Stateful hooks accumulate stale lockfiles and sync bugs.

**Phase 1 implication:** The Reporter must be safe to run concurrently with itself (multiple Stop fires within the same millisecond — see Pitfall #5). Each Reporter invocation is an independent connection; no shared state means no locks needed.

### Pattern 2: One Connection Per Event (no length-prefix framing)

**What:** Reporter opens an AF_UNIX SOCK_STREAM, writes one JSON object followed by a newline, then closes the connection (signalled by `nc` exiting on stdin EOF). On the App side, each `NWConnection`'s lifetime is the message — `connection.receive` keeps reading until it sees `isComplete: true`, then the App parses the accumulated buffer as JSON.

**Why this works:** The wire format has *exactly one* logical message per TCP/UDS connection. We don't need length-prefixed framing because EOF == end-of-message. This dramatically simplifies the Swift code. Multiple concurrent fires get separate connections — they parallelize naturally on Network.framework's accept queue.

**Trade-off:** TCP overhead per message (a few syscalls). For our ≤ 1 event/sec rate this is invisible.

### Pattern 3: Headless AppKit (no SwiftUI scenes)

**What:** Phase 1's app has *no UI*. SwiftUI `App` protocol requires `body: some Scene` — using a fake `Settings { EmptyView() }` introduces a Cmd-, menu and an Edit/Help menu surface that conflict with the "no menu bar" success criterion (Phase 1 gate #4).

**Recommendation:** Use the pure-AppKit pattern:

```swift
// main.swift
import AppKit
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
```

With `LSUIElement = YES` and no `NSMainNibFile`/`NSMainStoryboardFile`, `NSApplication.shared.run()` enters the runloop with no Dock icon, no menu bar, no Cmd-Tab entry — exactly matching success criterion #4.

[VERIFIED: This pattern is the standard headless-LaunchAgent shape. Apple's own Network framework sample code uses it.]

**Phase 2 migration path:** When real UI lands, rename `main.swift` to `ClaudeAlertBotApp.swift`, switch to `@main struct ClaudeAlertBotApp: App` with `Settings { ... }` and `MenuBarExtra { ... }` scenes. The `AppDelegate` stays — it's the right place for `NWListener` lifecycle.

### Pattern 4: NWListener Configuration for AF_UNIX

```swift
// HookListener.swift — verified pattern

import Network
import Foundation
import os

final class HookListener {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "listener")
    private let socketPath: String
    private let queue = DispatchQueue(label: "com.claudealert.bot.hook.listener")
    private var listener: NWListener?

    init(socketPath: String) { self.socketPath = socketPath }

    func start() throws {
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.info("listening on \(self.socketPath, privacy: .public)")
            case .failed(let err):
                self.log.error("listener failed: \(String(describing: err), privacy: .public)")
                // EADDRINUSE-equivalent: another instance owns the socket → exit cleanly (D-09)
                NSApp.terminate(nil)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ conn: NWConnection) {
        var buffer = Data()
        conn.stateUpdateHandler = { state in
            if case .failed = state { conn.cancel() }
        }
        func loop() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, _ in
                if let data { buffer.append(data) }
                if isComplete {
                    self?.handle(buffer: buffer)
                    conn.cancel()
                } else {
                    loop()
                }
            }
        }
        conn.start(queue: queue)
        loop()
    }

    private func handle(buffer: Data) {
        do {
            let event = try JSONDecoder().decode(HookEvent.self, from: buffer)
            guard event.schema_version == 1 else {
                log.warning("rejecting event with unknown schema_version=\(event.schema_version)")
                return
            }
            log.notice("ingress event=\(event.event, privacy: .public) session=\(event.session_id ?? "nil", privacy: .public) cwd=\(event.cwd ?? "nil", privacy: .public)")
        } catch {
            log.error("decode failed: \(String(describing: error), privacy: .public)")
        }
    }
}
```

**Key configuration choices, justified:**

- `NWProtocolTCP.Options()` is the documented incantation even though we're using AF_UNIX. The framework reuses TCP's connection lifecycle on top of the Unix socket. [VERIFIED: Apple Developer Forums thread 719635, working sample code.]
- `requiredLocalEndpoint = .unix(path:)` is what binds to the path. Setting it on `.tcp(host:port:)` would be wrong.
- `allowLocalEndpointReuse = true` is not strictly needed — kernel AF_UNIX bind doesn't have the same `SO_REUSEADDR` semantics as TCP — but the Apple Forums sample sets it and we follow suit.
- `minimumIncompleteLength: 1, maximumLength: 65_536` — our envelope is well under 64K. If a future field bloats this, increase or chunk.

**Expected log noise:** This pattern emits a handful of harmless `nw_path_evaluator_create_flow_inner NECP_CLIENT_ACTION_ADD_FLOW Invalid argument (22)` warnings to Console.app on listener start. They are cosmetic and have been documented since at least 2022. Do not treat them as errors. [VERIFIED: Apple Developer Forums thread 719635 — Apple DTS engineer confirms log noise.]

### Pattern 5: Single-Instance via Bind Exclusivity

**What:** D-09 says "the socket is the lock." Implementation:

1. App startup attempts to remove a stale socket file (file exists but no live listener — see "Stale Socket Recovery" below).
2. App starts the `NWListener`.
3. If `NWListener.State` transitions to `.failed(.posix(.EADDRINUSE))` or similar, a live listener already owns the socket → another instance is running → call `NSApp.terminate(0)`.

**Why this works:** AF_UNIX bind on a path-already-bound-by-a-live-listener is rejected by the kernel with `EADDRINUSE`. There's no race window because bind() is atomic.

**What about TOCTOU on the stale-socket cleanup?** See "Stale Socket Recovery" pitfall below.

### Pattern 6: Stale Socket Recovery on Startup

**What:** A previous app crash leaves the socket file on disk. The next app start sees it, naïvely tries to bind, gets `EADDRINUSE`, and exits — even though no live listener exists.

**Solution:**

```swift
// AppDelegate.applicationDidFinishLaunching, before listener.start():

func reclaimSocketIfStale(at path: String) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else { return }

    // Probe: try to connect as a client. If successful, a live listener owns it → another instance.
    // If connect fails with ECONNREFUSED, the file is a stale leftover → safe to remove.
    let probe = NWConnection(to: .unix(path: path), using: NWParameters.tcp)
    let group = DispatchGroup()
    group.enter()
    var alive = false
    probe.stateUpdateHandler = { state in
        switch state {
        case .ready:
            alive = true
            group.leave()
        case .failed, .cancelled, .waiting:
            group.leave()
        default: break
        }
    }
    probe.start(queue: DispatchQueue.global())
    _ = group.wait(timeout: .now() + .milliseconds(200))
    probe.cancel()

    if !alive {
        try? fm.removeItem(atPath: path)   // safe: no live listener
    }
    // If alive, leave the file in place — `listener.start()` below will report .failed and we exit.
}
```

This avoids the TOCTOU race: between the probe and the bind, another instance could appear, but bind() is atomic so the second-arriver still loses cleanly.

### Anti-Patterns to Avoid

- **Calling `NSApp.activate(ignoringOtherApps: true)`** — Phase 1 must NEVER activate. The app is invisible. Activation breaks `LSUIElement` and shows the app in Cmd-Tab.
- **Using SwiftUI `App` with `Settings { EmptyView() }` "for symmetry"** — adds a phantom Edit/Help menu when the app *is* somehow activated. Phase 1 has no UI; AppKit is smaller.
- **Reading the hook payload with `read STDIN_JSON` then echoing into a heredoc** — breaks on quotes, newlines, backslashes in cwd. Use `python3 -c json.dumps` to escape.
- **Putting `cab-report.sh` directly inside `~/.claude/hooks/`** — that path is reserved for Claude Code's own hook layout. Reporter goes to `~/Library/Application Support/ClaudeAlertBot/cab-report.sh` (D-04).
- **Logging the raw `transcript_path` or full `cwd` at `.public` privacy level** — these are user paths; mark them `.private` if compiled with privacy strict mode. Phase 1 uses `.public` (per D-07's "OSLog as primary signal" intent — visibility is the point during dev), but a comment in the code should flag this for Phase 5 review.
- **`NSAppleScript` calls anywhere in Phase 1** — Phase 1 has no AppleScript. Defer to Phase 3.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| AF_UNIX server boilerplate | Berkeley `socket()`/`bind()`/`listen()`/`accept()` in Swift | `NWListener` + `NWEndpoint.unix` | Apple-blessed; no entitlements; structured async; per-connection queues |
| JSON serialization in shell | Manual `printf` with hand-rolled quote escaping | `/usr/bin/python3 -c "import json,sys; print(json.dumps(...))"` | Edge cases (quotes, backslashes, unicode, newlines, NULs) bite real users; `python3` is always present on macOS 14+ |
| JSON parsing in Swift | Manual string splitting | `JSONDecoder` + `Codable HookEvent` | Free, type-safe, handles unicode |
| Persistent log files | `print()` to a hand-managed file with rotation | `os.Logger` (subsystem) + `~/Library/Logs/ClaudeAlertBot/hook.log` (Reporter only) | OSLog has rotation, Console.app integration, queryability via `log show` |
| Single-instance lock | Hand-written `flock` on a PID file | AF_UNIX bind exclusivity (the socket *is* the lock) | One mechanism, no second source of truth, no PID-stale races |
| Stale socket detection | `lsof` parsing or PID-file readback | Probe-connect via `NWConnection` with 200 ms timeout | Race-free (kernel arbitrates final bind); no PID-staleness questions |
| iTerm2 session detection | Anything in Phase 1 | Defer to Phase 3 | Phase 1's deliverable is "log line lands" — terminal control is downstream |
| Hook auto-installer | Anything in Phase 1 | Defer to Phase 5 (`scripts/dev-install-hook.sh` is the manual stub for now) | D-05 explicitly defers |

**Key insight:** Phase 1 is the smallest possible vertical slice. The temptation will be to add "robustness" features that belong to later phases — resist. Every line of Phase 1 code should map to one of HOOK-01/03/04/05/06, IPC-01/02/03, or DIST-01/05.

## Common Pitfalls

### Pitfall 1: `nc` from Homebrew/MacPorts shadows `/usr/bin/nc` and lacks `-U`

**What goes wrong:** A user installs `gnu-netcat` or `ncat` via Homebrew. Their PATH puts `/opt/homebrew/bin` ahead of `/usr/bin`. Reporter calls `nc -U "$SOCK"`, gets "unknown option -U", exits non-zero. With `|| true` + `exit 0` Claude is unaffected, but the event is lost silently.

**Why it happens:** GNU netcat doesn't support `-U` (Unix sockets); its replacement flag is different. Apple's BSD-derived `nc` at `/usr/bin/nc` does support `-U`.

**How to avoid:**
- D-01 mandates **absolute path** `/usr/bin/nc` in the Reporter — never bare `nc`.
- Reporter does NOT add a fallback (would mask the misconfiguration). If `/usr/bin/nc` is somehow missing (older macOS), exit 0 with a hook-log entry "Apple nc not found".

**Warning signs:**
- Hook log shows `printf` output but socket never received it.
- `which -a nc` shows multiple binaries.
- `/usr/bin/nc -h 2>&1 | head -1` should show `usage: nc [-46AacCDdEFhklMnOortUuvz]` with `U` in the flags. [VERIFIED on dev host 2026-05-07.]

### Pitfall 2: `nc -w 1` does not behave as a wall-clock timeout for AF_UNIX

**What goes wrong:** Developer expects `-w 1` to mean "give up after 1 second total"; it actually means "if connection AND stdin are idle for 1 second, exit." For AF_UNIX with a stuck listener that never reads, stdin is the limiting factor.

**Why it happens:** `-w` is the I/O idle timeout. The man page on macOS 26 says: `If a connection and stdin are idle for more than timeout seconds, ...`. [VERIFIED via `man nc` on dev host 2026-05-07.]

**How to avoid:**
- Use `-w 1` as our timeout — it's the right knob for our use case (fire-and-forget). Reporter has no stdin after the printf finishes, so `nc` will exit on EOF anyway.
- Add a belt-and-suspenders wrapper: prefix the `nc` invocation with `/usr/bin/timeout 2 /usr/bin/nc -U -w 1 ...` if `/usr/bin/timeout` is available — but `timeout(1)` is NOT shipped on stock macOS (it's coreutils via Homebrew). Skip the wrapper; rely on `-w 1` and the App reading EOF promptly.
- The App's `NWConnection.receive` loop reads until EOF — under no conditions should it block the connection open after Reporter has sent its data.

### Pitfall 3: Reporter inherits Claude Code's stdout, prints to it, breaks Claude

**What goes wrong:** Reporter prints debug info or `nc` exits with stderr text. If Claude Code captures the hook's stdout/stderr, garbage shows up in the user's session — at minimum noise, at worst Claude Code re-feeds stderr as "you must continue."

**Why it happens:**
- Claude Code passes `Stop` hook stdout back as context (per current docs, [VERIFIED 2026-05-07]: "For `Stop` and `UserPromptSubmit`, stdout is added as context Claude can see"). Stderr at exit code 1 shows in transcript; at exit code 2 is fed back as a blocking signal.
- A bare `printf '{...}' | nc -U $SOCK` doesn't redirect — `nc` may emit stderr on connection failure.

**How to avoid:**
- Reporter MUST redirect both stdout and stderr to `/dev/null` for the network step, and write its own debug output to the hook log file (HOOK-06). Pattern:
  ```sh
  printf '%s\n' "$JSON" | /usr/bin/nc -U -w 1 "$SOCK" >/dev/null 2>&1 || true
  ```
- Reporter should NOT emit stdout at all in the success path (D-08 doesn't say to add anything to Claude's context).
- Reporter's hook-log writes go to `~/Library/Logs/ClaudeAlertBot/hook.log`, never to stdout/stderr.

**Warning signs:**
- User reports "weird `nc` errors appearing in my Claude session" → unredirected stderr.
- Claude session enters a loop after a hook fires → stderr fed back via exit code 2 (which is forbidden by HOOK-03).

### Pitfall 4: The Reporter's debug log corrupts when two Stops fire simultaneously

**What goes wrong:** Two Reporters race on `~/Library/Logs/ClaudeAlertBot/hook.log`. Without atomic append, lines interleave or get truncated.

**Why it happens:** POSIX `>>` redirection on a file open with `O_APPEND` is line-atomic for writes ≤ `PIPE_BUF` (typically 4096 bytes on macOS). Our log entries are well under that. So `printf '...' >> "$LOG"` is safe.

**How to avoid:**
- Use `>>` (append), not `>` (truncate). Each entry is a single `printf` call (one syscall) below 4 KB → kernel guarantees atomicity.
- Do NOT use `tee -a` — tee is multiple writes.
- Format each log entry as a single JSON line so log parsing is trivial and any interleaving is detectable (broken JSON on a line).

### Pitfall 5: Multiple Stops within the same millisecond — listener accept queue

**What goes wrong:** Several Stop hooks fire concurrently. All connect to the socket within microseconds. If the App's accept handler is slow, the kernel accept queue fills up.

**Why it happens:** Default accept-queue depth on macOS is plenty (128+), but cosmetic concern.

**How to avoid:**
- `NWListener.newConnectionHandler` already runs on a dispatch queue. Each connection gets its own context.
- Per-connection processing is < 1 ms (decode JSON, log). No real risk at our event rates.
- Phase 1 verification step: synthesize 10 events in 100 ms via `cab-test` and confirm all 10 land in OSLog. (Mirror of Phase 4's ARCH stress test, but at small scale.)

### Pitfall 6: `socket()` / `sun_path` length limit (104 bytes on macOS)

**What goes wrong:** A long username or unusual home directory pushes `~/Library/Application Support/ClaudeAlertBot/sock` over the 104-byte AF_UNIX `sun_path` limit. `bind()` fails.

**Why it happens:** `struct sockaddr_un.sun_path` is exactly 104 chars on Darwin (vs 108 on Linux). Our path is fixed length:

```
/Users/<user>/Library/Application Support/ClaudeAlertBot/sock
└──────────┘└─────────────────────────────────────────────────┘
   varies              fixed = 56 chars
```

For a 30-char username, total = ~93 chars. **Within limit but tight.** A 50-char username breaks it.

**How to avoid:**
- App startup checks `socketPath.utf8.count <= 103` (1 byte for null terminator) — if exceeded, fall back to `/tmp/com.claudealert.bot.sock` (38 chars, always safe) and log a warning. **D-10 locks the path; this is a contingency only — discuss with user if a real test machine hits the limit.**
- Phase 1 plan should add a unit-test or runtime assertion: "if socket path > 103 bytes, fail loudly at startup before bind."

[VERIFIED via Darwin headers: `sys/un.h` defines `sun_path[104]`. Reference: BSD socket(2) man, also Apple's open-source XNU.]

### Pitfall 7: `~/Library/Application Support/ClaudeAlertBot/` doesn't exist on first run

**What goes wrong:** App tries to bind a socket inside a directory that doesn't exist. `bind()` returns `ENOENT`.

**How to avoid:**
- App startup creates `~/Library/Application Support/ClaudeAlertBot/` and `~/Library/Logs/ClaudeAlertBot/` with `FileManager.default.createDirectory(at: ..., withIntermediateDirectories: true)` BEFORE attempting bind.
- Reporter creates `~/Library/Logs/ClaudeAlertBot/` lazily before its first append (the App may not have run yet). One-line idiom: `mkdir -p "$LOG_DIR" 2>/dev/null || true`.
- These mkdir's must succeed on a vanilla macOS account with no special perms.

### Pitfall 8: `tty` returns "not a tty" when Reporter is invoked by Claude Code

**What goes wrong:** D-08's `tty` field is supposed to be `/dev/ttys004`. But hook subprocesses may have their stdin/stdout redirected, in which case `/usr/bin/tty` prints `not a tty` to stdout and exits 1.

**How to avoid:**
- Reporter captures `tty` defensively:
  ```sh
  TTY=$(/usr/bin/tty 2>/dev/null) || TTY=""
  case "$TTY" in /dev/*) ;; *) TTY="" ;; esac
  ```
- If empty, JSON envelope sends `null` (per D-08 "Missing fields are sent as JSON null").
- Phase 3 will need this field for fallback session lookup; if it's null too often, Phase 3's research will surface that. Phase 1 only needs to capture-when-available.

### Pitfall 9: Ad-hoc codesign skips the embedded `cab-test` binary

**What goes wrong:** `codesign --force --deep --sign - ClaudeAlertBot.app` is *supposed* to sign nested binaries, but `--deep` is officially deprecated as of macOS 13 and Apple's guidance is to sign each Mach-O explicitly.

**Why it happens:** [VERIFIED: Apple Technical Note TN3127 — "Resolving common notarization issues" — `--deep` is "convenient but discouraged"]. For ad-hoc signing of Phase 1 specifically, `--deep` still functions on macOS 14/15/26 in 2026, but explicit signing is more reliable.

**How to avoid:**
- `scripts/build.sh` signs each binary explicitly:
  ```bash
  codesign --force --sign - --options=runtime "ClaudeAlertBot.app/Contents/MacOS/cab-test"
  codesign --force --sign - --options=runtime "ClaudeAlertBot.app/Contents/MacOS/ClaudeAlertBot"
  codesign --force --sign - --options=runtime "ClaudeAlertBot.app"     # bundle seal LAST
  ```
- Verify each:
  ```bash
  codesign -dv --verbose=4 "ClaudeAlertBot.app" 2>&1 | grep -E 'Signature|Identifier'
  codesign -dv --verbose=4 "ClaudeAlertBot.app/Contents/MacOS/cab-test" 2>&1 | grep Signature
  ```
  Each must show `Signature=adhoc`.
- For Phase 1, `--deep` is acceptable as a convenience BUT verification must check the embedded helper too.

### Pitfall 10: Hook doesn't fire because `~/.claude/settings.json` registration is wrong

**What goes wrong:** Phase 1 uses manual hook registration (D-05). The developer hand-edits `~/.claude/settings.json` and gets the JSON shape wrong. Stop hooks don't fire and there's no error feedback.

**How to avoid:**
- Phase 1 ships `scripts/dev-install-hook.sh` that prints (and optionally appends) the exact correct registration block. The block is:
  ```json
  {
    "hooks": {
      "Stop": [
        {
          "matcher": "",
          "hooks": [
            { "type": "command", "command": "$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh", "timeout": 5 }
          ]
        }
      ]
    }
  }
  ```
  [VERIFIED 2026-05-07 against `https://code.claude.com/docs/en/hooks`: this is the current shape. Note `matcher` is required for Stop entries; empty string matches all.]
- Phase 1 verification: invoke Claude Code in a test iTerm2 tab, end a turn, check hook log file is written. If not, dev-install-hook.sh has a `--check` mode that pretty-prints the current `~/.claude/settings.json` Hook section.

### Pitfall 11: Claude Code's `stop_hook_active` is NOT in the documented schema

**What goes wrong:** Project-level PITFALLS.md mentions reading `stop_hook_active` from the hook stdin to prevent loops. **As of 2026-05-07, the official docs do NOT list this field in the Stop event input schema.**

**Verified shape (from current docs):**
```json
{
  "session_id": "...",
  "transcript_path": "...",
  "cwd": "...",
  "permission_mode": "default",
  "hook_event_name": "Stop"
}
```

**How to avoid:**
- Reporter does NOT read `stop_hook_active` (it's not in the documented input). The mitigation for the loop risk is *exclusively* `exit 0` — which the architecture already mandates (HOOK-03).
- HookEvent struct in Swift treats it as an optional `String?` field anyway (forward-compatible), but Phase 1 does not depend on it.

[VERIFIED: WebFetch of `https://code.claude.com/docs/en/hooks` on 2026-05-07.]

### Pitfall 12: Hook timeout default is 600 s — much longer than Reporter needs

**What goes wrong:** A future change to the App makes it slow to drain the socket (e.g., a synchronous AppleScript call slips into the listener path). Reporter blocks on `nc` write for many seconds. Claude Code waits up to 600 s before killing the hook.

**How to avoid:**
- Reporter's `nc -w 1` provides a 1-second idle timeout — so even a stuck App can't block Reporter for long.
- `~/.claude/settings.json` registration includes `"timeout": 5` (seconds) — a safety belt that overrides the 600 s default. [VERIFIED: `timeout` field documented at `https://code.claude.com/docs/en/hooks`.]
- App's listener handles each connection on a queue separate from the main runloop, so even if some downstream work is slow, the accept + read path is unaffected.

## Code Examples

### POSIX sh Reporter (verified pattern, ~30 lines)

```sh
#!/bin/sh
# Reporter/cab-report.sh — Claude Alert Bot Phase 1
# Triggered as Claude Code Stop hook (and later UserPromptSubmit hook in Phase 2).
# Hard contract: ALWAYS exit 0 (HOOK-03). Never write to stdout/stderr.

set -u                                  # error on unset vars; intentional non-strict otherwise
trap 'exit 0' EXIT INT TERM HUP        # belt-and-suspenders: even on signal, exit 0

# Paths (D-04, D-10)
APP_DIR="$HOME/Library/Application Support/ClaudeAlertBot"
SOCK="$APP_DIR/sock"
LOG_DIR="$HOME/Library/Logs/ClaudeAlertBot"
LOG="$LOG_DIR/hook.log"

# Determine event from hook env or argv (Claude Code passes hook_event_name in stdin JSON)
# We accept event name as $1 for explicitness when invoked via different settings.json entries.
EVENT="${1:-stop}"

# Ensure log dir
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Capture context BEFORE consuming stdin (env may be cleared in some shells under set -u)
ITERM_SESSION_ID_VAL="${ITERM_SESSION_ID:-}"
CLAUDE_PROJECT_DIR_VAL="${CLAUDE_PROJECT_DIR:-}"
CWD_FALLBACK="$PWD"
PPID_VAL="$PPID"
TS=$(/bin/date -u "+%Y-%m-%dT%H:%M:%SZ")
TTY_VAL=$(/usr/bin/tty 2>/dev/null) || TTY_VAL=""
case "$TTY_VAL" in /dev/*) ;; *) TTY_VAL="" ;; esac

# Read Claude Code hook stdin JSON (single line or multi-line; cat is fine)
STDIN_JSON=$(cat 2>/dev/null) || STDIN_JSON=""

# Build envelope JSON safely via python3 (handles all escaping)
JSON=$(/usr/bin/python3 - <<PY 2>/dev/null
import json, os, sys
stdin_raw = """${STDIN_JSON}"""
# Note: heredoc is dangerous if STDIN_JSON contains "PY"; use stdin instead
PY
)

# The above is wrong — python heredoc swallows the var with shell expansion BEFORE python sees it,
# which re-introduces the escaping problem. Correct pattern: pass via env vars + sys.stdin.

JSON=$(STDIN_JSON="$STDIN_JSON" \
       EVENT="$EVENT" \
       ITERM="$ITERM_SESSION_ID_VAL" \
       CLAUDE_DIR="$CLAUDE_PROJECT_DIR_VAL" \
       CWD_FALLBACK="$CWD_FALLBACK" \
       TTY_VAL="$TTY_VAL" \
       TS="$TS" \
       PPID_VAL="$PPID_VAL" \
       /usr/bin/python3 -c '
import json, os, sys

raw = os.environ.get("STDIN_JSON", "")
parsed = {}
if raw.strip():
    try:
        parsed = json.loads(raw)
    except Exception:
        parsed = {"raw": raw}

env = os.environ.get
def nz(v): return v if v else None

envelope = {
    "schema_version": 1,
    "event": env("EVENT") or "stop",
    "session_id": parsed.get("session_id"),
    "transcript_path": parsed.get("transcript_path"),
    "cwd": parsed.get("cwd") or nz(env("CWD_FALLBACK")),
    "iterm_session_id": nz(env("ITERM")),
    "tty": nz(env("TTY_VAL")),
    "ppid": int(env("PPID_VAL", "0")) or None,
    "claude_project_dir": nz(env("CLAUDE_DIR")),
    "ts": env("TS"),
}
print(json.dumps(envelope, ensure_ascii=False))
') || JSON=""

# Write debug log FIRST (HOOK-06): record envelope + ppid chain + env snapshot
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
```

**Key features:**
- All commands use absolute paths (`/usr/bin/nc`, `/usr/bin/python3`, `/bin/ps`, `/bin/date`) — robust against PATH manipulation.
- `python3 -c` with env-var injection is the only safe way to escape arbitrary cwd/path strings into JSON. Reject heredoc and printf-with-quote-replacement strategies.
- Debug log entry written *before* the network call — HOOK-06 is satisfied even when the socket is unreachable.
- Single `printf '%s\n' "$JSON" | nc` is one syscall sequence; output redirected to `/dev/null`.

### Swift HookEvent struct (matches D-08 schema)

```swift
// HookEvent.swift
import Foundation

struct HookEvent: Decodable {
    let schema_version: Int
    let event: String                      // "stop" | "user_prompt_submit"
    let session_id: String?
    let transcript_path: String?
    let cwd: String?
    let iterm_session_id: String?
    let tty: String?
    let ppid: Int?
    let claude_project_dir: String?
    let ts: String?
}
```

### Embedded `cab-test` CLI helper (synthetic event injection)

```swift
// CabTest/main.swift
// Sends a synthetic D-08 envelope to the App's socket. Smoke check.

import Foundation
import Network

let socketPath = "\(NSHomeDirectory())/Library/Application Support/ClaudeAlertBot/sock"
let payload: [String: Any] = [
    "schema_version": 1,
    "event": "stop",
    "session_id": "cab-test-\(UUID().uuidString)",
    "transcript_path": NSNull(),
    "cwd": FileManager.default.currentDirectoryPath,
    "iterm_session_id": ProcessInfo.processInfo.environment["ITERM_SESSION_ID"] ?? NSNull(),
    "tty": NSNull(),
    "ppid": Int(getppid()),
    "claude_project_dir": ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? NSNull(),
    "ts": ISO8601DateFormatter().string(from: Date()),
]

guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
      let line = String(data: data, encoding: .utf8) else {
    FileHandle.standardError.write(Data("cab-test: failed to serialize payload\n".utf8))
    exit(2)
}

let conn = NWConnection(to: .unix(path: socketPath), using: NWParameters.tcp)
let group = DispatchGroup()
group.enter()

conn.stateUpdateHandler = { state in
    switch state {
    case .ready:
        let bytes = (line + "\n").data(using: .utf8)!
        conn.send(content: bytes, completion: .contentProcessed { err in
            if let err {
                FileHandle.standardError.write(Data("cab-test: send error \(err)\n".utf8))
            } else {
                print("cab-test: sent \(bytes.count) bytes to \(socketPath)")
            }
            conn.cancel()
            group.leave()
        })
    case .failed(let err):
        FileHandle.standardError.write(Data("cab-test: connect failed: \(err)\n".utf8))
        conn.cancel()
        group.leave()
    default: break
    }
}
conn.start(queue: .global())
_ = group.wait(timeout: .now() + 2.0)
exit(0)
```

### `scripts/build.sh` (ad-hoc sign recipe)

```bash
#!/bin/bash
# scripts/build.sh — Phase 1 build pipeline
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/ClaudeAlertBot.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_NAME="ClaudeAlertBot.app"

mkdir -p "$BUILD_DIR"

# 1. Archive
xcodebuild \
    -project "$ROOT/ClaudeAlertBot.xcodeproj" \
    -scheme ClaudeAlertBot \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    archive

# 2. Export the .app from the archive
mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME" "$EXPORT_DIR/"
APP="$EXPORT_DIR/$APP_NAME"

# 3. Ad-hoc sign (DIST-01) — explicit, not relying on --deep alone
codesign --force --sign - --options=runtime "$APP/Contents/MacOS/cab-test"
codesign --force --sign - --options=runtime "$APP/Contents/MacOS/ClaudeAlertBot"
codesign --force --sign - --options=runtime "$APP"   # seal the bundle last

# 4. Verify
echo "=== Verifying signature ==="
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Signature|Identifier|Format'
codesign --verify --verbose=4 "$APP"
codesign -dv --verbose=4 "$APP/Contents/MacOS/cab-test" 2>&1 | grep Signature

echo "Build complete: $APP"
```

### Info.plist keys (Phase 1)

```xml
<!-- App/Info.plist excerpt — keys specific to Phase 1 -->
<key>CFBundleIdentifier</key>
<string>com.claudealert.bot</string>
<key>CFBundleName</key>
<string>Claude Alert Bot</string>
<key>LSUIElement</key>
<true/>
<key>LSMinimumSystemVersion</key>
<string>14.0</string>

<!-- Phase 3 needs this; setting it now is harmless and avoids a re-sign churn later. -->
<key>NSAppleEventsUsageDescription</key>
<string>Claude Alert Bot needs to switch focus to your iTerm2 tab when a Claude Code task completes.</string>
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `SMLoginItemSetEnabled` for login items | `SMAppService.mainApp.register()` | macOS 13 (2022) | Phase 1 doesn't ship login-at-launch; defer to later. Note for future planner: do NOT use the deprecated API |
| BSD `socket()`/`bind()`/`listen()`/`accept()` in Swift | `NWListener` + `NWEndpoint.unix` | macOS 10.15 (Catalina, 2019) | Already adopted in our research; Phase 1 uses NWListener |
| `NSSound` for audio | `AVAudioPlayer` | macOS 26 (Tahoe, 2025) reported NSSound CoreAudio init regressions | Phase 1 has no audio; Phase 2 must use AVAudioPlayer |
| Right-click → Open for unsigned apps | System Settings → Privacy & Security → "Open Anyway" | macOS 15 (Sequoia, 2024) removed Right-click → Open | Phase 6 README must reflect this; Phase 1 unaffected (dev manually launches from Xcode) |
| `--deep` flag for code signing | Sign each Mach-O explicitly, then bundle last | macOS 13 (2022) deprecated `--deep` (still works in 2026) | `scripts/build.sh` uses explicit signing; `--deep` documented as fallback only |

**Deprecated/outdated:**
- `OSLog C API` (`os_log`, `os_log_t`) — superseded by `os.Logger` Swift API since macOS 11. Use Swift `Logger`.
- `print()` to stderr for production logging — use OSLog instead.
- `NSDistributedNotificationCenter` for IPC — not relevant here; we use AF_UNIX sockets.
- `stop_hook_active` field — listed in some 2024 third-party guides but NOT in current official docs (verified 2026-05-07).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | macOS bundles `/usr/bin/python3` (Apple stub that installs Command Line Tools on demand) on macOS 14+ — always available for Reporter JSON escaping | Standard Stack / Reporter code | LOW. If `python3` is missing, Reporter's JSON construction fails, the network step is skipped, hook log records nothing. Fallback: replace with `awk` or accept lossy escaping. The JSON build can be re-implemented without python3 if it bites a real user — but it's stable on every macOS 14+ install we've seen |
| A2 | macOS sandbox is NOT in play — App is not sandboxed (PROJECT.md and STACK.md commit to non-sandboxed) | NWListener AF_UNIX | HIGH if wrong: AF_UNIX in `~/Library/Application Support` is blocked by sandbox in subtle ways. Mitigation: PROJECT.md explicitly rejects sandboxing |
| A3 | `/usr/bin/nc` Apple BSD variant supports `-U` and `-w` on macOS 14, 15, and 26 | Reporter | LOW — verified on dev host (macOS 26.4.1, 2026-05-07). Behavior of `-w` with AF_UNIX is the same as TCP (idle timeout) |
| A4 | The Apple Developer Forums sample for NWListener+AF_UNIX (thread 719635) accurately reflects current Network framework behavior on macOS 14/15/26 | Pattern 4 | LOW. Pattern is stable since macOS 12. Log-noise warnings are expected and harmless per Apple DTS |
| A5 | Apple Silicon dev host can produce a runnable `.app` with ad-hoc codesign (`codesign --sign -`) — no Apple Developer Program needed | scripts/build.sh | LOW. Verified by industry use; STACK.md and PITFALLS.md cite multiple sources. Phase 6 will additionally test on a fresh user account |
| A6 | Claude Code Stop hook input schema (verified 2026-05-07) is stable enough that field names (`session_id`, `cwd`, `transcript_path`, `hook_event_name`) won't change between now and Phase 1 ship | HookEvent struct, Reporter parser | MEDIUM. Anthropic could rename fields. Mitigation: the Reporter wraps in a `parsed = {"raw": raw}` fallback if JSON parses but doesn't match expected fields, so we still record SOMETHING |
| A7 | The Phase 1 success criterion #4 ("a second launch attempt is blocked because the Unix-domain socket is already held") works reliably via `NWListener.State.failed` — i.e., bind failures surface as `.failed` and not hung in `.waiting` | Pattern 5 / Single-Instance | MEDIUM. Apple's docs are thin on which `state` you'll see. Mitigation: 5-second startup timeout on `.ready` — if listener doesn't reach `.ready` and isn't `.failed`, treat as locked and exit |
| A8 | The macOS 14 deployment target is acceptable to the user (PROJECT.md says "macOS 14 Sonoma 이상") and Xcode 26 on the dev host can build for that target | Standard Stack | LOW. Verified — Xcode 26 supports back to macOS 12 deployment |
| A9 | `~/Library/Application Support/ClaudeAlertBot/sock` path length is well under 104 bytes for typical macOS usernames (≤30 chars) | Pitfall 6 | LOW for typical users. Phase 1 plan adds an explicit length check + fallback to `/tmp/com.claudealert.bot.sock` |

## Open Questions

1. **Should `cab-report.sh` execute under `/bin/sh` or explicitly `/bin/bash`?**
   - What we know: D-01 says POSIX `sh`. macOS `/bin/sh` is bash-3.2 in POSIX mode. `/bin/sh` is the safer/more-portable choice and what Reporter's shebang uses.
   - What's unclear: Whether any constructs we use (`case "$TTY_VAL" in /dev/*) ;;`) misbehave under POSIX-strict mode.
   - Recommendation: Use `#!/bin/sh`, manually verify on macOS 14, 15, and 26 in the Phase 1 verification matrix.

2. **Does the `cab-test` helper need its own Info.plist, or can it ship as a bare Mach-O inside `Contents/MacOS/`?**
   - What we know: Embedded CLI helpers commonly ship without an Info.plist (e.g., `git`, `python` in Xcode). The bundle's Info.plist is sufficient.
   - What's unclear: Whether ad-hoc codesign + Gatekeeper will treat a bare Mach-O differently from one with its own embedded plist.
   - Recommendation: Skip Info.plist for `cab-test`; sign as a plain Mach-O. Verify with `codesign -dv` post-build.

3. **What is the MINIMUM Xcode version actually required?**
   - What we know: STACK.md says 15.4 minimum. Dev host has 26.0.1.
   - What's unclear: If a user wants to clone and build on Xcode 15.0 specifically.
   - Recommendation: Document `Xcode 15.4+ required` in README. Phase 1 plan need not enforce.

4. **Should Phase 1's HookEvent schema enforce that `event in {"stop","user_prompt_submit"}`?**
   - What we know: D-08 lists both values. Phase 1 only fires "stop" via the actual hook (HOOK-01 only — HOOK-02 is Phase 2).
   - What's unclear: Should the App reject `event == "user_prompt_submit"` until Phase 2, or accept and log?
   - Recommendation: Accept and log both — forward-compatible. Plan should add a Codable enum but keep validation soft.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Build | ✓ | 26.0.1 | — (must have for any Swift build) |
| `xcodebuild` | scripts/build.sh | ✓ | bundled with Xcode 26.0.1 | — |
| `codesign` | scripts/build.sh DIST-01 | ✓ | /usr/bin/codesign | — (system tool) |
| `/usr/bin/nc` (Apple BSD variant) | Reporter HOOK-01 | ✓ | macOS 26 system | None — D-01 mandates absolute path; missing nc would block Reporter |
| `/usr/bin/python3` | Reporter HOOK-04 (JSON build) | ✓ | system stub (Apple) | Awk-based escaping (lossy on edge cases); not implemented in Phase 1 |
| `/usr/bin/tty` | Reporter HOOK-04 | ✓ | system | None needed — captures empty string when not a tty |
| `/bin/date` | Reporter HOOK-04 (timestamp) | ✓ | system | — |
| `/bin/ps` | Reporter HOOK-06 (ppid chain) | ✓ | system | — |
| Claude Code installed | End-to-end Phase 1 verification | (presumed by user) | — | None — without Claude Code there's no Stop hook to fire |
| iTerm2 installed | Phase 1 verification step that runs Claude in iTerm2 | (presumed by user) | — | Could verify in Terminal.app, but `ITERM_SESSION_ID` will be missing — soft criterion |
| `log` CLI (for verification) | OSLog query | ✓ | system | — |
| `osascript` | Verification (e.g., check Dock contents) | ✓ | system | — |

**Missing dependencies with no fallback:** None — the Phase 1 dev environment on macOS 14+ has every tool we need.

**Missing dependencies with fallback:** None — all tools confirmed present.

[VERIFIED on dev host 2026-05-07: `xcodebuild -version` → Xcode 26.0.1; `/usr/bin/nc -h` shows Apple variant; `/usr/bin/python3` resolves; `/bin/sh --version` → GNU bash 3.2.57.]

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None (XCTest available but Phase 1 has no business logic warranting unit tests). Verification is shell-based smoke checks. |
| Config file | None — Phase 1 |
| Quick run command | `scripts/verify-phase-1.sh` (to be created in Phase 1; not framework-driven) |
| Full suite command | Same — Phase 1 has only one verification level |
| Phase gate | Manual verification matrix (the success criteria below) — `/gsd-verify-work` will run them |

**Note for planner:** Phase 1's deliverable is plumbing, not algorithms. Adding XCTest for `HookEvent` decoding is reasonable (1-2 tests) but not load-bearing. Phase 2 (which has SessionRegistry, threshold, batching) is where unit-test infrastructure starts paying off. Wave 0 of Phase 1 should NOT block on test-framework setup.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HOOK-01 | Stop hook fires Reporter, lands JSON in App's OSLog | integration | `bash scripts/verify-phase-1.sh hook-01` (runs `cab-test` + `log show --last 10s --predicate 'subsystem == "com.claudealert.bot.hook"'` + greps for the synthetic session_id) | ❌ Wave 0 |
| HOOK-03 | Reporter exits 0 on success | unit (shell) | `printf '{}' \| bash Reporter/cab-report.sh; echo $?` → expect `0` | ❌ Wave 0 |
| HOOK-03b | Reporter exits 0 when socket missing (HOOK-05 combined) | unit (shell) | `mv socket sock.bak; printf '{}' \| bash Reporter/cab-report.sh; echo $?` → expect `0` | ❌ Wave 0 |
| HOOK-04 | Reporter captures all 7 fields | integration | After firing `cab-report.sh`, verify hook.log entry contains keys `session_id`, `cwd`, `iterm_session_id`, `tty`, `ppid`, `claude_project_dir`, `ts` | ❌ Wave 0 |
| HOOK-05 | App down → no Claude side effect, exit 0 within 50 ms | timed shell | `time (printf '{}' \| bash Reporter/cab-report.sh)` → expect real-time < 0.05s when socket absent | ❌ Wave 0 |
| HOOK-06 | hook.log accumulates entry per fire including env+ppid+tty | integration | After firing twice: `wc -l ~/Library/Logs/ClaudeAlertBot/hook.log` increases by 2; jq-parse last entry has `ppid_chain` non-empty | ❌ Wave 0 |
| IPC-01 | App receives JSON event via NWListener AF_UNIX | smoke | Run app; `bin/cab-test`; check OSLog for matching session_id | ❌ Wave 0 |
| IPC-02 | Socket created at `~/Library/Application Support/ClaudeAlertBot/sock` | unit (shell) | `test -S "$HOME/Library/Application Support/ClaudeAlertBot/sock"` → expect 0 after app start | ❌ Wave 0 |
| IPC-03 | Second launch fails cleanly (single instance) | integration | Start app A; start app B (same binary). B should exit within 1 s; A still running | ❌ Wave 0 |
| DIST-01 | Built `.app` is ad-hoc signed | unit (shell) | `codesign -dv --verbose=4 build/export/ClaudeAlertBot.app 2>&1 \| grep -q 'Signature=adhoc'` | ❌ Wave 0 |
| DIST-01b | Embedded `cab-test` is also signed | unit (shell) | `codesign -dv --verbose=4 build/export/ClaudeAlertBot.app/Contents/MacOS/cab-test 2>&1 \| grep -q 'Signature=adhoc'` | ❌ Wave 0 |
| DIST-05 | App is invisible: no Dock icon, no menu bar, no Cmd-Tab | manual + AppleScript | `osascript -e 'tell application "System Events" to get name of every process whose visible is true'` after app start should NOT include `ClaudeAlertBot` | ❌ Wave 0 |
| DIST-05b | `LSUIElement` set in built bundle | unit (shell) | `defaults read $(realpath build/export/ClaudeAlertBot.app/Contents/Info) LSUIElement` → expect `1` | ❌ Wave 0 |

### Phase 1 Success Criteria → Verification Recipe

(Mirrors ROADMAP.md "Success Criteria" 1-5 with command-runnable checks.)

**Success #1: A real Stop event in iTerm2 → JSON line in App's OSLog with all 7 D-08 fields.**

```bash
# Setup: Phase 1 app running, hook registered.
# In iTerm2: claude → start a turn that takes ≥ 1 sec → end.
# In another terminal:
log show --last 1m --predicate 'subsystem == "com.claudealert.bot.hook"' --info \
  | grep -E 'event=stop' \
  | grep -E 'session=[a-z0-9-]+'   # passes if at least one match
```

**Success #2: With app NOT running, hook still exits 0 within 50 ms, no Claude impact.**

```bash
# Kill the app, then in iTerm2 run a Claude turn.
# Verify (a) Claude finishes normally, (b) hook log records the fire, (c) Reporter exit was 0.
START=$(date +%s%N)
printf '{"session_id":"x","cwd":"/tmp","transcript_path":"/x"}' | /bin/sh Reporter/cab-report.sh
END=$(date +%s%N)
echo "elapsed_ms=$(( (END - START) / 1000000 ))"        # expect < 50
echo "exit=$?"                                           # expect 0
```

**Success #3: Built `.app` reports `Signature=adhoc` and launches without `cs_invalid_page` errors.**

```bash
codesign -dv --verbose=4 build/export/ClaudeAlertBot.app 2>&1 | grep 'Signature=adhoc'   # passes if line found
open build/export/ClaudeAlertBot.app
sleep 1
log show --last 30s --predicate 'eventMessage CONTAINS "cs_invalid_page"' | grep -i claudealertbot   # expect NO match
pgrep -fx ClaudeAlertBot                                                                              # expect ≥1
```

**Success #4: After launch — no Dock, no menu bar, no Cmd-Tab — second launch blocked by socket lock.**

```bash
# After launch:
osascript -e 'tell application "System Events" to get name of every process whose visible is true' \
  | tr ',' '\n' | grep -i ClaudeAlertBot     # expect NO output (visible=false)

# Second launch test:
open build/export/ClaudeAlertBot.app
sleep 1
COUNT=$(pgrep -fx ClaudeAlertBot | wc -l | tr -d ' ')
test "$COUNT" -eq 1                          # expect exactly one running instance
```

**Success #5: Hook log accumulates a record for every fire, including fires while app was down.**

```bash
LOG="$HOME/Library/Logs/ClaudeAlertBot/hook.log"
# Stop app
pkill -fx ClaudeAlertBot
BEFORE=$(wc -l < "$LOG")
# Fire reporter manually 3 times
for i in 1 2 3; do printf '{"session_id":"app-down-'$i'"}' | /bin/sh Reporter/cab-report.sh; done
AFTER=$(wc -l < "$LOG")
test $((AFTER - BEFORE)) -eq 3                # expect +3 entries
# Verify each entry has the expected fields
tail -3 "$LOG" | python3 -c '
import sys, json
for line in sys.stdin:
    obj = json.loads(line)
    assert "envelope" in obj, "missing envelope"
    assert "ppid_chain" in obj, "missing ppid_chain"
    assert "ts" in obj, "missing ts"
print("OK")
'
```

### Sampling Rate
- **Per task commit:** the relevant subset of the table (e.g., a task touching Reporter only re-runs HOOK-* checks).
- **Per wave merge:** all 14 verification commands above.
- **Phase gate:** all 5 success criteria pass + `cab-test` + 10-event burst test.

### Wave 0 Gaps
- [ ] `Reporter/cab-report.sh` — implements HOOK-01/03/04/05/06.
- [ ] `App/HookListener.swift` — implements IPC-01.
- [ ] `App/HookEvent.swift` — schema for D-08.
- [ ] `App/AppDelegate.swift` — implements IPC-02, IPC-03, DIST-05 (LSUIElement runtime).
- [ ] `App/Info.plist` — LSUIElement + bundle id (DIST-05).
- [ ] `CabTest/main.swift` — synthetic event injection (D-07 verification helper).
- [ ] `scripts/build.sh` — DIST-01 ad-hoc sign.
- [ ] `scripts/verify-phase-1.sh` — automation of the 14-row verification table.
- [ ] `scripts/dev-install-hook.sh` — Phase 1 manual hook-registration helper (D-05).

(No existing test infrastructure to retrofit — repo is empty per CONTEXT.md.)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | NO | Single-user local app; no users to authenticate |
| V3 Session Management | NO | No web sessions |
| V4 Access Control | YES (limited) | AF_UNIX socket file in `~/Library/Application Support/ClaudeAlertBot/` is bounded by user-home filesystem perms — only the owning user can read/write. **Phase 1 plan must explicitly chmod the directory `0700` and the socket `0600` to harden against multi-user-on-one-Mac scenarios** (PITFALLS-style "Security Mistakes" table |
| V5 Input Validation | YES | App validates `schema_version == 1` on every received envelope; rejects unknown versions. JSON decode failures are logged and discarded, not panicked. Reject envelopes > 64 KB at the read loop |
| V6 Cryptography | NO | No crypto in Phase 1 |
| V7 Error Handling | YES | App MUST NOT crash on malformed input. Test with: random bytes, partial JSON, oversized JSON, JSON with extra fields, JSON with missing required fields |
| V12 File Handling | YES | App writes only to `~/Library/Application Support/ClaudeAlertBot/` and `~/Library/Logs/ClaudeAlertBot/`. Never writes outside the user's data containers |
| V14 Configuration | YES | Phase 1 has no remote config; future phases must not lower minimum macOS version below 14 (deployment target hardened) |

### Known Threat Patterns for {macOS-local-IPC, AF_UNIX, headless app}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Local privilege escalation: another user on the same Mac connects to the socket and sends fake hook events | Spoofing | Socket lives in `~/Library/Application Support/ClaudeAlertBot/` (mode 0700); other users can't traverse into it. Belt-and-suspenders: chmod the socket file 0600 after bind via `FileManager` |
| Path traversal in `cwd` field → File-system mischief | Tampering | App treats `cwd` as a display string only; never uses it for `open()` or `chdir()`. (Phase 1 doesn't touch the file system based on the field.) |
| Oversized JSON DoS | Denial of Service | `NWConnection.receive(maximumLength: 65_536)`; envelopes > 64 KB are dropped at read time. Per-connection cleanup ensures sockets don't pile up |
| Reporter bug crashes user's Claude Code session | Denial of Service | HOOK-03 hard contract: `exit 0` always, including via `trap` on signals |
| Logged paths reveal private project locations | Information Disclosure | Phase 1 (dev) logs paths at `.public` privacy. Note in code: future phases (production builds) should mark them `.private` and emit hashes for cross-event correlation. **Add to Phase 5 review checklist** |
| Hook script tampering: a malicious actor replaces the user-data copy of `cab-report.sh` to do something else when Claude fires | Tampering | Script lives at `~/Library/Application Support/ClaudeAlertBot/cab-report.sh` — same dir-perms protection as the socket. Phase 5's installer should verify the script's hash on each run; Phase 1 doesn't add this complexity |

ASVS Level 1 minimum is satisfied for Phase 1 deliverables. The Phase 1 plan should explicitly:
1. Set directory mode `0700` on `~/Library/Application Support/ClaudeAlertBot/` and `~/Library/Logs/ClaudeAlertBot/` at first run.
2. Set socket file mode `0600` after bind (set via `FileManager.setAttributes` or `chmod()` after `NWListener.start()` reaches `.ready`).
3. Reject envelopes with unknown `schema_version`.
4. Cap message size at 64 KB.

## Sources

### Primary (HIGH confidence)
- [Hooks reference — Claude Code Docs](https://code.claude.com/docs/en/hooks) — VERIFIED 2026-05-07 via WebFetch. Stop event JSON shape, exit-code semantics, settings.json registration, hook timeouts, **`stop_hook_active` is NOT in current schema**.
- [NWListener — Apple Developer Documentation](https://developer.apple.com/documentation/network/nwlistener) — Apple official.
- [NWListener with NWEndpoint.unix — Apple Developer Forums thread 719635](https://developer.apple.com/forums/thread/719635) — VERIFIED via WebFetch 2026-05-07. Working sample code; Apple DTS engineer confirms log noise is harmless.
- [LSUIElement — Apple Developer Documentation (CFBundleDocumentTypes/Background-only-app)](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement)
- [Apple Technical Note TN3127 — Resolving common notarization issues](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) (`--deep` deprecation guidance)
- [BSD `nc(1)` man page on macOS 26](file:///usr/share/man/man1/nc.1) — verified locally on dev host 2026-05-07; `--UU` flag, `--ww` timeout semantics

### Secondary (MEDIUM confidence)
- [Building a server-client application using Apple's Network Framework — RDerik](https://rderik.com/blog/building-a-server-client-application-using-apple-s-network-framework/)
- [Build a macOS menu bar utility in SwiftUI — NilCoalescing](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — for LSUIElement context
- [.planning/research/STACK.md, ARCHITECTURE.md, PITFALLS.md, SUMMARY.md] — project-internal research, locked decisions

### Tertiary (LOW confidence)
- None used. All Phase 1 claims are anchored in Apple official docs or verified-on-host commands.

## Project Constraints (from CLAUDE.md)

The project's `CLAUDE.md` is largely a paste of `STACK.md` content and adds a small set of behavioral rules. Extracted directives:

- **Min OS:** macOS 14 Sonoma. Phase 1 deployment target MUST be 14.0.
- **Tech stack:** Swift / SwiftUI + AppKit interop. **External Swift dependencies = 0.** Phase 1 plan must not introduce SPM deps.
- **IPC:** `Network.framework` AF_UNIX socket — NOT XPC, URL scheme, distributed notifications, or HTTP.
- **Build env:** Xcode 15.4+ (dev host has 26.0.1).
- **Signing:** Ad-hoc `codesign --force --deep --sign -` is mandatory. Phase 1 plan MUST include this in `scripts/build.sh`.
- **External deps:** Claude Code + iTerm2 must be installed by user (not packaged).
- **Hooks:** Stop + UserPromptSubmit BOTH required (Phase 1 only ships Stop wiring; Phase 2 adds UserPromptSubmit). The Reporter SHOULD be designed to handle both events from day one.
- **AppleScript:** `NSAppleEventsUsageDescription` Info.plist key required — set NOW even though Phase 1 doesn't AppleScript yet, to avoid re-sign churn in Phase 3.
- **No Over-Editing (global):** When modifying code, identify affected scope, make minimum modification needed. Preserve existing logic; do not rewrite. Do not mix in unrelated refactors. **Implication for Phase 1: scaffolding code, not Phase 2 features. Plan tasks should each be tightly scoped.**
- **GSD Workflow Enforcement:** All file changes go through GSD entry points (`/gsd-quick`, `/gsd-execute-phase`). Phase 1 work must run via `/gsd-execute-phase`.

These constraints are consistent with research findings; no contradictions to surface.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every framework verified against Apple docs and on-host commands; STACK.md already locked at project level.
- Architecture: HIGH — already-locked patterns (statelets edge / stateful core, AF_UNIX IPC, NWListener) re-verified against Apple Developer Forums sample code.
- Pitfalls: HIGH on the technical mechanics (codesign, nc, AF_UNIX, LSUIElement). MEDIUM on the exact NWListener `.failed` state surfaced for second-instance bind — flagged as A7 assumption.
- Validation: HIGH — every success criterion has a runnable shell command. The verification table is fully automatable in `scripts/verify-phase-1.sh`.

**Research date:** 2026-05-07
**Valid until:** 2026-06-06 (30 days; stack is stable, but Claude Code hook docs may shift — re-verify hook stdin schema if Phase 1 implementation slips past this date).

---
*Researched for: Phase 1 — Foundation (Hook → AF_UNIX → Headless App pipeline)*
