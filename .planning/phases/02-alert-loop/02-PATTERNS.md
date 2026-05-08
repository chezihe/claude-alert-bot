# Phase 2: Alert Loop — Pattern Map

**Mapped:** 2026-05-07
**Files analyzed:** 22 new + 9 modified = 31
**Analogs found:** 28 / 31 (3 files have no direct Phase 1 analog — flagged below)

> Downstream: `gsd-planner` reads this to assign concrete copy-from sources for every Phase 2 plan. All excerpts are verbatim from Phase 1 source (`App/`, `CabTest/`, `Reporter/`, `scripts/`, `project.yml`) unless flagged `[research-only]`. Line numbers refer to the file at HEAD as of commit shipping `01-03-SUMMARY.md`.

---

## File Classification

### New Swift sources (App target)

| File | Role | Data Flow | Closest Analog | Match Quality |
|------|------|-----------|----------------|---------------|
| `App/SessionRegistry.swift` | actor / domain core | event-driven (in: ingest; out: notifier broadcast) | `App/HookListener.swift` (Phase 1 actor-shape; this is the second actor-like component) | role-match (HookListener is `final class` not `actor`, but exhibits identical race-isolation + Logger + queue pattern; SessionRegistry literally upgrades that pattern to `actor`) |
| `App/SessionRecord.swift` | model (Codable structs/enums: `InFlightStart`, `CompletedSession`, `DedupeKey`, `WidgetCorner`, `PermissionStatus`) | data | `App/HookEvent.swift` | exact (same Codable struct + Foundation-only style) |
| `App/SessionStore.swift` (a.k.a. `SessionsPersistence`) | persistence (atomic JSON read/write) | file-I/O | `App/SocketPaths.swift` (path source-of-truth) + `App/AppDelegate.ensureDirectories` (FileManager + 0700) | role-match for path constants; persistence write itself has **no analog** — uses `Data.write(to:options:[.atomic])` per RESEARCH Pattern 5 |
| `App/NotificationOrchestrator.swift` | orchestrator (registry → widget+sound) | event-driven, MainActor hop | `App/AppDelegate.swift` (component wiring + `signalSources` retain pattern) | role-match (AppDelegate wires components; Orchestrator is the Phase 2 second-tier wirer) |
| `App/SoundPlayer.swift` | helper (AVAudioPlayer wrapper) | one-shot | (none in Phase 1 — first audio code) | **no analog** — RESEARCH Pattern 10 is canonical reference |
| `App/SettingsStore.swift` | model + ObservableObject | UserDefaults bidirectional | `App/SocketPaths.swift` (single-source-of-truth for constants — closest structural analog) | partial — both are static-value-source; SettingsStore is `@MainActor class` not `enum`, but role of "central typed accessor" matches |
| `App/SettingsView.swift` | SwiftUI view | request-response (user input → UserDefaults) | (no SwiftUI in Phase 1 — `App/main.swift` was deliberately pure-AppKit) | **no analog** — RESEARCH Code Examples §SettingsView is canonical |
| `App/FloatingWidgetWindowController.swift` | AppKit bridge (NSWindowController + NSPanel) | request-response (registry state → panel reposition/orderFront) | `App/AppDelegate.swift` (lifecycle component owner pattern) + `App/main.swift` (NSApp.setActivationPolicy(.accessory)) | role-match for ownership; NSPanel itself: see RESEARCH Pattern 7 |
| `App/FloatingWidgetPanel.swift` | NSPanel subclass | (none — UI surface) | (none in Phase 1) | **no analog** — RESEARCH Pattern 7 is canonical |
| `App/WidgetIconView.swift` | SwiftUI view | (none — pure render) | (none) | **no analog** |
| `App/PopoverContentView.swift` | SwiftUI view | request-response (row click → registry.clearOne) | (none) | **no analog** — UI-SPEC §"Hover Popover" + RESEARCH Anti-Pattern note ("Task { @MainActor in await registry.clearOne(...) }") |
| `App/PopoverRowView.swift` | SwiftUI view | (render) | (none) | **no analog** |
| `App/PermissionBannerView.swift` | SwiftUI view | request-response (button → NSWorkspace.open) | (none) | **no analog** — UI-SPEC §"Permission Banner" |
| `App/AppleScriptHelper.swift` | actor (compile-once NSAppleScript) | request-response (BG serial queue) | `App/HookListener.swift` (dedicated DispatchQueue + Logger pattern) | role-match (both isolate I/O off main; helper is `actor`, listener is `final class`) |
| `App/PermissionDeepLink.swift` | helper (URL fallback chain) | one-shot | (none) | **no analog** — RESEARCH Pattern 12 |
| `App/WakeObserver.swift` | observer (NSWorkspace.didWakeNotification) | event-driven | `App/AppDelegate.installSignalHandler` (DispatchSource retain pattern — observer must be retained) | role-match (both are "observer that must be retained or it's silently lost") |
| `App/WorkspaceFrontmostObserver.swift` (D2-15) | observer (NSWorkspace.didActivateApplicationNotification) | event-driven | `App/AppDelegate.installSignalHandler` (same retain-or-lose pattern) | role-match |
| `App/SessionGCTimer.swift` | timer (DispatchSourceTimer) | event-driven (30-min tick) | `App/AppDelegate.installSignalHandler` (DispatchSource retain pattern) | role-match (DispatchSource family — same retention requirement) |
| `App/ProjectName.swift` | utility (cwd basename / claude_project_dir) | transform | `App/SocketPaths.swift` (pure-function namespace `enum`) | exact (small `enum`-of-static-funcs Foundation-only) |

### Modifications to existing files

| File | Insertion Point | Pattern |
|------|-----------------|---------|
| `App/main.swift` | After `app.delegate = delegate` (line 9) | Add SwiftUI Settings scene wiring (or accept that AppDelegate constructs it programmatically — see RESEARCH Code Examples) |
| `App/AppDelegate.swift` | New step 6/7 in `applicationDidFinishLaunching` after step 5 | Wire SessionRegistry, NotificationOrchestrator, FloatingWidgetWindowController, SettingsStore, restore from sessions.json, schedule GC |
| `App/HookListener.swift` | `handle(buffer:)` after schema_version guard (line 89-94) | Replace logger-only emit with `Task { @MainActor in … await SessionRegistry.shared.ingest(event, …) }` (RESEARCH Pattern 2 dispatch) |
| `App/HookEvent.swift` | None (no struct change needed — `event` is already `String`, see line 10 comment) | Phase 1 explicitly anticipated this (see Plan 03 SUMMARY decisions row "Kept event field as String not enum per RESEARCH Open Question 4") |
| `App/SocketPaths.swift` | Add `static let sessionsJSONPath` after line 10 | Same `"\(appSupportDir)/sessions.json"` shape as existing socketPath |
| `App/Info.plist` | After existing `NSAppleEventsUsageDescription` line 25-26 | **Already present** — verify Korean copy per D2-33; may need to update string |
| `Reporter/cab-report.sh` | None (already supports `EVENT="${1:-stop}"` line 16 + python branch line 58) | Phase 1 already implemented HOOK-02 contract — Phase 2 only needs the hook *registration* (already in `dev-install-hook.sh` line 51-58). Verify with cab-test |
| `project.yml` | `targets.ClaudeAlertBot.sources` (already `path: App` so any new file under `App/` is auto-picked) | No yml change needed unless adding subdirectories. If splitting `App/UI/`, `App/Domain/`, `App/Persistence/`, add explicit subpath entries. |
| `scripts/dev-install-hook.sh` | None (already registers Stop AND UserPromptSubmit, lines 44-58) | Phase 1 already shipped this — Phase 2 verifies via cab-test |
| `scripts/verify-phase-2.sh` (new) | New file | Copy structure verbatim from `scripts/verify-phase-1.sh` |

---

## Pattern Assignments

### `App/SessionRegistry.swift` (actor, event-driven)

**Analog:** `App/HookListener.swift`

**Imports + class declaration pattern** (HookListener.swift lines 9-22):
```swift
import Network
import Foundation
import AppKit
import os

final class HookListener {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "listener")
    private let ingressLog = Logger(subsystem: "com.claudealert.bot.hook", category: "ingress")
    private let socketPath: String
    private let queue = DispatchQueue(label: "com.claudealert.bot.hook.listener")
    private var listener: NWListener?

    init(socketPath: String) { self.socketPath = socketPath }
```

**Phase 2 application:** Replace `final class` with `actor`, drop `queue` (actor isolates implicitly), keep one Logger per category. New categories: `registry`, `notification`, `widget`, `settings`, `applescript` (per CONTEXT D2-31 + D2-37).

**Logger formatting pattern** (HookListener.swift lines 34, 89, 94):
```swift
self.log.notice("listener bound on \(self.socketPath, privacy: .public)")
log.warning("rejecting event with unknown schema_version=\(event.schema_version)")
ingressLog.notice("ingress event=\(event.event, privacy: .public) session=\(event.session_id ?? "nil", privacy: .public) cwd=\(event.cwd ?? "nil", privacy: .public)")
```

**Phase 2 application:** Every public actor method emits one OSLog line at `.notice` for happy-path or `.warning`/`.error` for skip-paths. The `privacy: .public` annotation is mandatory per Phase 1 D-07 dev-visibility contract — keep it for Phase 2 with the inline comment "Phase 5 review" (Plan 03 SUMMARY explicitly carries this forward).

**Schema/threshold guard pattern** (HookListener.swift lines 87-91):
```swift
guard event.schema_version == 1 else {
    log.warning("rejecting event with unknown schema_version=\(event.schema_version)")
    return
}
```

**Phase 2 application:** Same `guard … else { log.warning(…); return }` shape for: pre-suppress (D2-14), threshold drop (THR-01), dedupe drop (AUD-01).

---

### `App/SessionRecord.swift` (model, data)

**Analog:** `App/HookEvent.swift` (entire file, 19 lines)

**Excerpt** (HookEvent.swift lines 1-19, full):
```swift
// App/HookEvent.swift — D-08 envelope schema (10 fields, schema_version=1).
// Locked for Phase 2 to consume; Phase 1 only decodes/logs.
// RESEARCH Pitfall #11: stop_hook_active is NOT in current Claude Code docs — do NOT add it.
// RESEARCH Open Question 4: keep `event` as String (not enum) so Phase 2's UserPromptSubmit
//   ingestion does not require a struct change.
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

**Phase 2 application:** New file `SessionRecord.swift` follows the same conventions:
- Header comment block: `// App/<File>.swift — <one-line purpose>`
- Sources commented inline (e.g. `// D2-23 atomic; D2-25 path; SESS-03 schema`)
- `import Foundation` only (no AppKit/SwiftUI in pure data files)
- All structs are `Codable` (not just `Decodable`) since SessionStore needs both directions
- Field comments use the `// "stop" | "user_prompt_submit"` shape — show the enumerated value set inline

---

### `App/SessionStore.swift` (persistence, file-I/O)

**Analog (path constant):** `App/SocketPaths.swift` lines 1-18

**Excerpt** (SocketPaths.swift, full file):
```swift
// App/SocketPaths.swift — single source of truth for paths (D-10).
// Pitfall #6: AF_UNIX sun_path is 104 bytes on Darwin (incl. NUL); path must fit.
// Pitfall #7: containing directory must exist before bind() — AppDelegate.ensureDirectories().
import Foundation

enum SocketPaths {
    static let appSupportDir: String = {
        "\(NSHomeDirectory())/Library/Application Support/ClaudeAlertBot"
    }()
    static let socketPath: String = "\(appSupportDir)/sock"
    static let logsDir: String = "\(NSHomeDirectory())/Library/Logs/ClaudeAlertBot"
```

**Phase 2 application:** Add `static let sessionsJSONPath: String = "\(appSupportDir)/sessions.json"` to existing `SocketPaths` enum (do **not** create a parallel `Phase2Paths` enum — extend the canonical one, per CLAUDE.md "strengthen the existing one rather than appending a parallel duplicate").

**Analog (directory + 0700 perms):** `App/AppDelegate.ensureDirectories` lines 48-56:
```swift
private func ensureDirectories() {
    let fm = FileManager.default
    for dir in [SocketPaths.appSupportDir, SocketPaths.logsDir] {
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        // Re-apply 0700 in case the directory pre-existed with different perms.
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
    }
}
```

**Phase 2 application:** sessions.json directory is *the same* `appSupportDir` — already 0700 from Phase 1. SessionStore does **not** need to re-create it. The file itself: use `Data.write(to:options:[.atomic])` per RESEARCH Pattern 5 (Foundation handles temp+rename). Set 0600 on the file after first write via `chmod` from `Darwin` (HookListener.swift line 36 pattern: `chmod(self.socketPath, 0o600)`).

**Persistence actor shape (no Phase 1 analog — RESEARCH Pattern 5 verbatim):**
```swift
// [research-only — no Phase 1 file]
actor SessionsPersistence {
    private let url: URL
    init(url: URL) { self.url = url }
    func save(...) async {
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: url, options: [.atomic])
    }
    func load() async -> SessionsSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionsSnapshot.self, from: data)
    }
}
```

**Corrupt-file handling** (UI-SPEC line 190 + RESEARCH Pattern 5 note): on decode failure, OSLog `.error` + rename `sessions.json` → `sessions.json.corrupt-{ts}` + boot empty queue.

---

### `App/NotificationOrchestrator.swift` (orchestrator, MainActor hop)

**Analog:** `App/AppDelegate.swift` (component wiring pattern, lines 13-17, 33-41)

**Excerpt** (AppDelegate.swift lines 13-46):
```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "lifecycle")
    private var listener: HookListener?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Validate socket path length (Pitfall #6)
        guard SocketPaths.validateSocketPathLength() else { ... }
        // 2. Ensure directories exist with mode 0700
        ensureDirectories()
        // 3. Stale-socket reclaim
        reclaimSocketIfStale(at: SocketPaths.socketPath)
        // 4. Start listener
        do {
            let l = HookListener(socketPath: SocketPaths.socketPath)
            try l.start()
            self.listener = l
        } catch { ... }
        // 5. Signal handlers
        installSignalHandler(SIGTERM)
        installSignalHandler(SIGINT)
    }
```

**Phase 2 application:** NotificationOrchestrator is `@MainActor final class` that owns:
- `private let widget: FloatingWidgetWindowController`
- `private let sound: SoundPlayer`
- weak `private weak var registry: SessionRegistry?` (or non-weak — see RESEARCH Pattern 2 line 357 `weak var notifier: NotificationOrchestrator?` for the symmetric direction)
- `present(session:playSoundOnce:)` / `refreshQueueState(...)` MainActor methods called by the actor.

Lifecycle wiring exactly mirrors AppDelegate's 5-step structure: numbered steps, comment per step, `do { try … } catch { log.error; NSApp.terminate(nil) }` on hard failure paths, store-or-die for retained components.

---

### `App/AppleScriptHelper.swift` (actor, BG queue)

**Analog:** `App/HookListener.swift` queue pattern (line 18, 47)

**Excerpt** (HookListener.swift lines 17-18, 47):
```swift
private let queue = DispatchQueue(label: "com.claudealert.bot.hook.listener")
...
listener.start(queue: queue)
```

**Phase 2 application:** AppleScriptHelper has its own dedicated **serial** queue with the same naming convention `com.claudealert.bot.applescript`. Per RESEARCH Pitfall 3, AppleScript is not main-thread safe and the queue must be serial (not the global concurrent queue).

**Logger pattern** (HookListener.swift lines 15-16):
```swift
private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "listener")
private let ingressLog = Logger(subsystem: "com.claudealert.bot.hook", category: "ingress")
```

**Phase 2 application:** New category `applescript` per D2-37 — log every cheap-query attempt/success/failure/timeout/permission-denied.

---

### `App/WakeObserver.swift`, `App/WorkspaceFrontmostObserver.swift`, `App/SessionGCTimer.swift` (observers/timers — must be retained)

**Analog:** `App/AppDelegate.installSignalHandler` lines 87-98

**Excerpt** (AppDelegate.swift lines 87-98):
```swift
private func installSignalHandler(_ sig: Int32) {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { [weak self] in
        self?.log.info("received signal \(sig) — shutting down")
        self?.listener?.cancel()
        NSApp.terminate(nil)
    }
    src.resume()
    // CRITICAL: retain the source — otherwise it's deallocated and signals are silently ignored.
    signalSources.append(src)
}
```

**Phase 2 application:** This is the *master template* for "observer/timer or it's silently lost":
- WakeObserver stores `private var token: NSObjectProtocol?` and removes it in `deinit` (RESEARCH Pattern 6 line 668)
- WorkspaceFrontmostObserver: same shape, different notification name (`NSWorkspace.didActivateApplicationNotification`)
- SessionGCTimer: `private var timer: DispatchSourceTimer?` retained on self; `setEventHandler { [weak self] in … }` + `timer.resume()` + store

The "CRITICAL: retain the source" comment from line 96 should be **copy-pasted verbatim** into each new observer file with file-appropriate substitutions. This is institutional knowledge from Phase 1.

---

### `App/FloatingWidgetWindowController.swift` (AppKit bridge)

**Analog:** `App/main.swift` lines 1-11 + `App/AppDelegate.swift` lines 33-41 (component lifecycle)

**Excerpt** (main.swift, full):
```swift
// App/main.swift — pure-AppKit headless entry (RESEARCH Pattern 3).
// LSUIElement=true in Info.plist suppresses Dock/menu-bar/Cmd-Tab; .accessory belt-and-suspenders.
// No NSApp.activate — Phase 1 app is invisible by contract (DIST-05, RESEARCH Anti-Patterns).
import AppKit

let delegate = AppDelegate()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
```

**Phase 2 application — invariant preservation:** Phase 2 does **not** call `NSApp.activate(ignoringOtherApps:)` even when the widget appears (RESEARCH Anti-Patterns line 865 + Phase 1 main.swift line 3 explicit comment). The NSPanel `.nonactivatingPanel` style mask + `becomesKeyOnlyIfNeeded = true` cover this; LSUIElement=true is preserved (Info.plist line 23-24 — `<key>LSUIElement</key><true/>`).

**Window controller construction pattern (RESEARCH Pattern 7 — no Phase 1 NSWindow code):**
```swift
// [research-only]
final class FloatingWidgetPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // ...
    }
}
```

---

### `App/SettingsStore.swift`, `App/SettingsView.swift` (Settings)

**Analog:** None in Phase 1 (Phase 1 deliberately ships zero SwiftUI scenes — RESEARCH Pattern 3 anti-pattern note in Plan 03 SUMMARY).

**Use RESEARCH Pattern 4 (line 587-612) verbatim** — the canonical pattern:
```swift
// [research-only]
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    @AppStorage("threshold_seconds") var thresholdSeconds: Int = 30
    @AppStorage("sound_enabled") var soundEnabled: Bool = true
    @AppStorage("widget_corner") private var cornerRaw: String = WidgetCorner.topRight.rawValue
    // ...
    @Published var applescriptPermission: PermissionStatus = .unknown
}
```

**Phase 2 single-direction rule (Anti-Patterns line 860):** SettingsStore does **not** hold a reference to SessionRegistry. Actor methods receive threshold/soundEnabled as **arguments** read at call time on MainActor (RESEARCH Pattern 2 line 478 explicit "Threshold 전달 규칙").

---

### `Reporter/cab-report.sh` (already complete — verification only)

**Analog (and currently-shipped pattern):** `Reporter/cab-report.sh` itself, lines 15-16:
```bash
# Event name from $1 (callers pass "stop" or "user_prompt_submit"); default "stop"
EVENT="${1:-stop}"
```

**Phase 2 application:** **No code change to Reporter/cab-report.sh**. The Phase 1 ship already implements the full HOOK-02 D-08 envelope branch. The `python3 -S` envelope builder at lines 42-69 already substitutes `EVENT` correctly. Phase 2 verification:

1. `dev-install-hook.sh --apply` registers both Stop and UserPromptSubmit (already does — lines 44-58, **already shipped**).
2. Trigger a UserPromptSubmit synthetic via `cab-test` modified to pass `event: "user_prompt_submit"` (one-line change to `CabTest/main.swift` line 11) OR add a second tiny CLI helper. Recommendation: extend `CabTest/main.swift` to accept `--event=stop|user_prompt_submit` argv, otherwise duplicate the binary.

---

### `CabTest/main.swift` (modify — add event argv)

**Analog:** `CabTest/main.swift` itself, lines 9-20 (current envelope dictionary):
```swift
let payload: [String: Any] = [
    "schema_version": 1,
    "event": "stop",
    "session_id": "cab-test-\(UUID().uuidString)",
    ...
]
```

**Phase 2 application — minimum change (CLAUDE.md "fix only the offending line"):**
```swift
// CabTest/main.swift line 11 (modified):
"event": CommandLine.arguments.dropFirst().first ?? "stop",
```

That single substitution lets the verifier fire `cab-test user_prompt_submit` immediately followed by `cab-test stop` (with same session_id via env var or argv) to exercise the full SessionRegistry start→stop sequence in `verify-phase-2.sh`. No other CabTest changes needed.

---

### `App/AppDelegate.swift` (modify — add Phase 2 components)

**Insertion point:** `applicationDidFinishLaunching` after step 5 (line 45-46), preserving the existing 5 numbered steps verbatim.

**Pattern (extend the existing numbered comment scheme):**
```swift
// 5. Signal handlers — clean shutdown removes socket file
installSignalHandler(SIGTERM)
installSignalHandler(SIGINT)

// 6. Settings store + sessions.json restore (Phase 2 SESS-03)
// 7. SessionRegistry actor + NotificationOrchestrator wiring (Phase 2 SESS-01)
// 8. FloatingWidgetWindowController construction + reposition (Phase 2 WIDG-*)
// 9. WakeObserver + GC timer + frontmost observer (Phase 2 SESS-04 + D2-15)
// 10. AppleScriptHelper.shared compile (Phase 2 D2-34) — eager compile, lazy permission trigger
```

Each new component is stored on `self` to retain (matching `private var listener: HookListener?` at line 15). New `private var` declarations go directly under the existing two (lines 15-16) — same style.

**Phase 1 listener integration in `HookListener.handle(buffer:)` lines 84-99:**
```swift
private func handle(buffer: Data) {
    do {
        let event = try JSONDecoder().decode(HookEvent.self, from: buffer)
        guard event.schema_version == 1 else { ... return }
        ingressLog.notice("ingress event=\(event.event, privacy: .public) ...")
    } catch {
        log.error("decode failed: \(String(describing: error), privacy: .public)")
    }
}
```

**Phase 2 minimum-edit modification:** insert one `Task { @MainActor in await SessionRegistry.shared.ingest(event, …) }` block after the existing `ingressLog.notice(…)` line (preserve the OSLog line — it's a Phase 1 verification anchor that Plan 03 row 1-04-01 still greps).

---

### `scripts/verify-phase-2.sh` (new — copy structure verbatim)

**Analog:** `scripts/verify-phase-1.sh` (entire file, 569 lines)

**Excerpt — header + record helpers** (verify-phase-1.sh lines 1-80):
```bash
#!/bin/bash
# verify-phase-1.sh — Single-shot validation harness for Phase 1 (Foundation).
set -uo pipefail
# NOTE: deliberately NO `-e` — we want every check to run even when an earlier
# one fails, then aggregate.

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; DIM='\033[2m'; RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; DIM=''; RESET=''
fi

# Constants — overridable via env for CI / alternate build dirs
APP_PATH="${APP_PATH:-build/export/ClaudeAlertBot.app}"
SOCK="$HOME/Library/Application Support/ClaudeAlertBot/sock"
LOG_FILE="$HOME/Library/Logs/ClaudeAlertBot/hook.log"
LOG_SUBSYS="com.claudealert.bot.hook"

# Aggregation
PASS=0; FAIL=0; SKIP=0; RESULTS=()

_record_pass() { ... }
_record_fail() { ... }
_record_skip() { ... }
```

**Phase 2 application:** Copy this scaffolding verbatim into `scripts/verify-phase-2.sh`. New constants for Phase 2:
```bash
SESSIONS_JSON="$HOME/Library/Application Support/ClaudeAlertBot/sessions.json"
LOG_SUBSYS_REGISTRY="com.claudealert.bot.hook"  # same — categories: registry, notification, widget, settings, applescript
```

**Per-row verifier function pattern** (verify-phase-1.sh lines 124-147 for `verify_1_01_02`):
```bash
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
```

**Phase 2 verifier names:** `verify_2_HH_NN` where `HH` is the REQ tier (e.g. 02 for SESS, 04 for WIDG, 06 for SET, 08 for AUD). Each row maps to a single bash function. Re-use `_ensure_app_running` helper (lines 155-164) verbatim — it already handles the cold-launch pattern.

**Latency budget pattern** (verify-phase-1.sh lines 269-285) — the `python3 + perf_counter()` micro-benchmark:
```bash
elapsed=$(python3 - <<'PY' 2>/dev/null || echo "999"
import subprocess, time
t = time.perf_counter()
subprocess.run([...], input=b"", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(f"{time.perf_counter()-t:.4f}")
PY
)
if awk -v e="$elapsed" 'BEGIN { exit !(e+0 <= 0.250) }'; then
    _record_pass "$id" "$name (${elapsed}s)"
else
    _record_fail "$id" "$name" "elapsed ${elapsed}s exceeds 0.250s budget"
fi
```

**Phase 2 application:** Same pattern for the AppleScript cheap-query 1-second budget (D2-34) and any new latency targets.

---

### `project.yml` (modify — add new Swift sources)

**Analog:** `project.yml` lines 7-22 (current ClaudeAlertBot target):
```yaml
targets:
  ClaudeAlertBot:
    type: application
    platform: macOS
    sources:
      - path: App
        name: App
    info:
      path: App/Info.plist
      properties:
        CFBundleIdentifier: com.claudealert.bot
        CFBundleName: Claude Alert Bot
        LSMinimumSystemVersion: "14.0"
        LSUIElement: true
        NSAppleEventsUsageDescription: "Claude Alert Bot needs to switch focus to your iTerm2 tab when a Claude Code task completes."
```

**Phase 2 application — zero-or-minimal change:** `path: App` already includes every `.swift` under `App/`. New Phase 2 files dropped into `App/` are auto-discovered — **no project.yml edit required** unless Phase 2 reorganizes into subdirectories (`App/UI/`, `App/Domain/`). Plan 03 SUMMARY shipped this as the working pattern.

If Phase 2 needs to update the Korean copy on `NSAppleEventsUsageDescription` (per D2-33), modify line 21 of project.yml AND `App/Info.plist` line 26 — both must match (`xcodegen` regenerates from project.yml but Info.plist on disk is the source for runtime).

**Critical preservation:** Do **not** alter `postBuildScripts` (lines 36-56). Those embed cab-test and cab-report.sh; Plan 03 had to fight `embed: true` defaults and the current state is the working configuration.

---

## Shared Patterns

### 1. OSLog subsystem extension

**Source:** `App/HookListener.swift` lines 15-16, `App/AppDelegate.swift` line 14

**Apply to:** Every new actor / class / orchestrator in Phase 2.

**Pattern:**
```swift
private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "<phase2-category>")
```

**Phase 2 categories** (per CONTEXT D2-31 + D2-37): `registry`, `notification`, `widget`, `settings`, `applescript`. The subsystem string is **invariant** — never use a different subsystem (`verify-phase-1.sh` line 45 hard-codes `LOG_SUBSYS="com.claudealert.bot.hook"`; verify-phase-2.sh inherits this).

**Privacy annotation contract (D-07 carry-over):** Every interpolated string uses `privacy: .public` for now, with the inline comment `// NOTE (Phase 5 review): … reclassify to .private once OSLog is no longer the primary verification surface.` (HookListener.swift lines 92-93 verbatim — copy this comment into each new file that logs user data).

### 2. DispatchSource / observer retention

**Source:** `App/AppDelegate.swift` lines 87-98 (`installSignalHandler`)

**Apply to:** `App/WakeObserver.swift`, `App/WorkspaceFrontmostObserver.swift`, `App/SessionGCTimer.swift`, and the AppDelegate addition that owns them.

**Pattern (verbatim):**
```swift
// CRITICAL: retain the source — otherwise it's deallocated and signals are silently ignored.
signalSources.append(src)
```

This single comment is institutional knowledge — copy it into each new file.

### 3. Single-source-of-truth path constants

**Source:** `App/SocketPaths.swift` (entire file)

**Apply to:** Any new path Phase 2 introduces (sessions.json, plus any future Phase 2 paths). **Extend the existing `SocketPaths` enum** rather than creating a parallel one.

```swift
// Add to SocketPaths.swift:
static let sessionsJSONPath: String = "\(appSupportDir)/sessions.json"
```

CLAUDE.md "strengthen the existing one rather than appending a parallel duplicate" applies directly here.

### 4. Codable struct conventions

**Source:** `App/HookEvent.swift` (full file, 19 lines)

**Apply to:** `App/SessionRecord.swift` and any other model file.

**Conventions extracted:**
- Header comment names the file path + one-line purpose
- RESEARCH/Pitfall/Decision IDs cited inline in comments
- `import Foundation` only
- Optional fields are `String?`/`Int?` — never `String!` or empty-string-as-nil
- Snake_case field names match the JSON wire format (`schema_version`, `session_id`) when interoperating with Reporter/sessions.json
- Trailing inline comment with enumerated values for string-typed fields

### 5. Atomic file ops (extension of Phase 1's atomic socket bind)

**Source pattern (Phase 1 socket bind exclusivity):** D-09 single-instance lock (HookListener.swift lines 37-39 — `.failed` → `NSApp.terminate(nil)`).

**Phase 2 echo:** sessions.json atomic write via `Data.write(to:options:[.atomic])`. The conceptual "atomic operation as primary correctness guarantee" pattern is shared. Both succeed-or-fail with no partial state.

### 6. ad-hoc codesign + LSUIElement invariant

**Source:** `App/main.swift` lines 1-11, `App/Info.plist` lines 23-24, `project.yml` lines 29-31

**Apply to:** Every Phase 2 artifact. **Do not introduce** any Phase 2 code that:
- Calls `NSApp.activate(ignoringOtherApps:)` (Phase 1 main.swift line 3 explicit anti-pattern comment)
- Sets `LSUIElement=false` or removes the key
- Adds a `<NSPrincipalClass>` that creates a Dock-visible window
- Requires Apple Developer signing (Phase 2 must continue to work with `codesign --force --sign -`)

The existing `NSAppleEventsUsageDescription` Info.plist key (line 25-26) is already present from Phase 1; Phase 2's only Info.plist work is **reviewing the Korean copy** per D2-33 (currently English: "Claude Alert Bot needs to switch focus to your iTerm2 tab when a Claude Code task completes.").

### 7. cab-test / verify harness loop

**Source:** `CabTest/main.swift` (full file) + `scripts/verify-phase-1.sh` `_ensure_app_running` helper (lines 155-164)

**Apply to:** Every Phase 2 verification row. The pattern is:
1. `_ensure_app_running` (helper from Phase 1, copy verbatim)
2. Fire synthetic envelope via cab-test (modify CabTest/main.swift to accept event argv)
3. Sleep 1-2s
4. `log show --last 5s --predicate "subsystem == \"$LOG_SUBSYS\"" | grep <expected-pattern>`
5. PASS/FAIL via `_record_pass`/`_record_fail`

This loop is the canonical Phase 1 → Phase 2 verification pattern. Plan 03 SUMMARY's "Open Issues 2 & 3" already document the BSD-pgrep gotchas; Phase 2 inherits both fixes (full-path anchoring + `wc -l | tr -d ' '`).

---

## No Analog Found

Files with no close match in the Phase 1 codebase. Planner should use RESEARCH.md patterns directly:

| File | Role | Reason | RESEARCH reference |
|------|------|--------|--------------------|
| `App/SettingsView.swift` | SwiftUI view | Phase 1 deliberately ships zero SwiftUI scenes (Plan 03 SUMMARY: "no SwiftUI; Settings { EmptyView() } anti-pattern avoided") | RESEARCH Code Examples §SettingsView (lines 1019-1064) |
| `App/FloatingWidgetPanel.swift` (NSPanel subclass) | AppKit view-class | First NSPanel/NSWindow code in repo | RESEARCH Pattern 7 (lines 672-708) |
| `App/WidgetIconView.swift`, `App/PopoverContentView.swift`, `App/PopoverRowView.swift`, `App/PermissionBannerView.swift` | SwiftUI views | First SwiftUI views in repo | RESEARCH Pattern 8 + UI-SPEC §"Hover Popover" / §"Permission Banner" |
| `App/SoundPlayer.swift` | AVAudioPlayer wrapper | First audio code in repo | RESEARCH Pattern 10 (lines 801-832) |
| `App/PermissionDeepLink.swift` | URL fallback chain | First system-deep-link code | RESEARCH Pattern 12 (lines 837-856) |

All 7 of these have explicit, tested pattern sources in `02-RESEARCH.md` — planner should cite the RESEARCH section + line range in each plan's action block, not invent fresh patterns.

---

## Metadata

**Analog search scope:** `/Users/choijihye/Study/source/claude_alert_bot/App/`, `/CabTest/`, `/Reporter/`, `/scripts/`, `/project.yml`
**Files scanned:** 11 (all Phase 1 source files: 6 Swift + 1 plist + 1 sh + 1 yml + 2 verify/install scripts)
**Phase 1 lines analyzed:** ~750 (all read in full; small files)
**Pattern extraction date:** 2026-05-07
**Pattern reuse rate:** 18 / 22 new files have a Phase 1 analog (82%); the remaining 4 categories (SwiftUI views, NSPanel subclass, AVAudioPlayer wrapper, deep-link helper) are intentional Phase 2 first-introductions backed by RESEARCH patterns.

---

*Phase: 02-alert-loop*
*Pattern map produced: 2026-05-07*
