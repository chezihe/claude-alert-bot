---
phase: 03-click-to-iterm2
plan: 06
subsystem: PopoverRowView state machine + missing animation (D3-11/12/14)
tags: [phase-3, wave-4, d3-11, d3-12, d3-14, animation, jump-05]
requires:
  - 03-01 contracts (TerminalJumper, JumpResult — referenced in callback wiring docstring)
  - Phase 2 02-08 PopoverRowView/PopoverContentView (extend in place; CLAUDE.md "minimum modification")
  - Phase 2 FloatingWidgetWindowController.swift lines 113-115 (reduced-motion pattern source)
provides:
  - file-scope `enum RowState { case normal, jumping, missing }` (Equatable)
  - PopoverRowView `state: RowState` parameter (default .normal)
  - PopoverRowView `onMissingComplete: () -> Void` parameter (default no-op)
  - Two-phase missing animation (도리도리 ±12° 0..0.3s + collapse/fade 0.3..0.7s)
  - Reduced-motion fallback (skip rotation, immediate easeInOut(0.2) collapse)
  - PopoverContentView `rowStates: [String: RowState]` and `onRowMissingComplete: (String) -> Void` props
  - PopoverRowStateTests (3 cases — case identity + 2 source-level audits)
affects:
  - Plan 03-07 (WidgetPopoverController must publish rowStates + dispatch onRowMissingComplete → SessionRegistry.clearOne)
  - Plan 03-09 (manual checkpoint exercises the full 도리도리+collapse path live in iTerm2)
tech-stack:
  added: []
  patterns:
    - "SwiftUI two-phase animation via withAnimation(_:completionCriteria:) + DispatchQueue.main.asyncAfter chain (RESEARCH Pattern 3)"
    - "Reduced-motion guard via NSWorkspace.accessibilityDisplayShouldReduceMotion (Phase 2 FloatingWidgetWindowController parity)"
    - "Source-string-audit unit tests (#filePath relative resolution) — pragmatic alternative to UI test target for SwiftUI internals"
    - "State-down per PATTERNS Option C — `[String: RowState] rowStates` map in container, `let state: RowState` in row"
key-files:
  created:
    - ClaudeAlertBotTests/PopoverRowStateTests.swift
  modified:
    - App/PopoverRowView.swift
    - App/PopoverContentView.swift
    - ClaudeAlertBotTests/PopoverContentTests.swift
    - ClaudeAlertBot.xcodeproj/project.pbxproj
decisions:
  - "RowState lives at FILE scope in PopoverRowView.swift (not nested) — keeps `RowState` referenceable as a plain unqualified type from PopoverContentView and tests, mirrors how Phase 2 enums live."
  - "`state` and `onMissingComplete` carry default values — keeps the WidgetPopoverController call site (Phase 2 02-08, untouched here) compiling until 03-07 wires actual state. Aligns with CLAUDE.md `minimum modification`."
  - "Used `withAnimation(_:completionCriteria:_:completion:)` (macOS 14+) with explicit `.logicallyComplete` over the omitted-criteria overload — Plan 03-06 §Step 4 flagged this as the safer compiler path, and the explicit form documents intent."
  - "Dropped `unavailableSessionIDs` prop + `PopoverContentRules.isUnavailable` + `unavailableLabelText` outright (not just deprecated). D3-12 mandates animation IS the message — the `Session unavailable` Phase 2 placeholder is not just unused, it is forbidden copy now. Three matching tests in `PopoverContentTests` were removed in lockstep."
  - "Did NOT introduce a Stop hook for animation cancellation. RowState transitions are monotonic in the 03-07 wiring (`.normal → .jumping → .normal|.missing`). If a future plan needs to cancel mid-animation, add an explicit `case cancelled` rather than rewinding."
  - "Source-string-audit tests over UI tests: documented inline as a deferred trade-off. UI test target adds bundle-product complexity disproportionate to the asserted invariants (one `guard` line + one method-body call count). 03-07 will add behavioural coverage at the controller level."
metrics:
  duration_min: ~6
  tasks_completed: 3
  files_created: 1
  files_modified: 4
  commits: 3
  tests_added: 3
  tests_removed: 3   # PopoverContentTests dead-code companion removals
  completed: 2026-05-09
---

# Phase 3 Plan 06: PopoverRowView 상태머신 + 사라짐 애니메이션 요약

CONTEXT D3-11/D3-12/D3-14을 구현해 PopoverRowView를 leaf 상태머신으로 승격하고, "세션 없음"
응답을 텍스트 없이 도리도리 + collapse 애니메이션으로 완성한 Wave 4 단일-파일-범위 플랜이다.
3개 태스크 모두 자동 실행되어 `xcodebuild test`가 103 tests / 0 failures로 그린이다.
STATE/ROADMAP 변경은 없다(orchestrator 소관).

## 완료된 태스크

| Task | 이름 | 커밋 | 핵심 파일 |
|------|------|------|----------|
| 1 | RowState enum + missing 애니메이션 (PopoverRowView) | 6022e05 | App/PopoverRowView.swift, App/PopoverContentView.swift |
| 2 | rowStates / onRowMissingComplete 와이어링 + dead-code 제거 | fe0eb17 | App/PopoverContentView.swift, ClaudeAlertBotTests/PopoverContentTests.swift |
| 3 | PopoverRowStateTests (D3-14 회귀 가드) | 2b1ae61 | ClaudeAlertBotTests/PopoverRowStateTests.swift, ClaudeAlertBot.xcodeproj/project.pbxproj |

## 결정 사항

### RowState enum의 위치 — file scope

`enum RowState`을 PopoverRowView.swift 파일 최상단(struct 선언 위)에 두고 nested 하지 않았다.
근거:
- PopoverContentView가 `rowStates[session.sessionID, default: .normal]`로 직접 참조한다 →
  중첩 enum이면 `PopoverRowView.RowState`로 적어야 해 가독성이 떨어진다.
- 03-07에서 WidgetPopoverController도 직접 참조 예정 — 같은 이유.
- Phase 2의 다른 enum(예: `JumpResult`)도 file scope에 있어 일관성 확보.

### 기본값 전략 — 03-07 합류 전까지 호환

- `state: RowState = .normal`
- `onMissingComplete: () -> Void = {}`
- `rowStates: [String: RowState] = [:]`
- `onRowMissingComplete: (String) -> Void = { _ in }`

WidgetPopoverController(`App/WidgetPopoverController.swift:54`)가 Phase 2에서 만들어진
`PopoverContentView(queue:onRowClick:onClearAll:)` 시그니처를 그대로 유지한 채 빌드된다.
03-07에서 두 인자를 추가로 전달하면 자동 활성화. CLAUDE.md "minimum modification" 원칙 준수.

### Dead-code 제거 목록

Phase 2 D3 placeholder였던 다음 심볼들이 production code에서 완전히 사라졌다:

| 심볼 | 위치 | 제거 사유 |
|------|------|----------|
| `var isAvailable: Bool = true` | App/PopoverRowView.swift | RowState `.missing`이 의미 흡수 |
| `var unavailableSessionIDs: Set<String>` | App/PopoverContentView.swift | RowState 맵으로 대체 |
| `static let unavailableLabelText = "Session unavailable"` | App/PopoverContentView.swift (PopoverContentRules) | D3-12: 텍스트 라벨 금지 |
| `static func isUnavailable(sessionID:in:)` | App/PopoverContentView.swift (PopoverContentRules) | 호출자 0 |
| `test_isUnavailable_membershipCheck` | ClaudeAlertBotTests/PopoverContentTests.swift | 대상 심볼 삭제 |
| `test_isUnavailable_emptySet_neverUnavailable` | 같음 | 대상 심볼 삭제 |
| `test_unavailableLabelText_minimalEnglishCopy_locked` | 같음 | D3-12 정책상 카피 자체 금지 |

`grep -rc 'unavailableLabelText\|unavailableSessionIDs\|isUnavailable\b' App/`은 모두 0.
PopoverContentTests에 남아있는 4개 매치는 historical 주석(왜 삭제됐는지 future reader 안내)이라
production 코드 영향 없음.

## 트레이드오프 — 단위 테스트 범위

CONTEXT D3-14에 명시: "애니메이션 시각 자체는 단위 테스트 안 함; state 전이 + clearOne 호출 +
OSLog 시그니처만 검증." 본 플랜은 **상태 대수**(RowState 케이스 동등성)와 **소스 레벨 invariant**
두 부분만 단위 테스트로 잠갔다:

1. `test_RowState_caseIdentity` — `.normal != .jumping != .missing` (3 cases brittle-by-design).
2. `test_clickHandler_isNoOpInJumpingState` — `App/PopoverRowView.swift`을 `#filePath` 기반으로 읽어
   `guard state == .normal else { return }` 라인 존재 검증.
3. `test_missingAnimation_callsOnMissingCompleteCallback` — 같은 소스에서 `onMissingComplete()`
   호출이 ≥2개임을 검증(reduce-motion 분기 + full-animation 분기).

**소스-스트링 단위 테스트는 일반적이지 않은 패턴**이지만, ViewInspector 의존을 회피하고(Phase 2
D2-29에서 거부됨) UI 테스트 타겟을 새로 도입할 만큼의 가치가 없는 invariant라 판단했다.
실제 SwiftUI 렌더링 동작은 03-07의 WidgetPopoverController 통합 테스트와 03-09 매뉴얼
체크포인트에서 라이브로 확인된다.

## 검증 결과

| 게이트 | 기대값 | 실제값 |
|--------|--------|--------|
| `grep -c 'enum RowState' App/PopoverRowView.swift` | 1 | 1 |
| `grep -c 'guard state == .normal' App/PopoverRowView.swift` | 1 | 1 |
| `grep -c 'accessibilityDisplayShouldReduceMotion' App/PopoverRowView.swift` | 1 | 1 |
| `grep -c 'onMissingComplete()' App/PopoverRowView.swift` | ≥2 | 3 |
| `grep -rc 'unavailableLabelText' App/` | 0 (모든 파일) | 0 |
| `xcodebuild build -scheme ClaudeAlertBot` | BUILD SUCCEEDED | ✓ |
| `xcodebuild test` 전체 | TEST SUCCEEDED | ✓ (103 tests, 0 failures) |
| `xcodebuild test -only-testing:.../PopoverRowStateTests` | passed | ✓ (3/3 in 0.007s) |

## 후속 플랜 의존성

- **03-07** — WidgetPopoverController가 jump 결과별로 `rowStates[sessionID] = .jumping` →
  성공 시 `clearOne` 직접 호출 / 실패 시 `.missing`으로 전이 → 콜백 도착 시 `clearOne` 호출.
  본 플랜에서 도입한 4개 prop의 default value가 그때까지 호환을 유지한다.
- **03-09** — 매뉴얼 체크포인트에서 도리도리 ±12° 1왕복 + 큐가 비면 popover 자동 dismiss 검증.
- (선택) **03-08** — OSLog `[jumped session=...]` / `[jump-missed session=...]` 시그니처
  회귀 가드(D3-13). 본 플랜 범위 밖.

## 변경/추가 통계

- 변경 파일: 4 (PopoverRowView.swift, PopoverContentView.swift, PopoverContentTests.swift, project.pbxproj)
- 신규 파일: 1 (PopoverRowStateTests.swift, 72 lines)
- 추가 라인: ~75
- 제거 라인: ~50 (dead code + 3 deprecated tests)
- 신규 테스트: 3, 제거 테스트: 3 (테스트 수 100 → 103, 모두 그린)

## 알려진 스텁 / 위협 플래그

알려진 스텁 없음. 위협 플래그 없음. (T-A11Y-01 mitigation은 reduced-motion 분기로 본 플랜에서
적용 완료.)

## Self-Check: PASSED

- [x] App/PopoverRowView.swift updated with RowState enum + animation
- [x] App/PopoverContentView.swift updated with rowStates / onRowMissingComplete props
- [x] ClaudeAlertBotTests/PopoverRowStateTests.swift exists
- [x] ClaudeAlertBot.xcodeproj/project.pbxproj registers the new test file
- [x] commits 6022e05, fe0eb17, 2b1ae61 in `git log`
- [x] xcodebuild test green (103 tests / 0 failures)
- [x] all 7 verification gates pass

---

*Phase: 3 / Plan: 06 — Wave 4 (PopoverRowView 상태머신 + missing 애니메이션)*
*Completed: 2026-05-09*
