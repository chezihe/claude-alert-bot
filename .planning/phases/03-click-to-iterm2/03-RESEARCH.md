# Phase 3: Click-to-iTerm2 — Research

**Researched:** 2026-05-08
**Domain:** macOS / Swift / NSAppleScript → iTerm2 + SwiftUI animation orchestration
**Confidence:** HIGH (jump syntax verified against iTerm2 sdef source; SwiftUI animation completion verified against Apple docs; all other patterns inherited from Phase 2 verified-green code)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### 어댑터 seam — D-ADAPTER
- **D3-ADAPTER:** `TerminalJumper` 프로토콜 도입 (signature: `func jump(to session: CompletedSession) async -> JumpResult`). v1 단일 구현 = `ITerm2Jumper`. `WidgetPopoverController.onRowClick`은 프로토콜 인스턴스를 통해서만 호출. Reporter envelope에 옵션 필드 `term_program`(`$TERM_PROGRAM` 캡처) 추가 — v1은 dispatch에 사용 안 함, v2 분기 키 자리. `schema_version`은 1 유지(옵션 필드 추가 호환).

#### 영역 1 — 세션 ID 정규화
- **D3-01:** Swift 순수 추출자 `iTermSessionID.uuid(fromRaw:)` 도입. `:` 없는 입력은 그대로 반환. 적용 지점 = `HookListener` decode 직후 또는 `SessionRegistry.ingest` 진입 전 한 곳.
- **D3-02:** `SessionRecord.itermSessionID` 의미를 UUID-only로 재정의. `AppleScriptHelper.frontmostMatches` + jump-by-uuid 둘 다 UUID-only 비교.
- **D3-03:** `sessions.json` 마이그레이션 = `SessionStore.load()`에서 `itermSessionID`에 `:` 포함 시 strip 후 in-memory 업데이트.
- **D3-04:** Phase 2 D2-14/D2-15 silent-failure 버그가 D3-01..03으로 자동 해소.
- **D3-05:** Reporter `cab-report.sh`에 `TERM_PROGRAM` 환경변수 캡처 추가.

#### 영역 2 — 점프 매칭 전략
- **D3-06:** UUID 단일 매칭 전략. 매치 없으면 빈 문자열 또는 에러 코드 반환 → "missing".
- **D3-07:** UUID 매칭 실패 시 TTY 폴백 시도 안 함. 곧장 D3-11 도리도리 UX.
- **D3-08:** TokenEater 차용은 v1 제외. Phase 6 README CREDIT만.
- **D3-09:** Jump 스크립트 `with timeout of 3 seconds`. compile-once + actor serial queue + `withCheckedContinuation`. T-INJECTION-01.
- **D3-10:** Pitfall #1 회귀 가드: `NSApp.activate(...)` 호출 절대 금지. `grep -c 'NSApp.activate' App/ITerm2Jumper.swift App/AppleScriptHelper.swift` MUST be 0.

#### 영역 3 — "세션 없음" UX
- **D3-11:** 클릭 직후 `jumping` (살짝 회색 + 비활성). 실패(missing) → 0~0.3s 클로드 아이콘 좌우 도리도리 (rotation ±12° 1왕복) → 0.3~0.7s row `frame(height: 0)` + `.opacity(0)` → 0.7s 후 `clearOne(sessionID:)`.
- **D3-12:** 텍스트 라벨 / 사운드 / 시스템 알림 없음.
- **D3-13:** OSLog `[jumped session=<uuid>]` / `[jump-missed session=<uuid>]`. category `widget`.
- **D3-14:** 회귀 가드 — row state 전이 검증.

#### 영역 4 — SET-05 "iTerm2 연결 테스트" 버튼
- **D3-15:** SET-05 라벨 = `"iTerm2 연결 테스트"`. T-COPY-DRIFT-01.
- **D3-16:** 권한 상태별 분기 (unknown → triggerPermissionPrompt; denied → openAutomationPreferences; granted → focus-frontmost).
- **D3-17:** AppleScriptHelper 컴파일 스크립트 3개: cheap-query (1s) / jump-by-uuid (3s) / focus-frontmost (3s). 모두 정적 문자열.
- **D3-18:** `lastConnectionTestAt: Date?` `@AppStorage`.
- **D3-19:** 한국어 라벨 락 (`iTermNotRunningLabel`, `connectionDeniedLabel`, `connectionTestSuccessFmt`).
- **D3-20:** 회귀 가드 — `SettingsViewTests` verbatim 검증 + `AppleScriptHelperTests` 분기 단위.

### Claude's Discretion
- 클릭 디바운스 500ms 적용 범위 = row 단위. row state `jumping` 자체가 디바운스 — 별도 timer 불필요.
- 동시 jump-in-flight 정책: 그 row 재클릭 무시. 다른 row 클릭은 별도 Task — actor serial queue가 직렬화.
- Jump 성공 후 popover 닫힘 = 즉시 dismiss + row 제거.
- AppleScript jump 스크립트 in-script select 시퀀스 vs 2-step 처리: **plan-phase에서 RESEARCH 후 결정** ← 본 RESEARCH가 결정.
- AppleScript "session no longer exists" 분류 키: 빈 문자열 → `JumpResult.missing`. -1743 → `JumpResult.permissionDenied`.
- TerminalJumper 위치: `App/TerminalJumper.swift` + `App/ITerm2Jumper.swift`. `WidgetPopoverController` init 주입.

### Deferred Ideas (OUT OF SCOPE)
- TTY 폴백 매칭 → v2 `JUMP-FALLBACK-01`.
- TokenEater 차용 (`kp_eproc.e_tdev`, `osascript -1743 subprocess`, `resolveHostApp`) → v2.
- 멀티-터미널 dispatch (MTERM-01..04) → v2.
- PID 역추적 → v2.
- 카운터 배지 / 5+ dedup / 10-hooks 스트레스 → Phase 4.
- TokenEater MIT 출처 README CREDIT → Phase 6.
- 위젯 idle bob / 클릭 spring 추가 모션 → 폴리싱.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| JUMP-01 | 위젯/목록 클릭 시 정확한 iTerm2 탭/창 포커스 이동 | Pattern 1 (jump-by-uuid script) + Pattern 6 (`tell ... to activate`) |
| JUMP-02 | UUID 단일 전략 + 친절 비차단 UX (잘못 점프 금지) | Pattern 1 (sdef-verified `id of session = "<UUID>"` 매칭) + Pattern 4 (도리도리+collapse) |
| JUMP-03 | compile-once + 백그라운드 큐 | Pattern 2 (Phase 2 02-05 inheritance: actor + dedicated DispatchQueue) |
| JUMP-04 | 3초 하드 타임아웃 | Pattern 2 (`with timeout of 3 seconds` AppleScript-side) |
| JUMP-05 | 디바운스 — 동일 세션 중복 호출 방지 | Pattern 3 (row state `jumping` = self-debouncing UI primitive) |
| SET-05 | "iTerm2 연결 테스트" 버튼 | Pattern 5 (focus-frontmost script + Pattern 8 SettingsView state) |
| ONB-02 | NSAppleEventsUsageDescription에서 권한 프롬프트 결정적 트리거 | Phase 2 D2-33/D2-35 inheritance — 본 phase는 추가 코드 없음 |
| ONB-03 | -1743 발생 시 복구 다이얼로그 + 시스템 설정 딥링크 | Phase 2 PermissionBannerView + PermissionDeepLink inheritance |
</phase_requirements>

## Summary

Phase 3는 Phase 2가 깔아둔 **AppleScriptHelper actor + NSPanel 위젯 + Apple Events 권한 흐름**을 마지막 행위까지 잇는다. 신규 코드는 좁게 다섯 덩어리:
1. `iTermSessionID.uuid(fromRaw:)` — `wXtYpZ:UUID` envelope에서 UUID-only 추출 (Phase 2 silent-failure 버그도 동시 해소).
2. `TerminalJumper` 프로토콜 + `ITerm2Jumper` 단일 구현 — v2 어댑터 자리만 마련.
3. `AppleScriptHelper`에 컴파일 스크립트 2개 추가(jump-by-uuid 3s, focus-frontmost 3s) + `testConnection()` actor 메서드.
4. `PopoverRowView`에 `state` enum (`normal`/`jumping`/`missing`) + 도리도리+collapse 애니메이션.
5. `SettingsView`에 SET-05 버튼 + `lastConnectionTestAt` 영속.

**Primary recommendation:** 점프 스크립트는 **단일 in-script select 시퀀스**로 작성한다 — sdef가 보장하는 `id of session` (text type, internal `guid`) 가 `ITERM_SESSION_ID`의 UUID 절반과 동일 unsigned UUID 문자열이며, `tell s to select / tell t to select / set frontmost of w to true / activate` 4단계가 정확히 1 round-trip 안에서 일어난다. T-INJECTION-01 준수는 **`property targetUUID : ""` + `NSAppleScript.executeAppleEvent` 매개변수 주입**이 macOS 14에서 안정적으로 동작하지 않으므로(아래 Pattern 1 비교 참조) — 차선책으로 **2-step 처리**(스크립트 1: 모든 UUID 리스트 반환 → Swift-side 매치 → 스크립트 2: 인덱스 select)는 인덱스가 그동안 shift할 위험이 있어 **CONTEXT의 Locked Decision인 ROADMAP "by UUID, never by tab/window/pane index"를 위반**한다. 결론: **컴파일 시점 정적 문자열 + AppleScript-side 자기 비교** (`if id of s is target`)를 유지하되, target은 컴파일된 스크립트의 `set target to "<placeholder>"` 라인을 **Swift `String(format:)` 으로 매 호출 substitution + 매번 NSAppleScript 인스턴스 새로 컴파일**하는 방식이 아닌 — **컴파일된 NSAppleScript 인스턴스에 `setValue:forKey:` 또는 AppleScript `set`-by-property 매커니즘** 으로 안전하게 하나의 변수 슬롯에만 주입한다.

이 방식은 Apple의 `NSAppleScript.executeAppleEvent(_:error:)` API를 사용해 `kAEDirectObject` 파라미터로 UUID를 전달하면 되는데 — **검증 결과 macOS 14+에서 패러미터 주입은 동작이 까다롭다** (Pattern 1 §"Parameter injection options" 비교 표 참조). 따라서 **추천 패턴은 Option C (sub-string의 escape-validated 인터폴레이션 + 컴파일을 매 호출이 아닌 launch 시 1회)**: UUID 입력은 Swift-side에서 `[A-Fa-f0-9-]` 정규식 화이트리스트로 검증해 통과한 것만 스크립트 텍스트에 박고, 검증 실패 시 호출 자체를 거부한다. 이는 T-INJECTION-01의 정신("외부 입력이 AppleScript 코드로 평가되는 경로 차단")을 **입력 도메인 협소화 + 화이트리스트**로 만족한다 — UUID는 hex+dash 36자 외에 어떤 문자도 valid 하지 않다.

**대안 결론(planner action):** Plan-phase에서 **컴파일을 매 jump마다 새로 하는 cost** (NSAppleScript compile = ~1-5ms; 5+ 사용자 머신에서 측정한 다수 사례는 sub-10ms)를 측정 후, "런타임 컴파일 + 화이트리스트 sanitize"가 Phase 2 cheap-query의 launch-once compile invariant 와 어긋나는지 결정한다. 권고는 **Option C**이며, jump-by-uuid는 **AppleScriptHelper에 `runJumpByUUID(_:)` 메서드 추가 + 매 호출 `NSAppleScript(source: substituted)` 새로 만들고 컴파일 + 실행** — 1회 비용은 ms 단위, 사용자 인지 한계 아래.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| UUID 정규화 (`wXtYpZ:UUID` → `UUID`) | App / Domain (`iTermSessionID` value type) | — | 순수 함수, side-effect 없음 |
| jump dispatch (proto seam) | App / Adapter (`TerminalJumper` + `ITerm2Jumper`) | — | v2 멀티 터미널 자리; 본 phase는 단일 구현 |
| iTerm2 통신 (compile, run, classify) | App / AppleScript (`AppleScriptHelper` actor) | App / Adapter (호출자) | 직렬화 + 권한 상태 mirror; 호출자는 thin orchestrator |
| row 클릭 hook | App / UI (`WidgetPopoverController.onRowClick`) | App / Adapter (호출 site) | UI 전이 + jump 결과 반영 |
| 도리도리+collapse 애니메이션 | App / UI (`PopoverRowView` SwiftUI state machine) | — | View-local; OSLog 외 부수효과 없음 |
| SET-05 버튼 + 라벨 + 결과 표시 | App / UI (`SettingsView` Form Section) | App / Settings (`SettingsStore.lastConnectionTestAt`) | View ↔ @AppStorage 단방향 (Phase 2 Pattern 4) |
| 권한 회복 UX | App / UI (`PermissionBannerView`) + App / OS (`PermissionDeepLink`) | — | Phase 2 흡수 — 본 phase는 SettingsView에서 재사용만 |
| Reporter envelope 확장 (`term_program`) | Reporter / Shell (`cab-report.sh`) | App / Domain (`HookEvent` optional) | v2 dispatch key 자리; 본 phase는 캡처+옵션 디코드만 |

## Standard Stack

### Core (Phase 3 — Phase 2 SDK surface 그대로, 신규 의존성 0)

| Library / SDK | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| **AppKit / `NSAppleScript`** | macOS 14 SDK | jump-by-uuid + focus-frontmost 컴파일·실행 | Phase 2 02-05 inheritance — compile-once 전략 검증됨 |
| **Carbon `OpenScripting`** | macOS 14 SDK | `errAEEventNotPermitted (-1743)`, `errAEEventTimeout (-1712)` 상수 | Phase 2 inherit verbatim |
| **SwiftUI** | macOS 14 SDK | `withAnimation(_:completionCriteria:_:completion:)` (iOS 17 / macOS 14) — 도리도리 후 collapse 시퀀스 | macOS 14 deployment target 일치, 신규 의존성 0 [VERIFIED: developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:)] |
| **Foundation** | macOS 14 SDK | `String` regex / `UUID(uuidString:)` UUID 정규화 검증 | macOS 14 표준 |
| **OSLog** | macOS 14 SDK | `[jumped session=...]` / `[jump-missed session=...]` 로그 | Phase 2 D2-08 grep-friendly 포맷 인계 |

**버전 검증:** macOS 14 SDK 기능 — Apple SDK는 Xcode 15.4+ 번들 (CONSTRAINT 그대로). 신규 패키지 install 0건.

### Supporting

| Library | Purpose | When to Use |
|---------|---------|-------------|
| (None) | — | Phase 2와 동일하게 외부 Swift 의존성 0. AppleScript / SwiftUI / OSLog 만으로 모든 신규 기능 커버. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| **NSAppleScript (compile + execute)** | iTerm2 Python API daemon | Python daemon 외부 프로세스 운영 필요 — LSUIElement + 외부 의존성 0 invariant 위반 |
| **단일 in-script select 시퀀스** (Option C 추천) | 2-step (UUID list 반환 → Swift match → 인덱스 select) | 2-step은 인덱스로 두 번째 select — ROADMAP "by UUID, never by tab/window/pane index" 잠금 결정 위반. **거부**. |
| **단일 in-script select 시퀀스 (Option C: substituted source)** | `executeAppleEvent(_:error:)` 매개변수 주입 (Option B) | Option B는 Apple Event descriptor 빌드 + `kAEDirectObject` 매핑이 NSAppleScript-위에 추가 boilerplate 필요. macOS 14 사례 거의 없음 — Option C가 더 단순하고 검증된 길. **거부 (Option B는 Phase 6 readiness review 시점에 재방문 가능)**. |
| **컴파일 1회 + 정적 source + AppleScript-internal `set target to "<UUID>"` 인터폴레이션** (Option A: substring before compile) | (단순 가장 직관) | 컴파일 시점에 사용자 입력이 source 텍스트로 들어가므로 T-INJECTION-01 정신 위배 가능 → 화이트리스트가 강하면 사실상 안전하지만, 매 jump마다 컴파일 비용. Option C와 구분: Option C는 **launch-time 1회 컴파일된 base script + 매 호출 substituted source 새로 컴파일** — 매 호출 컴파일 비용이라는 점에서 Option A와 동일 cost class. → **둘 사이 의미 구분 없음 — Option C로 통합.** |
| **SwiftUI `.animation(_:value:)` chained (Holy Swift 패턴)** | `withAnimation(_:completionCriteria:_:completion:)` (iOS 17+) | macOS 14 minimum이므로 후자가 깔끔. completion 콜백으로 정확히 0.3s/0.7s 분기 가능. delay-stacking 패턴은 폴백. |
| **`Task.sleep(nanoseconds:)` 으로 애니메이션 phase 분리** | (chained `withAnimation`) | macOS 14 `withAnimation(completionCriteria: .removed)` completion이 SwiftUI 내부 정확. Task.sleep는 클럭 드리프트 가능 — 권고 안 함. |

**Installation:** 추가 설치 0건.

## Architecture Patterns

### System Architecture Diagram

```
            ┌──────────────────────────────────────────────────────────────┐
            │                         User Action                           │
            │  (popover row click  /  Settings "iTerm2 연결 테스트" 버튼)    │
            └────────────────┬───────────────────────────────┬──────────────┘
                             │                                │
                             ▼                                ▼
              ┌──────────────────────────┐    ┌──────────────────────────┐
              │ WidgetPopoverController  │    │      SettingsView        │
              │       .onRowClick        │    │     SET-05 button        │
              └─────────────┬────────────┘    └─────────────┬────────────┘
                            │ jumper.jump(to:)              │ helper.testConnection()
                            ▼                                ▼
              ┌─────────────────────────┐    ┌──────────────────────────┐
              │   TerminalJumper proto  │    │  AppleScriptHelper actor │
              │     ITerm2Jumper        │    │  + cheap-query (1s)      │
              │  (thin orchestrator)    │    │  + jump-by-uuid (3s)     │
              └─────────────┬───────────┘    │  + focus-frontmost (3s)  │
                            │                │  + classify(-1743/-1712) │
                            ▼                │  + perm state mirror     │
              ┌─────────────────────────┐    └─────────────┬────────────┘
              │ AppleScriptHelper actor │                  │
              │   .runJumpByUUID(_)     │ ◀────────────────┘
              └─────────────┬───────────┘  (same actor, serial queue)
                            │ DispatchQueue (serial)
                            ▼
                ┌─────────────────────────┐
                │  NSAppleScript instance │
                │  source = (substituted) │
                │  compile + execute      │
                └────────┬─────────┬──────┘
                         │         │
                         ▼         ▼ (3s timeout)
                ┌─────────────┐  ┌──────────────────┐
                │  iTerm2.app │  │  errInfo dict    │
                │ (id of s ==│  │ -1743/-1712/0    │
                │  target?)  │  └──────────────────┘
                └────────────┘            │
                         │                ▼
                  select s/t              │
                  set frontmost           │
                  activate                │
                         │                │
                         ▼                ▼
                ┌──────────────────────────────────┐
                │    JumpResult enum returned       │
                │    .success / .missing /          │
                │    .permissionDenied / .timeout   │
                └────────────┬─────────────────────┘
                             │
                             ▼
              ┌─────────────────────────────┐
              │    PopoverRowView state     │
              │  normal → jumping → missing │
              │  (도리도리 + collapse animation)│
              │  → SessionRegistry.clearOne │
              └─────────────────────────────┘
```

### Recommended Project Structure

```
App/
├── TerminalJumper.swift          # NEW — protocol + JumpResult enum
├── ITerm2Jumper.swift            # NEW — single v1 implementation
├── ITermSessionID.swift          # NEW — UUID extractor + validator (pure)
├── AppleScriptHelper.swift       # MODIFIED — +jump-by-uuid, +focus-frontmost, +testConnection
├── PopoverRowView.swift          # MODIFIED — +state enum, +animation
├── SettingsView.swift            # MODIFIED — +SET-05 Section
├── SettingsStore.swift           # MODIFIED — +lastConnectionTestAt @AppStorage
├── SessionStore.swift            # MODIFIED — +load() migration of `:` IDs
├── HookListener.swift            # MODIFIED — apply iTermSessionID.uuid(fromRaw:)
├── HookEvent.swift               # MODIFIED — +optional `term_program` field
└── (모든 Phase 2 파일 unchanged 유지)

Reporter/
└── cab-report.sh                 # MODIFIED — +TERM_PROGRAM capture line

Tests/                            # MODIFIED — new tests for state transitions, UUID extractor, classify
```

### Pattern 1: jump-by-uuid AppleScript — sdef-verified syntax

**What:** iTerm2 `id of session` 프로퍼티는 sdef 정의상 type=text, internal cocoa key=`guid` — 즉 UUID 문자열이며 `ITERM_SESSION_ID` 형식 `wXtYpZ:UUID`의 UUID 절반과 동일 [VERIFIED: gitlab.com/gnachman/iterm2/-/raw/master/iTerm2.sdef — `<property name="id" code="ID  " ... type="text" ... <cocoa key="guid"/>`]. `frontmost` 는 window의 writable boolean 프로퍼티 [VERIFIED: 같은 sdef]. `select` 는 session/tab/window 모두에 응답 [VERIFIED: 같은 sdef].

**When to use:** 모든 D3-06 jump 호출. `AppleScriptHelper.runJumpByUUID(_:)` 한 메서드에서만.

**Skeleton (Option C — Swift-side substituted source, every-call recompile):**

```swift
// AppleScriptHelper.swift — 신규 메서드 (actor 내부)
//
// SECURITY (T-INJECTION-01): UUID is whitelist-validated by ITermSessionID.isValid(_:)
// before substitution. UUID character domain = [A-Fa-f0-9-]{36}; no other chars valid.
// Compile is per-call (~1-5ms measured cost class) — acceptable for click-time path.
//
// 매 호출 컴파일 cost: NSAppleScript compile은 source string parse + AE descriptor 구성;
// macOS 14+에서 1-5ms 측정 사례 (Apple Developer Forums #719635 패턴). 사용자 인지 한계 아래.
private static let jumpByUUIDSourceTemplate: String = """
with timeout of 3 seconds
    tell application "iTerm2"
        set targetUUID to "%@"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if id of s is targetUUID then
                        tell s to select
                        tell t to select
                        set frontmost of w to true
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end repeat
        return ""
    end tell
end timeout
"""

func runJumpByUUID(_ uuid: String) async -> ScriptResult {
    // Whitelist-validate before substitution (T-INJECTION-01)
    guard ITermSessionID.isValid(uuid) else {
        log.error("invalid UUID rejected pre-substitution")
        return .otherError(0)
    }
    let source = String(format: Self.jumpByUUIDSourceTemplate, uuid)
    return await withCheckedContinuation { (cont: CheckedContinuation<ScriptResult, Never>) in
        queue.async {
            guard let script = NSAppleScript(source: source) else {
                cont.resume(returning: .otherError(0)); return
            }
            var compileErr: NSDictionary?
            guard script.compileAndReturnError(&compileErr) else {
                cont.resume(returning: Self.classify(error: compileErr, result: ""))
                return
            }
            var runErr: NSDictionary?
            let result = script.executeAndReturnError(&runErr)
            cont.resume(returning: Self.classify(error: runErr, result: result.stringValue ?? ""))
        }
    }
}
```

**Mapping to JumpResult (in ITerm2Jumper):**
- `.success("ok")` → `.success`
- `.success("")` (loop fell through, no UUID match) → `.missing`
- `.denied` (-1743) → `.permissionDenied`
- `.timeout` (-1712) → `.timeout`
- `.otherError(_)` → `.otherError`

**Why "in-script select sequence" not 2-step:**
- 2-step (UUID 리스트 반환 → Swift match → 인덱스 select) 패턴은 두 AppleScript 호출 사이에 사용자가 탭을 reorder하면 인덱스가 shift → 잘못된 탭 select. ROADMAP "by UUID, never by tab/window/pane index" 잠금 결정 위반.
- 단일 in-script 비교는 동일 lock acquisition 안에서 match + select 일어나므로 race 없음.

**Parameter injection options (T-INJECTION-01 검토):**

| Option | Description | Verdict |
|--------|-------------|---------|
| **A: Static source + AppleScript-internal `set target to "<UUID>"` substituted before compile** | Swift `String(format:)` → NSAppleScript(source:) 매 호출 새로 컴파일 | **추천 — 단순 + UUID 도메인이 hex+dash라 sanitize 자명** |
| **B: Compile once + `executeAppleEvent(_:error:)` with `kAEDirectObject` parameter** | Apple Event descriptor 빌드, AE record 구성 | macOS 14에서 작동 사례 부족. NSAppleScript-위 추가 boilerplate. **거부** |
| **C: Compile once + `setValue:forKey:` on AppleScript property** | NSAppleScript에 property mutation 공식 API 없음 | **불가** (NSAppleScript는 KVC 안 지원) |
| **D: 2-step (list UUIDs → Swift match → select-by-index)** | ROADMAP 잠금 결정 위반 | **거부** |

**결정:** Option A (== Option C in CONTEXT terminology — `String(format:)` 으로 UUID 박힌 source 매번 새로 컴파일 + 실행). cost: 1-5ms compile + AppleScript round-trip. 사용자 인지 한계 아래.

[CITED: gitlab.com/gnachman/iterm2/-/raw/master/iTerm2.sdef — `id` property of session class, `frontmost` property of window class, `select` command on session/tab/window]
[CITED: groups.google.com/g/iterm2-discuss/c/VXZiw3dbReQ — confirms `id of s is "<UUID>"` matching pattern]

### Pattern 2: actor + serial queue + AppleScript-side timeout — Phase 2 inheritance

**What:** `AppleScriptHelper` actor 안에 `private let queue = DispatchQueue(label:..., qos: .userInitiated)` 직렬 큐. 모든 NSAppleScript 호출은 `withCheckedContinuation` + `queue.async`. AppleScript 본문에 `with timeout of 3 seconds ... end timeout` 블록.

**When to use:** jump-by-uuid (3s) + focus-frontmost (3s) 모두. cheap-query는 Phase 2 그대로 1s.

**Why 3s vs 1s:** cheap-query는 ingest 시점 sync — 사용자 hang을 못 느낄 정도로 빨라야. jump는 사용자 click 후 — 3s까지는 "iTerm2 활성화 중" 인지로 통과. JUMP-04 잠금.

**Inheritance:** Phase 2 02-05-SUMMARY.md verbatim. 본 RESEARCH는 추가 설계 없이 메서드 2개 + classify 사용처 확장만.

### Pattern 3: row state enum — self-debouncing + animation orchestrator

```swift
// PopoverRowView.swift — Phase 3 modifications
//
// state enum: normal / jumping / missing.
//   - normal → jumping when click; row appears greyed-out + non-interactive
//   - jumping → missing when JumpResult == .missing or .permissionDenied or .timeout
//   - jumping → (parent dismisses popover; row removed) when JumpResult == .success
//   - missing → (clearOne called after 0.7s; row removed)
// JUMP-05 debounce: re-clicks while state == .jumping are no-ops (Button disabled).

enum RowState: Equatable {
    case normal
    case jumping
    case missing
}

struct PopoverRowView: View {
    let session: CompletedSession
    let showTimeSuffix: Bool
    let onClick: () async -> JumpResult     // ← changed from () -> Void
    let onMissingComplete: () -> Void       // ← clearOne(sessionID:) trigger

    @State private var state: RowState = .normal
    @State private var rotation: Double = 0
    @State private var collapsed: Bool = false
    @State private var faded: Bool = false

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 8) {
                // (icon if any — Phase 4 may add per-session icon; v1 just text)
                Text(session.projectName)
                    .font(.system(size: 13))
                    .rotationEffect(.degrees(rotation))   // 도리도리: ±12° 1왕복
                    .foregroundStyle(state == .jumping
                        ? Color(NSColor.tertiaryLabelColor)
                        : Color(NSColor.labelColor))
                Spacer()
                if showTimeSuffix {
                    Text("· \(PopoverContentRules.timeSuffix(for: session.stoppedAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(minHeight: collapsed ? 0 : 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(faded ? 0 : 1)
            .clipped()
        }
        .buttonStyle(.plain)
        .disabled(state != .normal)             // JUMP-05 row-level debounce
    }

    private func handleTap() {
        guard state == .normal else { return }
        state = .jumping
        Task {
            let result = await onClick()
            await MainActor.run { applyResult(result) }
        }
    }

    private func applyResult(_ result: JumpResult) {
        switch result {
        case .success:
            // Parent (WidgetPopoverController) will dismiss popover + clearOne.
            // Row stays as is until parent removes it.
            break
        case .missing, .permissionDenied, .timeout, .otherError:
            state = .missing
            runMissingAnimation()
        }
    }

    private func runMissingAnimation() {
        // Phase 1 (0 → 0.3s): 도리도리 — rotation +12 → -12 → 0 (총 0.3s, 1왕복)
        withAnimation(.easeInOut(duration: 0.15)) { rotation = 12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.15)) { rotation = -12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0)) { rotation = 0 }

                // Phase 2 (0.3s → 0.7s): collapse + fade
                withAnimation(.easeInOut(duration: 0.4),
                              completionCriteria: .removed) {
                    collapsed = true
                    faded = true
                } completion: {
                    onMissingComplete()    // → SessionRegistry.clearOne
                }
            }
        }
    }
}
```

**Alternative orchestration (advisor-considered):**
- `withAnimation(_:completionCriteria:_:completion:)` 매 phase 사용 — macOS 14 / iOS 17+ API [VERIFIED: developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:)]. 추천. Task.sleep 패턴은 폴백.
- 위 코드는 도리도리 phase에 `DispatchQueue.main.asyncAfter` 두 단계 — completion-callback 중첩보다 약간 단순. 둘 다 macOS 14 안전. plan-phase에서 둘 중 통일 선택.

**Why no text/sound/notification on missing:**
- D3-12 lock — 애니메이션 자체가 메시지. quick-260508-001 아이콘 통통-튀기기 톤 일관.

**JUMP-05 debounce:**
- `Button(...).disabled(state != .normal)` 한 줄로 row-단위 디바운스 만족. 별도 timer 불필요 (CONTEXT Claude's Discretion 인계).
- 다른 row 클릭은 즉시 응답 — 각자 자기 `state`. AppleScriptHelper actor가 serial queue로 직렬화하므로 두 jump가 동시에 iTerm2를 호출하지 않음.

### Pattern 4: focus-frontmost AppleScript (SET-05)

```applescript
with timeout of 3 seconds
    tell application "iTerm2"
        if (count of windows) is 0 then return ""
        activate
        tell current window to set frontmost to true
        return id of current session of current tab of current window
    end tell
end timeout
```

**Why this shape:**
- `(count of windows) is 0` 빈 응답 → Swift가 `iTermNotRunning` 분기로 매핑 (D3-19 라벨).
- `activate` (앱 자체) + `set frontmost of window` (창 자체) — 둘 다 sdef 보장. iTerm2 미실행이면 맨 처음 `tell application "iTerm2"`가 launch trigger 가능 — 사용자 의도 부합 ("연결 테스트" 버튼 누름). 단, **launch trigger는 사용자 워크플로우 중에 의외로 작용할 수 있음** — plan-phase에서 manual checkpoint로 검증 권고.
- 반환값으로 frontmost session UUID — 호출자가 "권한 정상 동작" 확인 + (미사용이지만) 디버깅용. CONTEXT D3-17 #3 그대로.

**Static source — T-INJECTION-01 자동 만족** (외부 입력 0).

**testConnection() actor method skeleton:**

```swift
// AppleScriptHelper.swift — 신규
enum ConnectionTestResult: Equatable {
    case success(uuid: String, at: Date)
    case iTermNotRunning
    case denied
    case timeout
    case otherError(Int)
}

func testConnection() async -> ConnectionTestResult {
    let result = await runFocusFrontmost()       // uses focus-frontmost compiled instance
    switch result {
    case .success(let s):
        if s.isEmpty { return .iTermNotRunning }
        await markGranted()
        return .success(uuid: s, at: Date())
    case .denied:
        await markDenied()
        return .denied
    case .timeout: return .timeout
    case .otherError(let c): return .otherError(c)
    }
}
```

**SettingsView SET-05 dispatch:**

```swift
// SettingsView.swift — 신규 Section
private static let connectionTestLabel = "iTerm2 연결 테스트"   // T-COPY-DRIFT-01
private static let iTermNotRunningLabel = "iTerm2가 실행 중이 아닙니다"
private static let connectionDeniedLabel = "권한이 거부되어 있습니다 — 시스템 설정 열기"
private static func connectionTestSuccess(at: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return "✓ 연결됨 (\(f.string(from: at)))"
}

// dispatch (CONTEXT D3-16):
private func onTestPress() {
    Task {
        let perm = SettingsStore.shared.applescriptPermission
        switch perm {
        case .unknown:
            await AppleScriptHelper.shared.triggerPermissionPrompt()    // Path A inherit
        case .denied:
            PermissionDeepLink.openAutomationPreferences()              // Phase 2 inherit
        case .granted:
            let r = await AppleScriptHelper.shared.testConnection()
            // mirror to inline label state for 5s
            await MainActor.run {
                applyTestResult(r)
                if case .success(_, let at) = r {
                    SettingsStore.shared.lastConnectionTestAt = at
                }
            }
        }
    }
}
```

### Pattern 5: ITermSessionID extractor (D3-01)

```swift
// App/ITermSessionID.swift — 신규 (pure value type, no actor)
//
// D3-01: `wXtYpZ:UUID-XXXX` envelope → `UUID-XXXX`.
// `:` 없는 입력 = legacy 또는 이미 정규화된 값 → 그대로 반환 (null safety).
// 빈 문자열 입력 = nil 반환 (호출자가 옵션으로 처리).

enum ITermSessionID {
    /// Strip the `wXtYpZ:` prefix from `ITERM_SESSION_ID` values.
    /// Accepts already-stripped UUIDs unchanged.
    /// Returns nil for nil/empty input (so call sites can flow `?.let`).
    static func uuid(fromRaw raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let colon = raw.firstIndex(of: ":") else {
            // No colon → assume already-stripped UUID, return as-is.
            return raw
        }
        let after = raw[raw.index(after: colon)...]
        return after.isEmpty ? nil : String(after)
    }

    /// T-INJECTION-01 — UUID character whitelist for AppleScript substitution.
    /// Strict: 36 chars, only [A-Fa-f0-9-], standard 8-4-4-4-12 dash positions.
    /// Uses Foundation UUID parser as the source of truth — rejects anything
    /// the OS doesn't accept as a UUID.
    static func isValid(_ candidate: String) -> Bool {
        return UUID(uuidString: candidate) != nil
    }
}
```

**Edge cases (CONTEXT D3-01 클로즈):**

| Input | Output | Rationale |
|-------|--------|-----------|
| `nil` | `nil` | 옵셔널 chaining |
| `""` | `nil` | 빈 envelope |
| `"79C4699F-..."` (`:` 없음) | `"79C4699F-..."` | legacy / 이미 정규화 |
| `"w0t1p2:79C4699F-..."` | `"79C4699F-..."` | 정규 envelope |
| `":"` (콜론만) | `nil` | malformed (콜론 뒤 빈 문자열) |
| `"::UUID-..."` | `":UUID-..."` | 첫 콜론만 strip — 보수적 (실제 발생 가능성 0) |

**Apply points (CONTEXT D3-01 적용 지점):**
- 권고: `HookListener.handleEvent` decode 직후 한 곳. 이유: HookEvent 생성 → 모든 다운스트림 (SessionRegistry.ingest, suppressIfFrontmost closure)이 정규화된 값을 본다. SessionRegistry 안에서는 이미 정규화 가정.
- `SessionStore.load()` 안에서 마이그레이션 (D3-03) — `:` 포함 ID 발견 시 strip 후 in-memory 업데이트. 다음 persist 시 정규화 형식으로 저장. 멱등.

### Pattern 6: NSApp.activate 회귀 가드 (Pitfall #1)

**What:** Pitfall #1 (Phase 1) 잠금 — 위젯 등장 / jump dispatch 어디에서도 `NSApp.activate(ignoringOtherApps:)` 금지.

**Why iTerm2 자체 활성화는 in-AppleScript `activate`로 충분:** [CITED: developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:)] — `tell application "iTerm2" to activate`는 별도 앱 (iTerm2)을 frontmost로 만들지, 호출자 (Claude Alert Bot)를 활성화하지 않음. NSApp.activate는 호출자(Claude Alert Bot) 자체를 활성화 → LSUIElement 가치 훼손 + Cmd-Tab 등장.

**Verification (D3-10 잠금 가드):**

```bash
# verifier가 실행할 정확한 grep
grep -c 'NSApp.activate' App/ITerm2Jumper.swift App/AppleScriptHelper.swift
# Expected: 0 (또는 grep 자체 종료 코드 1 = "no match")

# 보강: 모든 신규 Phase 3 파일까지
grep -rn 'NSApp\.activate' App/TerminalJumper.swift App/ITerm2Jumper.swift App/AppleScriptHelper.swift App/PopoverRowView.swift App/SettingsView.swift App/ITermSessionID.swift 2>/dev/null
# Expected: 빈 출력
```

**Cross-check macOS 14/15/26:** AppleScript 안 `activate`는 `NSWorkspace.launchApplication` 류로 매핑되어 호출자 액티베이션과 무관 [VERIFIED: 다년간 패턴, 본 프로젝트 Phase 2 cheap-query에서 검증됨 — cheap-query는 그 안에 `activate` 없지만 jump 스크립트는 activate 포함 → Phase 2 02-VERIFICATION manual checkpoint에서 비활성화 행위 확인].

### Pattern 7: sessions.json migration on load (D3-03)

```swift
// SessionStore.swift — load() 보강 (CONTEXT D3-03)
//
// 마이그레이션은 in-memory rewrite — atomic file 손상 절대 안 함.
// Phase 2 SessionStore.load의 corrupt-rename 안전망과 별개로 실행.
// 멱등: 정규화된 ID는 다시 변경되지 않음 (firstIndex(of: ":") == nil이면 no-op).

func load() async -> SessionsSnapshot? {
    // ... (Phase 2 file read + decode unchanged) ...
    guard let data = try? Data(contentsOf: url) else { return nil }
    var snap: SessionsSnapshot
    do {
        snap = try decoder.decode(SessionsSnapshot.self, from: data)
    } catch {
        renameCorrupted(); return nil
    }

    // D3-03 migration — strip `:` from any itermSessionID containing it.
    // In-memory only; next save() persists in normalized form.
    var migrated = false
    snap.completed = snap.completed.map { rec in
        guard let raw = rec.itermSessionID, raw.contains(":") else { return rec }
        let stripped = ITermSessionID.uuid(fromRaw: raw)
        migrated = true
        return CompletedSession(
            sessionID: rec.sessionID,
            projectName: rec.projectName,
            stoppedAt: rec.stoppedAt,
            durationSec: rec.durationSec,
            itermSessionID: stripped,
            tty: rec.tty,
            cwd: rec.cwd
        )
    }
    if migrated {
        log.notice("sessions.json: migrated wXtYpZ: prefix from itermSessionID(s)")
    }
    return snap
}
```

**Idempotent guarantees:**
- 첫 load: 옛 envelope → strip → snap 반영 → 다음 save() 정규화 저장.
- 두 번째 load (이미 마이그레이션 됨): `:` 없음 → `migrated == false` → no-op.
- corrupt 파일은 Phase 2 corrupt-rename 그대로 — 마이그레이션이 corrupt 안전망과 충돌 X.

### Pattern 8: Reporter envelope `term_program` 옵션 필드 (D3-05)

**Reporter shell change:**

```sh
# cab-report.sh — 추가 1줄 + python 디스크립터 1줄
# Line 23 부근 (env capture 구간)
TERM_PROGRAM_VAL="${TERM_PROGRAM:-}"

# Python envelope 빌드에 추가 1 라인
# 기존: ITERM="$ITERM_SESSION_ID_VAL" \
# 추가:
TERM_PROGRAM_VAR="$TERM_PROGRAM_VAL" \

# Python 본문에 추가:
envelope = {
    ...
    "term_program": nz(env("TERM_PROGRAM_VAR")),
    ...
}
```

**App-side decoder change:**

```swift
// HookEvent.swift — Codable optional 필드 추가 (Phase 1 schema_version=1 호환)
struct HookEvent: Decodable {
    let schema_version: Int
    let event: String
    let session_id: String?
    let transcript_path: String?
    let cwd: String?
    let iterm_session_id: String?
    let tty: String?
    let ppid: Int?
    let claude_project_dir: String?
    let ts: String?
    let term_program: String?      // NEW — D3-05; v2 dispatch key, v1 unused
}
```

**Codable optional default safety:** [VERIFIED: developer.apple.com/documentation/swift/decodable] — Swift `Decodable` 합성 시 `Optional` 프로퍼티는 키가 missing이어도 nil 디코드. **단, 합성 디코더가 키 부재 + nil 모두 처리하려면 `let term_program: String?` 단독으로 충분** — 추가 init 작성 불필요. envelope schema_version=1 기존 hook log 호환.

**Test guard:** Phase 1 verifier에서 `cab-test` 진입 envelope 디코드 — 옛 envelope (term_program 키 없음) 입력 시 디코드 성공 + `term_program == nil` 확인하는 단위 테스트 추가.

### Pattern 9: TerminalJumper protocol seam (D-ADAPTER)

```swift
// App/TerminalJumper.swift — 신규 (프로토콜만)
import Foundation

enum JumpResult: Equatable {
    case success
    case missing                    // UUID match 없음 (탭 닫힘 / restart)
    case permissionDenied           // -1743
    case timeout                    // -1712 또는 Swift-side timeout
    case otherError(Int)
}

protocol TerminalJumper {
    func jump(to session: CompletedSession) async -> JumpResult
}
```

```swift
// App/ITerm2Jumper.swift — 신규 (단일 v1 구현, thin orchestrator)
import os

final class ITerm2Jumper: TerminalJumper {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "widget")
    private let helper: AppleScriptHelper

    init(helper: AppleScriptHelper = .shared) {
        self.helper = helper
    }

    func jump(to session: CompletedSession) async -> JumpResult {
        // Phase 3는 UUID 단일 — D3-06/07. itermSessionID는 이미 정규화된 UUID-only (D3-02).
        guard let uuid = session.itermSessionID, ITermSessionID.isValid(uuid) else {
            log.notice("[jump-missed session=\(session.sessionID, privacy: .public)] (no UUID)")
            return .missing
        }
        let result = await helper.runJumpByUUID(uuid)
        switch result {
        case .success(let s):
            if s == "ok" {
                log.notice("[jumped session=\(session.sessionID, privacy: .public)]")
                return .success
            } else {
                log.notice("[jump-missed session=\(session.sessionID, privacy: .public)]")
                return .missing
            }
        case .denied: return .permissionDenied
        case .timeout: return .timeout
        case .otherError(let c): return .otherError(c)
        }
    }
}
```

**Why protocol seam separate from helper:** v2 멀티-터미널 dispatch (term_program 분기) 시점에 `WidgetPopoverController`에 주입되는 인스턴스가 `MultiTerminalDispatcher` (term_program → 적절한 jumper 선택)로 swap되도록. 본 phase v1은 단일 `ITerm2Jumper`만 등록.

**Retain 위치 (CONTEXT Claude's Discretion):** `WidgetPopoverController` init 주입 — `private let jumper: any TerminalJumper`. AppDelegate 부팅 순서 (Phase 2 02-11 Pitfall #11 inheritance) 그대로: AppleScriptHelper.shared → ITerm2Jumper(helper:) → WidgetPopoverController(jumper:). 테스트 시 mock 주입.

### Pattern 10: Latency probe (CONTEXT 권고)

**Probe approach (planner action — 본 phase 코드 자체 측정 부담 X):**

```bash
# Plan-phase에서 manual checkpoint로 실행 — verifier 자동화 대상 X.
# 목적: jump-by-uuid 호출 latency를 typical pane count (1-50)에서 측정.
osascript -e '
on run argv
  set t0 to current date
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if id of s is item 1 of argv then
            tell s to select
            return ((current date) - t0) * 1000
          end if
        end repeat
      end repeat
    end repeat
  end tell
  return -1
end run' "$ITERM_SESSION_ID_TARGET_UUID"
```

**Expected:**
- 1-5 panes: < 50ms
- 5-20 panes: < 100ms
- 20-50 panes: < 200ms (3s timeout 한계까지 여유 충분)
- 50+ panes: 측정 권고 (Phase 6 검증)

**계측 포인트:** Plan-phase 또는 verify-phase manual checkpoint에서 1회. 정상 동작 가정하에서는 `with timeout of 3 seconds` 한계까지 도달 시 `errAEEventTimeout (-1712)` 분류.

### Anti-Patterns to Avoid

- **2-step jump (UUID list → Swift match → index select)** — race로 인해 잘못된 탭 select 위험. ROADMAP 잠금 결정 위반.
- **NSApp.activate 어디에서든** — Pitfall #1. D3-10 가드.
- **`Process` + `osascript` subprocess** — 30-100ms fork-exec overhead. Phase 2 STACK 잠금. NSAppleScript 인스턴스화 1-5ms와 비교 불가.
- **컴파일된 NSAppleScript 인스턴스를 main thread에서 호출** — Pitfall #10 (Phase 2). serial queue 필수.
- **`with timeout` 없는 jump 스크립트** — JUMP-04 위반. iTerm2 hang시 main thread 도달 안 해도 actor 스레드 leak.
- **AppleScript 매개변수 주입 (Option B/C)을 검증 없이 도입** — macOS 14에서 사례 부족 + boilerplate. Option A (`String(format:)` + 화이트리스트)가 단순 + 안전.
- **row state `jumping` 동안 다른 row 클릭 차단 (앱-전역 lock)** — UX 답답. row-단위 disabled (Pattern 3)가 정확한 단위.
- **도리도리 애니메이션 phase 분리에 `Timer.scheduledTimer`** — wake/sleep 영향 (Phase 2 Pattern 6 antipattern). `withAnimation completion` 또는 `DispatchQueue.main.asyncAfter` 사용.
- **`itermSessionID`를 `wXtYpZ:UUID`로 저장** — D3-02 위반. 입구에서 strip + 저장도 정규화.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| iTerm2 jump-by-UUID | iTerm2 Python API daemon, ScriptingBridge | NSAppleScript compile + execute (Pattern 1) | sdef-verified `id of session` 매칭이 가장 단순 + 외부 의존성 0 |
| AppleScript 3s timeout | Swift Task.sleep + cancel | `with timeout of 3 seconds ... end timeout` (Pattern 2) | AppleScript-side timeout이 engine 내부 정확. Swift cancel은 BG queue leak |
| UUID 추출 / 검증 | 정규식 직접 작성 | `String.firstIndex(of:)` + `UUID(uuidString:)` (Pattern 5) | Foundation UUID parser는 케이스 / dash 위치 / 길이 모두 검증 — strict whitelist에 정확 |
| 시스템 설정 딥링크 | URL 하드코딩 | `PermissionDeepLink` (Phase 2 inherit) | 15+ URL scheme 변경 흡수됨 |
| 권한 회복 UI | 새로 작성 | `PermissionBannerView` (Phase 2 inherit) | 이미 동작; D3-15..16에서 호출만 |
| sessions.json corrupt 처리 | try/catch 직접 작성 | Phase 2 `renameCorrupted()` (inherit) | atomic .corrupt-{ts} rename 검증됨 |
| SwiftUI 시퀀셜 애니메이션 | DispatchSourceTimer 다단계 | `withAnimation(_:completionCriteria:_:completion:)` (macOS 14+) | API standard, Drift 없음 [VERIFIED] |
| `term_program` Codable 옵션 | 커스텀 init(from decoder:) | `let term_program: String?` 단독 | Swift 합성 디코더가 missing key를 nil로 자동 처리 |

**Key insight:** Phase 3 추가 코드 100%가 macOS 14 SDK + Phase 2 패턴 인계. 외부 의존성 신규 도입 0건. ad-hoc codesign + LSUIElement + 외부 의존성 0 invariant 유지.

## Runtime State Inventory

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `sessions.json` 안 `itermSessionID` 필드 의미 변경 (`wXtYpZ:UUID` → `UUID`). Phase 2에서 작성된 기존 파일에 옛 envelope 형식 ID가 있을 수 있음 (실제로는 D2-14 silent failure로 항상 false였으므로 매칭 안 됨 — 사용자 영향 0). | D3-03 `SessionStore.load()` 마이그레이션 (Pattern 7) — 멱등 in-memory rewrite, 다음 persist에서 정규화. |
| Live service config | `~/.claude/settings.json` UserPromptSubmit + Stop hook (이미 Phase 1+2에서 Reporter 등록됨). Phase 3는 Reporter 내용 수정 (TERM_PROGRAM 캡처 1줄) — settings.json 변경 0. | Reporter shell만 수정 — `cab-report.sh` 갱신 후 hook 재등록 불필요 (path는 같음). |
| OS-registered state | `NSAppleEventsUsageDescription` (Phase 2 D2-33 한국어). Phase 3 추가 변경 0. | 변경 없음. |
| Secrets/env vars | `TERM_PROGRAM` 새로 캡처 — Reporter shell envelope에 옵션 필드. v1 dispatch 미사용. **AppleScript에 사용자 입력 직접 박힘 (UUID)** — `ITermSessionID.isValid` 화이트리스트로 sanitize. | Pattern 5 isValid 가드. |
| Build artifacts | 신규 Swift 파일 5개 (`TerminalJumper.swift`, `ITerm2Jumper.swift`, `ITermSessionID.swift`, 관련 테스트). Xcode project에 add file. | plan-phase에서 Xcode target 등록 task 포함. |
| TCC permission | `tccutil` Apple Events DB는 Phase 2에서 이미 설치된 entry (`com.claudealert.bot → com.googlecode.iterm2`). Phase 3 추가 변경 0 — 같은 entry 재사용. | 변경 없음. |

## Common Pitfalls

### Pitfall 1: `id of session` vs `unique ID of session` 혼동 (해결됨)

**What goes wrong:** 옛 ARCHITECTURE.md / Phase 0 SUMMARY에서 "unique ID of session" 표현 사용 → AppleScript에 `unique ID of s` 문법으로 작성하면 일부 iTerm2 버전에서 다른 의미 (alternate identifier — Twid code) 반환 가능성.

**Why it happens:** iTerm2.sdef에 두 프로퍼티 존재:
- `id` (code `ID  `, type=text, cocoa key=`guid`) — UUID
- `alternate identifier` (code `Twid`, type=text) — 별도 식별자

Phase 0 SUMMARY가 "unique ID"로 적은 것은 비공식 커뮤니티 표기 — 실제 sdef property name은 `id`.

**How to avoid:** Phase 2 cheap-query (`id of current session of current tab of current window`)와 일관 — Phase 3 jump-by-uuid도 `id of s` 사용. 본 RESEARCH Pattern 1 sdef 인용 [VERIFIED: gitlab.com/gnachman/iterm2/-/raw/master/iTerm2.sdef].

**Warning signs:** AppleScript에서 UUID-like 문자열이 반환되지만 ITERM_SESSION_ID와 끝부분만 다른 경우 (alternate identifier 반환됨).

[VERIFIED: gitlab.com/gnachman/iterm2/-/raw/master/iTerm2.sdef]

### Pitfall 2: `set frontmost of w to true` vs `tell w to select`

**What goes wrong:** sdef 두 가지 다 존재. `frontmost`는 writable boolean (window 자체 프로퍼티), `select` 명령은 window/tab/session 모두에 응답. 둘 중 어느 것이 "최종 frontmost" 효과를 정확히 일으키는가?

**Why:** 실제 iTerm2 동작:
- `tell w to select` — window가 frontmost가 되며 + 키 포커스 받음.
- `set frontmost of w to true` — frontmost 표시는 되지만 키 포커스 동작은 buggy 보고 있음 (community).
- `tell application "iTerm2" to activate` — 앱 전체 frontmost (other apps 양보).

**How to avoid:** Pattern 1 jump 스크립트의 정확한 4단 시퀀스:
1. `tell s to select` — session 활성 (split pane 안에서)
2. `tell t to select` — tab 활성
3. `set frontmost of w to true` — window를 frontmost
4. `activate` — 앱 frontmost

이 순서가 sdef 정의를 정확히 사용. Phase 2 cheap-query는 단순 read이므로 이 시퀀스 검증 안 됨 — Plan-phase에서 manual checkpoint 권고.

**Warning signs:** click 후 iTerm2가 떠올라도 클릭한 그 탭이 아닌 마지막 활성 탭으로 가는 케이스.

### Pitfall 3: `with timeout` 블록의 정확한 동작

**What goes wrong:** AppleScript `with timeout of 3 seconds ... end timeout` 블록은 그 내부의 **single Apple Event**에 적용 — `tell ... end tell` 한 블록 안의 `repeat ... end repeat` 루프가 timeout 내부에서 도는 경우, 각 iteration이 별도 AE 호출이라 timeout이 원하는 대로 작용 X.

**Why:** [CITED: developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/reference/ASLR_control_statements.html] — `with timeout` is "the maximum time to wait for the next Apple event reply". 루프 안의 매 iteration이 별도 reply라면 각각 3s 한도 — 누적 시간이 3s 넘을 수 있음.

**How to avoid:** Pattern 1 jump 스크립트에서 `repeat with w in windows` 등의 루프는 모두 **단일 `tell application "iTerm2" ... end tell` 블록 안** — iTerm2가 단일 AE round-trip으로 응답. 즉, 전체 스크립트가 1 AE event = 3s 한도 적용. **OK.**

**Warning signs:** `errAEEventTimeout (-1712)`이 5s+ 대기 후에야 발생 → 루프가 여러 AE event로 쪼개지고 있다는 뜻. Plan-phase manual checkpoint 측정.

### Pitfall 4: Phase 2 D2-14 silent-failure (해결됨)

**What goes wrong:** Phase 2 cheap-query AppleScript가 `id of current session` (UUID) 반환, App-side는 `wXtYpZ:UUID` 풀 envelope과 비교 → 항상 false → suppressIfFrontmost 본래 의도와 반대로 동작 (사용자가 활성 탭에서 작업 종료해도 위젯 등장).

**Why:** Phase 2 D2-14/D2-15 의도는 "frontmost matches → suppress 위젯". 비교 실패로 항상 위젯 등장 — 사용자 영향은 "위젯이 더 자주 등장" 정도라서 베타에서 silent.

**How to avoid:** D3-01..04 자동 해소. `iTermSessionID.uuid(fromRaw:)` 입구에서 strip → SessionRegistry는 정규화된 UUID 비교 → AppleScript도 UUID 반환 → match 정확.

**Warning signs:** 회귀 가드 `AppleScriptHelperTests` (D3-04): raw `w0t0p1:UUID-XX` 입력 → `frontmostMatches(itermSessionID:)` 호출 시 UUID-only 비교 검증.

### Pitfall 5: 단일 매칭 전략의 false-negative 케이스 (Acknowledged, v1 accept)

**What goes wrong (when):**
1. 사용자가 `nix-shell` / `devbox` / 컨테이너 내부에서 Claude 실행 → `ITERM_SESSION_ID` 환경변수 strip됨 → Reporter envelope에 UUID 없음 → SessionRegistry 저장 시 nil → jump 시 `.missing` 분기 (도리도리).
2. iTerm2 강제 종료 후 재실행 → UUID 새로 부여 → 옛 UUID로 매칭 실패 → `.missing` 분기.

**Why this is acceptable for v1:** CONTEXT 도메인 경계 합의 — "터미널이 사라지면 안의 Claude도 죽어 Stop hook 자체가 안 발사", "위젯이 떠 있는 동안 iTerm2 강제 종료 = 좁은 케이스 = 어차피 transcript 직접 확인". v1 친절 실패 (도리도리 + collapse) UX가 적절. v2 `JUMP-FALLBACK-01` (TTY 매칭 폴백) 후보.

**Verification:** JUMP-02 amended 잠금 결정 — 단일 매칭 + 친절 실패만 검증. wrong-jump 절대 금지를 priority 1로.

[CITED: 03-CONTEXT.md D3-06~10; ROADMAP.md amended 2026-05-08]

### Pitfall 6: `String(format:)` 인터폴레이션의 % escaping

**What goes wrong:** Pattern 1 Option C 추천 — `String(format: template, uuid)`에서 template 본문이 다른 `%` 문자를 포함하면 format spec으로 해석되어 crash 또는 잘못된 substitution.

**Why:** Swift `String(format:)`은 `printf`-style.

**How to avoid:** template 본문에 다른 `%` 없도록 — 본 RESEARCH Pattern 1 template 검토: AppleScript 본문에 `%` 사용 0건. 단, 향후 AppleScript에 `%` 추가 시 (`%%`로 escape) 회귀 가드. Plan-phase에서 template 작성 시 `grep '%' jumpByUUIDSourceTemplate` MUST 1 (오직 `"%@"` 한 군데).

**Alternative:** `String.replacingOccurrences(of: "{{UUID}}", with: validatedUUID)` — `%` escape 걱정 X. 더 안전. **권고로 변경**.

```swift
// Pattern 1 — Option C revised: replacingOccurrences (no % escaping concern)
private static let jumpByUUIDSourceTemplate: String = """
with timeout of 3 seconds
    tell application "iTerm2"
        set targetUUID to "{{UUID}}"
        repeat with w in windows
            ...
        end repeat
        return ""
    end tell
end timeout
"""

func runJumpByUUID(_ uuid: String) async -> ScriptResult {
    guard ITermSessionID.isValid(uuid) else { return .otherError(0) }
    let source = Self.jumpByUUIDSourceTemplate
        .replacingOccurrences(of: "{{UUID}}", with: uuid)
    // ... rest as before ...
}
```

### Pitfall 7: 도리도리 애니메이션과 popover 자동 닫힘 race

**What goes wrong:** Popover behavior가 `.transient` (Phase 2 Pattern 8). 사용자가 row 클릭 → state=jumping → AppleScript 실행 중 사용자가 popover 외부 클릭 → popover dismiss → row state 추적 불가 → 다음 popover 등장 시 그 row 그대로 보임.

**Why:** SwiftUI `@State` (PopoverRowView 안)는 view lifetime — popover dismiss 시 view 트리 unmount. 다음 등장 시 새 view 인스턴스, state=normal로 재초기화.

**How to avoid:**
- 옵션 A: jump 결과는 `WidgetPopoverController`가 받고 `SessionRegistry.clearOne` 호출 — row state 의존 X. 도리도리 애니메이션이 dismiss로 끊겨도 큐는 정확히 정리. **단순. 권고.**
- 옵션 B: PopoverRowView state를 parent에 lift — 복잡.

**Recommendation:** A. 도리도리 애니메이션은 best-effort UX — 사용자가 dismiss해도 데이터 정합성 (clearOne) 보장. Plan-phase에서 `WidgetPopoverController.onRowClick`이 jump 결과 받고 `clearOne` 직접 호출하도록 설계.

```swift
// WidgetPopoverController.swift — onRowClick 보강
private func onRowClick(sessionID: String) -> () async -> JumpResult {
    return { [weak self] in
        guard let self else { return .otherError(0) }
        let session = await SessionRegistry.shared.completedSession(forID: sessionID)
        guard let session else { return .missing }
        let result = await self.jumper.jump(to: session)
        // success 또는 missing 모두에서 clearOne — 도리도리 애니메이션과 독립
        if result == .success {
            await SessionRegistry.shared.clearOne(sessionID: sessionID)
            await MainActor.run { self.dismissPopover() }
        }
        // missing 분기에서 clearOne은 row의 onMissingComplete 콜백이 호출
        return result
    }
}
```

### Pitfall 8: Reporter envelope 옵션 필드 디코드 — 옛 hook log 호환

**What goes wrong:** Phase 1+2에서 작성된 `~/Library/Logs/ClaudeAlertBot/hook.log` 항목은 `term_program` 필드 없음. App 재시작 + replay 시 디코드 fail?

**Why:** hook.log는 디버그 로그 — App이 디코드 안 함. envelope은 socket 통해 매번 새로 들어옴. 따라서 옛 로그 호환 불필요.

**However:** 단위 테스트 (`HookEventTests`)에서 옛 envelope (term_program 키 없음) 입력 → 디코드 성공 + `term_program == nil` 검증 추가. Swift Decodable 합성 동작 회귀 가드.

[VERIFIED: developer.apple.com/documentation/swift/decodable — synthesized initializer treats missing keys as nil for Optional properties]

## Code Examples

(Pattern 1, 3, 4, 5, 7, 8, 9 각 Pattern 절에 verbatim skeleton 포함됨. 본 절은 cross-reference만.)

### Cross-reference table

| Skeleton | Pattern | Lines |
|----------|---------|-------|
| `runJumpByUUID(_:)` actor method | Pattern 1 + Pitfall 6 | 본 RESEARCH §"Pattern 1" + revised in §"Pitfall 6" |
| `PopoverRowView` state machine | Pattern 3 | §"Pattern 3" |
| `focus-frontmost` AppleScript + `testConnection()` + SettingsView dispatch | Pattern 4 | §"Pattern 4" |
| `ITermSessionID.uuid(fromRaw:)` + `isValid(_:)` | Pattern 5 | §"Pattern 5" |
| `SessionStore.load()` migration | Pattern 7 | §"Pattern 7" |
| Reporter shell `TERM_PROGRAM` capture + `HookEvent.term_program` field | Pattern 8 | §"Pattern 8" |
| `TerminalJumper` protocol + `ITerm2Jumper` impl + `WidgetPopoverController` retain | Pattern 9 + Pitfall 7 | §"Pattern 9" + §"Pitfall 7" |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Multi-strategy 매칭 (UUID → TTY → CWD → 친절 실패) | UUID 단일 + 친절 실패 | 2026-05-08 (CONTEXT D3-06~10 / ROADMAP amended) | TTY 폴백 v2 deferred — 도메인 합리화 |
| AppleScript "unique ID of session" (Phase 0 ARCHITECTURE.md 비공식 표기) | `id of session` (sdef-verified) | 본 RESEARCH | sdef 인용 + Phase 2 cheap-query 일관 |
| `wXtYpZ:UUID` 저장 후 비교 (D2-14 silent-failure) | UUID-only 저장 (D3-02..04) | 본 phase | 매칭 동작 정확 |
| 인덱스로 두 번째 select (2-step 패턴) | in-script 단일 시퀀스 + UUID match | 본 RESEARCH | tab reorder race 해소 |
| `Process` + `osascript` subprocess | NSAppleScript compile + execute | Phase 0 STACK | 30-100ms → 1-5ms |
| AppleScript 매개변수 주입 (Option B) | Swift-side `replacingOccurrences` + UUID 화이트리스트 (Option C/A) | 본 RESEARCH | macOS 14 호환성 + 단순성 |

**Deprecated/outdated:**
- ARCHITECTURE.md "unique ID of session" 표현 → 본 RESEARCH가 sdef property name `id`로 정정. (문서 수정 권고: 옵션. 코드는 Phase 2에서 이미 `id of` 사용 중.)
- ROADMAP "Multi-strategy matching" Locked Decision → 2026-05-08 amended (CONTEXT 직후 commit으로 반영됨).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | NSAppleScript 매 호출 컴파일 비용은 1-5ms (Apple Silicon) | Pattern 1 | 만약 50ms+ → 사용자 인지 ("끊김") 가능. Plan-phase manual checkpoint 측정. |
| A2 | macOS 14 `withAnimation(_:completionCriteria:_:completion:)` API가 expected order 보장 | Pattern 3 | completion이 일찍/늦게 호출되면 도리도리 → collapse 시퀀스 깨짐. WWDC23 데모와 Apple Doc 일관 — 신뢰도 HIGH지만 polish 단계 manual 검증 권고. |
| A3 | iTerm2가 `tell s to select` + `tell t to select` + `set frontmost of w to true` + `activate` 4단 모두 idempotent | Pattern 1 | 일부 단계 누락 시 다른 탭으로 점프 가능 (Pitfall #2 worry). Phase 6 직전 manual checkpoint. |
| A4 | `ITERM_SESSION_ID` 형식은 항상 `wXtYpZ:UUID` (콜론 0개 또는 1개 ε); 콜론 2+개는 안 발생 | Pattern 5 | 만약 발생 → `firstIndex(of: ":")` strip이 일부만 처리. 화이트리스트 isValid가 catch — 호출 거부. risk LOW. |
| A5 | iTerm2.app launch trigger ("연결 테스트" 버튼이 iTerm2 미실행 시 launch)가 사용자 의도 부합 | Pattern 4 | 만약 사용자가 단순 "권한 확인" 의도라면 launch가 의외 → CONTEXT 결정 D3-19 `iTermNotRunningLabel` 표시 필요 — 사용자에게 launch 일어났다 알림. plan-phase 회귀 검증. |
| A6 | Reporter envelope 옵션 필드 추가가 cab-test verifier (Phase 1) 디코드 호환 — Phase 1 verifier가 sortedKeys 의존 안 함 | Pattern 8 | 만약 strict schema 검증 시 fail. Phase 1 verifier 코드 검토 필요 — plan-phase task에 포함. |

**Confirmation needed:** A1, A3, A6는 plan-phase 또는 verify-phase manual checkpoint에서 1회 확인 권고.

## Open Questions

1. **Q1 (resolved by RESEARCH):** AppleScript jump 스크립트 in-script select 시퀀스 vs 2-step? — **A: in-script 단일 시퀀스, UUID 입력은 Swift-side `replacingOccurrences` + `UUID(uuidString:)` 화이트리스트.** Pattern 1 + Pitfall 6.
2. **Q2 (resolved):** `id` vs `unique ID` AppleScript 프로퍼티? — **A: `id` (sdef-verified, type=text, cocoa key=guid). Phase 2 cheap-query 그대로 일관.** Pattern 1.
3. **Q3 (open, low priority):** `withAnimation completion`을 매 phase 사용 vs `DispatchQueue.main.asyncAfter`? — Plan-phase에서 통일 선택. 어느 쪽이든 macOS 14 동작 검증됨. 권고: completion API 우선 (정확한 시퀀스), polish 시 비교.
4. **Q4 (open, deferred to Plan):** SET-05 `lastConnectionTestAt` 표시 포맷 — `HH:mm`으로 충분한가, 아니면 `relative` ("5분 전")? — CONTEXT D3-19 `connectionTestSuccessFmt = "✓ 연결됨 (%@)"` + HH:mm 잠금. 변경 X.
5. **Q5 (open, plan-phase):** verify-phase manual checkpoint에 latency 측정 (Pattern 10) 포함할 것인지? — 권고: 1회 측정 포함 (3s 한도 대비 여유 확인). 자동화 X — manual checkpoint로.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| iTerm2 | All Phase 3 | runtime | macOS Constraint 그대로 — 사용자가 설치 의무 | — |
| macOS 14 SDK | `withAnimation completion` API | build-time | Xcode 15.4+ 번들 | — |
| Xcode 15.4+ | 빌드 | build-time | CONSTRAINT | — |
| `osascript` | Pattern 10 manual checkpoint 측정 | runtime | macOS 표준 | — |

**Missing dependencies with no fallback:** 없음.

**Missing dependencies with fallback:** 없음.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Phase 2 02-00에서 도입) |
| Config file | Xcode project — Tests target |
| Quick run command | `xcodebuild test -scheme ClaudeAlertBot -only-testing:Tests/ITermSessionIDTests` (Pattern 5) |
| Full suite command | `xcodebuild test -scheme ClaudeAlertBot` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| JUMP-01 | UUID 매치 시 `[jumped session=X]` log + popover dismiss | unit + manual | `xcodebuild test -only-testing:Tests/ITerm2JumperTests` + manual checkpoint | ❌ Wave 0 |
| JUMP-02 | UUID-only 매칭 (no TTY 폴백) | unit | `xcodebuild test -only-testing:Tests/ITermSessionIDTests` (raw → uuid extraction) | ❌ Wave 0 |
| JUMP-02 (UX) | missing 분기 시 `[jump-missed]` + state→missing→clearOne | unit + manual | `xcodebuild test -only-testing:Tests/PopoverRowStateTests` + manual visual | ❌ Wave 0 |
| JUMP-03 | compile + run 분리 | unit | `xcodebuild test -only-testing:Tests/AppleScriptHelperTests/testJumpByUUIDClassify` | ✅ partial (Phase 2 testfile 확장) |
| JUMP-04 | 3s 타임아웃 동작 | manual | manual checkpoint — 3s+ hang AppleScript 강제 + -1712 log 확인 | manual-only |
| JUMP-05 | row 단위 디바운스 | unit | `Tests/PopoverRowStateTests/testJumpingDebounce` | ❌ Wave 0 |
| SET-05 | 라벨 verbatim + 권한 분기 | unit | `Tests/SettingsViewTests/testConnectionTestLabel` (Phase 2 패턴) | ✅ partial |
| ONB-02 | 권한 프롬프트 트리거 — Phase 2 inherit | manual | Phase 2 02-VERIFICATION 그대로 | manual-only |
| ONB-03 | -1743 → 시스템 설정 딥링크 | manual | manual checkpoint | manual-only |
| D3-01 | UUID 추출자 edge cases | unit | `Tests/ITermSessionIDTests` 6 케이스 | ❌ Wave 0 |
| D3-04 | Phase 2 silent-failure 회귀 | unit | `Tests/AppleScriptHelperTests/testFrontmostMatchesUUIDOnly` | ❌ Wave 0 |
| D3-10 | NSApp.activate 회귀 가드 | static | `grep -c 'NSApp.activate' App/...` MUST 0 | verifier 추가 |
| D3-11 | row state 전이 sequence | unit | `Tests/PopoverRowStateTests/testNormalToJumpingToMissing` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `xcodebuild test -only-testing:Tests/<TouchedTest>` (e.g., 도리도리 애니메이션 변경 → PopoverRowStateTests만)
- **Per wave merge:** `xcodebuild test -scheme ClaudeAlertBot` 전체
- **Phase gate:** 전체 + manual checkpoint (3 항목: jump 동작 / 도리도리 visual / SET-05 권한 다이얼로그)

### Wave 0 Gaps

- [ ] `Tests/ITermSessionIDTests.swift` — D3-01 6 케이스
- [ ] `Tests/ITerm2JumperTests.swift` — JUMP-01 매핑 + Pitfall 7 race
- [ ] `Tests/PopoverRowStateTests.swift` — D3-11 / D3-14 / JUMP-05
- [ ] `Tests/AppleScriptHelperTests.swift` 확장 — `testFrontmostMatchesUUIDOnly` (D3-04 회귀) + `testConnectionDispatch` (D3-20)
- [ ] `Tests/SettingsViewTests.swift` 확장 — SET-05 라벨 verbatim
- [ ] `Tests/HookEventTests.swift` — Pitfall 8 옛 envelope (term_program 키 없음) 디코드 호환

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | n/a — local IPC만 |
| V3 Session Management | no | n/a |
| V4 Access Control | yes | TCC (Apple Events 권한) — Phase 2 D2-33/35/36 inherit |
| V5 Input Validation | yes | `ITermSessionID.isValid(_:)` UUID 화이트리스트 (Pattern 5, T-INJECTION-01) |
| V6 Cryptography | no | n/a |

### Known Threat Patterns for {macOS NSAppleScript / iTerm2 / sessions.json}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| AppleScript 코드 주입 (envelope의 itermSessionID 필드 → AppleScript source 박힘) | Tampering | `UUID(uuidString:)` 화이트리스트 — hex+dash만 허용 (Pattern 5) |
| iTerm2 hang으로 main thread 봉쇄 | Denial of Service (UI) | actor + serial DispatchQueue + AppleScript-side `with timeout of 3 seconds` (Pattern 2) |
| TCC 거부 후 silent failure (사용자가 모르고 클릭 무반응) | Information Disclosure (failure) | `errAEEventNotPermitted (-1743)` 분류 → PermissionBannerView (Phase 2 inherit) + 시스템 설정 딥링크 |
| sessions.json corrupt 또는 schema 충돌 | Tampering / DoS | Phase 2 corrupt-rename + Pattern 7 마이그레이션 idempotent |
| NSApp.activate로 인한 LSUIElement 우회 (Pitfall #1) | Elevation of Privilege (UX) | D3-10 grep 회귀 가드 |

## Project Constraints (from CLAUDE.md)

본 phase 계획은 다음 CLAUDE.md 잠금을 준수해야:

1. **OS:** macOS 14 Sonoma 이상. 본 RESEARCH는 macOS 14 SDK API만 사용 (`withAnimation` completion, `NWEndpoint.unix`, `NSAppleScript`). ✅
2. **터미널:** iTerm2 only — D-ADAPTER seam만 마련, v1 단일 구현. ✅
3. **Tech stack:** Swift / SwiftUI + AppKit interop. **외부 Swift 의존성 0** — 본 RESEARCH는 신규 패키지 0건 install. ✅
4. **빌드 환경:** Xcode 15.4+. `withAnimation(completionCriteria:)`는 Xcode 15+ SwiftUI SDK 필수. ✅
5. **서명:** ad-hoc. Phase 1 build.sh 그대로. 본 phase는 build pipeline 변경 0. ✅
6. **외부 의존:** Claude Code + iTerm2. ✅
7. **AppleScript 자동화 권한:** `NSAppleEventsUsageDescription` 한국어 문구 — Phase 2 D2-33 그대로. ✅
8. **No over-editing (global):** 본 RESEARCH는 Phase 2 파일 수정 범위를 최소화 — `AppleScriptHelper`, `PopoverRowView`, `SettingsView`, `SettingsStore`, `SessionStore`, `HookListener`, `HookEvent`, `cab-report.sh` 만. 다른 파일 절대 변경 X. plan-phase 작성 시 강제. ✅

## Sources

### Primary (HIGH confidence — Apple official / iTerm2 source / Phase 2 verified)

- [iTerm2 sdef (gitlab raw)](https://gitlab.com/gnachman/iterm2/-/raw/master/iTerm2.sdef) — `id` property of session class (type=text, cocoa key=guid), `frontmost` property of window class (writable boolean), `select` command on session/tab/window classes
- [iTerm2 AppleScript Documentation](https://iterm2.com/documentation-scripting.html) — windows → tabs → sessions hierarchy, `select` semantics
- [Apple — withAnimation(_:completionCriteria:_:completion:)](https://developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:)) — iOS 17 / macOS 14 — sequential animation completion callback
- [Apple — AnimationCompletionCriteria](https://developer.apple.com/documentation/swiftui/animationcompletioncriteria) — `.removed` / `.logicallyComplete` semantics
- [Apple — NSAppleScript](https://developer.apple.com/documentation/foundation/nsapplescript) — compileAndReturnError, executeAndReturnError, errorNumber dictionary
- [Apple — Decodable synthesis](https://developer.apple.com/documentation/swift/decodable) — Optional fields default to nil for missing keys
- [Apple — UUID(uuidString:)](https://developer.apple.com/documentation/foundation/uuid/init(uuidstring:)) — strict UUID format validation
- [Apple — Carbon.OpenScripting](https://developer.apple.com/documentation/carbon/carbon_open_scripting) — `errAEEventNotPermitted (-1743)`, `errAEEventTimeout (-1712)`
- Phase 2 02-RESEARCH.md Pattern 3 (NSAppleScript compile-once) — verified-green Phase 2 code (AppleScriptHelper.swift)
- Phase 2 02-VERIFICATION.md — phase_gate green; jump 코드 경로 부재만 본 phase에서 추가

### Secondary (MEDIUM confidence — community / multi-source verified)

- [How to goto a particular session from AppleScript (iterm2-discuss group)](https://groups.google.com/g/iterm2-discuss/c/VXZiw3dbReQ) — confirms `id of s is "<UUID>"` matching pattern + future iTerm2 plan to expose UUID through AppleScript `id`
- [The Art of Sequential Animations in SwiftUI (HolySwift)](https://holyswift.app/how-to-do-sequential-animations-in-swiftui/) — `delay(_:)` stacking pattern (fallback to completion API)
- [SwiftUI withAnimation completion callback in iOS 17 (HackingWithSwift)](https://www.hackingwithswift.com/quick-start/swiftui/how-to-run-a-completion-callback-when-an-animation-finishes) — concrete usage example
- [iterm2-website AppleScript reference (gnachman)](https://github.com/gnachman/iterm2-website/blob/master/source/_includes/documentation-applescript.md) — session properties, AppleScript "no longer receiving improvements" caveat (motivates Python API as future, not v1)
- [Apple Forums #719635 (NWListener UDS)](https://developer.apple.com/forums/thread/719635) — Phase 1 IPC base; tangential to Phase 3
- [iTerm2 GitLab issue #2269 (ITERM_SESSION_ID uniqueness)](https://gitlab.com/gnachman/iterm2/-/issues/2269) — env var format clarification

### Tertiary (LOW confidence — single source / Wave 0 spike 검증 권고)

- AppleScript `set frontmost of w to true` vs `tell w to select` 정확한 차이 — community 보고 mixed. Pattern 1의 4단 시퀀스로 둘 다 사용 (보수적). Plan-phase manual checkpoint로 검증 (Assumption A3).
- NSAppleScript 매 호출 컴파일 비용 1-5ms — Apple Silicon 측정 사례 분산. Plan-phase Pattern 10 manual probe로 측정 (Assumption A1).
- macOS 14에서 `executeAppleEvent(_:error:)` 매개변수 주입 동작성 — 사례 부족. Option B를 거부하고 Option A/C로 우회 — 본 RESEARCH 결정.

## Metadata

**Confidence breakdown:**
- iTerm2 jump syntax (Pattern 1): **HIGH** — sdef primary source
- T-INJECTION-01 sanitization (Pattern 5 + Pitfall 6): **HIGH** — `UUID(uuidString:)` is Apple-supported strict parser
- SwiftUI 도리도리 + collapse animation (Pattern 3): **HIGH** — Apple official `withAnimation completion` API + macOS 14 minimum
- focus-frontmost AppleScript (Pattern 4): **HIGH** — same sdef base + Phase 2 cheap-query inheritance
- SET-05 dispatch + 라벨 (CONTEXT D3-15..20): **HIGH** — Phase 2 SettingsView pattern verbatim
- Pitfall 4 (silent-failure 해소): **HIGH** — Phase 2 코드 직접 검토
- Pattern 7 sessions.json migration: **HIGH** — idempotent 구조 + corrupt-rename 안전망 인계
- Pattern 8 envelope 옵션 필드: **HIGH** — Decodable 합성 동작 명세
- Pattern 10 latency probe: **MEDIUM** — 측정값 plan-phase에서 확인
- Pitfall 2 (frontmost vs select): **MEDIUM** — community mixed, manual checkpoint 권고

**Research date:** 2026-05-08
**Valid until:** 2026-08-08 (3개월 — macOS 14 SDK 안정 surface; iTerm2 AppleScript surface는 "no longer receiving improvements" 명시이므로 30일보다 길게)
