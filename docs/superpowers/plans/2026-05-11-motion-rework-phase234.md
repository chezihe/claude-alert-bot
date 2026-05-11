# Motion Rework Phases 2–4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring row-dismiss, popover-open, and the SPEC §4 motion table in line with the HTML prototype, finishing the four-phase motion rework that started in Phase 1.

**Architecture:** Three discrete changes. (1) `PopoverContentView` mirrors the parent `queue` prop into an internal `@State` so SwiftUI runs ID-based ForEach transitions when rows are removed — the controller no longer needs to know about animation. (2) `PopoverContentView` runs a one-shot spring overshoot on first appearance with an anchor derived from the widget corner. (3) `SPEC.md` §4 table is rewritten to match the HTML prototype's actual keyframe data so it stops drifting from the source of truth. Sonar drawable expansion is intentionally deferred — it requires widening the floating panel and shifting badge/Zzz overlays, which is out of scope for a motion-only sweep.

**Tech Stack:** Swift 5, SwiftUI (macOS 14 SDK — `.transition`, `withAnimation(.spring)`, `@State` mirror pattern), XCTest, xcodegen + xcodebuild.

**Reference spec:** `docs/superpowers/specs/2026-05-11-motion-rework-design.md` (commit `bd5ec9a`)
**Source of truth (visual):** `Claude Alert Bot - Prototype v2.html` — `@keyframes row-out` (lines 287–290 area) and `@keyframes pop-in` (lines 217–220 area).
**Previous plan in this sweep:** `docs/superpowers/plans/2026-05-11-motion-rework-phase1.md`

---

## Out of Scope (Acknowledged)

- **Sonar drawable expansion (Phase 4 sub-item from the spec):** Widening `GeometryTokens.widgetBaseSize` from 44pt to ~56pt to give the 42pt-diameter peak sonar wave a breathing margin would shift the floating panel size, badge offset coordinates, hover hit-test area, and corner snap positions. The visual win (a thin sonar tail that currently brushes the panel edge) is small relative to that blast radius. Leave as a future task; record it in `SPEC.md` §4 corrections (Task 4).
- **New-alert pulse "spring spam" refinement (Phase 4 sub-item from the spec):** Current implementation fires `spring(response: 0.3, dampingFraction: 0.5)` 4 times with `asyncAfter` delays. The HTML prototype uses a single `cubic-bezier(.4, 1.5, .5, 1)`. The result is close enough that the user did not flag it during Phase 1 visual sign-off, and rewriting it brings the same `CubicKeyframe`-vs-`spring` interpolation tradeoffs we already debated. Defer until a user complaint surfaces it.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `App/PopoverContentView.swift` | **Modify** | Mirror `queue` prop into `@State displayQueue`. Add `.transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))` to ForEach children. Add `widgetCorner` parameter + `@State hasAppeared` for spring entry. |
| `App/WidgetPopoverController.swift` | **Modify** | Pass `widgetCorner: SettingsStore.shared.widgetCorner` into `PopoverContentView` at both call sites (`showPopover()` and `reloadPopoverContent()`). |
| `ClaudeAlertBotTests/PopoverContentTests.swift` | **Modify** | Add source-string assertions for the new dismiss transition + spring-on-appear wiring. |
| `SPEC.md` | **Modify** | Rewrite §4 Motion table to match HTML prototype. Add Heart row (currently missing). Adjust Bounce, Ring, Sonar entries. Append known-divergence notes for sonar drawable + new-alert pulse. |

---

## Build & Test Commands

```bash
xcodegen generate
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/PopoverContentTests
xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS'
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'   # full suite
```

If the running app holds the IPC socket, kill it before tests: `pkill -x ClaudeAlertBot`.

---

## Task 1: Row dismiss slide (Phase 2)

**Files:**
- Modify: `App/PopoverContentView.swift` — `PopoverContentView` body and state
- Modify: `ClaudeAlertBotTests/PopoverContentTests.swift` — add source-string test

The HTML prototype's `row-out` is 180ms ease, translateX +8pt + opacity → 0 + height collapse. The SPEC table says 0.32s easeIn. We adopt **0.32s easeIn** (SPEC value — slightly longer; reads more deliberate at 36pt row height). Row removal happens when the controller mutates `queue` and reloads `rootView`. SwiftUI runs the transition automatically when the ForEach child with a stable `id` disappears — but only if the diff happens inside an animatable transaction. The simplest robust way is to mirror `queue` into a `PopoverContentView`-owned `@State` and update it inside `withAnimation` on `.onChange`.

- [ ] **Step 1.1: Write the failing source-string test**

Open `ClaudeAlertBotTests/PopoverContentTests.swift`. Add this method inside the `PopoverContentTests` class (place it near the other source-string tests, e.g. after the existing `readPopoverContentViewSource()`-using tests):

```swift
    // MARK: - Row dismiss slide (Phase 2 motion rework)

    func test_popoverContentViewSource_mirrorsQueueForRowDismissTransition() {
        let src = readPopoverContentViewSource()

        XCTAssertTrue(src.contains("@State private var displayQueue: [CompletedSession]"))
        XCTAssertTrue(src.contains(".onChange(of: queue)"))
        XCTAssertTrue(src.contains("withAnimation(.easeIn(duration: 0.32))"))
        XCTAssertTrue(src.contains(".transition(.asymmetric("))
        XCTAssertTrue(src.contains(".move(edge: .trailing)"))
    }
```

- [ ] **Step 1.2: Run the test to verify it fails**

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_popoverContentViewSource_mirrorsQueueForRowDismissTransition
```
Expected: FAIL — the strings are not yet in `PopoverContentView.swift`.

- [ ] **Step 1.3: Add the `displayQueue` mirror state and `.onChange` updater**

Edit `App/PopoverContentView.swift`. Inside `struct PopoverContentView`, find the existing `@State` block (currently around lines 164–165):

```swift
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var scrollContentFrame: CGRect = .zero
```

Add a new `@State` right above them:

```swift
    @State private var displayQueue: [CompletedSession] = []
```

Find the `private var listItems: [PopoverListItem]` computed property (currently line 169). Change its body from:

```swift
    private var listItems: [PopoverListItem] {
        PopoverContentRules.groupedListItems(queue, expandedProjects: expandedProjects)
    }
```

to:

```swift
    private var listItems: [PopoverListItem] {
        PopoverContentRules.groupedListItems(displayQueue, expandedProjects: expandedProjects)
    }
```

(Internal layout now reads from the mirror, but the public prop is still `queue` so call sites don't change.)

Find the `if PopoverContentRules.shouldShowEmptyState(queue: queue, ...)` and similar references inside `body` (currently lines 197, 199, 200, ~263) — they all read `queue`. Change every one of them inside `body` to read `displayQueue` instead. Specifically:

1. Line ~177: `let clearableSessionCount = PopoverContentRules.clearableSessionCount(queue)` → `...clearableSessionCount(displayQueue)`
2. Line ~178: `let clearAllLabel = PopoverContentRules.clearAllButtonLabel(queue: queue)` → `...clearAllButtonLabel(queue: displayQueue)`
3. Line ~197: `if PopoverContentRules.shouldShowEmptyState(queue: queue, everHadAlerts: everHadAlerts)` → `...queue: displayQueue, ...`
4. Line ~199: `} else if !queue.isEmpty {` → `} else if !displayQueue.isEmpty {`

(The `everHadAlerts` parameter stays unchanged — it is not the queue.)

Then add an `.onAppear` and `.onChange(of: queue)` on the top-level `VStack` of `body`. Find the closing modifier chain of the outer `VStack`:

```swift
        .frame(width: GeometryTokens.popoverWidth)
        .background(PopoverMaterialBackground())
        .onHover { hovering in onPopoverHoverChange(hovering) }
    }
}
```

Insert two new modifiers immediately before `.frame(width: GeometryTokens.popoverWidth)`:

```swift
        .onAppear {
            displayQueue = queue
        }
        .onChange(of: queue) { _, newQueue in
            withAnimation(.easeIn(duration: 0.32)) {
                displayQueue = newQueue
            }
        }
```

- [ ] **Step 1.4: Attach `.transition` to ForEach children**

Still in `App/PopoverContentView.swift`, find the `ForEach(listItems) { item in ... }` block inside `body` (currently around lines 209–232). Wrap each switch branch's view with a `.transition` modifier. Change:

```swift
                        ForEach(listItems) { item in
                            switch item {
                            case .group(let projectName, let count, let isExpanded):
                                ProjectGroupHeaderView(
                                    projectName: projectName,
                                    count: count,
                                    isExpanded: isExpanded,
                                    isMuted: isProjectMuted(projectName),
                                    onClick: { onToggleGroup(projectName) },
                                    onToggleMute: { onToggleMute(projectName) }
                                )
                            case .session(let session, let showTimeSuffix):
                                PopoverRowView(
                                    session: session,
                                    showTimeSuffix: showTimeSuffix,
                                    state: rowStates[session.id, default: .normal],
                                    isMuted: isProjectMuted(session.projectName),
                                    onClick: { onRowClick(session.id) },
                                    onTogglePin: { onTogglePin(session.id) },
                                    onToggleMute: { onToggleMute(session.projectName) },
                                    onMissingComplete: { onRowMissingComplete(session.id) }
                                )
                            }
                        }
```

to:

```swift
                        ForEach(listItems) { item in
                            Group {
                                switch item {
                                case .group(let projectName, let count, let isExpanded):
                                    ProjectGroupHeaderView(
                                        projectName: projectName,
                                        count: count,
                                        isExpanded: isExpanded,
                                        isMuted: isProjectMuted(projectName),
                                        onClick: { onToggleGroup(projectName) },
                                        onToggleMute: { onToggleMute(projectName) }
                                    )
                                case .session(let session, let showTimeSuffix):
                                    PopoverRowView(
                                        session: session,
                                        showTimeSuffix: showTimeSuffix,
                                        state: rowStates[session.id, default: .normal],
                                        isMuted: isProjectMuted(session.projectName),
                                        onClick: { onRowClick(session.id) },
                                        onTogglePin: { onTogglePin(session.id) },
                                        onToggleMute: { onToggleMute(session.projectName) },
                                        onMissingComplete: { onRowMissingComplete(session.id) }
                                    )
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }
```

- [ ] **Step 1.5: Build and run the new test**

```bash
pkill -x ClaudeAlertBot 2>&1 || true
xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS' 2>&1 | tail -3
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_popoverContentViewSource_mirrorsQueueForRowDismissTransition 2>&1 | tail -3
```
Expected: build succeeds, test passes.

- [ ] **Step 1.6: Run the full suite to confirm no regressions**

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' 2>&1 | tail -5
```
Expected: TEST SUCCEEDED.

- [ ] **Step 1.7: Commit**

```bash
git add App/PopoverContentView.swift ClaudeAlertBotTests/PopoverContentTests.swift
git commit -m "$(cat <<'EOF'
feat: animate row dismiss with slide+fade transition

Mirror the queue prop into PopoverContentView-owned @State so SwiftUI
runs ForEach removal transitions when the controller reloads with a
shorter queue. Row dismiss now slides right (+8pt) and fades out over
0.32s easeIn, matching SPEC §4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Popover open spring (Phase 3)

**Files:**
- Modify: `App/PopoverContentView.swift` — add `widgetCorner` prop, `@State hasAppeared`, spring onAppear
- Modify: `App/WidgetPopoverController.swift` — pass `widgetCorner` into the two `PopoverContentView(...)` constructions
- Modify: `ClaudeAlertBotTests/PopoverContentTests.swift` — add source-string test

NSPopover's stock entry is an alpha fade — it cannot be replaced with a custom spring at the window level without rewriting the popover plumbing (out of scope). The realistic implementation is: on first content appear, start with `scale = 0.85` anchored at the widget corner, animate to `1.0` with a slight overshoot via `withAnimation(.spring(response: 0.35, dampingFraction: 0.6))`. The system fade is short enough that the content's spring reads as the dominant entry motion.

- [ ] **Step 2.1: Write the failing source-string test**

In `ClaudeAlertBotTests/PopoverContentTests.swift`, add another source-string test inside the same class:

```swift
    // MARK: - Popover open spring (Phase 3 motion rework)

    func test_popoverContentViewSource_runsSpringEntryAnimation() {
        let src = readPopoverContentViewSource()

        XCTAssertTrue(src.contains("@State private var hasAppeared: Bool = false"))
        XCTAssertTrue(src.contains("var widgetCorner: WidgetCorner"))
        XCTAssertTrue(src.contains("withAnimation(.spring(response: 0.35, dampingFraction: 0.6))"))
        XCTAssertTrue(src.contains("hasAppeared = true"))
        // Anchor scales toward the corner the widget lives in.
        XCTAssertTrue(src.contains("entryAnchor"))
    }
```

- [ ] **Step 2.2: Verify the new test fails**

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_popoverContentViewSource_runsSpringEntryAnimation 2>&1 | tail -3
```
Expected: FAIL.

- [ ] **Step 2.3: Add the `widgetCorner` prop and `hasAppeared` state**

Edit `App/PopoverContentView.swift`. In `struct PopoverContentView` (after the existing props, before the `@State` block), add:

```swift
    var widgetCorner: WidgetCorner = .topRight
```

Below the existing `@State` declarations (next to `displayQueue`), add:

```swift
    @State private var hasAppeared: Bool = false
```

Add a computed property on the struct (place it right above `private var listItems`):

```swift
    /// Anchor for the spring entry scale. The popover should appear to
    /// expand outward from the widget glyph that triggered it.
    private var entryAnchor: UnitPoint {
        switch widgetCorner {
        case .topLeft:     return .topLeading
        case .topRight:    return .topTrailing
        case .bottomLeft:  return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
```

- [ ] **Step 2.4: Apply the entry scale and trigger the spring on appear**

Still in `App/PopoverContentView.swift`, find the outer `VStack(alignment: .leading, spacing: 0) { ... }` in `body`. We need to apply `.scaleEffect` and `.opacity` to it, then drive `hasAppeared` from `true` inside `withAnimation` on `.onAppear` (replacing the version from Task 1).

Replace the current `.onAppear { displayQueue = queue }` block (added in Task 1) with this expanded version:

```swift
        .scaleEffect(hasAppeared ? 1.0 : 0.85, anchor: entryAnchor)
        .opacity(hasAppeared ? 1.0 : 0.0)
        .onAppear {
            displayQueue = queue
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                hasAppeared = true
            }
        }
```

(The `.onChange(of: queue)` block from Task 1 stays as-is.)

- [ ] **Step 2.5: Pass `widgetCorner` from the controller**

Edit `App/WidgetPopoverController.swift`. Find the `PopoverContentView(...)` construction inside `showPopover()` (around line 88) and the one inside `reloadPopoverContent()` (around line 149). Both currently end with `everHadAlerts: SettingsStore.shared.everHadAlerts`.

In **both** call sites, add `widgetCorner: SettingsStore.shared.widgetCorner,` as a new argument. Insert it after `expandedProjects: expandedProjects,` and before the `onToggleGroup:` closure, so the call site reads:

```swift
            expandedProjects: expandedProjects,
            widgetCorner: SettingsStore.shared.widgetCorner,
            onToggleGroup: { [weak self] projectName in
                self?.onToggleGroup(projectName: projectName)
            },
            everHadAlerts: SettingsStore.shared.everHadAlerts
        )
```

Make the same insertion in both `showPopover()` and `reloadPopoverContent()`.

- [ ] **Step 2.6: Build and run the new test plus full suite**

```bash
pkill -x ClaudeAlertBot 2>&1 || true
xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS' 2>&1 | tail -3
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/PopoverContentTests 2>&1 | tail -3
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' 2>&1 | tail -3
```
Expected: build succeeds; PopoverContentTests pass; full suite passes.

- [ ] **Step 2.7: Commit**

```bash
git add App/PopoverContentView.swift App/WidgetPopoverController.swift ClaudeAlertBotTests/PopoverContentTests.swift
git commit -m "$(cat <<'EOF'
feat: spring entry for popover content from widget corner

PopoverContentView starts at scale 0.85 anchored at the widget corner
and springs to 1.0 with mild overshoot on first appear, approximating
HTML pop-in. NSPopover's own alpha fade remains underneath; the
content-level spring is the dominant entry motion.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: SPEC §4 Motion table correction (Phase 4)

**Files:**
- Modify: `SPEC.md` — rewrite §4 table; add divergence-notes block below it.

This task changes no source code — only `SPEC.md`. The goal is to make the table match the HTML prototype (the source of truth per `CLAUDE.md`) so future engineers don't reintroduce the Phase 1 mismatch.

- [ ] **Step 3.1: Replace §4 Motion table contents**

Open `SPEC.md`. Find the heading `## 4. Motion` and the table immediately following it. Replace the table body (the rows beginning with `| Bounce (idle) | ...` and ending with `| Popover open | ...`) with:

```markdown
| Animation | Duration | Curve | Notes |
|---|---|---|---|
| Bounce (idle) | 0.9s, infinite | easeInOut, 5-keyframe | 2-axis squash-and-stretch. Bottom (0%, 100%): scale(1.04, 0.94) translateY 0. Apex (50%): scale(0.97, 1.05) translateY -5pt. Mid (18%, 82%): scale(1.01, 0.99) translateY -2pt. Source: HTML `@keyframes bounce-cute`. |
| Breathe | 2.4s, autoreverse, infinite | easeInOut | scale 1.0↔1.06 |
| Heart (idle) | 1.4s, infinite | easeInOut, 6-keyframe | Double-pulse: 14% scale 1.14, 28% 1.0, 42% 1.08, 56% 1.0, 56→100% idle. Source: HTML `@keyframes heartbeat`. |
| Ring (bell) | 1.4s, autoreverse, infinite | easeInOut | rotate ±15° from top anchor. Source: HTML `@keyframes ring` (line 154). Note: current Swift uses 0.55s ±10° — divergent; reconcile in a follow-up if visual regression surfaces. |
| Roam (running track) | 1.6s, infinite, linear | linear | 24×6pt elliptical path, counter-clockwise |
| Drift | 6s, infinite | easeInOut | random jitter within 14×16pt |
| New-alert pulse | 0.45s | spring (response 0.3, damping 0.5) | scale 1.14 → 0.96 → 1.06 → 1, rotate ±7°. HTML prototype uses `cubic-bezier(.4, 1.5, .5, 1)`; Swift uses chained springs. Treated as equivalent. |
| Sonar wave | 0.75s | easeOut | ring scales 0.5 → 3.0, opacity 0.75 → 0. Base 14pt → peak 42pt. **Known divergence:** widget drawable is 44pt so the peak brushes the panel edge; HTML host is 56pt. Deferred — see §4 divergence notes. |
| Status dot ripple (just-arrived) | 1s × 3 cycles | easeOut | secondary ring scale 1 → 2.4, opacity 0.6 → 0 |
| Row dismiss | 0.32s | easeIn | translateX(8pt) + opacity + height collapse. Implemented via SwiftUI `.transition(.asymmetric(...))` on ForEach children, driven by a `displayQueue` `@State` mirror inside `PopoverContentView`. |
| Popover open | spring (response 0.35, damping 0.6) | spring with mild overshoot | NSPopover's stock alpha fade plus a content-level scale 0.85→1.0 anchored at the widget corner. Not a window-level spring (NSPopover does not expose one); the content scale is the dominant motion. |
```

- [ ] **Step 3.2: Append a divergence-notes section after the table**

Still in `SPEC.md`, immediately after the table (and before the existing `**Reduce Motion (Accessibility):**` line), insert a new subsection:

```markdown
### Known motion divergences (acknowledged, deferred)

- **Sonar drawable.** HTML widget host is 56×56pt giving the 42pt peak sonar 7pt of margin per side. The native widget panel is 44×44pt, so the peak sonar tail brushes the panel edge. Widening `GeometryTokens.widgetBaseSize` would cascade into badge offset, hover hit-test area, and corner-snap geometry — out of scope for a motion-only sweep. Revisit if users report the clipping is visible.
- **Ring keyframe period and amplitude.** Swift uses 0.55s and ±10°; HTML uses 1.4s and ±15°. The current Swift values match the original SPEC table; the HTML prototype diverged later. No user-visible complaint yet — reconcile if Ring is selected as the user's idle animation and the difference is flagged.
- **New-alert pulse curve.** HTML applies a single `cubic-bezier(.4, 1.5, .5, 1)` over 0.45s; Swift chains four `spring(response: 0.3, damping: 0.5)` calls at 0%, 25%, 50%, and 100% of the same window. End shape is close. Refactor to a `KeyframeAnimator` if the spring chain ever produces visible jitter.
- **Popover open spring.** Window-level spring is not achievable through `NSPopover.show(relativeTo:)` — the stock alpha fade is always applied. Approximated via a content-level scale spring anchored at the widget corner. Migrating to a custom `NSPanel`-based popover would unlock a true window-level spring but is a much larger change.
```

- [ ] **Step 3.3: Verify the document still parses cleanly**

```bash
head -150 SPEC.md | tail -80
```
Skim the §4 section — confirm the table is well-formed Markdown (column alignment is decorative; what matters is each row has 5 `|` separators).

- [ ] **Step 3.4: Commit**

```bash
git add SPEC.md
git commit -m "$(cat <<'EOF'
docs: align SPEC §4 motion table with HTML prototype

The previous table compressed HTML keyframe data (e.g. Bounce 5-keyframe
2-axis squash-and-stretch → one-line "5pt vertical + 1.04↔0.94 squash"),
which led Phase 1 codex implementation astray. Rewrite each row to
match the prototype, add the missing Heart row, and capture the four
acknowledged divergences (sonar drawable, ring period/amplitude, new-
alert pulse curve, popover open spring) so future work doesn't reopen
those debates from scratch.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Manual visual sign-off

This is a checkpoint, not a code task. Do not skip.

- [ ] **Step 4.1: Build the app**

```bash
pkill -x ClaudeAlertBot 2>&1 || true
./scripts/build.sh 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED` and `build/export/ClaudeAlertBot.app` exists.

- [ ] **Step 4.2: Launch app and prototype side-by-side**

```bash
open build/export/ClaudeAlertBot.app
open "Claude Alert Bot - Prototype v2.html"
```

- [ ] **Step 4.3: Trigger an alert and verify dismiss slide**

Send a synthetic stop event:

```bash
echo '{"schema_version":1,"event":"stop","session_id":"manual-test","cwd":"'"$(pwd)"'","iterm_session_id":"manual","tty":"/dev/ttys000","term_program":"iTerm.app","ts":"'"$(date -u +%FT%TZ)"'","exit_code":0,"kind":"success"}' \
  | nc -U "$HOME/Library/Application Support/ClaudeAlertBot/ipc.sock"
```

Hover the widget to show the popover. Click the row. Confirm: the row slides right (~8pt) and fades over ~0.32s instead of disappearing instantly.

- [ ] **Step 4.4: Verify popover open spring**

Move the cursor off and back onto the widget. Confirm: the popover content expands from the widget corner (top-right by default) with a mild overshoot, not a flat fade-in.

- [ ] **Step 4.5: Verify reduce-motion path**

System Settings → Accessibility → Display → enable Reduce Motion. Trigger another alert. Confirm: row dismiss still works (SwiftUI honors reduce-motion by shortening transitions) but the popover spring is muted.

- [ ] **Step 4.6: User sign-off**

Stop and ask the user: "Does the row dismiss slide and popover entry match the prototype?" Wait for explicit yes. If mismatched, capture the specific complaint and treat as a new task — do not silently retune.

---

## Self-Review Notes

- **Spec coverage:** Phase 2 → Task 1; Phase 3 → Task 2; Phase 4 (SPEC §4 corrections) → Task 3. Phase 4 sub-items "sonar drawable" and "new-alert pulse refactor" are explicitly out of scope, with rationale captured in the Out-of-Scope section above and in the SPEC divergence notes (Task 3 Step 2).
- **Placeholder scan:** No TBD/TODO/"implement later". Every step shows exact code or commands.
- **Type consistency:** `displayQueue: [CompletedSession]` (Task 1) and `hasAppeared: Bool` (Task 2) introduced in `PopoverContentView` are both used later in the same file; `widgetCorner: WidgetCorner` is added to `PopoverContentView` (Task 2 Step 3) and passed in by `WidgetPopoverController` (Task 2 Step 5) at both call sites.
- **Known intermediate states:** Task 1 leaves `PopoverContentView` reading from a mirror but with no entry spring; Task 2 adds the entry spring on top of the same mirror. Each task ends in a green-test, committable state.
