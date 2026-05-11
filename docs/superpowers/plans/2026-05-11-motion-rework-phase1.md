# Motion Rework Phase 1 (Bounce + Heart) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace single-axis Bounce + step-based Heart in `App/WidgetIconView.swift` with HTML-prototype-faithful `KeyframeAnimator` multi-track animations driven by a new pure-data module `App/MotionKeyframes.swift`.

**Architecture:** Keyframe data lives as pure structs (`BounceKeyframe`, `HeartKeyframe`) in `App/MotionKeyframes.swift` for easy unit testing. `WidgetIconView` wraps the glyph in SwiftUI's `KeyframeAnimator(initialValue:repeating:trigger:)` for the `.bounce` and `.heart` idle branches. Quiet Hours / Reduce Motion gate the animator at the view level (static glyph when on). Existing tokens for the deleted animation paths are removed; tests that locked the deleted symbols are updated accordingly.

**Tech Stack:** Swift 5, SwiftUI (macOS 14 SDK — `KeyframeAnimator`, `CubicKeyframe`, `KeyframeTrack`), XCTest, xcodegen + xcodebuild.

**Reference spec:** `docs/superpowers/specs/2026-05-11-motion-rework-design.md` (commit `bd5ec9a`)
**Source of truth (visual):** `Claude Alert Bot - Prototype v2.html` keyframes `@keyframes bounce-cute` (lines 117–123) and `@keyframes heartbeat` (lines 147–153).

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `App/MotionKeyframes.swift` | **Create** | Pure keyframe data: `BounceKeyframe`, `HeartKeyframe`, `MotionKeyframes.bouncePeriod`, `bounceCycle`, `heartPeriod`, `heartCycle` |
| `ClaudeAlertBotTests/MotionKeyframesTests.swift` | **Create** | Unit tests for keyframe data (monotonic percent, loop continuity, exact values) |
| `App/WidgetIconView.swift` | **Modify** | Replace `.bounce` + `.heart` paths with `KeyframeAnimator`. Remove `@State` `bounceOffset`, `bounceScale`, `heartScale`, `heartGeneration`. Remove `startHeartAnimation`, `stopHeartAnimation`, `runHeartBeat`, `scheduleHeartBeat`. Update `scaleEffect`/`offset` composition. |
| `App/DesignTokens.swift` | **Modify** | Delete `bounceDuration`, `bounceOffset`, `bounceStretchScale`, `bounceSquashScale`, `bounceAnimation(reduceMotion:)`, `heartDuration`, `heartBeatStepDuration`, `heartPeakScale`, `heartSecondScale`, `heartBeatAnimation(reduceMotion:)`. |
| `ClaudeAlertBotTests/DesignTokensTests.swift` | **Modify** | Delete the 6 tests locking the removed bounce/heart tokens. |
| `ClaudeAlertBotTests/IdleAnimationTests.swift` | **Modify** | Replace `test_widgetIconViewSource_wiresHeartBranch`, `test_widgetIconViewSource_wiresBounceSquashScale`, and the bounce/heart strings inside `test_widgetIconViewSource_restartsWhenIdleAnimationChanges` so they assert the new `KeyframeAnimator` wiring. |

---

## Build & Test Commands (used throughout)

Regenerate the Xcode project after creating any new `.swift` file:
```bash
xcodegen generate
```

Run a single test:
```bash
xcodebuild test \
  -scheme ClaudeAlertBot \
  -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/MotionKeyframesTests/<test_method>
```

Run an entire test class:
```bash
xcodebuild test \
  -scheme ClaudeAlertBot \
  -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/MotionKeyframesTests
```

Run the full suite:
```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'
```

Build only:
```bash
xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS'
```

---

## Task 1: Create `MotionKeyframes` data with Bounce cycle

**Files:**
- Create: `App/MotionKeyframes.swift`
- Test: `ClaudeAlertBotTests/MotionKeyframesTests.swift`

- [ ] **Step 1.1: Create the failing test file**

Create `ClaudeAlertBotTests/MotionKeyframesTests.swift`:

```swift
// MotionKeyframesTests.swift — Phase 1 motion rework.
// Drift-guard for App/MotionKeyframes.swift. Bounce cycle mirrors
// `Claude Alert Bot - Prototype v2.html` @keyframes bounce-cute (lines 117–123).
import XCTest
@testable import ClaudeAlertBot

final class MotionKeyframesTests: XCTestCase {

    // MARK: - Bounce cycle

    func test_bouncePeriod_matchesPrototype_0_9s() {
        XCTAssertEqual(MotionKeyframes.bouncePeriod, 0.9, accuracy: 0.0001)
    }

    func test_bounceCycle_startsAtPercent0_endsAtPercent100() {
        XCTAssertEqual(MotionKeyframes.bounceCycle.first?.percent, 0)
        XCTAssertEqual(MotionKeyframes.bounceCycle.last?.percent, 100)
    }

    func test_bounceCycle_percentIsMonotonicallyIncreasing() {
        let percents = MotionKeyframes.bounceCycle.map(\.percent)
        for i in 1..<percents.count {
            XCTAssertGreaterThan(percents[i], percents[i - 1],
                                 "bounceCycle[\(i)].percent must be > [\(i-1)]")
        }
    }

    func test_bounceCycle_isLoopContinuous() {
        let first = MotionKeyframes.bounceCycle.first
        let last = MotionKeyframes.bounceCycle.last
        XCTAssertEqual(first?.translateY, last?.translateY, "translateY must loop")
        XCTAssertEqual(first?.scaleX, last?.scaleX, "scaleX must loop")
        XCTAssertEqual(first?.scaleY, last?.scaleY, "scaleY must loop")
    }

    func test_bounceCycle_matchesPrototypeKeyframesExactly() {
        // HTML @keyframes bounce-cute (Claude Alert Bot - Prototype v2.html:117–123)
        let expected: [(Double, CGFloat, CGFloat, CGFloat)] = [
            (0,    0,  1.04, 0.94),
            (18,  -2,  1.01, 0.99),
            (50,  -5,  0.97, 1.05),
            (82,  -2,  1.01, 0.99),
            (100,  0,  1.04, 0.94),
        ]
        XCTAssertEqual(MotionKeyframes.bounceCycle.count, expected.count)
        for (kf, exp) in zip(MotionKeyframes.bounceCycle, expected) {
            XCTAssertEqual(kf.percent,    exp.0, accuracy: 0.0001)
            XCTAssertEqual(kf.translateY, exp.1, accuracy: 0.0001)
            XCTAssertEqual(kf.scaleX,     exp.2, accuracy: 0.0001)
            XCTAssertEqual(kf.scaleY,     exp.3, accuracy: 0.0001)
        }
    }
}
```

- [ ] **Step 1.2: Regenerate Xcode project and run test to verify it fails**

Run:
```bash
xcodegen generate
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/MotionKeyframesTests
```
Expected: FAIL at compile time — `MotionKeyframes` symbol undefined.

- [ ] **Step 1.3: Create `App/MotionKeyframes.swift` with minimal Bounce data**

Create `App/MotionKeyframes.swift`:

```swift
// App/MotionKeyframes.swift — Phase 1 motion rework.
// Pure keyframe data (no view code). Source of truth: HTML prototype
// `Claude Alert Bot - Prototype v2.html` @keyframes bounce-cute (117–123)
// and @keyframes heartbeat (147–153). Loop-continuous; consumed by
// WidgetIconView's KeyframeAnimator multi-track wiring.
import CoreGraphics
import Foundation

struct BounceKeyframe: Equatable {
    let percent: Double   // 0...100 along the cycle
    let translateY: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
}

enum MotionKeyframes {
    // HTML bounce-cute is 0.9s ease-in-out infinite (Prototype v2 line 101).
    static let bouncePeriod: TimeInterval = 0.9

    // HTML @keyframes bounce-cute (Prototype v2 lines 117–123).
    // Bottom squash (1.04, 0.94) → apex stretch (0.97, 1.05) → bottom squash.
    static let bounceCycle: [BounceKeyframe] = [
        BounceKeyframe(percent:   0, translateY:  0, scaleX: 1.04, scaleY: 0.94),
        BounceKeyframe(percent:  18, translateY: -2, scaleX: 1.01, scaleY: 0.99),
        BounceKeyframe(percent:  50, translateY: -5, scaleX: 0.97, scaleY: 1.05),
        BounceKeyframe(percent:  82, translateY: -2, scaleX: 1.01, scaleY: 0.99),
        BounceKeyframe(percent: 100, translateY:  0, scaleX: 1.04, scaleY: 0.94),
    ]
}
```

- [ ] **Step 1.4: Regenerate project and run test to verify it passes**

Run:
```bash
xcodegen generate
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/MotionKeyframesTests
```
Expected: 5 tests pass.

- [ ] **Step 1.5: Commit**

```bash
git add App/MotionKeyframes.swift ClaudeAlertBotTests/MotionKeyframesTests.swift ClaudeAlertBot.xcodeproj
git commit -m "feat: add MotionKeyframes module with Bounce cycle data

Pure-data keyframe definitions sourced from HTML prototype @keyframes
bounce-cute. Consumed by upcoming KeyframeAnimator wiring in
WidgetIconView (Phase 1 of the motion rework)."
```

---

## Task 2: Add Heart cycle to `MotionKeyframes`

**Files:**
- Modify: `App/MotionKeyframes.swift`
- Modify: `ClaudeAlertBotTests/MotionKeyframesTests.swift`

- [ ] **Step 2.1: Add failing Heart tests**

Append to `ClaudeAlertBotTests/MotionKeyframesTests.swift` (inside the same class, after the Bounce tests):

```swift
    // MARK: - Heart cycle

    func test_heartPeriod_matchesPrototype_1_4s() {
        XCTAssertEqual(MotionKeyframes.heartPeriod, 1.4, accuracy: 0.0001)
    }

    func test_heartCycle_startsAtPercent0_endsAtPercent100() {
        XCTAssertEqual(MotionKeyframes.heartCycle.first?.percent, 0)
        XCTAssertEqual(MotionKeyframes.heartCycle.last?.percent, 100)
    }

    func test_heartCycle_percentIsMonotonicallyIncreasing() {
        let percents = MotionKeyframes.heartCycle.map(\.percent)
        for i in 1..<percents.count {
            XCTAssertGreaterThan(percents[i], percents[i - 1])
        }
    }

    func test_heartCycle_isLoopContinuous() {
        let first = MotionKeyframes.heartCycle.first
        let last = MotionKeyframes.heartCycle.last
        XCTAssertEqual(first?.scale, last?.scale)
    }

    func test_heartCycle_matchesPrototypeKeyframesExactly() {
        // HTML @keyframes heartbeat (Claude Alert Bot - Prototype v2.html:147–153).
        let expected: [(Double, CGFloat)] = [
            (0,   1.00),
            (14,  1.14),
            (28,  1.00),
            (42,  1.08),
            (56,  1.00),
            (100, 1.00),
        ]
        XCTAssertEqual(MotionKeyframes.heartCycle.count, expected.count)
        for (kf, exp) in zip(MotionKeyframes.heartCycle, expected) {
            XCTAssertEqual(kf.percent, exp.0, accuracy: 0.0001)
            XCTAssertEqual(kf.scale,   exp.1, accuracy: 0.0001)
        }
    }
```

- [ ] **Step 2.2: Run tests to verify they fail**

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/MotionKeyframesTests
```
Expected: compile error — `HeartKeyframe` / `heartPeriod` / `heartCycle` undefined.

- [ ] **Step 2.3: Add Heart data to `App/MotionKeyframes.swift`**

Append to `App/MotionKeyframes.swift` (after `BounceKeyframe` and before `enum MotionKeyframes`):

```swift
struct HeartKeyframe: Equatable {
    let percent: Double   // 0...100 along the cycle
    let scale: CGFloat
}
```

Append to the `MotionKeyframes` enum:

```swift
    // HTML heartbeat is 1.4s ease-in-out infinite (Prototype v2 line 106).
    static let heartPeriod: TimeInterval = 1.4

    // HTML @keyframes heartbeat (Prototype v2 lines 147–153).
    // Double-pulse: peak 1 at 14% (1.14), peak 2 at 42% (1.08), then idle.
    static let heartCycle: [HeartKeyframe] = [
        HeartKeyframe(percent:   0, scale: 1.00),
        HeartKeyframe(percent:  14, scale: 1.14),
        HeartKeyframe(percent:  28, scale: 1.00),
        HeartKeyframe(percent:  42, scale: 1.08),
        HeartKeyframe(percent:  56, scale: 1.00),
        HeartKeyframe(percent: 100, scale: 1.00),
    ]
```

- [ ] **Step 2.4: Run tests to verify they pass**

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/MotionKeyframesTests
```
Expected: all 10 tests pass.

- [ ] **Step 2.5: Commit**

```bash
git add App/MotionKeyframes.swift ClaudeAlertBotTests/MotionKeyframesTests.swift
git commit -m "feat: add Heart cycle to MotionKeyframes

Mirrors HTML @keyframes heartbeat: double-pulse at 14%/42% with idle
gap from 56%→100%. Consumed by upcoming KeyframeAnimator wiring."
```

---

## Task 3: Rewire Bounce in `WidgetIconView` with `KeyframeAnimator`

**Files:**
- Modify: `App/WidgetIconView.swift`
- Modify: `ClaudeAlertBotTests/IdleAnimationTests.swift:118-126` and `:172-184`

This task replaces the single-axis `bounceScale`/`bounceOffset` path with a multi-track `KeyframeAnimator`. The animator is composed with the rest of the view by wrapping `Image("ClaudeCodeIcon")` so the existing `breatheScale`, `heartScale`, `alertPulseScale`, `idleRotation`, `driftOffset`, and `RoamOffsetEffect` modifiers continue to apply *outside* the animator. For the `.bounce` and `.heart` idle modes, the animator drives the transform; for other modes the animator is bypassed via an outer `Group { if idleAnimation == .bounce && !quietHoursEnabled && !reduceMotion { … } else { … } }` split.

- [ ] **Step 3.1: Update `IdleAnimationTests.swift` — replace bounce source-string assertions**

Edit `ClaudeAlertBotTests/IdleAnimationTests.swift`. Replace the entire `test_widgetIconViewSource_wiresBounceSquashScale` method (currently at lines 118–126) with:

```swift
    func test_widgetIconViewSource_wiresBounceKeyframeAnimator() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("KeyframeAnimator"))
        XCTAssertTrue(src.contains("MotionKeyframes.bounceCycle"))
        XCTAssertTrue(src.contains("MotionKeyframes.bouncePeriod"))
        XCTAssertTrue(src.contains("BounceAnimatorValue"))
        // Anchor at bottom — HTML transform-origin: 50% 100% for bounce-cute.
        XCTAssertTrue(src.contains("anchor: .bottom"))
    }
```

Also remove (delete) these lines from `test_widgetIconViewSource_restartsWhenIdleAnimationChanges` (currently lines 176–177):

```swift
        XCTAssertTrue(restartBody.contains("bounceOffset = 0"))
        XCTAssertTrue(restartBody.contains("bounceScale = 1.0"))
```

- [ ] **Step 3.2: Run the updated tests to verify they fail**

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/IdleAnimationTests/test_widgetIconViewSource_wiresBounceKeyframeAnimator
```
Expected: FAIL — `KeyframeAnimator` / `MotionKeyframes.bounceCycle` not yet in `WidgetIconView.swift`.

- [ ] **Step 3.3: Add the bounce animator-value struct**

In `App/WidgetIconView.swift`, after the closing brace of `WidgetIconView` and `RoamOffsetEffect` (i.e., at the end of the file), add:

```swift
struct BounceAnimatorValue {
    var translateY: CGFloat = MotionKeyframes.bounceCycle[0].translateY
    var scaleX: CGFloat = MotionKeyframes.bounceCycle[0].scaleX
    var scaleY: CGFloat = MotionKeyframes.bounceCycle[0].scaleY
}
```

- [ ] **Step 3.4: Remove the old `bounceOffset` / `bounceScale` state and its uses**

Edit `App/WidgetIconView.swift`:

1. Delete lines 23 and 24 (`@State private var bounceOffset` and `@State private var bounceScale`).
2. In the `.scaleEffect(...)` modifier (currently line 71), change:
   ```swift
   .scaleEffect(quietHoursEnabled ? 1.0 : heartScale * breatheScale * bounceScale * alertPulseScale)
   ```
   to:
   ```swift
   .scaleEffect(quietHoursEnabled ? 1.0 : breatheScale * alertPulseScale)
   ```
   (Note: `heartScale` and `bounceScale` are removed here — Heart is rewired in Task 4; this leaves Heart visually broken between Tasks 3 and 4. That is acceptable for the intermediate commit because Task 4 lands immediately after.)
3. In the `.offset(...)` modifier (currently line 73), change:
   ```swift
   y: quietHoursEnabled ? 0 : bounceOffset + driftOffset.height
   ```
   to:
   ```swift
   y: quietHoursEnabled ? 0 : driftOffset.height
   ```
4. In `startIdleAnimation()` (currently line 138), delete the entire `case .bounce:` block (lines 142–148):
   ```swift
   case .bounce:
       guard let anim = MotionTokens.bounceAnimation(reduceMotion: reduceMotion) else { return }
       bounceScale = MotionTokens.bounceStretchScale
       withAnimation(anim) {
           bounceOffset = -MotionTokens.bounceOffset
           bounceScale = MotionTokens.bounceSquashScale
       }
   ```
   Replace with:
   ```swift
   case .bounce:
       // Bounce is driven by the KeyframeAnimator wrapper around the glyph
       // (see `body`). startIdleAnimation has nothing to set up here.
       return
   ```
5. In `restartIdleAnimation()` (currently line 173), delete the two lines:
   ```swift
   bounceOffset = 0
   bounceScale = 1.0
   ```

- [ ] **Step 3.5: Wrap the glyph in `KeyframeAnimator` when Bounce is active**

In `App/WidgetIconView.swift`, inside `body`, find the `Image("ClaudeCodeIcon")` block (currently lines 66–104). Refactor it so the entire `Image` and its modifier chain is produced by a private helper `glyph()`, and the outer `body` chooses between `KeyframeAnimator { glyph() } keyframes: { ... }` and `glyph()` depending on whether bounce is active.

Add this private helper inside `WidgetIconView` (place it just before `private func startIdleAnimation()`):

```swift
    @ViewBuilder
    private func glyph(bounceValue: BounceAnimatorValue) -> some View {
        Image("ClaudeCodeIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 36, height: 36)
            .frame(width: 44, height: 44)
            .scaleEffect(
                x: quietHoursEnabled ? 1.0 : bounceValue.scaleX,
                y: quietHoursEnabled ? 1.0 : bounceValue.scaleY,
                anchor: .bottom
            )
            .scaleEffect(quietHoursEnabled ? 1.0 : breatheScale * alertPulseScale)
            .rotationEffect(.degrees(quietHoursEnabled ? 0 : alertPulseRotation + idleRotation), anchor: .top)
            .offset(
                x: quietHoursEnabled ? 0 : driftOffset.width,
                y: quietHoursEnabled ? 0 : bounceValue.translateY + driftOffset.height
            )
            .modifier(RoamOffsetEffect(
                angle: roamPhase,
                radiusX: Double(MotionTokens.roamRadiusX),
                radiusY: Double(MotionTokens.roamRadiusY),
                isActive: idleAnimation == .roam && !quietHoursEnabled && !reduceMotion
            ))
            .onAppear {
                startIdleAnimation()
                runNewAlertPulse()
            }
            .onDisappear {
                stopDriftAnimation()
                stopHeartAnimation()
            }
            .onChange(of: quietHoursEnabled) { _, _ in
                resetAlertPulse()
                restartIdleAnimation()
            }
            .onChange(of: idleAnimation) { _, _ in
                restartIdleAnimation()
            }
            .onChange(of: reduceMotion) { _, _ in
                resetAlertPulse()
                restartIdleAnimation()
            }
            .onChange(of: alertPulseID) { _, _ in
                runNewAlertPulse()
            }
    }
```

Then in `body`, replace the `Image("ClaudeCodeIcon")` ... `.onChange(of: alertPulseID) ...` block with:

```swift
                if idleAnimation == .bounce && !quietHoursEnabled && !reduceMotion {
                    KeyframeAnimator(
                        initialValue: BounceAnimatorValue(),
                        repeating: true
                    ) { value in
                        glyph(bounceValue: value)
                    } keyframes: { _ in
                        // translateY: 5 segments mirroring HTML keyframes
                        KeyframeTrack(\.translateY) {
                            CubicKeyframe(MotionKeyframes.bounceCycle[1].translateY,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                            CubicKeyframe(MotionKeyframes.bounceCycle[2].translateY,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[3].translateY,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[4].translateY,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                        }
                        KeyframeTrack(\.scaleX) {
                            CubicKeyframe(MotionKeyframes.bounceCycle[1].scaleX,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                            CubicKeyframe(MotionKeyframes.bounceCycle[2].scaleX,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[3].scaleX,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[4].scaleX,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                        }
                        KeyframeTrack(\.scaleY) {
                            CubicKeyframe(MotionKeyframes.bounceCycle[1].scaleY,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                            CubicKeyframe(MotionKeyframes.bounceCycle[2].scaleY,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[3].scaleY,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[4].scaleY,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                        }
                    }
                } else {
                    glyph(bounceValue: BounceAnimatorValue())
                }
```

(`BounceAnimatorValue` must conform to nothing special — `KeyframeAnimator` infers the type from the `initialValue`; it uses key paths declared in `keyframes:` to interpolate.)

- [ ] **Step 3.6: Build and run the bounce tests**

```bash
xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS'
```
Expected: build succeeds.

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/IdleAnimationTests/test_widgetIconViewSource_wiresBounceKeyframeAnimator
```
Expected: PASS.

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/IdleAnimationTests/test_widgetIconViewSource_restartsWhenIdleAnimationChanges
```
Expected: PASS.

- [ ] **Step 3.7: Commit**

```bash
git add App/WidgetIconView.swift ClaudeAlertBotTests/IdleAnimationTests.swift
git commit -m "feat: replace Bounce single-axis path with KeyframeAnimator

Multi-track (translateY/scaleX/scaleY) animator driven by
MotionKeyframes.bounceCycle. Mirrors HTML @keyframes bounce-cute
2-axis squash-and-stretch. Removes bounceOffset and bounceScale state.

Heart still references the old MotionTokens path; Task 4 rewires it
next. Intermediate state — do not stop here."
```

---

## Task 4: Rewire Heart in `WidgetIconView` with `KeyframeAnimator`

**Files:**
- Modify: `App/WidgetIconView.swift`
- Modify: `ClaudeAlertBotTests/IdleAnimationTests.swift:47-58` and `:179-180`

- [ ] **Step 4.1: Replace heart source-string test**

In `ClaudeAlertBotTests/IdleAnimationTests.swift`, replace `test_widgetIconViewSource_wiresHeartBranch` (currently lines 47–58) with:

```swift
    func test_widgetIconViewSource_wiresHeartKeyframeAnimator() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("MotionKeyframes.heartCycle"))
        XCTAssertTrue(src.contains("MotionKeyframes.heartPeriod"))
        XCTAssertTrue(src.contains("HeartAnimatorValue"))
        // Anchor at center — HTML transform-origin: 50% 50% for heartbeat.
        XCTAssertTrue(src.contains("anchor: .center"))
    }
```

Also remove these lines from `test_widgetIconViewSource_restartsWhenIdleAnimationChanges` (currently lines 179–180):

```swift
        XCTAssertTrue(restartBody.contains("heartScale = 1.0"))
        XCTAssertTrue(restartBody.contains("heartGeneration += 1"))
```

- [ ] **Step 4.2: Run heart test to verify it fails**

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/IdleAnimationTests/test_widgetIconViewSource_wiresHeartKeyframeAnimator
```
Expected: FAIL — `HeartAnimatorValue` not yet defined.

- [ ] **Step 4.3: Add Heart animator-value struct**

In `App/WidgetIconView.swift`, just below `BounceAnimatorValue` (the struct added in Task 3.3), add:

```swift
struct HeartAnimatorValue {
    var scale: CGFloat = MotionKeyframes.heartCycle[0].scale
}
```

- [ ] **Step 4.4: Remove old heart state and helpers**

Edit `App/WidgetIconView.swift`:

1. Delete the `@State private var heartScale` and `@State private var heartGeneration` lines (currently lines 28–29).
2. In `glyph(bounceValue:)` (added in Task 3.5), the `.scaleEffect(...)` multiplier line currently reads:
   ```swift
   .scaleEffect(quietHoursEnabled ? 1.0 : breatheScale * alertPulseScale)
   ```
   Change its signature and the call sites so heart scale becomes a parameter. Update the helper signature to:
   ```swift
   private func glyph(bounceValue: BounceAnimatorValue, heartScale: CGFloat) -> some View {
   ```
   and the `.scaleEffect` line to:
   ```swift
   .scaleEffect(quietHoursEnabled ? 1.0 : heartScale * breatheScale * alertPulseScale)
   ```
3. Delete `case .heart:` from `startIdleAnimation()` and replace it with:
   ```swift
   case .heart:
       // Heart is driven by the KeyframeAnimator wrapper around the glyph.
       return
   ```
4. Delete the entire methods `startHeartAnimation()`, `stopHeartAnimation()`, `runHeartBeat(generation:)`, `scheduleHeartBeat(after:generation:scale:)`.
5. Remove `stopHeartAnimation()` from the `.onDisappear` chain inside `glyph(...)`.

- [ ] **Step 4.5: Wrap the glyph with a Heart `KeyframeAnimator` branch**

In `body`, change the branching from Task 3.5 so all three states are covered:

```swift
                if idleAnimation == .bounce && !quietHoursEnabled && !reduceMotion {
                    KeyframeAnimator(
                        initialValue: BounceAnimatorValue(),
                        repeating: true
                    ) { value in
                        glyph(bounceValue: value, heartScale: 1.0)
                    } keyframes: { _ in
                        // ... (unchanged from Task 3.5)
                    }
                } else if idleAnimation == .heart && !quietHoursEnabled && !reduceMotion {
                    KeyframeAnimator(
                        initialValue: HeartAnimatorValue(),
                        repeating: true
                    ) { value in
                        glyph(bounceValue: BounceAnimatorValue(), heartScale: value.scale)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(MotionKeyframes.heartCycle[1].scale,
                                          duration: MotionKeyframes.heartPeriod * 0.14)
                            CubicKeyframe(MotionKeyframes.heartCycle[2].scale,
                                          duration: MotionKeyframes.heartPeriod * 0.14)
                            CubicKeyframe(MotionKeyframes.heartCycle[3].scale,
                                          duration: MotionKeyframes.heartPeriod * 0.14)
                            CubicKeyframe(MotionKeyframes.heartCycle[4].scale,
                                          duration: MotionKeyframes.heartPeriod * 0.14)
                            CubicKeyframe(MotionKeyframes.heartCycle[5].scale,
                                          duration: MotionKeyframes.heartPeriod * 0.44)
                        }
                    }
                } else {
                    glyph(bounceValue: BounceAnimatorValue(), heartScale: 1.0)
                }
```

The Heart anchor is `.center` — that's the default for `.scaleEffect(_:)` (single CGFloat). No explicit `anchor:` argument needed for this multiplier, so the test assertion `src.contains("anchor: .center")` is satisfied via an explicit annotation: change the heart-specific multiplier line in `glyph(...)` to:

```swift
            .scaleEffect(quietHoursEnabled ? 1.0 : heartScale * breatheScale * alertPulseScale, anchor: .center)
```

- [ ] **Step 4.6: Build and run all `WidgetIconView`-source tests**

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/IdleAnimationTests
```
Expected: PASS for all IdleAnimationTests (the heart, bounce, restart tests all reflect the new wiring).

- [ ] **Step 4.7: Commit**

```bash
git add App/WidgetIconView.swift ClaudeAlertBotTests/IdleAnimationTests.swift
git commit -m "feat: replace Heart step-timer path with KeyframeAnimator

Single-track (scale) animator driven by MotionKeyframes.heartCycle.
Mirrors HTML @keyframes heartbeat double-pulse rhythm: peak 1 at
14% (1.14), peak 2 at 42% (1.08), idle from 56%→100%. Removes
heartScale/heartGeneration state and the runHeartBeat asyncAfter
ladder."
```

---

## Task 5: Remove deleted tokens from `DesignTokens.swift` and update tests

**Files:**
- Modify: `App/DesignTokens.swift:94-173`
- Modify: `ClaudeAlertBotTests/DesignTokensTests.swift:175-206` and `:269-277`

- [ ] **Step 5.1: Delete the now-dead token tests**

In `ClaudeAlertBotTests/DesignTokensTests.swift`, delete these 6 test methods entirely (line numbers from current source, ranges inclusive):
- `test_motionTokens_bounceDuration_is0_45` (lines 175–177)
- `test_motionTokens_bounceOffset_is5` (lines 179–181)
- `test_motionTokens_bounceStretchScale_is1_04` (lines 183–185)
- `test_motionTokens_bounceSquashScale_is0_94` (lines 187–189)
- `test_motionTokens_bounceAnimation_returnsNil_whenReduceMotionIsTrue` (lines 269–272)
- `test_motionTokens_bounceAnimation_returnsNonNil_whenReduceMotionIsFalse` (lines 274–277)

Also, inside whichever test currently contains the `heartDuration`/`heartBeatStepDuration`/`heartPeakScale`/`heartSecondScale`/`heartBeatAnimation` source-string assertions (around lines 202–206), delete those 5 `XCTAssertTrue(src.contains("..."))` lines. If the enclosing test ends up with no remaining assertions, delete the entire test method.

- [ ] **Step 5.2: Run the suite to confirm the deletions compile cleanly**

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
  -only-testing:ClaudeAlertBotTests/DesignTokensTests
```
Expected: PASS (with the 6 tests removed; remaining tests still hold).

- [ ] **Step 5.3: Delete the dead tokens from `App/DesignTokens.swift`**

In `App/DesignTokens.swift`, delete these specific lines inside `enum MotionTokens`:

1. Lines 95–99 — bounce token block:
   ```swift
   // SPEC.md §4 row "Bounce (idle)" — 0.45s duration, 5pt vertical, easeInOut, autoreverse, infinite.
   static let bounceDuration: TimeInterval = 0.45
   static let bounceOffset: CGFloat = 5
   static let bounceStretchScale: CGFloat = 1.04
   static let bounceSquashScale: CGFloat = 0.94
   ```
2. Lines 103–107 — heart token block:
   ```swift
   // FEATURES.md §1 row "Heart" — prototype heartbeat double-pulse at 14/28/42/56% of 1.4s.
   static let heartDuration: TimeInterval = 1.4
   static let heartBeatStepDuration: TimeInterval = heartDuration * 0.14
   static let heartPeakScale: CGFloat = 1.14
   static let heartSecondScale: CGFloat = 1.08
   ```
3. Lines 144–147 — `bounceAnimation(reduceMotion:)`:
   ```swift
   static func bounceAnimation(reduceMotion: Bool) -> Animation? {
       guard !reduceMotion else { return nil }
       return .easeInOut(duration: bounceDuration).repeatForever(autoreverses: true)
   }
   ```
4. Lines 154–157 — `heartBeatAnimation(reduceMotion:)`:
   ```swift
   static func heartBeatAnimation(reduceMotion: Bool) -> Animation? {
       guard !reduceMotion else { return nil }
       return .easeInOut(duration: heartBeatStepDuration)
   }
   ```
5. Update the doc comment at lines 141–143 if it still references `bounceAnimation` — change the example to `breatheAnimation` (a remaining function).

- [ ] **Step 5.4: Run the full suite**

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'
```
Expected: all tests pass.

- [ ] **Step 5.5: Verify no stale references remain**

```bash
grep -RIn "bounceOffset\|bounceStretchScale\|bounceSquashScale\|bounceDuration\|bounceAnimation\|heartBeatStepDuration\|heartPeakScale\|heartSecondScale\|heartDuration\|heartBeatAnimation" App/ ClaudeAlertBotTests/
```
Expected: no output.

- [ ] **Step 5.6: Commit**

```bash
git add App/DesignTokens.swift ClaudeAlertBotTests/DesignTokensTests.swift
git commit -m "refactor: drop dead Bounce/Heart motion tokens

The bounce/heart paths are now driven by MotionKeyframes via
KeyframeAnimator. Remove the legacy single-scalar / easeInOut tokens
and their drift-guard tests in one pass."
```

---

## Task 6: Visual sign-off (manual)

This is a checkpoint, not a code task. Do not skip.

- [ ] **Step 6.1: Build the app**

```bash
./scripts/build.sh
```
Expected: `build/export/ClaudeAlertBot.app` exists.

- [ ] **Step 6.2: Launch the app and the prototype side-by-side**

```bash
open build/export/ClaudeAlertBot.app
open "Claude Alert Bot - Prototype v2.html"
```

- [ ] **Step 6.3: Trigger a real alert**

Run any command in iTerm2 with the Claude Code or Codex CLI hooks installed (see `Reporter/cab-report.sh`). Or, send a synthetic stop event:

```bash
echo '{"schema_version":1,"event":"stop","session_id":"manual-test","cwd":"'"$(pwd)"'","iterm_session_id":"manual","tty":"/dev/ttys000","term_program":"iTerm.app","ts":"'"$(date -u +%FT%TZ)"'","exit_code":0,"kind":"success"}' \
  | nc -U "$HOME/Library/Application Support/ClaudeAlertBot/ipc.sock"
```

- [ ] **Step 6.4: Switch idle animation to Bounce in Preferences and compare**

Check:
- Glyph compresses laterally (`scaleX > 1, scaleY < 1`) at the bottom.
- Glyph stretches vertically (`scaleX < 1, scaleY > 1`) at the apex (~5pt up).
- Sub-perceptible mid-frames at 18%/82% prevent the motion from looking like a sine wave.
- Reduce Motion (System Settings → Accessibility) → glyph is static.
- Quiet Hours → glyph is static.

- [ ] **Step 6.5: Switch idle animation to Heart and compare**

Check:
- Two quick beats per 1.4-second cycle: peak at ~0.2s (14%), smaller peak at ~0.6s (42%).
- Long pause between cycles (56%→100% idle).
- Reduce Motion → static.
- Quiet Hours → static.

- [ ] **Step 6.6: User sign-off**

Stop and ask the user: "Bounce/Heart now matches the HTML prototype?" Wait for explicit yes before declaring Phase 1 complete. If the user finds a mismatch, capture the specific frame/timing complaint and treat it as a new task on top of this plan (do not silently re-tune).

---

## Self-Review Notes

- **Spec coverage:** §1 Phase 1 → Tasks 1–5; §2 architecture (new `MotionKeyframes.swift`, KeyframeAnimator in `WidgetIconView`) → Tasks 1, 2, 3, 4; §3 Bounce keyframes → Task 1, applied in Task 3; §4 Heart keyframes → Task 2, applied in Task 4; §5 compatibility/migration (token deletions) → Task 5; §7 testing (unit + manual visual) → Tasks 1, 2, 6; §6 SPEC §4 correction is explicitly Phase 4 (out of this plan).
- **Placeholder scan:** no TBD/TODO; every step shows the exact code or command.
- **Type consistency:** `BounceAnimatorValue` and `HeartAnimatorValue` declared in Task 3.3 / 4.3, used in Tasks 3.5 / 4.5; `MotionKeyframes.bounceCycle[i].translateY/scaleX/scaleY` matches the struct defined in Task 1.3.
- **Known intermediate breakage:** Between Task 3 commit and Task 4 commit, Heart visually loses its scaling (multiplier dropped from the `.scaleEffect`). This is acknowledged in the Task 3.7 commit message and resolved by the very next task. Do not interrupt the plan between Tasks 3 and 4.
