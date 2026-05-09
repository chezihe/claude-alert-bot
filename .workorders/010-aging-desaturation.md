# WO-010: Aging desaturation for popover rows older than 60 minutes

## Goal
60분 이상 popover 에 머문 row 는 **채도가 떨어진 형태**로 렌더되어 새 알림이 시각적으로 도드라지게 한다. binary on/off (60분 미만 = 정상, 60분 이상 = saturation 0.4). linear 보간·timer refresh·자동 clear 는 OUT.

## Context

(BACKLOG.md — 이번 WO 가 닫는 항목)
- Step 6 `[TODO] Aging style for rows older than 60 minutes is missing.` → DONE

(SPEC.md / FEATURES.md — Aging 규칙)
- 60분 이상 된 row 는 desaturate. "오래된 알림은 흐려지고, 새 알림이 도드라진다" 가 목적.
- 정확한 임계값: **60분 (3600 초)**. 초과 (`>` strict) 시 aged.
- 효과: SwiftUI `.saturation(0.4)`. **opacity 는 건드리지 않는다** (이미 unavailable 50% / faded 0% 로 사용 중 — 의미 충돌 방지).

(현재 코드 — `App/PopoverRowView.swift` body 발췌)
```swift
.opacity(faded ? 0 : (session.available ? 1 : 0.5))
.animation(.easeInOut(duration: 0.12), value: isHovered)
.clipped()
.contentShape(Rectangle())
```
- saturation modifier 는 아직 없음.

(현재 `PopoverContentRules` — `App/PopoverContentView.swift` 발췌)
```swift
enum PopoverContentRules {
    static func shouldShowClearAll(rowCount: Int) -> Bool { rowCount >= 2 }
    static func projectsWithDuplicates(...) -> Set<String> { ... }
    static func timeSuffix(for date: Date) -> String { ... }
    static func showsOrphanIndicator(session: CompletedSession) -> Bool { ... }
    static func orderedByPinnedThenStoppedAt(...) -> [CompletedSession] { ... }
}
```
- 이번 WO 는 같은 namespace 에 `agingThresholdSec` 상수와 `isAged(session:now:)` 추가.

(시각/거동 진실의 원천)
- `SPEC.md` §6 aging — saturation 효과로 명시.
- `FEATURES.md` §4 aging — 60분 boundary.
- `Claude Alert Bot - Prototype v2.html` — aging 의 시각 거동 (있다면 우선 따른다).

(AGENTS.md — binding)
- Code Change Discipline: 최소 변경. 함수 시그니처·기본 인자·docstring 변경 금지 (본 WO 가 명시적으로 요구하지 않는 한).
- UI Copy: 변경 없음.
- macOS 14 타깃, Swift 5.10+, no Sandbox, zero external Swift dependencies.

(시간 기준 — 정책 결정)
- `now: Date` 는 row body 가 렌더될 때마다 `Date()` 로 inline 평가. 즉 popover 가 다시 열리거나 새 알림이 오는 등 view 가 redraw 되는 순간 평가됨.
- **자동 60분 정확 hit 시 즉시 desaturate 하지 않는다** — 다음 redraw 때 자연스럽게 적용. timer 추가 금지 (별도 WO 면접).
- pinned row 도 동일 적용 (시간 효과는 핀 상태와 직교).
- unavailable / error / waiting kind 도 동일 적용 (saturation 은 색상 위에 곱셈 — kind 색이 자연스럽게 톤다운).

(스코프 명확화 — IN / OUT)
- **IN**: `PopoverContentRules.agingThresholdSec` 상수 + `isAged(session:now:)` 순수 함수 + `EffectTokens.agedSaturation` 토큰 + `PopoverRowView` 에 `.saturation(...)` modifier 한 줄 + 단위 테스트.
- **OUT**: linear interpolation, timer refresh, 자동 clear, opacity 변경, pinned 예외, settings 에서 임계값 조정 옵션, 다른 파일.

## Inputs

분석/수정 대상:
- `App/PopoverContentView.swift` — `PopoverContentRules` enum 안에 추가:
  ```swift
  static let agingThresholdSec: TimeInterval = 60 * 60
  static func isAged(session: CompletedSession, now: Date) -> Bool {
      now.timeIntervalSince(session.stoppedAt) > agingThresholdSec
  }
  ```
  다른 함수 손대지 말 것 (`shouldShowClearAll`, `projectsWithDuplicates`, `timeSuffix`, `showsOrphanIndicator`, `orderedByPinnedThenStoppedAt` 무변경).
- `App/DesignTokens.swift` — 새 enum `EffectTokens` 추가:
  ```swift
  enum EffectTokens {
      static let agedSaturation: Double = 0.4
  }
  ```
  `ColorTokens`, `GeometryTokens`, `MotionTokens` 손대지 말 것.
- `App/PopoverRowView.swift` — Button body 의 modifier chain 끝부분 (또는 `.opacity(...)` 직후) 에 한 줄 추가:
  ```swift
  .saturation(PopoverContentRules.isAged(session: session, now: Date()) ? EffectTokens.agedSaturation : 1.0)
  ```
  다른 modifier·element·layout·contextMenu·status dot·핀 글리프·time suffix·orphan·hover·opacity·missing animation 손대지 말 것.
- 테스트:
  - `ClaudeAlertBotTests/PopoverContentTests.swift` — `isAged` 보더리 4 케이스:
    - `stoppedAt = now` → false
    - `stoppedAt = now - 59min` → false
    - `stoppedAt = now - 60min` (정확) → false (`>` strict)
    - `stoppedAt = now - 60min - 1sec` → true
  - `ClaudeAlertBotTests/DesignTokensTests.swift` — `EffectTokens.agedSaturation == 0.4` 단순 검증
  - `ClaudeAlertBotTests/PopoverRowStateTests.swift` — source-level audit 2 케이스:
    - source 에 `.saturation(` 호출 존재
    - source 에 `PopoverContentRules.isAged` 호출 존재

읽어볼 것 (수정 X):
- `AGENTS.md`, `SPEC.md` §6, `FEATURES.md` §4, `Claude Alert Bot - Prototype v2.html`.
- `App/SessionRecord.swift` — `stoppedAt` 필드 타입 (`Date`) 확인.

## Deliverables

- [ ] **`PopoverContentRules.agingThresholdSec: TimeInterval = 3600`** + **`isAged(session:now:) -> Bool`** 순수 함수. 임계 strict (`>`).
- [ ] **`EffectTokens.agedSaturation: Double = 0.4`** 새 enum (DesignTokens.swift 안).
- [ ] **`PopoverRowView` 에 `.saturation(...)` modifier 1줄** — `now: Date()` inline 평가. aged 면 `EffectTokens.agedSaturation`, 아니면 `1.0`.
- [ ] **회귀 안전성**: `.opacity` 식 (`session.available ? 1 : 0.5`), hover bg, status dot kind 색 (WO-005), 핀 글리프 (WO-011), unavailable hollow ring (WO-002), missing animation (`rotation`, `collapsed`, `faded`), contextMenu (WO-006), click handler 모두 동일. row layout / 높이 / spacing 변경 없음.
- [ ] **테스트 추가** (총 7 assertion 안팎):
  - `isAged` 4 보더리
  - `EffectTokens.agedSaturation == 0.4`
  - PopoverRowView source 에 `.saturation(` 와 `PopoverContentRules.isAged` 둘 다 존재

## Constraints (WO-specific)

- **다른 파일 손대지 말 것**: `App/SessionRecord.swift`, `App/SessionRegistry.swift`, `App/SessionStore.swift`, `App/SettingsStore.swift`, `App/SettingsView.swift`, `App/WidgetPopoverController.swift`, `App/HookEvent.swift`, `App/HookListener.swift`, `App/NotificationOrchestrator.swift`, `App/FloatingWidgetWindowController.swift`, `App/WidgetIconView.swift`, `Reporter/*`, `scripts/*`. 빌드를 위해 read-only 참조는 허용.
- **`opacity` 변경 금지** — 이미 unavailable 50% / faded 0% 로 사용 중. aging 은 saturation 으로만 표현.
- **`agingThresholdSec` 상수 60 분 고정** — settings 에서 조정 가능 옵션 추가 금지.
- **임계 strict (`>`)** — 정확히 60분 시점은 not-aged.
- **timer / DispatchSource 추가 금지** — `now: Date()` 는 view body 의 inline 평가만. 60분 정확 hit 시 자동 redraw 안 됨 — 다음 자연 redraw 때 적용. 별도 WO.
- **pinned 예외 금지** — pinned row 도 동일하게 aged.
- **linear interpolation / multi-step desaturate 금지** — binary on/off.
- **자동 clear / hide 금지** — aged row 는 그대로 popover 에 남음.
- **DesignTokens 의 기존 enum (`ColorTokens`, `GeometryTokens`, `MotionTokens`) 손대지 말 것**.
- **`PopoverContentRules` 의 기존 함수 손대지 말 것**.
- **`justArrived`, ripple, sonar, breathe, ring, roam, drift, Quiet Hours, Reduce Motion 추가 금지**.
- **iTerm2 Python API 도입 금지** (AGENTS.md AVOID).
- 함수 시그니처·기본 인자·docstring 변경은 본 Deliverables 가 명시적으로 요구하는 경우에만.
- 무관 리팩터·rename·import 정렬·formatting 금지.

## Verification

- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` 성공.
- 단위 테스트: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` 모두 통과 (release 앱 종료 후. 환경 이슈 시 `CI=1 xcrun xctest …` fallback).
- 수동 검증 (가능 시):
  1. 디버거 / 임시 fixture 로 stoppedAt = 60분 + 1초 전 row → popover 다시 열면 채도 낮은 상태로 보임
  2. stoppedAt = 30분 전 row → 정상 채도
  3. aged 와 fresh row 가 popover 에 동시 존재 → fresh row 가 도드라짐
  4. aged 핀 row → 핀 글리프 (WO-011) 와 status dot kind 색 (WO-005) 모두 saturation 적용된 채로 정상 표시
  5. aged unavailable row → hollow ring 도 saturation 적용 (kind 색 톤 다운)
- 커밋: WO-010 단위로 atomic commit. 권장 메시지: `feat(WO-010): aging desaturation for rows older than 60 minutes`. 토큰 → rule → row modifier 순으로 분리 가능하면 더 좋음.
- RESULT 문서: `.workorders/010-RESULT.md` — `## Summary` / `## Verification` / `## Deviations`.

## Out of scope

- Linear interpolation / multi-step desaturate / aged 색상 변형
- Timer / DispatchSource 기반 1분마다 강제 refresh — 별도 WO
- 자동 clear / hide / pinned 예외
- Settings 화면에서 임계값 조정 옵션
- opacity 변경 / row 높이 / layout 재배치
- justArrived ripple, sonar wave, breathe, ring, roam, drift
- Quiet Hours, Reduce Motion 추가 정책
- WO-002/005/006/011 의 거동 변경
- popover 너비·행수·empty state·헤더 톱니
- iTerm2 Python API 도입 — **금지** (AGENTS.md AVOID)
- 무관 리팩터·rename·formatting
# === Codex Input — end ===
## Active Work Order

# WO-NNN: <짧은 제목>

## Goal
<1-2줄. 무엇이 끝났을 때 이 WO 가 종료되는가>

## Context
<Codex 가 알아야 할 최소 배경. SPEC/FEATURES/AGENTS 해당 섹션 인용 또는 line ref. 시각 거동은 Prototype HTML 가리킬 것>

## Inputs
- <참조 파일:line>
- <관련 문서/이슈>

## Deliverables
- [ ] <수정/생성할 파일 + 변경 내용 요지>
- [ ] <수용 기준 1>
- [ ] <수용 기준 2>

## Constraints (WO-specific)
- <이 WO 만의 추가 가드>

## Verification
- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build`
- 동작: <어떤 시나리오로 검증되면 끝인지>
- 커밋: 논리 단위로 atomic commit, conventional message
- RESULT: `.workorders/NNN-RESULT.md` 작성

## Out of scope
- <관련 있지만 이번엔 안 건드릴 것 — 폭주 방지>
```

