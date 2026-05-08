# Phase 3: Click-to-iTerm2 — Pattern Map

**Mapped:** 2026-05-08
**Files analyzed:** 5 new + 7 modified = 12
**Analogs found:** 12 / 12 (100% — Phase 2 codebase covers all Phase 3 introductions)

> Downstream: `gsd-planner` reads this to assign concrete copy-from sources for every Phase 3 plan. All excerpts are verbatim from Phase 1+2 source as of HEAD (commit `6976fc8`). Phase 3는 새 외부 의존 0(D2-29 invariant) — 모든 새 파일이 기존 actor / SwiftUI / namespace 패턴 재사용으로 처리된다.

---

## File Classification

### New Swift sources (App target)

| File | Role | Data Flow | Closest Analog | Match Quality |
|------|------|-----------|----------------|---------------|
| `App/TerminalJumper.swift` | protocol seam (D-ADAPTER) | request-response (call args; awaitable) | `App/SessionRegistry.swift` lines 8-11 (`NotifierProtocol` inline) + `App/FloatingWidgetWindowController.swift` lines 13-16 (`WidgetHoverDelegate` inline) | exact (Phase 2 file-ownership convention: protocol inline in primary owner — but D3-ADAPTER calls for the protocol's own file because both `WidgetPopoverController` and `ITerm2Jumper` consume it; analog = the *shape* of those declarations, applied to a standalone file) |
| `App/ITerm2Jumper.swift` | concrete adapter / thin orchestrator | request-response (delegates to AppleScriptHelper actor) | `App/NotificationOrchestrator.swift` lines 38-89 (thin `@MainActor` coordinator that translates registry events → widget+sound calls) | exact (NotificationOrchestrator is the *paradigm* "thin coordinator that owns dependencies and translates one signal into a handful of typed downstream calls" — ITerm2Jumper does the same: `CompletedSession → AppleScriptHelper.jump(itermSessionID:) → JumpResult`) |
| `App/iTermSessionID.swift` | utility namespace (transform) | pure function (transform String → String?) | `App/ProjectName.swift` (full file, 27 lines) | exact (small `enum`-of-static-funcs Foundation-only; `ProjectName.derive(cwd:claudeProjectDir:)` ↔ `iTermSessionID.uuid(fromRaw:)` — same namespace + same call shape) |

### Modified Swift sources

| File | Insertion Point | Pattern Source |
|------|-----------------|----------------|
| `App/AppleScriptHelper.swift` | After `scriptSource` (line 38), `ensureCompiled` (line 47), `frontmostMatches` (line 51-68); add new `JumpResult` enum sibling to `ScriptResult` (line 13-18) | Self-analog — extend the actor with parallel `static let jumpScriptSource` + `static let focusFrontmostScriptSource` + `private var compiledJump: NSAppleScript?` + `private var compiledFocus: NSAppleScript?` mirroring the existing single-script triple of constants/state/methods |
| `App/PopoverRowView.swift` | Add `@State private var rowState: RowState` (after line 13) + state-driven modifiers in body (after line 50) | Self-analog — existing `@State private var isHovered` + `.background(... isHovered ? ... : ...)` + `.animation(.easeInOut(duration:0.12), value: isHovered)` (lines 13, 41-43) |
| `App/PopoverContentView.swift` | `onRowClick` callback signature unchanged; popover may need to forward jump completion to row state (D3-11) | Self-analog — keep signature `onRowClick: (String) -> Void` (line 40); state ownership lives in `PopoverRowView` per D3-11 |
| `App/WidgetPopoverController.swift` | Replace `onRowClick(sessionID:)` body (lines 95-100) with `Task { await jumper.jump(...) }` + result-driven row state notification | Self-analog — preserve OSLog signature pattern (`[would-jump session=...]` → `[jumped session=...]` / `[jump-missed session=...]`) per D3-13 |
| `App/SettingsView.swift` | New SET-05 Section after existing testing section (line 65); new copy constants at top (after line 21) | Self-analog — Section + `static let` block (lines 11-21) + Button (lines 58-64) + onAppear path A (lines 70-76) all already in this file |
| `App/SettingsStore.swift` | Add `@AppStorage` after line 17 (within existing block) | Self-analog — existing `@AppStorage("widget_offset_y") var offsetY: Int = 16` lines 13-17. Date workaround = TimeInterval-backed Double (see Pattern Assignments §SettingsStore) |
| `App/SessionStore.swift` | Add UUID-strip migration in `load()` after successful decode (between lines 56 and 57) | Self-analog — corrupt-rename branch (lines 51-55) is the closest "post-decode mutation" hook; migration is a sibling step that runs *between* successful decode and return |
| `App/HookEvent.swift` | Add `let term_program: String?` after line 17 | Self-analog — every other field on the struct (lines 11-18) is already optional; Codable accepts missing field via Swift optional unwrap — no custom init required |
| `Reporter/cab-report.sh` | Add `TERM_PROGRAM_VAL="${TERM_PROGRAM:-}"` capture line (next to line 22) + python env injection (next to line 36) + JSON field (next to line 62-63) | Self-analog — `ITERM_SESSION_ID_VAL` (line 22), `nz(env("ITERM"))` python helper, `"iterm_session_id": nz(env("ITERM"))` JSON line — all three sites get a `TERM_PROGRAM` parallel |

### New + extended test files

| File | New / Extension | Closest Analog |
|------|-----------------|----------------|
| `ClaudeAlertBotTests/iTermSessionIDTests.swift` | new | `ClaudeAlertBotTests/ProjectNameTests.swift` (full file, 36 lines) — exact (pure-function test, 5 cases, one per branch) |
| `ClaudeAlertBotTests/AppleScriptHelperTests.swift` | extend | self-analog — existing `test_classifyError_*` quartet (lines 26-43) + `test_compileOnce_*` (lines 45-53) + `test_scriptSource_containsAppleScriptTimeout` (lines 14-24) |
| `ClaudeAlertBotTests/PopoverContentTests.swift` | extend (or new `PopoverRowStateTests.swift`) | self-analog — existing `PopoverContentRules.*` pure-function tests (lines 11-49). Recommended: add new file `PopoverRowStateTests.swift` to keep PopoverContentTests focused on `PopoverContentRules` namespace |
| `ClaudeAlertBotTests/SettingsViewTests.swift` | extend | self-analog — `test_settingsCopy_*` quintet (lines 24-44). Add SET-05 verbatim copy assertion in same shape |
| `ClaudeAlertBotTests/SessionStoreTests.swift` | extend | self-analog — existing `test_saveAndLoad_roundTrip` (line 30) + corrupt-recovery cases. Add `test_load_migrates_envelopeFormatItermID` |
| `ClaudeAlertBotTests/Fixtures/HookEventFactory.swift` | extend (optional) | self-analog — existing `stop(...)` JSON template (line 16). Add `term_program: String? = nil` parameter and inject when non-nil |

---

## Pattern Assignments

### `App/TerminalJumper.swift` (protocol seam)

**Analog:** `App/SessionRegistry.swift` lines 8-11 + `App/FloatingWidgetWindowController.swift` lines 13-16

**Inline-protocol pattern (SessionRegistry.swift lines 8-11):**
```swift
@MainActor protocol NotifierProtocol: AnyObject {
    func present(session: CompletedSession, playSoundOnce: Bool) async
    func refreshQueueState(completed: [CompletedSession], count: Int) async
}
```

**Inline-protocol pattern (FloatingWidgetWindowController.swift lines 13-16):**
```swift
@MainActor protocol WidgetHoverDelegate: AnyObject {
    func widgetMouseEntered()
    func widgetMouseExited()
}
```

**Phase 3 application:** Phase 2's convention is **protocol declared inline above the primary owner type**. D-ADAPTER explicitly inverts that (CONTEXT D3-ADAPTER: dedicated file `App/TerminalJumper.swift`). Reason for inversion: two different consumers in different files (`WidgetPopoverController` calls; `ITerm2Jumper` implements) and a v2 multi-terminal seam is the whole point — the protocol must live in the file that *names* the seam.

**Pattern shape to copy:**
- File header: `// App/TerminalJumper.swift — Phase 3 D-ADAPTER seam. v1 single impl = ITerm2Jumper.`
- One-line cite: `// CONTEXT.md D-ADAPTER + D3-06..09. v2 multi-terminal adds new conformers.`
- `@MainActor protocol TerminalJumper: AnyObject`
- Method signature: `func jump(to session: CompletedSession) async -> JumpResult`
- `JumpResult` enum lives **here** (not in AppleScriptHelper) because it is the protocol's contract surface. AppleScriptHelper-internal `ScriptResult` (line 13-18) maps **into** `JumpResult`, not the other way.

**Suggested `JumpResult` shape (per D3 closing remarks + D3-19):**
```swift
enum JumpResult: Equatable {
    case ok
    case missing                  // session UUID not found — D3-11 도리도리 UX
    case permissionDenied         // -1743 — D3-19 권한 거부 분기
    case iTermNotRunning          // SET-05 specific — frontmost-focus 빈 응답
    case otherError(Int)
}
```

**Diff size:** small (~25 lines new file).

**Cross-cutting invariants:**
- D2-29 zero deps — `import Foundation` only (model types). No AppKit/SwiftUI in protocol file.
- Comment header cites CONTEXT IDs (D-ADAPTER, D3-06, D3-19) per HookEvent.swift line 2-5 convention.

---

### `App/ITerm2Jumper.swift` (concrete adapter)

**Analog:** `App/NotificationOrchestrator.swift` lines 38-89 (`@MainActor final class … : NotifierProtocol`)

**Closest reasoning:** ITerm2Jumper is the *exact same shape* as NotificationOrchestrator —
- both are `@MainActor final class`
- both are constructor-injected with their downstream dependency (NotifOrch ← `WidgetControllerProtocol`+`SoundPlaying`; ITerm2Jumper ← AppleScriptHelper-by-shared-singleton, plus optional injectable seam for tests)
- both translate one signal into a handful of typed downstream calls
- both log every public method entry/result via `Logger(subsystem: "com.claudealert.bot.hook", category: <category>)`
- both have a single retain owner (AppDelegate retains NotifOrch; WidgetPopoverController will retain ITerm2Jumper per CONTEXT D3 Discretion)

**Class declaration pattern (NotificationOrchestrator.swift lines 38-54):**
```swift
@MainActor
final class NotificationOrchestrator: NotifierProtocol {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "notification")
    private weak var widget: (any WidgetControllerProtocol)?
    private let sound: any SoundPlaying
    private let settings: () -> SettingsStore   // closure so tests can swap

    init(widget: (any WidgetControllerProtocol)?,
         sound: any SoundPlaying,
         settings: @autoclosure @escaping () -> SettingsStore = SettingsStore.shared) {
        self.widget = widget
        self.sound = sound
        self.settings = settings
    }
```

**Phase 3 application — ITerm2Jumper init shape:**
```swift
@MainActor
final class ITerm2Jumper: TerminalJumper {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "widget")  // share with popover for OSLog [jump*-prefix*]
    private let helper: AppleScriptHelper

    init(helper: AppleScriptHelper = .shared) {
        self.helper = helper
    }

    func jump(to session: CompletedSession) async -> JumpResult { … }
}
```

**Translation pattern (NotifOrch's `present` → translate registry signal to widget call):**
```swift
// NotificationOrchestrator.swift lines 68-77 — public entry, log, dispatch, log
func present(session: CompletedSession, playSoundOnce: Bool) async {
    let store = settings()
    widget?.showWidget(pendingCount: 1, latest: session)
    if playSoundOnce && store.soundEnabled {
        sound.playOnce()
        log.notice("present session=\(session.sessionID, privacy: .public) sound=on")
    } else {
        log.notice("present session=\(session.sessionID, privacy: .public) sound=off ...")
    }
}
```

**Phase 3 application — ITerm2Jumper.jump body shape (translate one signal → AppleScriptHelper call → typed result):**
1. Guard `session.itermSessionID` non-nil (CompletedSession field is optional). If nil → `.missing` immediately + log.
2. `let result = await helper.jump(itermSessionID: uuid)` (new actor method per D3-09).
3. `switch result { … }` map → `JumpResult`.
4. Log `[jumped session=…]` on `.ok`, `[jump-missed session=…]` on `.missing` per D3-13.

**Diff size:** small (~50 lines).

**Cross-cutting invariants:**
- **D3-10 Pitfall #1 regression guard:** **Never** call `NSApp.activate(...)` in this file. Activation lives entirely in the AppleScript-side `tell application "iTerm2" to activate`. CONTEXT D3-10: `grep -c 'NSApp.activate' App/ITerm2Jumper.swift` MUST be 0. (Mirror FloatingWidgetWindowController.swift lines 5-6 anti-pattern comment verbatim.)
- **OSLog category `widget`** — share with popover so `[jump*-prefix*]` filters match the existing `[would-jump session=...]` line that PopoverController emitted (preserves Phase 2 verifier grep contract).
- **No SettingsStore reads** — ITerm2Jumper is single-direction-downstream-only (mirror NotifOrch's "View → Store → Registry/Helper" rule per CONTEXT D2-30).

---

### `App/iTermSessionID.swift` (utility namespace)

**Analog:** `App/ProjectName.swift` (full file, 27 lines)

**Excerpt** (ProjectName.swift, full file):
```swift
// App/ProjectName.swift — Phase 2 D2-06 project-name derivation.
// Rule: prefer cwd basename. Fall back to claude_project_dir basename. Sentinel "unknown" if both nil.
// PATTERNS.md §ProjectName: small enum-of-static-funcs Foundation-only, mirrors SocketPaths style.
import Foundation

enum ProjectName {
    /// D2-06: "프로젝트명만 (cwd basename 또는 CLAUDE_PROJECT_DIR basename)"
    static func derive(cwd: String?, claudeProjectDir: String?) -> String {
        if let s = cwd, !s.isEmpty { return basename(of: s) }
        if let s = claudeProjectDir, !s.isEmpty { return basename(of: s) }
        return "unknown"
    }

    private static func basename(of path: String) -> String { … }
}
```

**Phase 3 application — `iTermSessionID.swift` shape:**
```swift
// App/iTermSessionID.swift — Phase 3 D3-01 UUID 정규화 추출자.
// Rule: "wXtYpZ:UUID-XXXX" envelope → "UUID-XXXX". ":" 미포함 입력은 그대로 반환 (legacy 안전망).
// PATTERNS.md §iTermSessionID: ProjectName과 동일한 enum-of-static-funcs Foundation-only.
import Foundation

enum iTermSessionID {
    /// D3-01: Reporter envelope `iterm_session_id`는 `wXtYpZ:UUID` 형식.
    /// iTerm2 AppleScript `id of session`은 UUID-only — Swift-side에서 strip한 뒤 비교한다.
    static func uuid(fromRaw raw: String?) -> String? {
        guard let s = raw, !s.isEmpty else { return nil }
        if let colonIdx = s.lastIndex(of: ":") {
            let after = s.index(after: colonIdx)
            let uuid = String(s[after...])
            return uuid.isEmpty ? nil : uuid
        }
        return s   // legacy — 이미 UUID-only로 들어온 입력은 그대로 통과 (D3-01 안전망)
    }
}
```

**Why ProjectName is the closest analog:**
1. Same role: pure-function namespace.
2. Same data flow: `String? → String?` transform.
3. Same convention: header comment with rule + invariant cite, `enum`-of-static-funcs, `import Foundation` only.
4. Same testing pattern (ProjectNameTests covers each branch with one method) — directly portable.

**Diff size:** small (~20 lines new file).

**Cross-cutting invariants:**
- D2-29 zero deps; Foundation only.
- D3-04 회귀 가드: nil/empty/colonless/colon-with-empty-suffix 모두 단위 테스트 (ProjectNameTests의 5-case 패턴 그대로).

---

### `App/AppleScriptHelper.swift` (extend — 2 new compiled scripts + actor methods)

**Analog:** Self — extend the existing actor verbatim using the same `static let scriptSource` + `ensureCompiled` + `runQuery` + `classify` + private state shape.

**Existing single-script shape (AppleScriptHelper.swift lines 31-89 — verbatim):**
```swift
// SECURITY (T-INJECTION-01): static string constant — no `target` interpolation. Match is in Swift.
private static let scriptSource: String = """
with timeout of 1 second
    tell application "iTerm2"
        if (count of windows) is 0 then return ""
        return id of current session of current tab of current window
    end tell
end timeout
"""

private init() {}

private func ensureCompiled() {
    guard compiled == nil else { return }
    let s = NSAppleScript(source: Self.scriptSource)
    _ = s?.compileAndReturnError(nil)
    compiled = s
}

func frontmostMatches(itermSessionID target: String) async -> Bool {
    let result = await runQuery()
    switch result {
    case .success(let s):
        await markGranted()
        return !s.isEmpty && s == target
    case .denied: …
    }
}

private func runQuery() async -> ScriptResult {
    ensureCompiled()
    guard let script = compiled else { return .otherError(0) }
    return await withCheckedContinuation { (cont: CheckedContinuation<ScriptResult, Never>) in
        queue.async {
            var errInfo: NSDictionary?
            let result = script.executeAndReturnError(&errInfo)
            let value = result.stringValue ?? ""
            cont.resume(returning: Self.classify(error: errInfo, result: value))
        }
    }
}
```

**Phase 3 extensions (D3-17 — actor now owns 3 compiled scripts):**

1. **`jumpScriptSource`** (3s timeout, returns "ok" or "missing" — D3-09 + D3 Discretion):

   Per CONTEXT D3 Discretion clause: "AppleScript은 UUID 리스트만 반환하고 Swift-side에서 매칭 + 두 번째 AppleScript로 select 실행 — 2-step 처리. 또는 AppleScript 변수를 외부에서 주입(`NSAppleScript.executeAppleEvent(...)` 매개변수 방식). 둘 중 plan-phase에서 RESEARCH 후 결정."

   **Recommended pattern (planner to RESEARCH-confirm):** AppleScript reads the target UUID from an Apple Event parameter, comparing inside the script (avoids interpolation). Static script source. UUID is bound at execute time via `NSAppleScript.executeAppleEvent(_:error:)`. **OR** alternative: query-then-act 2-step (first script returns all UUIDs flattened; Swift matches; second compiled script "select-by-position" using window/tab indices).

   *Phase 3 plan-phase decides; pattern source for either path is the existing single-script shape above.*

2. **`focusFrontmostScriptSource`** (3s timeout — SET-05):
   ```swift
   // (illustrative; planner finalizes — copy timeout block + iTerm2 tell shape from line 31-38)
   private static let focusFrontmostScriptSource: String = """
   with timeout of 3 seconds
       tell application "iTerm2"
           if (count of windows) is 0 then return ""
           activate
           return id of current session of current tab of current window
       end tell
   end timeout
   """
   ```

3. **State extension:**
   ```swift
   private var compiledJump: NSAppleScript?
   private var compiledFocus: NSAppleScript?
   ```

4. **`ensureCompiled()` → split into 3 (mirror line 42-47):**
   ```swift
   private func ensureCompiledQuery()  { /* existing */ }
   private func ensureCompiledJump()   { /* same shape, jumpScriptSource + compiledJump */ }
   private func ensureCompiledFocus()  { /* same shape, focusFrontmostScriptSource + compiledFocus */ }
   ```

5. **New actor methods:**
   - `func jump(itermSessionID uuid: String) async -> JumpResult` — runs jumpScriptSource, classifies result, maps `ScriptResult → JumpResult`.
   - `func testConnection() async -> JumpResult` — D3-16 권한 분기:
     - if `lastKnownPermission == .denied` → return `.permissionDenied` immediately + log.
     - if `lastKnownPermission == .unknown` → call `triggerPermissionPrompt()` (existing line 72-74) + after dialog runs, retry with focus script.
     - if `.granted` → run `focusFrontmostScriptSource`. Empty result → `.iTermNotRunning`. Non-empty → `.ok`.

**Diff size:** medium (~80 lines added to existing file). Existing `frontmostMatches` / `runQuery` / `classify` / state-mirror helpers all reused unchanged.

**Cross-cutting invariants:**
- **T-INJECTION-01:** Static string constants only. No string interpolation of `uuid` into `jumpScriptSource`. Either Apple Event parameter binding *or* 2-step query+act (CONTEXT D3 Discretion lock to RESEARCH).
- **Pitfall 3:** Each script's own `with timeout of N seconds` block (1s for cheap-query existing, 3s for new two scripts per D3-09). Serial queue `com.claudealert.bot.applescript` shared by all three scripts (queue is one-per-actor; do not introduce a parallel queue).
- **Compile-once contract:** `ensureCompiled*` only initializes when `nil`; AppleScriptHelperTests `test_compileOnce_secondCallReusesInstance` regression guard extends to all three.
- **D3-10:** No `NSApp.activate(...)` anywhere in this file. Activation done by AppleScript-side `tell application "iTerm2" to activate` only.

---

### `App/PopoverRowView.swift` (modify — add `RowState` + animations)

**Analog:** Self — existing `@State` + `.background(... isHovered ? ...)` + `.animation(...)` triple already in this file (lines 13, 41-43).

**Existing animation/state pattern (PopoverRowView.swift lines 13, 40-43):**
```swift
@State private var isHovered: Bool = false
…
.background(
    isHovered ? Color(NSColor.controlAccentColor).opacity(0.12) : Color.clear
)
.animation(.easeInOut(duration: 0.12), value: isHovered)
```

**Phase 3 application — D3-11 row state machine (3 states):**
```swift
enum RowState { case normal, jumping, missing }

@State private var rowState: RowState = .normal
@State private var isHovered: Bool = false   // existing — keep
@State private var bounceAngle: Double = 0   // 도리도리 ±12° 1왕복
```

**State transitions (D3-11):**
- `normal` → click → `jumping` (살짝 회색 + 비활성, 3s timeout 동안 클릭 무시 — 디바운스 역할 자체)
- `jumping` → 결과 분기:
  - 성공 → `clearOne` 호출, popover 닫힘 (row consumes itself via SessionRegistry refresh)
  - 실패(missing) → `missing`
- `missing` → 0~0.3s 도리도리 (`rotationEffect(.degrees(bounceAngle))` + `withAnimation`) → 0.3~0.7s `frame(height: 0)` + `.opacity(0)` → 0.7s 후 `clearOne(sessionID:)`

**Click handler shape (replaces existing line 16 `Button(action: onClick)`):**
```swift
Button(action: {
    guard rowState == .normal else { return }   // D3-11 디바운스 (CONTEXT Discretion)
    rowState = .jumping
    onClick()   // PopoverContentView → WidgetPopoverController → Task { await jumper.jump(...) }
})
```

**Result-driven state push:** PopoverRowView is a leaf View with no SessionRegistry access. The state push must come from the click owner. Options for planner:
- **Option A (preferred — minimum signature drift):** Add a callback `onJumpResult: (JumpResult) -> Void` from popover content view down (or use SwiftUI environment).
- **Option B:** Make the row observe a `@Binding<RowState>` per session and let `WidgetPopoverController` mutate it.
- **Option C:** Move state machine entirely into `PopoverContentView` and pass `state` down as a `let`.

CONTEXT.md D3-11 doesn't lock the binding direction — planner's call. Existing pattern: PopoverRowView already accepts `let session`, `let showTimeSuffix`, `let onClick` (lines 9-11) — adding one more `let state: RowState` keeps the row pure (Option C).

**Diff size:** medium (~40 lines: `RowState` enum + 2 new `@State` or 1 new `let` + 3 `.modifier` chains for jumping/missing styling + animation closures).

**Cross-cutting invariants:**
- **D3-12:** No text labels / sound / system notifications in jumping/missing states. Animation alone communicates outcome.
- **No new copy strings** — T-COPY-DRIFT-01 lock skipped here (no user-facing text added). Accessibility label stays as line 50 `"\(session.projectName) 작업 완료, 클릭하여 정리"` unchanged.
- **Reduced motion fallback:** `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` should skip the bounce animation, mirror FloatingWidgetWindowController.swift lines 113-115. Plan-phase: confirm whether D3-11 missing UX honors reduced-motion (CONTEXT silent — recommend yes per Phase 2 02-07 precedent).

---

### `App/PopoverContentView.swift` (modify — forward jump completion)

**Analog:** Self — current `onRowClick: (String) -> Void` callback flow (lines 40, 67).

**Existing callback wiring (PopoverContentView.swift lines 38-78):**
```swift
struct PopoverContentView: View {
    let queue: [CompletedSession]
    let onRowClick: (String) -> Void   // sessionID
    let onClearAll: () -> Void
    …
    PopoverRowView(
        session: session,
        showTimeSuffix: dupProjects.contains(session.projectName),
        onClick: { onRowClick(session.sessionID) }
    )
```

**Phase 3 application:** Two forks depending on Option (A/B/C above) chosen for state ownership:

- **Option C (state down):** Add `let rowStates: [String: RowState]` map keyed by sessionID; pass `state: rowStates[session.sessionID] ?? .normal` to PopoverRowView. ContentView itself is still pure (no `@State`); the dictionary comes from `WidgetPopoverController`.
- **Option A:** Add `onRowClick: (String) async -> JumpResult` (signature change — async + return type). Row awaits result inside its own button action.

CONTEXT.md keeps the `onRowClick` signature open — planner picks. The callback itself remains the integration seam.

**Diff size:** small (~5-10 lines, exact size depends on option chosen).

**Cross-cutting invariants:**
- Preserve Pure Display Rules (`PopoverContentRules` enum) — do not add state mutation logic to that namespace.
- `shouldShowClearAll` still gated on `queue.count >= 2` — no change (D2-07 Phase 2 lock).

---

### `App/WidgetPopoverController.swift` (modify — D2-08 hook → real jump)

**Analog:** Self — `onRowClick(sessionID:)` lines 95-100.

**Existing D2-08 placeholder (WidgetPopoverController.swift lines 93-100):**
```swift
// MARK: - actions (D2-08 + D2-07)

private func onRowClick(sessionID: String) {
    // D2-08 verbatim — Phase 3 ITermBridge inherits the [would-jump session=<uuid>] format.
    log.notice("[would-jump session=\(sessionID, privacy: .public)]")
    Task { await SessionRegistry.shared.clearOne(sessionID: sessionID) }
    dismissPopover()
}
```

**Phase 3 replacement (D3-13 OSLog + D3-06 jump dispatch + D3-11 result branch):**
```swift
// MARK: - actions (D3-06 jump + D3-11 missing UX)

private func onRowClick(sessionID: String) {
    guard let session = currentSessionsByID[sessionID] else { return }
    Task { [weak self] in
        guard let self else { return }
        let result = await self.jumper.jump(to: session)
        await MainActor.run {
            switch result {
            case .ok:
                self.log.notice("[jumped session=\(sessionID, privacy: .public)]")
                Task { await SessionRegistry.shared.clearOne(sessionID: sessionID) }
                self.dismissPopover()
            case .missing:
                self.log.notice("[jump-missed session=\(sessionID, privacy: .public)]")
                // D3-11: row 자체가 도리도리 + collapse 후 SessionRegistry.clearOne 호출
                self.notifyRowMissing(sessionID: sessionID)
            case .permissionDenied:
                self.log.warning("[jump-denied session=\(sessionID, privacy: .public)]")
                PermissionDeepLink.openAutomationPreferences()
            case .iTermNotRunning, .otherError:
                self.log.warning("[jump-error session=\(sessionID, privacy: .public)]")
                self.notifyRowMissing(sessionID: sessionID)   // 동일 UX
            }
        }
    }
}
```

**New private state on this controller:**
- `private let jumper: any TerminalJumper` (constructor-injected per CONTEXT D3 Discretion).
- Lookup map `currentSessionsByID: [String: CompletedSession]` populated from `controller.queueSnapshot` at popover-show time (line 53). Or pass session directly through closure: `onRowClick: (CompletedSession) -> Void` (one-line signature change).

**Init signature change (line 24-27):**
```swift
init(widgetController: FloatingWidgetWindowController, jumper: any TerminalJumper = ITerm2Jumper()) {
    self.widgetController = widgetController
    self.jumper = jumper
    super.init()
}
```

**Diff size:** medium (~40 lines: init signature, new property, body of `onRowClick` rewritten, new helper `notifyRowMissing`).

**Cross-cutting invariants:**
- **D3-13 OSLog prefix preservation:** `[jumped session=...]`, `[jump-missed session=...]`, `[jump-denied session=...]`, `[jump-error session=...]` — all start with `[jump` so `log show --predicate ... | grep '\[jump'` filters keep working. (Phase 2 verifier pattern.)
- **D3-10 Pitfall #1:** Do not call `NSApp.activate(...)` in this file. (Already absent — keep absent.)
- **D2-08 OSLog signature preservation in spirit:** old `[would-jump session=...]` literal disappears, replaced by `[jumped/jump-missed session=...]`. Phase 2 verifier rows that grep for `[would-jump` will need updating in Phase 3 verify script (track in Phase 3 plan).

---

### `App/SettingsView.swift` (modify — SET-05 button + result label)

**Analog:** Self — existing 테스트 알림 보내기 Section + onAppear (lines 58-76) + locked-copy `static let` block (lines 11-21).

**Existing test-button section (SettingsView.swift lines 58-64):**
```swift
Section(Self.testHeading) {
    Button(Self.testButtonLabel) {
        Task { await SessionRegistry.shared.injectTest(soundEnabled: store.soundEnabled) }
    }
    .buttonStyle(.borderedProminent)
    .frame(maxWidth: .infinity)
}
```

**Existing locked-copy convention (SettingsView.swift lines 12-21):**
```swift
/// Locked Korean copy — exposed for SettingsViewTests regression guards.
static let thresholdHeading = "알림 임계값"
…
static let testHeading = "테스트"
static let testButtonLabel = "테스트 알림 보내기"
```

**Phase 3 application — SET-05 Section verbatim copy (D3-15 + D3-19):**
```swift
// Add to locked-copy block after line 21:
static let connectionTestHeading = "iTerm2 연결"
static let connectionTestLabel = "iTerm2 연결 테스트"
static let connectionTestSuccessFmt = "✓ 연결됨 (%@)"               // %@ = HH:mm
static let iTermNotRunningLabel = "iTerm2가 실행 중이 아닙니다"
static let connectionDeniedLabel = "권한이 거부되어 있습니다 — 시스템 설정 열기"
```

**Phase 3 application — SET-05 Section (after line 65 testing section):**
```swift
@State private var connectionTestResult: JumpResult? = nil
@State private var connectionTestResultDisplayedAt: Date? = nil
@State private var hideResultTask: Task<Void, Never>? = nil

…
Section(Self.connectionTestHeading) {
    Button(Self.connectionTestLabel) {
        Task { await runConnectionTest() }
    }
    .buttonStyle(.bordered)
    .frame(maxWidth: .infinity)

    if let last = store.lastConnectionTestAt, connectionTestResult == nil {
        // Persisted last-success line — visible across Settings opens (D3-18).
        Text(String(format: Self.connectionTestSuccessFmt, hhmm(last)))
            .font(.caption).foregroundStyle(.secondary)
    }
    if case .ok = connectionTestResult {
        Text(String(format: Self.connectionTestSuccessFmt, hhmm(connectionTestResultDisplayedAt ?? Date())))
            .font(.caption).foregroundStyle(.secondary)
    }
    if case .iTermNotRunning = connectionTestResult {
        Text(Self.iTermNotRunningLabel).font(.caption).foregroundStyle(.secondary)
    }
    if case .permissionDenied = connectionTestResult {
        Text(Self.connectionDeniedLabel).font(.caption).foregroundStyle(.red)
    }
}

private func runConnectionTest() async {
    let result = await AppleScriptHelper.shared.testConnection()
    await MainActor.run {
        connectionTestResult = result
        connectionTestResultDisplayedAt = Date()
        if case .ok = result {
            store.lastConnectionTestAt = Date()      // D3-18 영속
        }
        if case .permissionDenied = result {
            PermissionDeepLink.openAutomationPreferences()    // D3-16 deny path 자동 딥링크
        }
        // 5s 후 인라인 결과 자동 제거
        hideResultTask?.cancel()
        hideResultTask = Task {
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            await MainActor.run { connectionTestResult = nil }
        }
    }
}
```

**Diff size:** medium (~70 lines: copy constants + Section + state + handler).

**Cross-cutting invariants:**
- **T-COPY-DRIFT-01:** All new Korean strings are `static let` constants verified by `SettingsViewTests` (mirror lines 38-44 quintet). Verbatim per D3-19.
- **D2-29:** No new external deps. `Task.sleep` + `@State` + `@AppStorage` — all stdlib/SwiftUI.
- **Permission deny auto-deeplink:** `PermissionDeepLink.openAutomationPreferences()` already in repo (line 21-26 of `App/PermissionDeepLink.swift`) — reuse, don't duplicate.

---

### `App/SettingsStore.swift` (modify — `lastConnectionTestAt: Date?`)

**Analog:** Self — existing `@AppStorage` block (lines 13-17).

**Existing `@AppStorage` (SettingsStore.swift lines 13-17):**
```swift
@AppStorage("threshold_seconds") var thresholdSeconds: Int = 30
@AppStorage("sound_enabled")     var soundEnabled: Bool = true
@AppStorage("widget_corner")     private var cornerRaw: String = WidgetCorner.topRight.rawValue
@AppStorage("widget_offset_x")   var offsetX: Int = 16
@AppStorage("widget_offset_y")   var offsetY: Int = 16
```

**Phase 3 problem:** SwiftUI `@AppStorage` does **not** natively support `Date?`. Requires either:
1. **TimeInterval-backed Double** (most idiomatic, simplest): store as `Double` (timeIntervalSince1970), expose `Date?` via computed property. Sentinel value `0` = `nil`.
2. **RawRepresentable wrapper** type: `struct OptionalDate: RawRepresentable { var rawValue: Double; var date: Date? { rawValue == 0 ? nil : Date(timeIntervalSince1970: rawValue) } }`.
3. **Direct `UserDefaults` access via `@Published`** (mirror existing `applescriptPermission` lines 32-34 + 37-38).

**Recommended pattern (mirror existing `applescriptPermission` lines 31-38):**
```swift
/// D3-18 — written by SettingsView SET-05 button after focus-frontmost success.
/// Not @AppStorage because Date? has no native @AppStorage conformance.
@Published var lastConnectionTestAt: Date? {
    didSet {
        if let d = lastConnectionTestAt {
            UserDefaults.standard.set(d.timeIntervalSince1970, forKey: "last_connection_test_at")
        } else {
            UserDefaults.standard.removeObject(forKey: "last_connection_test_at")
        }
    }
}

private init() {
    let raw = UserDefaults.standard.string(forKey: "applescript_permission") ?? PermissionStatus.unknown.rawValue
    self.applescriptPermission = PermissionStatus(rawValue: raw) ?? .unknown
    let ti = UserDefaults.standard.double(forKey: "last_connection_test_at")
    self.lastConnectionTestAt = ti > 0 ? Date(timeIntervalSince1970: ti) : nil
}
```

**Why mirror `applescriptPermission`:** Phase 2 already established that "non-AppStorage-friendly types live as `@Published` with manual UserDefaults bridge in didSet." Same convention, same UserDefaults key naming (snake_case), same init load.

**Diff size:** small (~12 lines added to existing file).

**Cross-cutting invariants:**
- **D2-30 single-direction:** SettingsView writes to store; store does not call back. New `lastConnectionTestAt` follows same flow (SettingsView.runConnectionTest mutates).
- **D2-29 zero deps:** `Foundation.UserDefaults` only.

---

### `App/SessionStore.swift` (modify — UUID-strip migration in `load()`)

**Analog:** Self — corrupt-rename branch (lines 51-61) is the closest "post-decode hook for in-place mutation."

**Existing corrupt-rename branch (SessionStore.swift lines 47-62):**
```swift
do {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snap = try decoder.decode(SessionsSnapshot.self, from: data)
    guard snap.schema == SessionsSnapshot.currentSchema else {
        log.error("sessions.json schema=\(snap.schema) — expected \(SessionsSnapshot.currentSchema). Renaming.")
        renameCorrupted()
        return nil
    }
    return snap
} catch {
    log.error("sessions.json decode failed: …. Renaming.")
    renameCorrupted()
    return nil
}
```

**Phase 3 application — D3-03 in-memory migration (idempotent, no new schema bump):**

Insert UUID-strip pass between line 56 (`return snap`) and the corrupt-rename branch:
```swift
// D3-03 — strip envelope-format `wXtYpZ:UUID` → `UUID-only`.
// Idempotent: legacy UUID-only entries pass through unchanged (iTermSessionID.uuid).
// Migration is in-memory; the next persist cycle writes back normalized form.
let migrated = Self.migrateItermIDs(in: snap)
if migrated != snap {
    log.notice("D3-03 migrated \(self.countMigrated(snap, migrated), privacy: .public) sessions to UUID-only iterm_session_id")
}
return migrated
```

Plus new private static helper inside `SessionStore`:
```swift
private static func migrateItermIDs(in snap: SessionsSnapshot) -> SessionsSnapshot {
    let newCompleted = snap.completed.map { c -> CompletedSession in
        guard let raw = c.itermSessionID, raw.contains(":") else { return c }
        let stripped = iTermSessionID.uuid(fromRaw: raw)
        return CompletedSession(
            sessionID: c.sessionID, projectName: c.projectName,
            stoppedAt: c.stoppedAt, durationSec: c.durationSec,
            itermSessionID: stripped, tty: c.tty, cwd: c.cwd
        )
    }
    var result = snap
    result.completed = newCompleted
    return result
}
```

**Why "post-decode hook" is the right analog:** corrupt-rename is the existing post-decode path that mutates `snap` (in that case by replacing it with `nil` + side-effect rename). Migration is the same shape — decode succeeds, then optional in-place transform.

**Diff size:** small (~25 lines). `CompletedSession` is `Codable, Equatable` (line 14), so the post-migration round-trip is verifiable.

**Cross-cutting invariants:**
- **Idempotent:** `iTermSessionID.uuid(fromRaw:)` is colon-detecting — running migration twice is a no-op.
- **No schema bump:** `SessionsSnapshot.currentSchema` stays at `1` per CONTEXT D3-03 (옵션 필드 추가 호환).
- **Persist on next cycle:** SessionRegistry.handleStart/handleStop both call `await persist()` after mutating; the migrated value is automatically rewritten without explicit migration-only persist.

---

### `App/HookEvent.swift` (modify — add `term_program: String?`)

**Analog:** Self — every existing field on the struct (lines 11-18) is already optional.

**Existing struct (HookEvent.swift, full file):**
```swift
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

**Phase 3 application — D3-05 / D-ADAPTER one-line addition:**
```swift
let term_program: String?               // D3-05 — `$TERM_PROGRAM` capture; v1 미사용, v2 dispatch 키
```

**Codable verification:** Swift `Decodable` accepts a missing JSON field for `String?`-typed properties (decoded as `nil`). No custom `init(from decoder:)` required. Existing fixtures (`HookEventFactory.swift` lines 14-18) that don't include `term_program` will decode as `nil` — fully backward-compatible.

**Diff size:** trivial (1 line + comment).

**Cross-cutting invariants:**
- **schema_version=1 preservation:** Adding optional fields is forward/backward compatible per D-08 envelope contract. CONTEXT D-ADAPTER explicit: "schema_version은 1 유지(옵션 필드 추가 호환)."

---

### `Reporter/cab-report.sh` (modify — `TERM_PROGRAM` capture)

**Analog:** Self — existing `ITERM_SESSION_ID_VAL` capture + python env injection + JSON insertion triple.

**Existing 3-site pattern (cab-report.sh lines 22, 36, 62):**
```bash
# Site 1 — env capture (line 22):
ITERM_SESSION_ID_VAL="${ITERM_SESSION_ID:-}"

# Site 2 — python env injection (line 36):
JSON=$(STDIN_JSON="$STDIN_JSON" \
       EVENT="$EVENT" \
       ITERM="$ITERM_SESSION_ID_VAL" \
       ...

# Site 3 — JSON envelope field (line 62):
"iterm_session_id": nz(env("ITERM")),
```

**Phase 3 application — D3-05 (mirror exact same 3 sites, parallel field):**
```bash
# Site 1 — add after line 22:
TERM_PROGRAM_VAL="${TERM_PROGRAM:-}"

# Site 2 — add inside the env-injection block (between line 36 and 41):
       TERM_PROGRAM="$TERM_PROGRAM_VAL" \

# Site 3 — add inside the python envelope dict (after line 62):
"term_program": nz(env("TERM_PROGRAM")),
```

**Why 3 sites, not 1:** Pitfall #3 (line 33 comment): "the only safe escape strategy" for envelope construction is python with env-var injection. This forces every new field through the same triple-touch pattern — env var → python env → JSON dict. Drift in any one site = silent missing field.

**Diff size:** trivial (3 lines, one per site).

**Cross-cutting invariants:**
- **HOOK-03 / D-02:** Always `exit 0`. Adding env capture cannot fail (default-empty `:-` syntax). Preserved.
- **Pitfall #3:** No stdout/stderr output. Preserved (env capture writes nothing).
- **Idempotency:** `TERM_PROGRAM` unset on a system → `TERM_PROGRAM_VAL=""` → `nz()` returns `None` → `term_program: null` in JSON → HookEvent decodes as `nil`. Backward-compatible with existing App build that doesn't yet have the field.

---

## Test File Pattern Assignments

### `ClaudeAlertBotTests/iTermSessionIDTests.swift` (new)

**Analog:** `ClaudeAlertBotTests/ProjectNameTests.swift` (full file, 36 lines).

**Mirror 5-case structure verbatim** (one test method per branch — see ProjectNameTests for the canonical shape):
```swift
import XCTest
@testable import ClaudeAlertBot

final class iTermSessionIDTests: XCTestCase {

    func test_uuid_stripsEnvelopePrefix() {
        XCTAssertEqual(iTermSessionID.uuid(fromRaw: "w0t0p1:79C4699F-XXXX"), "79C4699F-XXXX")
    }

    func test_uuid_passesThroughUUIDOnly() {
        XCTAssertEqual(iTermSessionID.uuid(fromRaw: "79C4699F-XXXX"), "79C4699F-XXXX")
    }

    func test_uuid_handlesNil() {
        XCTAssertNil(iTermSessionID.uuid(fromRaw: nil))
    }

    func test_uuid_handlesEmpty() {
        XCTAssertNil(iTermSessionID.uuid(fromRaw: ""))
    }

    func test_uuid_handlesColonWithEmptySuffix() {
        XCTAssertNil(iTermSessionID.uuid(fromRaw: "w0t0p1:"))
    }
}
```

**Diff size:** small (~25 lines new file).

---

### `ClaudeAlertBotTests/AppleScriptHelperTests.swift` (extend)

**Analog:** Self — existing test methods (lines 14-87).

**Phase 3 additions (D3-04 + D3-20):**
1. **`test_jumpScriptSource_containsAppleScriptTimeout`** — mirror `test_scriptSource_containsAppleScriptTimeout` (lines 14-24). Assert `with timeout of 3 seconds` + iTerm2 hierarchy walk.
2. **`test_focusFrontmostScriptSource_containsActivate`** — mirror same shape. Assert `tell application "iTerm2" to activate` + 3s timeout.
3. **`test_jump_compileOnce_secondCallReusesInstance`** — mirror lines 45-53 for `compiledJump`.
4. **`test_focus_compileOnce_secondCallReusesInstance`** — mirror for `compiledFocus`.
5. **`test_testConnection_unknownTriggersPermissionPrompt`** — assert that calling `testConnection()` from `.unknown` state invokes the same path as `triggerPermissionPrompt()` (CONTEXT D3-16). Use `markGrantedForTesting` / `markDeniedForTesting` test seams (lines 120-121) to set up state.
6. **`test_testConnection_deniedReturnsPermissionDenied`** — set `markDeniedForTesting`, call `testConnection()`, assert `JumpResult.permissionDenied`.
7. **`test_classifyJump_*`** quartet — mirror lines 26-43 for the `ScriptResult → JumpResult` mapping. Specifically `test_jumpClassify_emptyResult_isMissing` covers D3-06 빈 응답 분류.
8. **`test_frontmostMatches_uuidOnly_envelope`** (D3-04 회귀 가드) — assert that calling `frontmostMatches(itermSessionID: "w0t0p1:UUID-XX")` directly (raw envelope form) does NOT match a frontmost UUID-only session. Then call with `iTermSessionID.uuid(fromRaw: ...)` first; assert it does match. Locks the silent-failure regression to a unit test.

**Diff size:** medium (~80 lines added).

**Cross-cutting invariants:**
- Test seams (`rawSource`, `compiledForTesting`, `markGrantedForTesting`, `markDeniedForTesting`) all gated behind `#if DEBUG` — preserve. Add `compiledJumpForTesting` / `compiledFocusForTesting` siblings for compile-once tests.

---

### `ClaudeAlertBotTests/PopoverRowStateTests.swift` (new — recommended)

**Analog:** `ClaudeAlertBotTests/PopoverContentTests.swift` (full file).

**Recommendation:** Create new file rather than extending `PopoverContentTests.swift`. Rationale: `PopoverContentTests` is named after `PopoverContentRules` namespace (lines 1-4 file header) and tests that pure-function namespace; row state machine is a different concern and deserves its own test file.

**Pattern (D3-14):** Test state transitions directly without rendering SwiftUI:
1. `test_initialState_isNormal` — guard.
2. `test_clickInNormal_transitionsToJumping` — mock `onClick`, fire button action, assert `rowState == .jumping`.
3. `test_clickInJumping_isIgnored` — second click in same state is no-op (debounce per CONTEXT Discretion).
4. `test_jumpResultMissing_transitionsToMissing` — mock JumpResult.missing → state machine sets `.missing`.
5. `test_jumpResultOk_doesNotEnterMissing` — successful jump removes row (via SessionRegistry.clearOne) without missing animation.
6. `test_missingState_callsClearOneAfter700ms` — use injected clock (mirror SessionRegistry's `Clock` injection pattern lines 13-18) or assert on a callback.

**Approach:** Extract the state machine into a pure function or class (e.g. `PopoverRowStateMachine`) that's testable without SwiftUI. Mirror Phase 2 pattern: `PopoverContentRules` namespace (PopoverContentView.swift lines 11-34) — pure logic separable from `View` rendering.

**Diff size:** small (~50 lines new file + ~20 lines extracted state machine helper inside PopoverRowView.swift).

---

### `ClaudeAlertBotTests/SettingsViewTests.swift` (extend)

**Analog:** Self — existing copy-lock quintet (lines 24-44).

**Phase 3 additions (D3-15 + D3-19 + D3-20):**
```swift
func test_settingsCopy_connectionTestSection() {
    XCTAssertEqual(SettingsView.connectionTestHeading, "iTerm2 연결")
    XCTAssertEqual(SettingsView.connectionTestLabel, "iTerm2 연결 테스트")
    XCTAssertEqual(SettingsView.connectionTestSuccessFmt, "✓ 연결됨 (%@)")
    XCTAssertEqual(SettingsView.iTermNotRunningLabel, "iTerm2가 실행 중이 아닙니다")
    XCTAssertEqual(SettingsView.connectionDeniedLabel, "권한이 거부되어 있습니다 — 시스템 설정 열기")
}
```

**D3-20 button-trace test:** harder — requires AppleScriptHelper test seam (`testConnection()` already invocable on actor; tests can mock via `markGrantedForTesting` / `markDeniedForTesting`). For verbatim copy assertions only, the above 5-XCTAssertEqual block satisfies T-COPY-DRIFT-01.

**Diff size:** small (~10 lines).

---

### `ClaudeAlertBotTests/SessionStoreTests.swift` (extend)

**Analog:** Self — existing `test_saveAndLoad_roundTrip` (line 30) which already constructs a `CompletedSession` with `itermSessionID: "w0t0p1:UUID"` (line 41) — a perfect test case for the migration.

**Phase 3 addition (D3-03 회귀 가드):**
```swift
func test_load_migratesEnvelopeFormatItermID_toUUIDOnly() async {
    // Pre-write a snapshot containing `wXtYpZ:UUID` envelope-format itermSessionID.
    let raw = SessionsSnapshot(
        schema: 1, inFlight: [:],
        completed: [CompletedSession(
            sessionID: "c1", projectName: "p", stoppedAt: Date(),
            durationSec: 5, itermSessionID: "w0t0p1:79C4699F-AAAA",
            tty: nil, cwd: nil)]
    )
    let store = SessionStore(url: tempURL)
    await store.save(raw)

    // Load via the same store — D3-03 strip should mutate to UUID-only.
    let loaded = await store.load()
    XCTAssertEqual(loaded?.completed.first?.itermSessionID, "79C4699F-AAAA")
}

func test_load_migration_isIdempotent() async { … }
```

**Diff size:** small (~30 lines).

---

### `ClaudeAlertBotTests/Fixtures/HookEventFactory.swift` (extend — optional)

**Analog:** Self — existing `stop(...)` factory (lines 11-19).

**Phase 3 application:** Add optional `termProgram` parameter:
```swift
static func stop(sessionID: String = …,
                 iTermSessionID: String? = "w0t0p1:TEST-UUID",
                 termProgram: String? = nil,
                 cwd: String? = …,
                 ts: String = …) -> HookEvent {
    let tpField = termProgram.map { ",\"term_program\":\"\($0)\"" } ?? ""
    let json = """
    {"schema_version":1,"event":"stop", … "ts":"\(ts)"\(tpField)}
    """
    return try! JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
}
```

**Diff size:** small (~3 lines).

---

## Shared Patterns

### 1. OSLog `[*-prefix*]` filter contract — extension

**Source:** `App/WidgetPopoverController.swift` line 97 (`[would-jump session=...]`)

**Apply to:** All Phase 3 jump-path log lines.

**Pattern:**
```swift
log.notice("[jumped session=\(sessionID, privacy: .public)]")
log.notice("[jump-missed session=\(sessionID, privacy: .public)]")
log.warning("[jump-denied session=\(sessionID, privacy: .public)]")
log.warning("[jump-error session=\(sessionID, privacy: .public)]")
```

All start with `[jump` — `log show --predicate 'subsystem == "com.claudealert.bot.hook"' | grep '\[jump'` continues working for Phase 3 verifier scripts. **Mandatory:** every new log line in jump path uses this prefix.

**Privacy contract:** `privacy: .public` for sessionID strings, with carry-over comment per D-07: `// NOTE (Phase 5 review): privacy: .public during dev verification window.` — copy verbatim from HookListener.swift lines 92-93.

---

### 2. Compile-once + serial queue + AppleScript-side timeout

**Source:** `App/AppleScriptHelper.swift` lines 31-89 (verbatim).

**Apply to:** Both new compiled scripts (jumpScriptSource, focusFrontmostScriptSource). Each gets:
- `static let xxxScriptSource: String` (T-INJECTION-01: no interpolation)
- `private var compiledXxx: NSAppleScript?`
- `private func ensureCompiledXxx()` (mirror lines 42-47)
- Reuse the **same** queue `com.claudealert.bot.applescript` — do not introduce a parallel queue.
- AppleScript-side `with timeout of N seconds` block (1s for cheap-query existing, 3s for new two per D3-09).

---

### 3. T-COPY-DRIFT-01 한국어 카피 락

**Source:** `App/SettingsView.swift` lines 11-21 + `App/PermissionBannerView.swift` (analogous block).

**Apply to:** Every Phase 3 user-facing Korean string in SET-05 (5 strings per D3-19). Each string:
1. Declared as `static let` on the View type.
2. Asserted in `SettingsViewTests` with `XCTAssertEqual` to the verbatim string literal.
3. Never inlined in the View body — always referenced as `Self.connectionTestLabel` etc.

**Phase 3 row-missing UX:** D3-12 explicitly skips text labels — no copy-lock needed for the 도리도리 animation. T-COPY-DRIFT-01 applies only where text is rendered.

---

### 4. Single-direction wiring (View → Store → Helper → Actor)

**Source:** `App/NotificationOrchestrator.swift` lines 38-89 (whole class) + CONTEXT D2-30.

**Apply to:** ITerm2Jumper. ITerm2Jumper does not import or read SettingsStore. It only:
1. Receives `CompletedSession` from popover (downstream call).
2. Forwards UUID to `AppleScriptHelper` actor (downstream call).
3. Returns typed `JumpResult` (return value, no side effects on State).

SettingsView for SET-05 is the ONE site that bridges View → Store → Helper directly — same shape as existing `injectTest` button (line 60) and onAppear path A (line 73-74).

---

### 5. Inline-protocol declaration vs dedicated file

**Source:**
- Inline (default for Phase 2): `App/SessionRegistry.swift` lines 8-11 + `App/FloatingWidgetWindowController.swift` lines 13-16 + `App/NotificationOrchestrator.swift` lines 23-36.
- Dedicated file (Phase 3 first instance): `App/TerminalJumper.swift`.

**Decision criterion:**
- **Inline** when the protocol has exactly ONE conformer in the same file (NotifierProtocol → NotificationOrchestrator; WidgetHoverDelegate → WidgetPopoverController; WidgetControllerProtocol → FloatingWidgetWindowController).
- **Dedicated file** when (a) v2 will add multiple conformers (D-ADAPTER multi-terminal), OR (b) the protocol is the seam name itself.

`TerminalJumper` satisfies both.

---

### 6. Pitfall #1 anti-pattern preservation

**Source:** `App/main.swift` lines 1-11 (explicit comment) + `App/FloatingWidgetWindowController.swift` lines 5-6 (explicit comment + grep regression intent).

**Apply to:** All Phase 3 jump-path code. **Verbatim grep regression guard** (CONTEXT D3-10):
```bash
grep -c 'NSApp.activate' App/ITerm2Jumper.swift App/AppleScriptHelper.swift   # MUST output 0
```

iTerm2 activation lives **only** inside AppleScript-side `tell application "iTerm2" to activate`. Never `NSApp.activate(...)` from Swift. The comment from FloatingWidgetWindowController.swift line 5-6 should be **copy-pasted verbatim** into `App/ITerm2Jumper.swift` header:
```
// LSUIElement invariant: NEVER call activate(ignoringOtherApps:) on NSApp (anti-pattern from RESEARCH).
// The literal symbol is intentionally absent here so a grep regression guard stays clean.
```

---

### 7. UserDefaults bridge for non-`@AppStorage` types

**Source:** `App/SettingsStore.swift` lines 32-39 (`applescriptPermission`).

**Apply to:** `lastConnectionTestAt: Date?` (D3-18). Same shape:
- `@Published` for SwiftUI broadcast.
- `didSet` writes to UserDefaults via raw key.
- Init reads UserDefaults raw value, wraps with parser, falls back to default.

This is the canonical Phase 2 escape hatch for types that `@AppStorage` doesn't natively handle.

---

### 8. Codable optional-field forward compatibility

**Source:** `App/HookEvent.swift` (full file) + `ClaudeAlertBotTests/Fixtures/HookEventFactory.swift` line 16.

**Apply to:** `term_program` addition. JSON envelope without the field → `nil` decode. Existing fixtures unchanged. Reporter `cab-report.sh` writes `null` when env var missing → decodes as `nil`. Forward-compatible: old App + new Reporter = `nil`; new App + old Reporter = `nil`. Both safe.

---

## No Analog Found

**None.** All 12 Phase 3 components have direct Phase 1 or Phase 2 analogs. Phase 2's wide pattern coverage (actors, SwiftUI views, NSPanel/NSPopover, AppleScript helper, settings, persistence, observers, deep-link) covers Phase 3 entirely — Phase 3 introduces no new pattern category, only new instances + thin coordinator classes that mirror existing ones.

This contrasts Phase 2's PATTERNS.md which had 7 categories with no Phase 1 analog (SwiftUI views, NSPanel, audio, etc.). Phase 3's pattern reuse rate is 100% — explicit confirmation that the project's pattern surface is now stable.

---

## Metadata

**Analog search scope:** `/Users/choijihye/Study/source/claude_alert_bot/App/`, `/ClaudeAlertBotTests/`, `/Reporter/`, `/.planning/phases/02-alert-loop/`
**Files scanned:** 27 Swift files (App + Tests) + 1 sh + prior PATTERNS.md (Phase 2)
**Phase 3 lines analyzed:** ~1,400 (all read in full or targeted excerpts)
**Pattern extraction date:** 2026-05-08
**Pattern reuse rate:** 12 / 12 (100%) — Phase 2 codebase covers every Phase 3 introduction
**Pattern source mix:**
- Self-extension (modify existing file using its own established convention): 7 files
- Cross-file analog within Phase 1+2 source: 5 files (ITerm2Jumper ← NotifOrch; iTermSessionID ← ProjectName; iTermSessionIDTests ← ProjectNameTests; PopoverRowStateTests ← PopoverContentTests; TerminalJumper ← inline protocol declarations)

---

*Phase: 03-click-to-iterm2*
*Pattern map produced: 2026-05-08*
