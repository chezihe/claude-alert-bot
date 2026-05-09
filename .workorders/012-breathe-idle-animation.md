# WO-012: Breathe idle animation

## Goal
WidgetIconView 에 Breathe idle animation 을 추가한다. SPEC §4 "Breathe" 행: 2.4s easeInOut, autoreverse, infinite, scale 1.0↔1.06. 현재 Bounce 가 하드코딩돼 있으므로 Breathe 를 **기본(default) idle animation** 으로 전환하고 Bounce 는 그대로 유지한 채 둘 중 하나를 소스 상수로 선택할 수 있게 구조를 잡는다. (사용자 선택 UI 는 별도 follow-up.)

## Context

(SPEC.md §4 Motion — 발췌)
| Animation | Duration | Curve | Notes |
|---|---|---|---|
| Bounce (idle) | 0.45s, autoreverse, infinite | `easeInOut` | 5pt vertical + scale 1.04↔0.94 squash |
| Breathe | 2.4s, autoreverse, infinite | `easeInOut` | scale 1.0↔1.06 |

(SPEC.md §4 Reduce Motion)
> when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == true`, disable all infinite loops, replace springs with linear 0.15s fades.

(FEATURES.md §1 Idle 애니메이션)
> Bounce / Heart / Ring / Roam — 사용자 선택, 무한 루프
> Breathe 는 FEATURES.md 에 직접 기명되지 않지만 SPEC §4 에 명시되고, SPEC §8 빌드 순서에서 "start with breathe (simplest)" 로 우선 추천.

(현재 코드)
- `App/DesignTokens.swift` `MotionTokens` 에 bounce 토큰 2개 (`bounceDuration: 0.45`, `bounceOffset: 5`) + `bounceAnimation(reduceMotion:) -> Animation?` factory.
- `App/WidgetIconView.swift` 에서 `bounceOffset` state 를 `onAppear` 에서 `withAnimation(MotionTokens.bounceAnimation(...))` 로 구동. 현재 **scaleEffect 없음** — bounce 는 offset 만 사용.
- `ClaudeAlertBotTests/DesignTokensTests.swift` 에 bounce 토큰 drift-guard 4개 케이스.

(idle animation 선택 구조 — 결정)
- `IdleAnimation` enum: `.bounce`, `.breathe`. static let `default: IdleAnimation = .breathe`.
- `WidgetIconView` 는 `idleAnimation: IdleAnimation = .default` 프로퍼티를 받고, `onAppear` 에서 분기.
- 향후 `.ring`, `.roam`, `.drift` 추가 + Settings UI 에서 선택 가능하도록 확장 여지를 남김.
- 이 WO 에서는 Settings UI 추가 **하지 않음** — 소스 상수 전환만.

## Inputs

분석/수정 대상:

- **`App/DesignTokens.swift`** — `MotionTokens` 에 breathe 토큰 추가:
  ```swift
  // SPEC.md §4 row "Breathe" — 2.4s, autoreverse, infinite, easeInOut, scale 1.0↔1.06.
  static let breatheDuration: TimeInterval = 2.4
  static let breatheScale: CGFloat = 1.06

  static func breatheAnimation(reduceMotion: Bool) -> Animation? {
      guard !reduceMotion else { return nil }
      return .easeInOut(duration: breatheDuration).repeatForever(autoreverses: true)
  }
  ```
  기존 bounce 토큰/factory 무변경.

- **(신규) `App/IdleAnimation.swift`** — 작은 enum:
  ```swift
  // App/IdleAnimation.swift — WO-012 idle animation selector.
  // SPEC §4 lists multiple idle animations; this enum lets WidgetIconView
  // switch between them. Settings UI for user selection is a follow-up.
  import Foundation

  enum IdleAnimation: String, CaseIterable {
      case bounce
      case breathe

      static let `default`: IdleAnimation = .breathe
  }
  ```
  Foundation import 만 (enum 은 SwiftUI 불필요).

- **`App/WidgetIconView.swift`** — 세 가지 변경:
  1. 새 프로퍼티 `var idleAnimation: IdleAnimation = .default` 추가 (`pendingCount` 아래).
  2. 새 `@State private var breatheScale: CGFloat = 1.0` 추가 (`bounceOffset` 옆).
  3. `Image("ClaudeCodeIcon")` 체인에 `.scaleEffect(breatheScale)` modifier 추가 — `.offset(y: bounceOffset)` **앞에** (scale 이 offset 기준점에 영향 주지 않도록).
  4. `onAppear` 블록을 idle animation 분기로 교체:
     ```swift
     .onAppear {
         switch idleAnimation {
         case .bounce:
             guard let anim = MotionTokens.bounceAnimation(reduceMotion: reduceMotion) else { return }
             withAnimation(anim) {
                 bounceOffset = -MotionTokens.bounceOffset
             }
         case .breathe:
             guard let anim = MotionTokens.breatheAnimation(reduceMotion: reduceMotion) else { return }
             withAnimation(anim) {
                 breatheScale = MotionTokens.breatheScale
             }
         }
     }
     ```
  - 기존 `bounceOffset` state + badge logic + accessibility label + frame/alignment 무변경.
  - bounce 분기의 기존 코드 그대로 보존 — switch case 로 감싸기만.

- 테스트:
  - **`ClaudeAlertBotTests/DesignTokensTests.swift`** — append 4 케이스:
    - `test_motionTokens_breatheDuration_is2_4`: `XCTAssertEqual(MotionTokens.breatheDuration, 2.4, accuracy: 0.001)`
    - `test_motionTokens_breatheScale_is1_06`: `XCTAssertEqual(MotionTokens.breatheScale, 1.06, accuracy: 0.001)`
    - `test_motionTokens_breatheAnimation_returnsNil_whenReduceMotionIsTrue`: `XCTAssertNil(MotionTokens.breatheAnimation(reduceMotion: true))`
    - `test_motionTokens_breatheAnimation_returnsNonNil_whenReduceMotionIsFalse`: `XCTAssertNotNil(MotionTokens.breatheAnimation(reduceMotion: false))`
  - **(신규) `ClaudeAlertBotTests/IdleAnimationTests.swift`** — 3 케이스:
    - `test_idleAnimation_defaultIsBreathe`: `XCTAssertEqual(IdleAnimation.default, .breathe)`
    - `test_idleAnimation_allCasesContainsBounceAndBreathe`: allCases 에 `.bounce`, `.breathe` 포함 확인.
    - source-level audit: `App/WidgetIconView.swift` source 에 `case .breathe:` 분기와 `MotionTokens.breatheAnimation` 호출 존재.

읽어볼 것 (수정 X):
- `AGENTS.md`, `App/FloatingWidgetWindowController.swift` (WidgetIconView 인스턴스화 위치), `App/ClaudeAlertBotApp.swift`.

## Deliverables

- [ ] **`MotionTokens.breatheDuration = 2.4`** + `breatheScale = 1.06` + `breatheAnimation(reduceMotion:)` factory.
- [ ] **`App/IdleAnimation.swift`** 신규 — `.bounce`, `.breathe`, `default = .breathe`.
- [ ] **`WidgetIconView` 에 breathe scale animation 구현** — `scaleEffect(breatheScale)` + `onAppear` 분기.
- [ ] **`WidgetIconView.idleAnimation` 프로퍼티** — 기본값 `.default` (= `.breathe`).
- [ ] **기존 bounce 코드 보존** — switch 분기 안에서 동일 로직 유지.
- [ ] **Reduce Motion 준수** — `breatheAnimation(reduceMotion: true)` → nil → 아무 애니메이션 없음.
- [ ] **회귀 안전성**: 기존 bounce 토큰 (`bounceDuration`, `bounceOffset`, `bounceAnimation`) 값/시그니처 무변경. badge logic, accessibility label, frame, 기타 WidgetIconView modifier 무변경. PopoverContentView, PopoverRowView, WidgetPopoverController, FloatingWidgetWindowController, SessionRegistry, SessionStore, SettingsStore, SettingsView 무변경.
- [ ] **테스트 추가**: DesignTokensTests 4개 append, IdleAnimationTests 신규 3개. 풀 스위트 통과.

## Constraints (WO-specific)

- **기존 bounce 토큰/factory 값 변경 금지** — 새 토큰만 추가.
- **Settings UI 추가 금지** — idle animation 선택은 별도 follow-up. 이 WO 에서 `@AppStorage` / `@Published` 추가 금지.
- **`WidgetIconView` 의 `pendingCount`, badge, accessibility, frame 변경 금지**.
- **FloatingWidgetWindowController 에서 `WidgetIconView` 인스턴스화 시 `idleAnimation:` 인자 전달하지 않아도 됨** — 기본값 `.default` 가 `.breathe` 이므로 기존 call-site 무변경.
- **새 SwiftPM 의존성 금지**.
- **`onAppear` 외 `onDisappear` / `onChange` 로 idle animation 재시작 로직 추가 금지** — 이 WO 에서는 `onAppear` 1회 시작만.
- **무관 리팩터·rename·import 정렬·formatting 금지**.

## Verification

- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` 성공.
- 단위 테스트: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` 모두 통과.
- RED → GREEN: 새 테스트 (`test_motionTokens_breatheDuration_is2_4`, `test_motionTokens_breatheScale_is1_06`, `test_motionTokens_breatheAnimation_*`, `IdleAnimationTests` 3개) 가 변경 전에 실패하고 변경 후 통과.
- 수동 검증 (가능 시):
  1. 앱 실행 → 위젯 아이콘이 천천히 (2.4s 주기) 1.0↔1.06 scale 로 숨쉬듯 커졌다 작아짐.
  2. Reduce Motion 켜면 애니메이션 없이 정지 상태.
  3. `IdleAnimation.default` 를 `.bounce` 로 바꾸고 재빌드하면 기존 bounce 동작 그대로 (회귀 확인).
- 커밋: `feat(WO-012): breathe idle animation with MotionTokens and IdleAnimation enum`
- RESULT: `.workorders/012-RESULT.md`

## Out of scope

- Settings UI 에서 idle animation 선택 (별도 WO)
- Ring bell, Roam, Drift, Heart animation 구현
- New-alert pulse + sonar
- Quiet Hours idle animation pause
- Bounce 의 squash scale (1.04↔0.94) — 현재 bounce 는 offset 만 사용, scale 미적용; 별도
- `onDisappear` / animation restart / animation state persistence
- FEATURES.md / SPEC.md 문서 reconcile
- 무관 리팩터·rename·formatting
