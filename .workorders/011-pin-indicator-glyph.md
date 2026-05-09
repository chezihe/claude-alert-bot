# WO-011: Pin visual indicator on popover row

## Goal
WO-006 에서 `pinned` 데이터·정렬·persistence 가 들어왔지만 **핀된 row 가 시각적으로 구분되지 않는다** — 사용자가 우클릭으로 핀해도 효과를 인지할 수 없음. 이번 WO 는 `PopoverRowView` 에 작은 핀 글리프 한 개를 추가해 핀 상태를 한눈에 보이게 한다. 다른 시각 변경은 OUT.

## Context

(현재 상태)
- `CompletedSession.pinned: Bool` 존재 (WO-006). 정렬·Clear All 보존도 작동.
- 핀해도 row 가 다른 row 와 시각적으로 동일 → 사용자 혼란.
- macOS Notes / Mail 의 핀 상태 시각 컨벤션: 작은 `pin.fill` SF Symbol, secondary label color, 보통 행 trailing 영역에 배치.

(현재 코드 — `App/PopoverRowView.swift` body HStack 발췌)
```swift
HStack(spacing: 8) {
    statusDot
    Text(session.projectName)
        .font(.system(size: 13))
        .foregroundStyle(state == .jumping ? .tertiary : .primary)
        .lineLimit(1)
        .truncationMode(.tail)
        .rotationEffect(.degrees(rotation))
    Spacer()
    if showTimeSuffix { Text("· …") }
    if PopoverContentRules.showsOrphanIndicator(…) { Text("?") }
}
```

(시각 가이드)
- SF Symbol `pin.fill`, 11pt, **45° 회전** (전통적인 책상 핀 모양 — Notes·Mail 의 canonical 표현).
- 색: `Color(NSColor.secondaryLabelColor)` — 새 ColorToken 추가 금지.
- 위치: `Text(session.projectName)` 직후, `Spacer()` 직전. (시간 suffix / orphan `?` 보다 앞 — 핀 상태가 행 정체성에 더 가깝다.)
- `session.pinned == false` 일 때 완전 미렌더 (공간도 차지하지 않음).

(BACKLOG 영향)
- BACKLOG 에는 별도 핀 시각 항목이 없음. WO-006 의 후속 폴리시 WO. 종료 후 Step 4 의 핀 항목을 "핀 상태가 ordering + Clear All 보존 + **시각 표식**으로 완결" 한 줄로 보강.

(Prototype v2 / SPEC.md)
- `Claude Alert Bot - Prototype v2.html` — 컨텍스트 메뉴 외에 핀 row 시각 정의 없음. 시스템 컨벤션 따른다.
- `SPEC.md` §3 row — pinned 시각 명시적 토큰 없음. 새 토큰 추가하지 않고 system semantic 색만 사용.

(AGENTS.md — binding)
- Code Change Discipline: 최소 변경.
- UI Copy: 영어 미니멀, 이모지·컬러 dot 금지 (이번엔 카피 변경 없음).
- macOS 14 타깃, Swift 5.10+, no Sandbox, zero external Swift dependencies.

(스코프 명확화 — IN / OUT)
- **IN**: `PopoverRowView` 에 핀 글리프 1개 conditional 렌더 + accessibility label 한 줄 + 단위 테스트.
- **OUT**: 새 ColorToken / GeometryToken, row height / layout 재배치, status dot·텍스트·time suffix·orphan 표식 변경, WO-006 의 정렬·Clear All 로직, 다른 파일.

## Inputs

분석/수정 대상:
- `App/PopoverRowView.swift` — body HStack 안에 `pinIndicator` 한 개 conditional view 추가. 다른 element (statusDot, projectName Text, Spacer, time suffix, orphan `?`, hover bg, opacity, missing animation, contextMenu) 손대지 말 것.
- 테스트:
  - `ClaudeAlertBotTests/PopoverRowStateTests.swift` (또는 신규 `PopoverRowPinTests.swift`) — source-level audit 패턴 (`readPopoverRowViewSource()` 헬퍼 활용):
    - `pin.fill` symbol name 이 source 에 존재
    - `session.pinned` conditional 로 게이팅 됨 (예: `if session.pinned` 또는 동등한 표현이 indicator 근처)
    - accessibility label 한 줄 존재 (예: `accessibilityLabel("Pinned")`)
  - WO-005 의 `kind → color` 매핑 테스트 패턴과 동일 스타일.

읽어볼 것 (수정 X):
- `AGENTS.md`, `SPEC.md` §3, `Claude Alert Bot - Prototype v2.html`.
- `App/SessionRecord.swift` — `pinned` 필드 확인.
- `App/DesignTokens.swift` — 기존 토큰 사용 가능한지 확인 (새 토큰 추가 금지).

## Deliverables

- [ ] **`pinIndicator` view (또는 inline `if`)** — `session.pinned == true` 일 때만 렌더. 구체:
  ```swift
  if session.pinned {
      Image(systemName: "pin.fill")
          .font(.system(size: 11))
          .rotationEffect(.degrees(45))
          .foregroundStyle(Color(NSColor.secondaryLabelColor))
          .accessibilityLabel("Pinned")
  }
  ```
  배치: HStack 안에서 `Text(session.projectName)` 다음, `Spacer()` 이전.
- [ ] **회귀 안전성**: `session.pinned == false` 일 때 row layout / 높이 / hover bg / status dot kind 색 (WO-005) / unavailable hollow ring (WO-002) / missing animation 거동 모두 동일. opacity 식 (`session.available ? 1 : 0.5`) 손대지 말 것.
- [ ] **테스트 추가** (3 케이스):
  - source 에 `pin.fill` 문자열 존재
  - source 에 `session.pinned` conditional 가 indicator 인접 (예: 같은 라인 근처 5 줄 이내) — 정확한 검사는 Codex 재량
  - source 에 `accessibilityLabel("Pinned")` 또는 그에 준하는 a11y 라벨 존재

## Constraints (WO-specific)

- **다른 파일 손대지 말 것**: `App/SessionRecord.swift`, `App/SessionRegistry.swift`, `App/SessionStore.swift`, `App/SettingsStore.swift`, `App/SettingsView.swift`, `App/PopoverContentView.swift`, `App/WidgetPopoverController.swift`, `App/DesignTokens.swift`, `App/HookEvent.swift`, `App/HookListener.swift`, `App/NotificationOrchestrator.swift`, `App/FloatingWidgetWindowController.swift`, `App/WidgetIconView.swift`, `Reporter/*`, `scripts/*`. 빌드를 위해 read-only 참조는 허용.
- **DesignTokens 새 토큰 추가 금지** — `Color(NSColor.secondaryLabelColor)` 직접 사용. font size 11 inline 허용 (이미 row 안 다른 텍스트들이 inline 11/13 식으로 쓰고 있음).
- **글리프·회전·크기 변경 금지**: SF Symbol `pin.fill`, 11pt, 45° 회전 고정.
- **위치 변경 금지**: `Text(projectName)` 다음, `Spacer()` 이전.
- **row layout / 높이 / hover bg / opacity / status dot / time suffix / orphan / contextMenu / click handler / missing animation 손대지 말 것**.
- **`justArrived`, ripple, aging, sonar, breathe, ring, roam, drift 추가 금지** — 별도 WO.
- **카피 변경 금지** — 컨텍스트 메뉴 라벨 (WO-006) 그대로.
- 함수 시그니처·기본 인자·docstring 변경은 본 Deliverables 가 명시적으로 요구하는 경우에만.
- 무관 리팩터·rename·import 정렬·formatting 금지.

## Verification

- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` 성공.
- 단위 테스트: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` 모두 통과 (release 앱 종료 후. 환경 이슈 시 `CI=1 xcrun xctest …` fallback).
- 수동 검증 (가능 시):
  1. row 우클릭 → "Pin" → 해당 row 의 projectName 우측에 작은 회전된 핀 글리프 등장
  2. "Unpin" → 글리프 사라짐, row 가 정렬 변경 (pinned 그룹에서 빠짐)
  3. unavailable / error / waiting kind row 도 핀하면 동일하게 글리프 표시 (kind 색·hollow ring 유지)
  4. 회귀 없음: 핀 안 한 row 들의 layout / 높이 / hover 동작 그대로
- 커밋: WO-011 단위로 atomic commit. 권장 메시지: `feat(WO-011): pin indicator glyph on popover row`.
- RESULT 문서: `.workorders/011-RESULT.md` — `## Summary` / `## Verification` / `## Deviations`.

## Out of scope

- 새 ColorToken / GeometryToken 추가
- 핀 row 의 background tint, border, font weight 변경
- 핀 글리프의 글리프·크기·회전·위치 변경
- 핀 hover 툴팁
- 핀 상태에 따른 row click 동작 분기
- justArrived ripple, aging desaturation, sonar, breathe, ring, roam, drift
- WO-006 정렬·Clear All·context menu 라벨·persistence 변경
- Settings 화면의 핀 목록 / 영구 핀 옵션
- Quiet Hours, Reduce Motion 정책
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

