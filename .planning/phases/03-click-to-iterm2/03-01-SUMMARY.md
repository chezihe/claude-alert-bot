---
phase: 03-click-to-iterm2
plan: 01
subsystem: contracts (D-ADAPTER + D3-01 + T-INJECTION-01)
tags: [phase-3, wave-1, contracts, d-adapter, d3-01, d3-02, t-injection-01]
requires:
  - 03-00 MockTerminalJumper compile-gated stub
  - App/SessionRecord.swift CompletedSession (Phase 2)
  - App/ProjectName.swift (pattern source for iTermSessionID)
provides:
  - protocol TerminalJumper (D-ADAPTER seam)
  - enum JumpResult (6 cases — covers row-click + testConnection paths)
  - enum iTermSessionID with uuid(fromRaw:) + isValid(_:)
  - Activated MockTerminalJumper test fixture (: TerminalJumper conformance)
affects:
  - Plans 03-02 / 03-03 / 03-04 / 03-05 / 03-07 / 03-08 (all import these contract types)
tech-stack:
  added: []
  patterns:
    - "ProjectName-style enum-of-static-funcs (Foundation-only namespace)"
    - "@MainActor protocol with single async method (mirrors NotifierProtocol pattern)"
    - "Compile-gated test stub → Wave 1 activation (mirrors Phase 2 02-00 → 02-06)"
key-files:
  created:
    - App/TerminalJumper.swift
    - App/iTermSessionID.swift
    - ClaudeAlertBotTests/iTermSessionIDTests.swift
  modified:
    - ClaudeAlertBotTests/Fixtures/MockTerminalJumper.swift
decisions:
  - "Lower-case iTermSessionID (matches iTerm2.app casing convention; iterm_session_id JSON, ITERM_SESSION_ID env var)"
  - "firstIndex(of: ':') over lastIndex — RESEARCH Pattern 5 + PATTERNS §iTermSessionID locked; safer for hypothetical deeper-prefixed envelopes"
  - "ONE JumpResult enum (not separate ConnectionTestResult) — covers both row-click (D3-06) and testConnection (D3-19) paths via iTermNotRunning + permissionDenied cases"
  - "@MainActor on protocol (mirrors NotifierProtocol) — call site (WidgetPopoverController in 03-07) becomes plain await without trampoline ceremony"
  - "Foundation UUID(uuidString:) is the source of truth for T-INJECTION-01 whitelist — no regex re-implementation"
metrics:
  duration_min: ~3
  tasks_completed: 3
  files_created: 3
  files_modified: 1
  commits: 3
  tests_added: 8
  completed: 2026-05-08
---

# Phase 3 Plan 01: Wave 1 Contracts (TerminalJumper + iTermSessionID) Summary

D-ADAPTER 프로토콜 seam과 T-INJECTION-01 화이트리스트 게이트를 도입하는 Wave 1 contracts 플랜.
3개 태스크 모두 자동 실행되어 빌드/테스트 모두 그린이며 STATE/ROADMAP 변경은 없다(orchestrator 소관).

## What Shipped

### `App/TerminalJumper.swift` (33 lines)
- `enum JumpResult: Equatable` — 6개 케이스 (`ok / missing / permissionDenied / iTermNotRunning / timeout / otherError(Int)`).
- `@MainActor protocol TerminalJumper: AnyObject` — 단일 async 메서드 `jump(to: CompletedSession) -> JumpResult`.
- 구현은 없음 (의도). 03-05의 `ITerm2Jumper`가 유일한 v1 conformer.

### `App/iTermSessionID.swift` (40 lines)
- `static func uuid(fromRaw: String?) -> String?` — `wXtYpZ:UUID` envelope을 UUID-only로 strip. nil/empty → nil, colon 없는 입력은 그대로 (idempotent).
- `static func isValid(_: String) -> Bool` — `UUID(uuidString:) != nil`을 화이트리스트로 사용.
- Foundation-only (AppKit/SwiftUI import 0).

### `ClaudeAlertBotTests/iTermSessionIDTests.swift` (8 test methods)
- 추출자 매트릭스 6개: stripsEnvelopePrefix / passesThroughUUIDOnly / handlesNil / handlesEmpty / handlesColonOnly / handlesEmptyAfterColon.
- validator 매트릭스 2개: acceptsCanonicalUUID / rejectsAppleScriptInjectionAttempt (4 sub-asserts).
- ProjectNameTests 패턴 그대로 — 메서드 1개당 분기 1개.

> Note: 플랜 frontmatter는 "5-case + 2 isValid" = 7 tests로 표기했으나 PATTERNS의 표는 6개 추출 케이스를 기재 — 표 기준으로 6+2=8 메서드를 작성함. 모두 통과.

### `ClaudeAlertBotTests/Fixtures/MockTerminalJumper.swift` (모디파이)
- Wave 0의 `#if false` / `#endif` 컴파일 게이트 제거.
- 클래스 선언에 `: TerminalJumper` conformance 추가.
- 헤더 코멘트도 history 형태로 정리(`#if false` 토큰을 본문에서 제거하여 verification grep 0건 충족).
- 메서드 시그니처는 03-00에서 이미 protocol과 일치 — 추가 수정 없음.

## Decisions (Locks)

1. **lower-case `iTermSessionID`** — `iTerm2.app` 케이싱과 `iterm_session_id` JSON 필드, `ITERM_SESSION_ID` env var 컨벤션과 일치. PATTERNS §iTermSessionID 락.
2. **`firstIndex(of: ":")`** — RESEARCH Pattern 5 + PATTERNS §iTermSessionID 합의. CONTEXT 예시의 `lastIndex`는 illustrative였고, 더 깊게 prefix가 추가될 가능성에 대비해 가장 바깥 prefix만 strip하는 first-index가 안전.
3. **단일 `JumpResult` enum** — row-click(D3-06)과 testConnection(D3-19) 양쪽이 같은 6 케이스 surface 공유. 별도 `ConnectionTestResult`를 만들지 않음. `iTermNotRunning` + `permissionDenied` 케이스로 두 경로를 모두 표현.
4. **`@MainActor` on protocol** — NotifierProtocol 패턴 미러. 호출 사이트(WidgetPopoverController, 03-07)가 `@MainActor`라 actor hopping 없이 plain `await` 사용 가능.
5. **Foundation UUID parser as the whitelist** — T-INJECTION-01 게이트는 자체 정규식 구현 없이 `UUID(uuidString:)`에 위임. OS가 거부하는 모든 문자/형식을 거부하므로 AppleScript injection 표면이 zero.

## xcodegen Run

`project.yml`은 `path: App` 재귀 규칙으로 신규 파일을 자동 발견하므로 source list 수정은 필요 없었다. 다만 빌드 안정성을 위해 각 신규 파일 추가 후 `xcodegen` 1회씩 실행해 `ClaudeAlertBot.xcodeproj/project.pbxproj`를 동기화했고, 그 변경분도 같은 task 커밋에 포함되었다.

## Threats Mitigated

| Threat ID | Mitigation Implemented |
|-----------|------------------------|
| T-INJECTION-01 | `iTermSessionID.isValid(_:)` ships with Foundation `UUID(uuidString:)` whitelist; AppleScript-grammar character that would survive substitution is impossible. Test `test_isValid_rejectsAppleScriptInjectionAttempt`로 회귀 잠금. |
| T-NORMALIZE-01 | `uuid(fromRaw:)`가 idempotent — colonless 입력 그대로 반환. `test_uuid_passesThroughUUIDOnly`로 검증. 03-03의 in-memory migration 재실행 시에도 no-op. |

## Deviations from Plan

**1. [Rule 1 - Editorial] MockTerminalJumper 헤더 코멘트의 `#if false` 토큰 제거**
- **Found during:** Task 3 verification (`grep -c '#if false' ... expects 0`).
- **Issue:** 가드를 제거했음에도 헤더 코멘트가 `\`#if false\`` 백틱 토큰을 본문 텍스트로 포함해 grep 카운트가 2로 나옴.
- **Fix:** Wave-0/Wave-1 트랜지션 history만 간략히 남기고 `#if false` 토큰을 코멘트에서 제거. 의미는 보존 — 같은 패턴(02-00 → 02-06)을 한 줄로 언급.
- **Files modified:** `ClaudeAlertBotTests/Fixtures/MockTerminalJumper.swift`
- **Commit:** `b9b53ce`

**2. [Plan-spec note] iTermSessionIDTests 테스트 메서드 8개 (plan은 7개로 표기)**
- **Note:** 플랜 frontmatter의 "5-case test matrix" 텍스트와 본문 표(6 cases)가 충돌 — 본문 표 기준 6 + 2 = 8 메서드를 작성. PATTERNS.md §iTermSessionIDTests의 의도와 일치하며, 매트릭스 커버리지가 더 두꺼워질 뿐 회귀 위험은 없음. 추가 케이스(`handlesEmptyAfterColon`)도 모두 통과.

이외 deviation 없음 — 플랜 그대로 실행.

## Auth Gates

해당 없음.

## Verification Snapshot

| Check | Result |
|-------|--------|
| `xcodebuild build -scheme ClaudeAlertBot` | BUILD SUCCEEDED |
| `xcodebuild test -only-testing:.../iTermSessionIDTests` | 8 tests, 0 failures |
| `xcodebuild test` (full suite) | All tests passed (ProjectNameTests / SessionGCTimerTests / SessionRecordTests / SessionRegistryTests / SessionStoreTests / SettingsViewTests / SoundPlayerTests / iTermSessionIDTests) |
| `grep -cE '^\\s+case [a-z]' App/TerminalJumper.swift` | 6 (JumpResult 케이스) |
| `grep -c '@MainActor' App/TerminalJumper.swift` | 1 |
| `grep -c '#if false' .../MockTerminalJumper.swift` | 0 |
| `grep -cE '^final class.*: TerminalJumper' .../MockTerminalJumper.swift` | 1 |
| `grep -cE 'import AppKit\|import SwiftUI' App/iTermSessionID.swift` | 0 |

## Commit Trail

| Task | Type | Commit | Description |
|------|------|--------|-------------|
| 1 | feat | `0aaf7ec` | TerminalJumper protocol + JumpResult enum (D-ADAPTER seam) |
| 2 | feat | `dd95f38` | iTermSessionID.uuid(fromRaw:) + .isValid(_:) (D3-01 + T-INJECTION-01) |
| 3 | test | `b9b53ce` | iTermSessionIDTests (8) + activate MockTerminalJumper conformance |

## Self-Check: PASSED

- `App/TerminalJumper.swift` — exists.
- `App/iTermSessionID.swift` — exists.
- `ClaudeAlertBotTests/iTermSessionIDTests.swift` — exists.
- `ClaudeAlertBotTests/Fixtures/MockTerminalJumper.swift` — modified (compile gate removed, conformance added).
- Commits `0aaf7ec`, `dd95f38`, `b9b53ce` — all present in `git log`.
- Build green, full test suite green.
