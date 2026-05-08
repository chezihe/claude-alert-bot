---
phase: 03-click-to-iterm2
plan: 04
subsystem: applescript-surface (D3-06 + D3-09 + D3-16 + D3-17 + SET-05 + T-INJECTION-01)
tags: [phase-3, wave-2, d3-06, d3-09, d3-16, d3-17, t-injection-01, set-05]
requires:
  - 03-01 TerminalJumper protocol + JumpResult enum + iTermSessionID.isValid
  - 02-05 AppleScriptHelper actor (compile-once + serial queue + classify pattern)
provides:
  - AppleScriptHelper.runJumpByUUID(_:) async -> JumpResult
  - AppleScriptHelper.testConnection() async -> JumpResult
  - jumpByUUIDTemplate (per-call recompile, T-INJECTION-01-guarded)
  - focusFrontmostSource (compile-once, fully static)
  - DEBUG test seams: jumpRawTemplate / focusFrontmostRawSource / markUnknownForTesting
affects:
  - 03-05 ITerm2Jumper (consumes runJumpByUUID)
  - 03-08 SettingsView SET-05 (consumes testConnection)
tech-stack:
  added: []
  patterns:
    - "Per-call NSAppleScript(source:) recompile + Foundation UUID whitelist (RESEARCH §Pattern 1 Option C)"
    - "Compile-once focus-frontmost mirror of Phase 2 cheap-query pattern"
    - "State mirror after withCheckedContinuation resume — actor-isolated markGranted/markDenied awaits (cleaner than dispatching back from non-actor context)"
key-files:
  created:
    - .planning/phases/03-click-to-iterm2/03-04-SUMMARY.md
  modified:
    - App/AppleScriptHelper.swift
    - ClaudeAlertBotTests/AppleScriptHelperTests.swift
decisions:
  - "scriptResultToJump is a private static func (pure mapping, no actor state) — usable from inside queue.async closures without actor isolation gymnastics"
  - "State mirror sequence: queue.async resume → switch on JumpResult on the actor → await markGranted/markDenied. Same shape applied to runJumpByUUID and runFocusFrontmost"
  - "Three AppleScript surfaces in one actor (cheap-query / jump-by-uuid / focus-frontmost) — keeps NSAppleScript main-thread serialization invariant in one place"
  - "jump-by-uuid uses per-call NSAppleScript(source:) (Option C, locked) — focus-frontmost uses compile-once because input is fully static"
  - ".granted branch of testConnection is integration-only — the unit suite covers .denied short-circuit + whitelist gate; live AppleScript exercise belongs to 03-09 SC checkpoint"
metrics:
  duration_min: ~10
  tasks_completed: 3
  files_created: 1
  files_modified: 2
  commits: 3
  tests_added: 6
  completed: 2026-05-09
---

# Phase 3 Plan 04: AppleScript Helper Extension (jump-by-uuid + testConnection) Summary

Wave 2의 AppleScript 표면 확장 플랜. Phase 2 02-05의 `AppleScriptHelper` actor에 두 개의 새 스크립트(jump-by-uuid 3s timeout, focus-frontmost 3s timeout)와 두 개의 새 actor 메서드(`runJumpByUUID(_:)`, `testConnection()`)를 추가하고, `JumpResult`로의 매핑을 잠갔다. T-INJECTION-01은 `iTermSessionID.isValid` 화이트리스트 게이트 + 03-01 contracts 위에 코드 레벨로 봉인.

3개 태스크 모두 자동 실행 — 빌드/단위 테스트 모두 그린이며 STATE/ROADMAP은 orchestrator 소관(이 플랜에서 변경 없음).

## What Shipped

### `App/AppleScriptHelper.swift` (+157 lines, no signature changes to existing methods)

**Three AppleScript surfaces in one actor** (D3-17 #3 정확히 충족):

| # | 스크립트 | Timeout | Compile policy | Caller |
|---|---|---|---|---|
| 1 | `scriptSource` (기존 cheap-query) | 1s | compile-once `compiled` | `frontmostMatches`, `triggerPermissionPrompt` |
| 2 | `jumpByUUIDTemplate` (신설) | 3s | per-call `NSAppleScript(source:)` (Option C) | `runJumpByUUID` |
| 3 | `focusFrontmostSource` (신설) | 3s | compile-once `compiledFocusFrontmost` | `runFocusFrontmost` (testConnection .granted 분기) |

**`runJumpByUUID(_ uuid: String) async -> JumpResult`** (D3-06):

1. `iTermSessionID.isValid(uuid)` 화이트리스트 게이트 — 실패 시 `.otherError(0)` 즉시 반환 (NSAppleScript 호출 자체를 우회).
2. `String(format: jumpByUUIDTemplate, uuid)` per-call 치환.
3. 전용 `queue.async` 안에서 `NSAppleScript(source:)` → `compileAndReturnError` → `executeAndReturnError` → `classify(error:result:)` → `scriptResultToJump(_:emptyMeans: .missing)`.
4. continuation resume 후 actor 본체에서 `.ok → markGranted()` / `.permissionDenied → markDenied()` 상태 미러 (D2-35/D2-36 인계).

**`testConnection() async -> JumpResult`** (D3-16):

```text
.denied   → .permissionDenied 즉시 반환 (no script execution)
.unknown  → triggerPermissionPrompt() 호출 → .permissionDenied 반환 (이번 누름은 다이얼로그 surface, 다음 누름이 실제 self-test)
.granted  → runFocusFrontmost() 호출
```

**`runFocusFrontmost()`**: cheap-query와 동일한 compile-once + serial queue + state-mirror 패턴. AppleScript가 빈 문자열을 반환하면(`emptyMeans: .iTermNotRunning`) iTerm2 미실행으로 분류, UUID 문자열을 반환하면 `.ok`.

**`scriptResultToJump(_ result: ScriptResult, emptyMeans: JumpResult) -> JumpResult`**: 순수 매핑 함수. `static` 으로 선언 — actor 상태에 손대지 않으니 `queue.async` 클로저 내부에서 isolation hop 없이 호출 가능. `.success("ok")` → `.ok`, `.success("")` → `emptyMeans` (호출자 의도 명시), `.success(non-empty non-"ok")` → `.ok` (focus-frontmost가 UUID 문자열을 반환하는 분기 흡수), `.denied/.timeout/.otherError` → 동명 케이스로 매핑.

### `ClaudeAlertBotTests/AppleScriptHelperTests.swift` (+85 lines, 6 new tests)

| Test | 검증 대상 |
|---|---|
| `test_runJumpByUUID_rejectsNonUUIDInput` | T-INJECTION-01 화이트리스트 게이트 (단순 비-UUID) |
| `test_runJumpByUUID_rejectsAppleScriptInjectionAttempt` | T-INJECTION-01 (실제 AppleScript-grammar 깨기 시도 문자열) |
| `test_jumpByUUIDTemplate_containsAppleScriptTimeout` | JUMP-04 3s 하드 timeout + sdef-검증 매칭 키 |
| `test_focusFrontmostSource_containsAppleScriptTimeout` | SET-05 3s timeout + iTerm2 activate 호출 |
| `test_testConnection_deniedShortCircuits` | D3-16 `.denied` 분기가 NSAppleScript 호출 없이 즉시 반환 |
| `test_d3_04_phase2SilentFailureRegression_postNormalizationContract` | D3-04 (plan-check B2 relocation) — HookListener 정규화 + AppleScript 쿼리 키 + idempotency 3중 invariant |

**테스트 시드** (`#if DEBUG` 블록):

- `static var jumpRawTemplate` — 템플릿 문자열에 대한 raw access (substitution 직전 형식 검증).
- `static var focusFrontmostRawSource` — 정적 source 문자열에 대한 raw access.
- `func markUnknownForTesting()` — `lastKnownPermission = .unknown` + SettingsStore 미러 (D3-16 `.unknown` 분기 향후 통합 테스트용 시드, 단위 테스트는 `.granted/.unknown` 라이브 의존이라 03-09에서 다룸).

기존 9개 테스트는 변경 없음. 총 15개 모두 패스.

## Decisions (Locks)

1. **`scriptResultToJump`는 private static func** — 순수 매핑(actor 상태 무관)이라 static. queue.async 클로저(non-actor context)에서 동기 호출 가능, 코드 동선이 가장 짧음.
2. **State mirror sequence — "after-await"** — `runJumpByUUID`/`runFocusFrontmost` 모두 동일 shape:
   ```
   let result: JumpResult = await withCheckedContinuation { … queue.async { … cont.resume(returning: …) } }
   switch result { case .ok: await markGranted(); case .permissionDenied: await markDenied(); default: break }
   return result
   ```
   actor isolation을 안에서 다시 hop하는 패턴 대신 외부에서 한 번에 처리. plan §"LOCK: use the second shape"와 정확히 일치.
3. **Per-call recompile (jump) vs compile-once (focus-frontmost)** — 입력이 동적이면 Option C, 정적이면 cheap-query 패턴. 한 actor 안에서 두 정책이 공존하지만 둘 다 같은 serial queue/state-mirror 컨트랙트 공유.
4. **`.granted` 분기 단위 테스트는 적재하지 않음** — 라이브 AppleScript + iTerm2 상태가 필요. 단위 표면은 `.denied` 단락 + 화이트리스트 게이트만 결정적으로 검증, `.granted` 라이브 경로는 03-09 SC 통합 검증으로 위임. plan §"defer to integration verifier (03-09)"와 일치.
5. **Test 시드 위치 — Task 3 안에서 같은 파일에 추가** — plan은 시드를 Task 3 액션에 명시했고, Task 3 하나의 커밋 안에 production 파일 변경(시드)과 테스트 파일이 함께 들어가는 것이 자연스러움 (`feat`는 Task 1-2가 이미 가졌고, 시드는 테스트 surface로 분류). 커밋 type은 `test`.

## Threats Mitigated

| Threat ID | Mitigation Implemented |
|-----------|------------------------|
| T-INJECTION-01 | RESEARCH §Pattern 1 Option C 정확히 잠금: `iTermSessionID.isValid(uuid)` Foundation UUID 화이트리스트 게이트 → 실패 시 `runJumpByUUID`가 `String(format:)` 치환 자체에 도달하지 않음. AppleScript-grammar에 의미 있는 문자(`"`, `\`, newline, `tell` 등)는 모두 거부. 테스트 두 개로 봉인. |
| T-INJECTION-02 | focus-frontmost source는 fully static — substitution 자체가 없어 trivially 만족. |
| T-TIMEOUT-01 | jump-by-uuid + focus-frontmost 모두 `with timeout of 3 seconds` AppleScript-side 하드 캡. `classify(_:_:)`가 `-1712 → .timeout`, `scriptResultToJump`이 `.timeout → JumpResult.timeout` 그대로 패스 — UX는 `.timeout` 분기에서 회복 가능 상태로 렌더(03-08 SettingsView). |
| T-PERM-01 | `-1743 → .denied`, `markDenied()` 호출이 SettingsStore 미러 → PermissionBannerView 자동 surface (Phase 2 D2-35/D2-36 인계). |

## Deviations from Plan

**1. [Process - worktree path]** 첫 번째 Edit 시 워크트리가 아닌 main working tree(`/Users/choijihye/Study/source/claude_alert_bot/App/AppleScriptHelper.swift`)에 변경이 떨어진 사실을 발견. 즉시 `git diff`로 패치 추출 → main working tree `git checkout`으로 원복 → 워크트리(`agent-ad7df9b1e5c02e2ef`)에 `git apply`. main에 staged/committed된 흔적 없음(`git status`로 검증). 이후 모든 Edit/Bash는 워크트리 절대 경로(`/Users/.../.claude/worktrees/agent-ad7df9b1e5c02e2ef/...`) 명시 + `git -C $WT` 사용 패턴으로 통일.

**2. [Plan-spec note - test count]** Plan `<done>`은 "5-6 new tests" 표기. 실제 작성 = 6개:
- `test_runJumpByUUID_rejectsNonUUIDInput` (whitelist scalar)
- `test_runJumpByUUID_rejectsAppleScriptInjectionAttempt` (whitelist injection)
- `test_jumpByUUIDTemplate_containsAppleScriptTimeout` (template invariant)
- `test_focusFrontmostSource_containsAppleScriptTimeout` (focus-frontmost invariant)
- `test_testConnection_deniedShortCircuits` (D3-16 .denied branch)
- `test_d3_04_phase2SilentFailureRegression_postNormalizationContract` (plan-check B2 relocation)

`done` grep regex (`test_runJumpByUUID|test_testConnection|test_focusFrontmost|test_jumpByUUIDTemplate|test_d3_04_phase2SilentFailureRegression`)가 6 매치 → 요구치 ≥5 충족.

이외 deviation 없음 — plan 그대로 실행.

## Auth Gates

해당 없음.

## Verification Snapshot

| Check | Result |
|-------|--------|
| `xcodebuild build -project … -scheme ClaudeAlertBot` | BUILD SUCCEEDED |
| `xcodebuild test -only-testing:.../AppleScriptHelperTests` | 15 tests, 0 failures (9 existing + 6 new) |
| `xcodebuild test` (full suite) | TEST SUCCEEDED |
| `grep -c 'with timeout of 3 seconds' App/AppleScriptHelper.swift` | 2 |
| `grep -c '^    with timeout of 1 second$' App/AppleScriptHelper.swift` (literal source line) | 1 (cheap-query unchanged) |
| `grep -c 'iTermSessionID.isValid' App/AppleScriptHelper.swift` | 3 (1 call + 2 doc-comments) |
| `grep -c 'func testConnection' App/AppleScriptHelper.swift` | 1 |
| `grep -c 'func runJumpByUUID' App/AppleScriptHelper.swift` | 1 |
| `grep -v '^\s*//' App/AppleScriptHelper.swift \| grep -c 'NSApp\.activate'` | 0 (Pitfall #1 회귀 가드) |
| Test method count regex | 6 |

## Commit Trail

| Task | Type | Commit | Description |
|------|------|--------|-------------|
| 1 | feat | `d3f8f07` | jump-by-uuid template + runJumpByUUID actor method (D3-06/D3-09) |
| 2 | feat | `9af98bf` | focus-frontmost script + testConnection actor method (D3-16/D3-17/SET-05) |
| 3 | test | `793c1dc` | AppleScriptHelperTests branch matrix + whitelist + D3-04 regression (+ DEBUG seams) |

## Self-Check: PASSED

- `App/AppleScriptHelper.swift` — modified at worktree path; greps verified above.
- `ClaudeAlertBotTests/AppleScriptHelperTests.swift` — modified; 6 new test methods present.
- Commits `d3f8f07`, `9af98bf`, `793c1dc` — all present in `git log` of `worktree-agent-ad7df9b1e5c02e2ef`.
- Build green, full test suite green.
- T-INJECTION-01 whitelist gate test pair passes deterministically (offline, no live AppleScript needed).
