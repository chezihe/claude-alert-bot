# WO-002: Unavailable row rendering + status dot scaffolding + hover token fix

## Goal
`PopoverRowView` 가 SPEC §3 의 status dot 토큰을 그리고, iTerm 세션이 사라진 행은 **삭제하지 않고** 50% opacity + hollow ring 으로 표시되게 한다. 동시에 row hover 색상을 SPEC 토큰으로 정정한다.

## Context

(WO-001 BACKLOG.md 발췌 — 이번 WO가 닫는 항목)
- Step 1: `[TODO] Popover footer gear icon` — **이번 WO 범위 아님**
- Step 3: `[PARTIAL] Missing iTerm session handling clears the row — 'WidgetPopoverController.swift'. SPEC asks to keep it unavailable with 50% opacity and a hollow status dot.`
- Step 4: `[TODO] Status dots for success/error/waiting/unavailable are missing.`
- Step 4: `[PARTIAL] Row hover exists but does not use the SPEC hover token — 'PopoverRowView.swift'. It uses 'controlAccentColor.opacity(0.12)', not the rgba accent hover values.`

(SPEC.md 인라인 — Codex가 SPEC.md 못 읽을 때 fallback)

§2 Row click → focus session: "If session no longer exists, mark row `unavailable` (50% opacity, hollow status dot)"

§3 Visual Tokens (관련 부분만):
| Token | Light | Dark |
|---|---|---|
| Status: success | `#D97757` | `#D97757` |
| Status: error | `#E5484D` | `#E5484D` |
| Status: waiting | `#F5A623` | `#F5A623` |
| Row hover | `rgba(217,119,87,0.13)` | `rgba(217,119,87,0.20)` |

Geometry:
- Status dot: **7pt diameter**; hollow ring stroke **1.5pt**
- Row: 36pt min height, 12pt horizontal padding, 8pt vertical padding

§5 State Model (관련 필드):
```swift
struct Session {
    // ...
    let kind: AlertKind                // .success | .error | .waiting
    var available: Bool                // false = iTerm session gone
    // ...
}
enum AlertKind: String, Codable { case success, error, waiting }
```

**중요한 스코프 결정**: hook payload 가 현재 `kind` 를 보내지 않는다 (BACKLOG Step 3 [PARTIAL]). 이번 WO 에서는 **`AlertKind` enum 을 도입하지 않으며**, 모든 status dot 을 일단 **success 색상(`#D97757`) 단일** 로 그린다. kind 분기 색상은 hook payload 확장 WO 이후 별도 WO 에서 다룬다.

## Inputs

분석/수정 대상:
- `App/SessionRecord.swift` — `available: Bool` 필드 추가 (이미 존재하면 그대로 사용)
- `App/SessionRegistry.swift` 또는 `App/SessionStore.swift` — `available` 의 mutate 경로
- `App/WidgetPopoverController.swift` — iTerm 세션 누락 시 row 를 제거하던 경로를 `available=false` 마킹으로 변경
- `App/PopoverRowView.swift` — status dot 렌더링 추가, hover 색상 토큰 교체, opacity 처리
- `App/DesignTokens.swift` — color/geometry 토큰이 이 파일에 모이는 패턴 (BACKLOG 에서 확인됨). 새 토큰은 여기에 추가
- (필요시) `App/PopoverContentView.swift` — `PopoverRowView` 사용 지점

읽어볼 것 (수정 X):
- `AGENTS.md` — 모든 룰의 출처 (binding)
- `SPEC.md` §2, §3, §5 — 위에 인라인했으나 원문 확인 권장

## Deliverables

- [ ] **모델**: `SessionRecord` (혹은 `CompletedSession`) 에 `available: Bool` 필드 추가. 기본값 `true`. `Codable` 호환을 위해 디코딩 시 누락된 기존 데이터는 `true` 로 폴백 (e.g. `decodeIfPresent(...) ?? true`)
- [ ] **iTerm missing 처리**: 세션 jump 시 iTerm UUID 가 더 이상 존재하지 않으면 row 를 제거하지 않고 `available = false` 로 표시. 사용자 행동(click/clear)이 없으면 row 는 popover 에 남아있어야 함
- [ ] **Status dot 컴포넌트**: `PopoverRowView` 에 7pt × 7pt 원형 dot 을 row 좌측에 추가. 현재는 success 색상 `#D97757` 단일
- [ ] **Hollow ring 변형**: `available == false` 일 때 dot 은 fill 없이 stroke 1.5pt 의 hollow ring 으로 렌더 (색상은 동일 `#D97757`, fill 만 비움)
- [ ] **Row opacity**: `available == false` 일 때 row 전체 (텍스트·dot·dismiss 등 자식 모두) 의 alpha 를 `0.5` 로
- [ ] **Hover 토큰**: row hover 배경을 `Color(red: 217/255, green: 119/255, blue: 87/255).opacity(0.13)` (light) / `... opacity(0.20)` (dark) 로 변경. `controlAccentColor.opacity(0.12)` 사용 제거. dark mode 분기는 `@Environment(\.colorScheme)` 또는 `Color(NSColor)` dynamic 사용 — 기존 `DesignTokens` 패턴 따를 것
- [ ] **DesignTokens**: 위 색상·도트 지오메트리(7pt, 1.5pt stroke)를 `DesignTokens.swift` 에 토큰으로 추가하고 `PopoverRowView` 가 토큰만 참조하도록 (`#D97757` 같은 raw 색상 리터럴 PopoverRowView 안에 두지 말 것)
- [ ] **테스트**: 가능하면 `SessionRecordTests` (또는 동등한 위치) 에 `available` 디코딩 fallback 테스트 1개 추가 (기존 JSON 에 필드 없을 때 `true` 가 되는지). UI 테스트는 신규 추가 불필요 — Xcode preview 로 시각 확인
- [ ] **Reduce Motion**: 정적 렌더라 영향 없음. 변경 금지

## Constraints

- AGENTS.md 의 모든 룰은 binding. 특히 "Code Change Discipline (No Over-Editing)" 절을 매 hunk 에 적용
- macOS 14 타깃, Swift 5.10+, no Sandbox, ad-hoc 서명, zero external Swift dependencies
- If you cannot read AGENTS.md / SPEC.md, use the inlined Context above as the canonical fallback
- **`AlertKind` enum 도입 금지** — 이번 WO 범위 아님. 모든 dot 은 success 색상 단일
- **mute/pin/context menu/right-click — 일체 손대지 말 것** (다음 WO)
- **Hook payload (`HookEvent.swift`, `Reporter/cab-report.sh`) 손대지 말 것** — 별도 WO
- **Aging desaturation (60분 후 색감 변화), grouping collapse, just-arrived ripple/sonar — 손대지 말 것**
- 함수 시그니처/기본 인자/docstring 변경은 본 Deliverables 가 명시적으로 요구하는 경우에만

## Verification

- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` 성공
- 단위 테스트: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` 모두 통과 (기존 + 신규 `available` 디코딩 fallback)
- 수동 시각 검증:
  1. 일반 row: 7pt 채워진 success dot, hover 시 SPEC 토큰 색상으로 배경 강조
  2. iTerm 세션이 사라진 row: 50% opacity, hollow ring dot, row 가 popover 에서 사라지지 않음
- 커밋: WO-002 단위로 atomic commit, conventional message (예: `feat(WO-002): unavailable row rendering + status dot scaffolding`). 모델 추가 → UI 추가 → hover 토큰 정정 처럼 논리 단위로 나누면 더 좋음

## Output format (Codex 환경에 맞춰 택)

(A) Unified diff 권장 — 변경 파일이 6개 이내로 작음. (B) 또는 (C) 가능. 새 파일 생성은 없을 가능성 큼 (DesignTokens 토큰 추가는 기존 파일 내 추가).

## Out of scope

- `AlertKind` enum 정의·import — **명시적으로 금지**
- 색상 분기 (success/error/waiting) — 다음 WO 에서 hook payload 확장 후
- Right-click menu / mute / pin / unpin — 다음 WO (WO-003 예정)
- Hook payload 확장 (`exit_code`, `kind`, `started_at`, `last_output`) — 별도 WO
- Reporter/cab-report.sh 변경 일체
- Aging desaturation (60분 룰) — Step 6 WO
- Grouping collapse (3+ same-project) — Step 4 별도 WO
- Just-arrived ripple, sonar wave, breathe, ring, roam, drift 등 SPEC §4 의 다른 motion — Step 2 별도 WO
- Popover gear icon, onboarding empty state — Step 1 별도 WO
- `Reporter/`, `CabTest/`, `scripts/`, `ClaudeAlertBotTests/Fixtures/` 무관 변경
