# WO-005: Status dot color branching by AlertKind (success / error / waiting)

## Goal
WO-004 에서 `CompletedSession.kind: AlertKind` 데이터까지 들어왔다. 이번 WO 는 그 값을 **PopoverRowView 의 status dot 색상**에만 매핑한다. 기존의 단일 `statusSuccess` 색을 `kind` 별 토큰으로 분기. 다른 시각 효과 (ripple / aging / breathe / ring) 는 모두 후속 WO.

## Context

(FEATURES.md §3 — 행 상태 닷)
> 각 row 의 status dot 은 `kind` 에 따라 색이 갈린다.
> - `success` → 따뜻한 success 톤
> - `error` → red error 톤
> - `waiting` → amber waiting 톤
> - 세션이 사라진 경우 (`available == false`) → hollow ring (현재 WO-002 동작 유지)

(BACKLOG.md — 이번 WO 가 닫는 항목 / 부분)
- Step 4 `[PARTIAL] Status dot scaffolding rendered (single success color + hollow ring for unavailable) — PopoverRowView.swift, DesignTokens.swift. (WO-002) Color branching for error/waiting awaits hook payload extension.` → 이번 WO 로 색상 분기를 채워 **DONE** 으로 닫는다.

(WO-004 결과 — 이미 완료, 이번 WO 의 **전제**)
- `enum AlertKind: String, Codable { case success, error, waiting }` 존재 (App/SessionRecord.swift). 디코딩 누락·알 수 없는 값은 `.success` 폴백.
- `CompletedSession.kind` 필드 존재. 모든 기존 코드 경로에서 `.success` 가 자연 폴백.

(현재 코드 — `App/PopoverRowView.swift` 발췌)
```swift
@ViewBuilder
private var statusDot: some View {
    if session.available {
        Circle()
            .fill(ColorTokens.statusSuccess)
            .frame(width: GeometryTokens.statusDotDiameter,
                   height: GeometryTokens.statusDotDiameter)
    } else {
        Circle()
            .stroke(ColorTokens.statusSuccess, lineWidth: GeometryTokens.statusDotRingStroke)
            .frame(width: GeometryTokens.statusDotDiameter,
                   height: GeometryTokens.statusDotDiameter)
    }
}
```

(이미 존재하는 토큰 — `App/DesignTokens.swift`)
- `ColorTokens.statusSuccess` (0xD97757)
- `ColorTokens.statusError` (0xE5484D)
- `ColorTokens.statusWaiting` (0xF5A623)
- `GeometryTokens.statusDotDiameter` (7), `GeometryTokens.statusDotRingStroke` (1.5)

(시각/거동 진실의 원천 — 함께 참조)
- `Claude Alert Bot - Prototype v2.html` — popover row status dot 의 색상 / 채움 / hollow ring 거동 시각 기준.
- `SPEC.md` §3 row "Status: success / error / waiting".

(AGENTS.md — binding)
- Code Change Discipline (No Over-Editing): 최소 변경, 무관 리팩터·rename 금지, 함수 시그니처·기본 인자·docstring 변경 금지 (본 WO 가 명시적으로 요구하지 않는 한).
- Min OS macOS 14, Swift 5.10+, no Sandbox, zero external Swift dependencies.
- UI Copy: 영어 미니멀 톤, 이모지·컬러 dot·장식 표현 지양 (이번 WO 는 카피 변경 없음).

(스코프 명확화 — IN / OUT)
- **IN**: `App/PopoverRowView.swift` 의 `statusDot` 가 `session.kind` 에 따라 success/error/waiting 색을 선택한다. 채움 (available) 과 hollow ring (unavailable) 양쪽에 동일한 색 매핑 적용. 단위 테스트.
- **OUT**: 신규 색 토큰 추가, hook payload 추가 변경, aging desaturation, ripple, motion, mute/pin, popover geometry, empty state, settings, NotificationOrchestrator, Reporter, scripts.

## Inputs

분석/수정 대상:
- `App/PopoverRowView.swift` — `statusDot` 가 `kind` 를 읽어 색을 분기. 다른 메서드·prop·레이아웃·접근성 라벨 손대지 말 것.
- (선택) `App/DesignTokens.swift` — **새 토큰 추가 금지**. 정 필요한 작은 매핑 헬퍼 (`func color(for kind: AlertKind) -> Color`) 를 둔다면 `ColorTokens` extension 으로 최소 추가 가능. 그 외 변경 금지.
- 테스트:
  - `ClaudeAlertBotTests/PopoverRowStateTests.swift` (또는 신규 `PopoverRowColorTests.swift`) — source-level audit 또는 pure-function 테스트. 기존 RowState 테스트 패턴을 따른다 (`readPopoverRowViewSource()` 헬퍼 또는 직접 String load).
  - 가능하면 `kind` 별 색이 올바른 토큰으로 매핑되는지 3 케이스 + unavailable hollow ring 케이스. SwiftUI View 의 픽셀 렌더 테스트는 하지 않는다 — 함수·소스 레벨 audit 으로 충분.

읽어볼 것 (수정 X):
- `AGENTS.md`, `FEATURES.md` §3, `SPEC.md` (state model), `Claude Alert Bot - Prototype v2.html`
- `App/SessionRecord.swift` — `AlertKind` 정의 위치 확인용.

## Deliverables

- [ ] **`statusDot` 색 분기**: `session.available == true` 일 때 `Circle().fill(<kind 별 색>)`, `false` 일 때 `Circle().stroke(<kind 별 색>, lineWidth: …)`. 색 매핑:
  - `.success` → `ColorTokens.statusSuccess`
  - `.error` → `ColorTokens.statusError`
  - `.waiting` → `ColorTokens.statusWaiting`
- [ ] **매핑 테스트성 확보**: `kind → Color` 매핑이 단위 테스트에서 검증 가능하도록 둘 중 하나로 분리:
  - (선호) `ColorTokens` 에 `static func statusDot(for kind: AlertKind) -> Color` extension 한 개 추가, `PopoverRowView.statusDot` 가 이를 호출.
  - 또는 `PopoverRowView` 내부 `private static func` 로 두고 source-level audit 로 검증.
- [ ] **테스트 추가**: 다음 4 케이스. (어느 방식이든 가능)
  - `.success` 매핑 → `ColorTokens.statusSuccess` 와 동일한 sRGB 컴포넌트
  - `.error` 매핑 → `ColorTokens.statusError`
  - `.waiting` 매핑 → `ColorTokens.statusWaiting`
  - unavailable + 임의 kind → hollow ring 으로 렌더링되는 코드 경로가 유지되는지 (source-level audit 로도 충분: `stroke(...)` 라인 한 개와 `fill(...)` 라인 한 개가 모두 존재)
- [ ] **회귀 안전성**: WO-002 의 unavailable hollow ring 거동·`statusDotDiameter`·`statusDotRingStroke` 그대로. opacity (`session.available ? 1 : 0.5`) 손대지 말 것.

## Constraints (WO-specific)

- **다른 파일 손대지 말 것**: `App/SessionRecord.swift`, `App/SessionRegistry.swift`, `App/SessionStore.swift`, `App/HookEvent.swift`, `App/HookListener.swift`, `App/WidgetPopoverController.swift`, `App/PopoverContentView.swift`, `App/NotificationOrchestrator.swift`, `App/SettingsStore.swift`, `App/SettingsView.swift`, `App/FloatingWidgetWindowController.swift`, `App/WidgetIconView.swift`, `Reporter/*`, `scripts/*`. 빌드를 위해 import/접근이 필요한 read-only 참조는 허용.
- **`DesignTokens.swift` 에 새 컬러 토큰 추가 금지** — 기존 `statusSuccess/Error/Waiting` 사용. 매핑 헬퍼 한 개만 허용 (필요한 경우).
- **레이아웃·접근성·click handler·missing animation 거동 손대지 말 것**.
- **`pinned`, `justArrived`, `aging`, ripple, sonar, breathe, ring, roam, mute, popover gear, empty state 추가 금지** — 모두 별도 WO.
- 함수 시그니처·기본 인자·docstring 변경은 본 Deliverables 가 명시적으로 요구하는 경우에만.
- 무관 리팩터·rename·import 정렬·formatting 금지.

## Verification

- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` 성공.
- 단위 테스트: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` 모두 통과. 환경 이슈 시 `CI=1 xcrun xctest …` direct fallback 허용 (이전 WO 들에서 동일 환경 deviation 기록됨).
- 수동 검증 (가능 시):
  1. 디버거나 임시 fixture 로 `kind == .error` row 1개 → 빨간 dot 으로 보이는지
  2. `kind == .waiting` row → 앰버 dot
  3. `available == false` 인 row → hollow ring (색은 kind 색으로 stroke)
  4. 기존 `.success` row 들의 색이 그대로 (회귀 없음)
- 커밋: WO-005 단위로 atomic commit. 권장 message: `feat(WO-005): status dot color branching by AlertKind`.
- RESULT 문서: `.workorders/005-RESULT.md` — `## Summary` / `## Verification` / `## Deviations`.

## Out of scope

- 신규 ColorToken 추가 / 기존 토큰 색 변경
- aging desaturation (60분+ 행)
- just-arrived ripple, sonar wave, breathe, ring, roam, drift
- Mute / pin / right-click context menu (별도 WO)
- Quiet Hours, Reduce Motion 추가 정책
- Reporter / hook payload / SessionRecord / SessionRegistry / SessionStore / HookEvent / HookListener 변경
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

