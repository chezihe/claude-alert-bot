# WO-009: Popover dimensions, empty state, and header gear

## Goal
Popover 의 (a) 폭을 SPEC §3 에 맞춰 270pt 로 줄이고, (b) 최대 표시 행수를 4로 줄이고, (c) 큐가 비었을 때 `EmptyStateView` ("Listening for Claude sessions") 를 보여주고, (d) 헤더 우측에 항상 보이는 톱니(⚙) 버튼으로 Settings 창 진입점을 추가한다. SPEC.md §3 Geometry 의 popover 폭 280→270 reconciliation 도 본 WO 안에서 같이 처리한다.

## Context

(현재 상태 — 코드 인용)
- `App/DesignTokens.swift` `GeometryTokens.popoverWidth: CGFloat = 280` (코멘트에 "SPEC §3 says 270pt; code uses 280pt — token follows code per Finding F-1" 로 drift 명시).
- `App/DesignTokens.swift` `GeometryTokens.popoverMaxVisibleRows: Int = 8` (현재 8, "Phase 4" 자리표시).
- `App/PopoverContentView.swift` 헤더는 `shouldShowClearAll(rowCount:)` 가 true 일 때만 한국어 "모두 지우기" 버튼이 우상단에 보이고, 그 외에는 헤더가 통째로 미렌더. 큐가 비어있어도 별도 메시지 없음 (그냥 빈 ScrollView 가 뜸).
- `App/WidgetPopoverController.swift` `showPopover` 안 sizing 식이 하드코딩됨:
  ```swift
  let rows = max(1, queue.count)
  let bodyHeight = min(36 * rows, 36 * 8)
  let chromeHeight = PopoverContentRules.shouldShowClearAll(rowCount: queue.count) ? 32 : 0
  pop.contentSize = NSSize(width: 280, height: bodyHeight + chromeHeight)
  ```
  본 WO 가 토큰화 + 규칙 변경에 맞춰 식도 같이 갱신.
- 톱니 진입점은 현재 `MenuBarMenuContent` ("Settings…" 메뉴 항목) + ⌘, 단축키 두 곳뿐. Popover 안에서 Settings 로 가는 경로 없음.
- `@Environment(\.openSettings)` 는 macOS 14 SDK 표준 환경값. `App/ClaudeAlertBotApp.swift` 의 `MenuBarMenuContent` 에서 이미 사용 중.
- working tree 에 `SPEC.md` line 78 의 `Popover: 280pt wide` → `270pt wide` 변경이 unstaged 상태로 존재. 본 WO 의 commit 에 함께 흡수.

(SPEC.md §3 Geometry — 발췌, working tree 기준)
- `Popover: 270pt wide, 14pt corner radius`
- `Row: 36pt min height, 12pt horizontal padding, 8pt vertical padding`
- `Status dot: 7pt; hollow ring stroke 1.5pt`

(SPEC.md §5 State Model "Behaviors" 발췌)
> **Onboarding:** if `queue.isEmpty && !state.everHadAlerts`, popover shows "Listening to iTerm" empty state

본 WO 는 `everHadAlerts` 게이팅을 **하지 않는다** — 단순히 `queue.isEmpty` 일 때 항상 empty state 를 보여준다. `everHadAlerts` flag 추가는 별도 follow-up. Empty state 카피는 SPEC 의 "Listening to iTerm" 보다 도메인 정확도 (이 앱은 iTerm2 + Claude Code 양쪽 모두 의존) 와 minimal English UI 메모리 정책에 맞춰 **"Listening for Claude sessions"** 으로 결정.

(FEATURES.md §3 발췌)
- **최대 4행** 표시, 그 이상은 세로 스크롤
- **빈 상태 온보딩** — `queue.isEmpty && !everHadAlerts` 일 때 "Listening to iTerm" 표시
- **설정 톱니** — 헤더 우측, Preferences 창 오픈

(스타일 — minimal English UI 메모리 정책 + 기존 한국어 카피 carry-over)
- Empty state 카피: `"Listening for Claude sessions"` — 영어, 보조 색상.
- 톱니 버튼: SF Symbol `"gearshape"`, accessibility label `"Open Settings"`. 한국어 라벨 없음.
- "모두 지우기" 한국어 카피 **그대로 유지** (carry-over). 헤더 안 위치만 톱니 왼쪽으로 정돈.

(헤더 구조 변경 정책 — 결정)
- 헤더는 **항상 렌더** (톱니가 항상 보여야 하므로). 큐 0행이어도 헤더 한 줄 + empty state.
- 헤더 행: `[Spacer] [모두 지우기 (조건부)] [톱니]` — 우측 정렬, 톱니가 가장 오른쪽.
- 헤더 padding 은 기존과 동일: `.padding(.horizontal, 12).padding(.top, 8)`.
- "모두 지우기" 가시성 규칙 (`shouldShowClearAll(rowCount: rowCount >= 2)`) 그대로.

(스코프 — IN/OUT)
- **IN**: `App/DesignTokens.swift` 토큰 2개 값/주석 갱신, `App/PopoverContentView.swift` 헤더 + empty state 분기 + `onOpenSettings` 콜백 추가, `App/EmptyStateView.swift` 신규 파일, `App/WidgetPopoverController.swift` 의 두 PopoverContentView 인스턴스화에 `onOpenSettings` 와이어업 + `showPopover` sizing 식 토큰화/empty 분기, `SPEC.md` §3 280→270 working tree 변경 같이 commit, 단위 테스트 추가/갱신.
- **OUT**: `everHadAlerts` flag 도입, popover 폭/행수 외 다른 GeometryTokens 변경, 톱니 위치를 좌측으로 옮기기, "모두 지우기" 카피 변경 / 영어화, empty state 카피를 SPEC 원문 ("Listening to iTerm") 로 그대로 두기, 헤더 separator/divider 추가, 폰트/간격 변경, popover background material 변경, MenuBarMenuContent 변경, FEATURES.md/HTML 문서 reconciliation (별도 사이클).

(AGENTS.md — binding)
- Code Change Discipline: 최소 변경, 함수 시그니처·기본 인자·docstring 변경 금지.
- macOS 14 타깃, Swift 5.10+, no Sandbox, zero external Swift dependencies.
- minimal English UI copy.

## Inputs

분석/수정 대상:

- **`App/DesignTokens.swift`** — `GeometryTokens` 안 두 토큰 값 + 주석 갱신:
  - `popoverWidth: 280 → 270`. 주석을 `// SPEC.md §3 row "Popover: 270pt wide" — WO-009 reconciles code/spec.` 로 교체. 기존 Finding F-1 / drift-guard 언급 줄 제거.
  - `popoverMaxVisibleRows: 8 → 4`. 주석을 `// FEATURES.md §3 row "최대 4행 표시" — WO-009 enforces; rows beyond scroll vertically.` 로 교체. 기존 "Phase 4" / "Centralise here" 언급 줄 제거.
  - 다른 토큰 (`popoverCornerRadius`, `rowMinHeight`, `rowHorizontalPadding`, `rowVerticalPadding`, `statusDotDiameter`, `statusDotRingStroke`, `MotionTokens.*`, `EffectTokens.*`, `ColorTokens.*`) 손대지 말 것.

- **`App/PopoverContentView.swift`** — 세 가지 변경:
  1. 새 콜백 프로퍼티 `onOpenSettings: () -> Void = {}` 추가 (기존 콜백 패턴 — `onTogglePin`, `onToggleMute`, `isProjectMuted`, `rowStates`, `onRowMissingComplete`, `onPopoverHoverChange` 옆에 한 줄로).
  2. 헤더 항상 렌더 + 톱니 추가. 기존
     ```swift
     if PopoverContentRules.shouldShowClearAll(rowCount: queue.count) {
         HStack {
             Spacer()
             Button("모두 지우기", action: onClearAll)
                 .buttonStyle(.plain)
                 .font(.system(size: 11))
                 .foregroundStyle(Color(NSColor.secondaryLabelColor))
                 .accessibilityLabel("모든 알림 지우기")
         }
         .padding(.horizontal, 12)
         .padding(.top, 8)
     }
     ```
     를 다음으로 교체:
     ```swift
     HStack(spacing: 8) {
         Spacer()
         if PopoverContentRules.shouldShowClearAll(rowCount: queue.count) {
             Button("모두 지우기", action: onClearAll)
                 .buttonStyle(.plain)
                 .font(.system(size: 11))
                 .foregroundStyle(Color(NSColor.secondaryLabelColor))
                 .accessibilityLabel("모든 알림 지우기")
         }
         Button(action: onOpenSettings) {
             Image(systemName: "gearshape")
                 .font(.system(size: 12))
                 .foregroundStyle(Color(NSColor.secondaryLabelColor))
         }
         .buttonStyle(.plain)
         .accessibilityLabel("Open Settings")
     }
     .padding(.horizontal, 12)
     .padding(.top, 8)
     ```
  3. 본문 분기:
     ```swift
     if queue.isEmpty {
         EmptyStateView()
     } else {
         ScrollView {
             VStack(spacing: 0) {
                 ForEach(orderedQueue) { session in
                     PopoverRowView(
                         session: session,
                         showTimeSuffix: dupProjects.contains(session.projectName),
                         state: rowStates[session.sessionID, default: .normal],
                         isMuted: isProjectMuted(session.projectName),
                         onClick: { onRowClick(session.sessionID) },
                         onTogglePin: { onTogglePin(session.sessionID) },
                         onToggleMute: { onToggleMute(session.projectName) },
                         onMissingComplete: { onRowMissingComplete(session.sessionID) }
                     )
                 }
             }
         }
         .scrollIndicators(.hidden)
         .frame(maxHeight: GeometryTokens.rowMinHeight * CGFloat(GeometryTokens.popoverMaxVisibleRows))
     }
     ```
     기존 `ScrollView` 본문은 그대로 보존 — `if queue.isEmpty / else` 분기로만 감쌈.
  - `.frame(width: GeometryTokens.popoverWidth)` / `.background(.thinMaterial)` / `.onHover { ... }` modifier 그대로.
  - `PopoverContentRules` 안 함수들 (`isAged`, `shouldShowClearAll`, `projectsWithDuplicates`, `timeSuffix`, `showsOrphanIndicator`, `orderedByPinnedThenStoppedAt`, `agingThresholdSec`) 시그니처 변경 금지. **새 helper 추가도 금지** — empty state 분기는 view-side `queue.isEmpty` 직접 체크로 충분.

- **(신규) `App/EmptyStateView.swift`** — 작은 SwiftUI View:
  ```swift
  // App/EmptyStateView.swift — WO-009 popover empty-state placeholder.
  // SPEC §5 Behaviors row "Onboarding" + FEATURES §3 row "빈 상태 온보딩".
  // Note: this WO does NOT gate on `everHadAlerts` (separate follow-up). Always renders when queue.isEmpty.
  import SwiftUI

  struct EmptyStateView: View {
      static let message = "Listening for Claude sessions"

      var body: some View {
          Text(Self.message)
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 16)
              .accessibilityLabel(Self.message)
      }
  }
  ```
  SwiftUI import 만. AppKit / Foundation 추가 import 금지. View 의 frame 폭은 부모 `popoverWidth` 가 결정 — 여기서는 `maxWidth: .infinity` 로 horizontal stretch.

- **`App/WidgetPopoverController.swift`** — 두 가지 변경:
  1. `PopoverContentView` 인스턴스화 두 군데 (`showPopover` ~line 87, `reloadPopoverContent` ~line 144) 모두에 새 콜백 와이어업 한 줄 추가:
     ```swift
     onPopoverHoverChange: { [weak self] hovering in self?.onPopoverHover(hovering) },
     onOpenSettings: {
         NSApp.activate(ignoringOtherApps: true)
         NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
     }
     ```
     macOS 14 minimum 이므로 `#available` 분기 불필요. `Selector(("showSettingsWindow:"))` 의 더블 괄호는 `@objc Selector` 문자열 리터럴 패턴.
  2. `showPopover` 의 sizing 식 갱신:
     ```swift
     let rows = max(1, queue.count)
     let rowsClamped = min(rows, GeometryTokens.popoverMaxVisibleRows)
     let bodyHeight: CGFloat = queue.isEmpty
         ? 48  // matches EmptyStateView natural height (text 12pt + .padding(.vertical, 16))
         : GeometryTokens.rowMinHeight * CGFloat(rowsClamped)
     let chromeHeight: CGFloat = 32  // header always visible (gear + optional Clear All)
     pop.contentSize = NSSize(width: GeometryTokens.popoverWidth, height: bodyHeight + chromeHeight)
     ```
     기존 width 280 / `36 * rows` / `36 * 8` / `shouldShowClearAll ? 32 : 0` 하드코딩 모두 제거.
  - controller 의 다른 메서드 (`onRowClick`, `onClearAll`, `onTogglePin`, `onToggleMute`, `dismissPopover`, `reloadPopoverContent` 본문 외 부분, `cornerToEdge`, `onPopoverHover`, hover 타이머 등) 무변경.

- **`SPEC.md`** — line 78 `Popover: 280pt wide, 14pt corner radius` → `Popover: 270pt wide, 14pt corner radius`. (이미 working tree 에 변경되어 있음 — 그대로 commit 에 포함만.)

- 테스트:
  - **`ClaudeAlertBotTests/DesignTokensTests.swift`** — 두 테스트 갱신:
    - `test_geometryTokens_popoverWidth_is280_perFindingF1` → `test_geometryTokens_popoverWidth_is270_perSpec`. assert `XCTAssertEqual(GeometryTokens.popoverWidth, 270)`. 코멘트에서 Finding F-1 언급 제거.
    - `test_geometryTokens_popoverMaxVisibleRows_is8` → `test_geometryTokens_popoverMaxVisibleRows_is4_perFeaturesSpec`. assert 4.
  - **(신규) `ClaudeAlertBotTests/EmptyStateViewTests.swift`** — 4~5 케이스:
    - `EmptyStateView.message == "Listening for Claude sessions"` 정적 카피 검증.
    - `EmptyStateView()` 인스턴스 구성 한 번 호출 (compile-time conformance 외 추가 부담 없음).
    - source-level audit: `App/EmptyStateView.swift` 가 `Text(Self.message)` 호출, `.foregroundStyle(.secondary)` 적용, `.accessibilityLabel(Self.message)` 호출, `import AppKit` 부재, `import Foundation` 부재 (SwiftUI 만).
  - **`ClaudeAlertBotTests/PopoverContentTests.swift`** (기존 파일 — append) — source-level audit:
    - `App/PopoverContentView.swift` source 에 `EmptyStateView()` 호출 존재.
    - source 에 `if queue.isEmpty {` 분기 존재.
    - source 에 `Image(systemName: "gearshape")` 존재.
    - source 에 `var onOpenSettings: () -> Void = {}` 또는 동등 (`onOpenSettings:` + `() -> Void`) 선언 존재.
    - source 에 `.accessibilityLabel("Open Settings")` 존재.
    - source 에 한국어 carry-over `"모두 지우기"`, `"모든 알림 지우기"` 두 문자열 모두 존재.
    - source 에 `Spacer()` 가 헤더 HStack 안에 존재 (헤더가 상시 렌더되도록 — 이 patch 가 외부 if 를 걷어냈음을 증명).

  - **rule level 회귀**: `PopoverContentTests` 의 기존 케이스 (`test_clearAllVisibility_*`, `test_sameProjectDuplicates_*`, `test_timeSuffix_*`, `test_orphanIndicator_*`, `test_orderedQueue_*`, `test_isAged_*`) 그대로 통과.

읽어볼 것 (수정 X):
- `AGENTS.md`, `App/PopoverRowView.swift`, `App/SessionRecord.swift`, `App/SessionRegistry.swift`, `App/ClaudeAlertBotApp.swift`, `App/AppDelegate.swift`, `App/SettingsView.swift`, `Claude Alert Bot - Prototype v2.html` (헤더/empty state 시각 톤 참조).

## Deliverables

- [ ] **`GeometryTokens.popoverWidth = 270`** + 주석에 SPEC §3 + WO-009 표기. Finding F-1 / drift-guard 언급 제거.
- [ ] **`GeometryTokens.popoverMaxVisibleRows = 4`** + 주석에 FEATURES §3 + WO-009 표기. "Phase 4" 언급 제거.
- [ ] **`PopoverContentView` 헤더 항상 렌더** (톱니 항상 보임). "모두 지우기" 는 `rowCount >= 2` 일 때만 표시.
- [ ] **헤더 톱니 버튼** (`Image(systemName: "gearshape")`) → `onOpenSettings()` 콜백 호출. accessibility label `"Open Settings"`.
- [ ] **`PopoverContentView.onOpenSettings: () -> Void = {}`** 새 콜백 프로퍼티. 다른 콜백 시그니처 (onRowClick / onClearAll / onTogglePin / onToggleMute / isProjectMuted / rowStates / onRowMissingComplete / onPopoverHoverChange) 무변경.
- [ ] **빈 큐 분기**: `queue.isEmpty` 면 `EmptyStateView()`, 아니면 기존 `ScrollView`. 헤더는 양쪽 모두 렌더.
- [ ] **`App/EmptyStateView.swift`** 신규 파일. `EmptyStateView.message == "Listening for Claude sessions"` 정적 카피.
- [ ] **`WidgetPopoverController` 두 인스턴스화에 `onOpenSettings:` 와이어업** — `NSApp.activate(ignoringOtherApps: true)` + `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` 실행.
- [ ] **`WidgetPopoverController` sizing 식 토큰화** — width 280 → `GeometryTokens.popoverWidth`, `36 * 8` → `GeometryTokens.rowMinHeight * CGFloat(GeometryTokens.popoverMaxVisibleRows)`, `36 * rows` 도 `GeometryTokens.rowMinHeight * CGFloat(rowsClamped)` 로, chrome 32 항상, empty 케이스 48pt body.
- [ ] **`SPEC.md` §3 Geometry "Popover: 280pt wide" → "270pt wide"** 같은 commit 에 포함.
- [ ] **회귀 안전성**: `PopoverRowView`, `SessionRegistry`, `SessionStore`, `SettingsStore`, `SettingsView`, `MutedProjectsRules`, `PopoverContentRules` (rule 함수들), `WidgetIconView`, `FloatingWidgetWindowController`, `FloatingWidgetPanel`, `MenuBarMenuContent`, `AppDelegate`, hook IPC, AppleScript path, sound/notification path, Reporter / scripts 무변경.
- [ ] **회귀 안전성 (cosmetic)**: 행 간격 / 행 폰트 / 행 stoppedAt 시간 suffix / aged saturation / context menu 카피 ("Mute this project for 1h" / "Unmute This Project" / "Pin alert (don't auto-clear)") / 한국어 "모두 지우기" 카피 / Settings 카피 모두 동일.
- [ ] **테스트 추가/갱신**: DesignTokensTests 두 케이스 갱신, EmptyStateViewTests 신규, PopoverContentTests append. 풀 스위트 통과.

## Constraints (WO-specific)

- **다른 토큰 변경 금지**: `popoverCornerRadius`, `rowMinHeight`, `rowHorizontalPadding`, `rowVerticalPadding`, `statusDotDiameter`, `statusDotRingStroke`, `MotionTokens.*`, `EffectTokens.*`, `ColorTokens.*` 그대로.
- **`PopoverContentRules` 함수 시그니처 변경 금지** — 새 함수 추가도 금지. 빈 큐 분기는 view-side `queue.isEmpty` 로 충분.
- **`everHadAlerts` flag 도입 금지** — `SessionStore` / `SettingsStore` / `@AppStorage` 추가 금지. 별도 follow-up.
- **헤더 톱니 좌측 이동 금지** — 항상 우상단, "모두 지우기" 왼쪽이 아니라 오른쪽 (가장 끝). HStack 순서: `Spacer → 모두지우기(if) → 톱니`.
- **`onOpenSettings` 외 새 콜백 추가 금지** — 한 개만.
- **`NSPopover.behavior`, `WidgetPopoverController` 의 dismiss 타이머 / hover handling 변경 금지** — 톱니 클릭이 popover 를 닫는 기존 동작 (외부 클릭 = transient close) 그대로 두면 됨.
- **MenuBarExtra 의 "Settings…" 항목 제거 금지** — 양쪽 진입점 공존.
- **새 SwiftPM 의존성 금지** (zero external Swift deps).
- **새 `@AppStorage` / `@Published` / `@StateObject` 추가 금지**.
- **`@Environment(\.openSettings)` 를 `PopoverContentView` 안에서 직접 사용 금지** — controller 가 closure 로 주입 (testability + 환경 propagation 의존성 줄이기).
- **carry-over 한국어 카피 변경 금지** — `"모두 지우기"`, `"모든 알림 지우기"`, contextMenu 의 한국어 항목 모두 그대로.
- **iTerm2 Python API 도입 금지** (AGENTS.md AVOID).
- **`pop.contentSize` 를 `reloadPopoverContent` 에서 새로 set 하지 말 것** — 기존 패턴 (showPopover 에서만 set) 그대로. 큐가 변하면서 새 행이 contentSize 를 넘어가면 ScrollView 가 처리.
- 함수 시그니처·기본 인자·docstring 변경은 본 Deliverables 가 명시적으로 요구하는 경우에만.
- 무관 리팩터·rename·import 정렬·formatting 금지.

## Verification

- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` 성공.
- 단위 테스트: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` 모두 통과. 환경 이슈 시 `CI=1 xcrun xctest <path-to-ClaudeAlertBotTests.xctest>` fallback.
- RED → GREEN: 새 / 갱신 테스트 (`test_geometryTokens_popoverWidth_is270_perSpec`, `test_geometryTokens_popoverMaxVisibleRows_is4_perFeaturesSpec`, `EmptyStateViewTests`, `PopoverContentTests` source-audit append) 가 변경 전에 실패하고 변경 후 통과하는 것 확인.
- 수동 검증 (가능 시):
  1. 앱 실행 후 popover 열기 — 폭이 (이전 280pt 대비) 약간 좁아 보임. 우상단 헤더에 톱니 아이콘 보임.
  2. 큐가 비어 있으면 popover 본문에 "Listening for Claude sessions" 가 secondary color 로 가운데 정렬.
  3. 큐가 1행: 헤더 = 톱니만. 본문 = 행 1개 ("모두 지우기" 없음).
  4. 큐가 2+행: 헤더 = "모두 지우기" + 톱니. 본문 = ScrollView.
  5. 큐가 5+행: 4행만 보이고 그 아래는 스크롤로 접근. (행 4 + 헤더 32 만큼 popover 세로 길이.)
  6. 톱니 클릭 → Settings 창이 열리고 (필요 시 앱이 foreground 로 활성화), popover 는 외부 클릭으로 닫힘.
  7. ⌘, 단축키 / MenuBarExtra 의 "Settings…" 도 동일하게 동작 (회귀 없음).
- 커밋: WO-009 단위 atomic commit. 권장 메시지: `feat(WO-009): popover width 270, 4-row cap, empty state, header gear`. 토큰-first → view → empty-state-file → controller-wire → SPEC reconcile → tests 순으로 분리해도 좋음 — 하지만 WO 단위 1 commit 권장.
- RESULT 문서: `.workorders/009-RESULT.md` — `## Summary` / `## Verification` / `## Deviations`.

## Out of scope

- `everHadAlerts` flag 추가 + Onboarding 게이팅 (SPEC §5 원문)
- Empty state 카피 다국어 / "Listening to iTerm" 정확한 SPEC 원문 매칭
- 헤더에 separator / divider / project count badge 추가
- 헤더에 Quiet Hours indicator 추가 (Zzz, moon overlay 등) — WO-008 영역
- 톱니 hover tint / animation
- popover background material (`.thinMaterial`) / corner radius / padding 변경
- popover dismiss policy (transient → semitransient 등) 변경
- 행 간격 / 행 폰트 / 행 카피 / 행 grouping 동작 변경
- `PopoverContentRules` 에 새 helper 추가
- `FEATURES.md`, `Claude Alert Bot - Prototype v2.html` 문서 reconciliation (별도 사이클)
- MenuBarExtra 메뉴 변경
- WidgetIconView, FloatingWidget panel 변경
- iTerm2 Python API 도입 — **금지** (AGENTS.md AVOID)
- 무관 리팩터·rename·formatting
