# Phase 3: Click-to-iTerm2 - Context

**Gathered:** 2026-05-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 2가 남긴 `[would-jump session=<uuid>]` 로그-no-op 자리(`App/WidgetPopoverController.swift:97` `onRowClick(sessionID:)`)를 **실제 iTerm2 탭 점프**로 대체. Apple Events 권한 흐름·NSAppleEventsUsageDescription·sequential deep-link는 Phase 2에서 이미 도입(D2-33/35/36)되어 있으므로, Phase 3는 ① UUID 단일 매칭 + 친절 실패 UX, ② SET-05 "iTerm2 연결 테스트" 버튼, ③ ONB-02/03 권한 회복 UX 마무리(이미 PermissionBannerView 존재)에 집중.

**ROADMAP 잠금 결정 정정:** ROADMAP "Locked Architectural Decisions"의 "UUID first, TTY fallback, friendly error last — never wrong-jump" 다단계 폴백은 사용자 결정으로 **단일 UUID 매칭 + 친절 실패** 로 축소. 사유: 터미널이 사라지면 안의 Claude도 죽어 Stop hook 자체가 안 발사되며, 위젯이 떠 있는 동안 iTerm2를 강제 종료한 좁은 케이스에서는 어차피 transcript를 직접 확인. nix-shell/컨테이너처럼 환경변수가 비워지는 좁은 예외만 v2 후보. ROADMAP/REQUIREMENTS 정정은 본 CONTEXT.md commit 직후 별도 commit으로 진행.

In scope:
- D2-08 hook-point(`WidgetPopoverController.onRowClick`) → 실제 jump 호출 (JUMP-01)
- 세션 ID 정규화 — `wXtYpZ:UUID` envelope 형식을 App ingest에서 UUID-only로 strip (Phase 2 D2-14/D2-15 silent-failure 버그 동시 해소)
- UUID 단일 매칭 jump AppleScript (JUMP-02 단일 전략, JUMP-03/04: compile-once + 백그라운드 큐 + AppleScript-side 3s timeout)
- 클릭 디바운스 500ms (JUMP-05) — Phase 2 popover hover-intent 패턴 인계, row-단위 적용
- "세션 없음" 친절 UX — 텍스트/사운드 없이 도리도리 + collapse 애니메이션 (JUMP-02 tier 3 구현)
- SET-05 "iTerm2 연결 테스트" 버튼 — frontmost-focus self-test + 마지막 테스트 시각 영속
- TerminalJumper 프로토콜 seam + ITerm2Jumper 단일 구현 (D-ADAPTER, v2 멀티-터미널 자리)
- Reporter envelope에 `term_program` 옵션 필드 추가 캡처 (v2 dispatch 키, schema_version=1 호환)
- ONB-02/03 권한 회복 — Phase 2 PermissionBannerView/PermissionDeepLink 재사용 (이미 동작 중)

Out of scope (다른 Phase 또는 v2):
- TTY 폴백 매칭 — env-stripped shell(nix-shell/컨테이너) 환경 케이스 v2
- TokenEater 차용(`kp_eproc.e_tdev` getProcessTTY / `osascript` -1743 subprocess 폴백 / `resolveHostApp`) — v2
- 멀티-터미널(VSCode/JetBrains/Warp/Ghostty) 실제 dispatch 구현 — v2 (MTERM-01..04)
- 카운터 배지·5+ 동시 완료 dedup·10-hooks-in-100ms 스트레스 — Phase 4
- 자동 hook installer / first-run wizard — Phase 5
- .dmg 패키징 / Gatekeeper README — Phase 6

</domain>

<decisions>
## Implementation Decisions

### 어댑터 seam — D-ADAPTER (locked)
- **D3-ADAPTER:** `TerminalJumper` 프로토콜 도입 (signature: `func jump(to session: CompletedSession) async -> JumpResult`). v1 단일 구현 = `ITerm2Jumper`. `WidgetPopoverController.onRowClick`은 프로토콜 인스턴스를 통해서만 호출. Reporter envelope에 옵션 필드 `term_program`(`$TERM_PROGRAM` 캡처) 추가 — v1은 dispatch에 사용 안 함, v2 분기 키 자리. `schema_version`은 1 유지(옵션 필드 추가 호환).

### 영역 1 — 세션 ID 정규화 (locked)
- **D3-01:** Swift 순수 추출자 `iTermSessionID.uuid(fromRaw:)` 도입 — `w0t0p1:79C4699F-XXXX-...` → `79C4699F-XXXX-...`. `:` 없는 입력은 그대로 반환(legacy 안전망 + null 안전 처리). 적용 지점 = `HookListener` decode 직후 또는 `SessionRegistry.ingest` 진입 전 한 곳.
- **D3-02:** `SessionRecord.itermSessionID` 의미를 **UUID-only**로 재정의. `AppleScriptHelper.frontmostMatches` + 신설 jump-by-uuid 스크립트 둘 다 UUID-only 비교.
- **D3-03:** `sessions.json` 마이그레이션 = `SessionStore.load()`에서 `itermSessionID`에 `:` 포함 시 strip 후 in-memory 업데이트(다음 persist 시 정규화 형식으로 저장). 멱등 — 매 load마다 안전.
- **D3-04:** Phase 2 D2-14/D2-15 silent-failure 버그(`AppleScriptHelper.scriptSource`가 UUID-only 반환 vs 저장된 `wXtYpZ:UUID` 비교 → 항상 false)는 D3-01..03으로 자동 해소. `AppleScriptHelperTests`에 raw `w0t0p1:UUID-XX` 입력 → `frontmostMatches` 호출 시 UUID만 비교 검증 회귀 가드 추가.
- **D3-05:** Reporter `cab-report.sh`에 `TERM_PROGRAM` 환경변수 캡처 추가 — envelope 옵션 필드 `term_program`. v1 dispatch 미사용, D-ADAPTER seam.

### 영역 2 — 점프 매칭 전략 (locked)
- **D3-06:** **UUID 단일 매칭 전략**. AppleScript 스크립트 1개 — windows → tabs → sessions 순회, `id of session = target_uuid` 매치 시 `select` (session) + `select` (tab) + `tell window to set frontmost to true` + `tell application "iTerm2" to activate`. 매치 없으면 빈 문자열 또는 에러 코드 반환 → Swift가 "missing"으로 분류.
- **D3-07:** UUID 매칭 실패 시 **TTY 폴백 시도 안 함**. 곧장 D3-11 도리도리 UX로 분기. 사유: 터미널이 살아있는데 UUID 매칭이 실패하는 케이스(env-stripped shell)는 좁고, 본인 + 일반 사용자 워크플로우 기준 합리적 단순화.
- **D3-08:** TokenEater(MIT) 차용은 v1 제외(`kp_eproc.e_tdev` getProcessTTY / `osascript` -1743 subprocess 폴백 / `resolveHostApp` Electron-helper skip 모두). 라이센스 의무에 따라 README CREDIT 섹션에 출처 표기만 (Phase 6 직전).
- **D3-09:** Jump 스크립트 `with timeout of 3 seconds` (JUMP-04). compile-once `NSAppleScript` 인스턴스, dedicated serial queue (`AppleScriptHelper` actor 내부), `withCheckedContinuation` (Phase 2 02-05 패턴 verbatim 인계, T-INJECTION-01: target은 AppleScript-side `id of session = "<UUID>"` 직접 매칭이 아닌 Swift-side 비교 — 정적 문자열 상수 유지).
- **D3-10:** **Pitfall #1 회귀 가드**: jump 코드 경로(ITerm2Jumper / AppleScriptHelper)에서 `NSApp.activate(...)` 호출 절대 금지. `grep -c 'NSApp.activate' App/ITerm2Jumper.swift App/AppleScriptHelper.swift` MUST be 0 (Phase 2 02-07 LSUIElement 가드 패턴 인계). iTerm2 측 활성화는 AppleScript 안에서 `tell application "iTerm2" to activate`.

### 영역 3 — "세션 없음" UX (locked)
- **D3-11:** UUID 매치 실패 시 row 클릭 응답 = **"도리도리 + collapse"** 애니메이션. SwiftUI `PopoverRowView`에 `state: enum { normal, jumping, missing }` 추가:
  - 클릭 직후 `jumping` (살짝 회색 + 비활성, 3s timeout 동안)
  - 결과 분기:
    - 성공 → popover 닫고 row 제거(SessionRegistry.clearOne)
    - 실패(missing) → `missing` 상태 진입, 0~0.3s 클로드 아이콘 좌우 도리도리 (rotation ±12° 1왕복) → 0.3~0.7s row `frame(height: 0)` + `.opacity(0)` 애니메이션 → 0.7s 후 `SessionRegistry.clearOne(sessionID:)` 호출 → 큐에서 자동 제거 → 큐가 비면 popover 자동 닫힘
- **D3-12:** **텍스트 라벨 / 사운드 / 시스템 알림 없음**. 동작(애니메이션) 자체가 메시지. 위젯 자체는 그대로(다른 큐 항목 있으면).
- **D3-13:** OSLog 인계 — Phase 2 D2-08 hook 자리(`[would-jump session=<uuid>]`) 교체. 성공 시 `[jumped session=<uuid>]`, 실패 시 `[jump-missed session=<uuid>]`. `[jump`-prefix 보존 (log show 필터 호환). category `widget` 그대로.
- **D3-14:** 회귀 가드 — `PopoverContentTests` 또는 신설 `PopoverRowStateTests`에 row state 전이 검증 (`normal → jumping → missing → 큐에서 제거` 시퀀스). 애니메이션 시각 자체는 단위 테스트 안 함; state 전이 + `clearOne` 호출 + OSLog 시그니처만 검증.

### 영역 4 — SET-05 "iTerm2 연결 테스트" 버튼 (locked)
- **D3-15:** `App/SettingsView.swift`에 SET-05 버튼 추가. 라벨 = `"iTerm2 연결 테스트"` (T-COPY-DRIFT-01 패턴, Phase 2 02-10 인계 — `static let connectionTestLabel` + `SettingsViewTests`에서 verbatim assert).
- **D3-16:** 버튼 누름 동작 = `AppleScriptHelper.testConnection()` (신설 actor 메서드) 호출. 권한 상태별 분기:
  - `unknown` → `triggerPermissionPrompt()` 동일 path (D2-35 Path A 재사용)
  - `denied` → `PermissionDeepLink.openAutomationPreferences()` 호출 (D2-36 재사용)
  - `granted` → 신설 focus-frontmost AppleScript 실행
- **D3-17:** **AppleScriptHelper actor가 컴파일 스크립트 3개 보유** (모두 compile-once + serial queue + 정적 문자열 상수, T-INJECTION-01 인계):
  1. **cheap-query** (Phase 2부터 존재, 1s timeout) — D2-14/D2-15용. `id of current session of current tab of current window` 반환.
  2. **jump-by-uuid** (신설, 3s timeout) — D3-06 메인 점프 경로. UUID 매칭 + select + activate.
  3. **focus-frontmost** (신설, 3s timeout) — SET-05 전용. `tell application "iTerm2" to activate` + frontmost session select. iTerm2 미실행 시 빈 응답 → "iTerm2가 실행 중이 아닙니다" 분기.
- **D3-18:** `SettingsStore`에 `lastConnectionTestAt: Date?` `@AppStorage` 추가. focus-frontmost 성공 시 timestamp 갱신. SettingsView에서 버튼 아래에 5초간 status 라벨 인라인 표시 (toast/window 안 만듦, SwiftUI `@State` + `.task { try? await Task.sleep(...) }` 패턴) + `lastConnectionTestAt` 영속이라 Settings 재오픈 시 마지막 테스트 시각 보임. **Status 카피는 minimal English / macOS-system tone** (memory: minimal-ui-copy 룰) — 데코 ✓ 체크마크 / 이모지 사용 안 함.
- **D3-19:** **Status 라벨 = minimal English** (T-COPY-DRIFT-01 락 패턴은 유지하되 한국어→영어 전환):
  - `connectionTestSuccessFmt = "Connected at %@"` (HH:mm 포맷; 데코 prefix 없음)
  - `iTermNotRunningLabel = "iTerm2 is not running"` (granted + frontmost 빈 응답 분기)
  - `connectionDeniedLabel = "Automation permission denied"` (denied 분기; 자동 딥링크와 동시 표시 — 별도 CTA 텍스트 없이 라벨만, 클릭 액션은 PermissionBannerView가 이미 owning)
  - **버튼 라벨 D3-15는 그대로** (`"iTerm2 연결 테스트"` Korean 유지) — Settings form 안 다른 Phase 2 버튼들("테스트 알림 보내기" 등)과 톤 일관. memory 룰의 "match existing tone" 조항 적용.
- **D3-20:** 회귀 가드 — `SettingsViewTests`에 SET-05 카피 verbatim 검증 + 버튼 누름 → `AppleScriptHelper.testConnection` 호출 트레이스 (테스트 시드). `AppleScriptHelperTests`에 `testConnection` 분기 단위 테스트 (unknown/denied/granted 모킹).

### Claude's Discretion
다음은 사용자가 별도 지시하지 않은 항목 — 합리적 기본값으로 진행:

- **클릭 디바운스 500ms 적용 범위 (JUMP-05):** **row 단위**. 같은 row 클릭 후 500ms 동안 그 row만 비활성. 다른 row 클릭은 즉시 응답. (앱-전역 lock은 다중 보류 큐에서 답답함 유발.) `PopoverRowView`의 `jumping` state 자체가 디바운스 역할 — 추가 timer 불필요.
- **동시 jump-in-flight 정책:** row state가 `jumping`인 동안 그 row 재클릭 무시. 다른 row 클릭은 별도 jump task — Swift `Task` 동시성에 의존, AppleScriptHelper actor의 serial queue가 직렬화 보장(Phase 2 02-05 패턴).
- **Jump 성공 후 popover 닫힘 타이밍:** 성공 시 즉시 popover dismiss + row 제거 (지연 없음). iTerm2가 활성화되면 어차피 popover는 .transient behavior로 자동 닫힘 — 수동 dismiss는 백업.
- **AppleScript jump 스크립트 in-script select 시퀀스:** `tell application "iTerm2" → repeat with w in windows → repeat with t in tabs of w → repeat with s in sessions of t → if id of s is "<UUID>" then tell s to select / tell t to select / tell w to set frontmost to true / activate / return "ok"`. 컴파일된 정적 문자열, target UUID는 Swift-side에서 이미 정규화된 상태로 비교(AppleScript 내부 `if id of s is target` 형태로 source에 박힘 — 컴파일 시점 string substitution X, 매 호출은 같은 source).
  - **수정:** Phase 2 T-INJECTION-01과 동일하게, AppleScript는 UUID 리스트만 반환하고 Swift-side에서 매칭 + 두 번째 AppleScript로 select 실행 — **2-step 처리**. (interpolation 회피.) 또는 AppleScript 변수를 외부에서 주입(`NSAppleScript.executeAppleEvent(...)` 매개변수 방식). 둘 중 plan-phase에서 RESEARCH 후 결정.
- **AppleScript "session no longer exists" 분류 키:** AppleScript 반환 = 빈 문자열 또는 매치 못 함 시그널 → Swift가 `JumpResult.missing` 매핑. `errAEEventNotPermitted -1743`은 별도 `JumpResult.permissionDenied`로 분류 (이미 cheap-query에서 처리하는 분류 패턴 인계).
- **TerminalJumper 프로토콜 위치:** `App/TerminalJumper.swift` 신설 (프로토콜만). `App/ITerm2Jumper.swift` 신설 (구현). `WidgetPopoverController`는 `private let jumper: any TerminalJumper`로 보유, init에서 주입 → 테스트 시 mock 교체 가능.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level (always read)
- `.planning/PROJECT.md` — Core Value("정확한 그 세션으로의 점프"), Constraints(macOS 14+, iTerm2 only, NSAppleEventsUsageDescription 한국어 문구), Out of Scope
- `.planning/REQUIREMENTS.md` — 53 v1 REQ-IDs; Phase 3 cover 8개: JUMP-01..05, SET-05, ONB-02, ONB-03 (정정 후 JUMP-02는 단일 전략으로 reword)
- `.planning/ROADMAP.md` §"Phase 3: Click-to-iTerm2" — 6개 Success Criteria (정정: SC#6 TTY 폴백 항목 v2 이동) + Locked Architectural Decisions(정정: multi-strategy → UUID-only)

### Prior phase (Phase 2, 직접 의존)
- `.planning/phases/02-alert-loop/02-CONTEXT.md` — Phase 2 전체 결정 (특히 D2-08 hook 자리, D2-13~15 자동 정리 3계층, D2-33~37 Apple Events 권한 흐름)
- `.planning/phases/02-alert-loop/02-VERIFICATION.md` — Phase 2 phase_gate green 증거 (D2-29 SwiftUI App 구조, AppDelegate 부팅 순서, 권한 다이얼로그 라이브 확인)
- `.planning/phases/02-alert-loop/02-RESEARCH.md` — Pattern 3(NSAppleScript compile-once), Pattern 8(NSPopover with .transient behavior), Pattern 12(sequential deep-link URL fallback), Pitfall #3(NSAppleEventsUsageDescription) — Phase 3 jump 스크립트가 동일 패턴 인계
- `.planning/phases/02-alert-loop/02-05-SUMMARY.md` — AppleScriptHelper actor 패턴 (compile-once + serial queue + classify error mapping). Phase 3는 actor에 jump-by-uuid + focus-frontmost 두 스크립트 추가만.
- `.planning/phases/02-alert-loop/02-08-SUMMARY.md` — WidgetPopoverController + Pattern 8 NSPopover. D2-08 OSLog 자리(`onRowClick`)가 Phase 3의 jump call site.
- `.planning/phases/02-alert-loop/02-10-SUMMARY.md` — SettingsView + 한국어 카피 락 패턴 (T-COPY-DRIFT-01). SET-05 버튼 추가 시 같은 패턴.
- `.planning/phases/02-alert-loop/02-11-SUMMARY.md` — AppDelegate Pitfall #11 부팅 순서. ITerm2Jumper 인스턴스 retain 위치는 plan-phase에서 결정 (현재 패턴: WidgetPopoverController가 retain).

### Prior phase (Phase 1, hook 파이프라인 의존)
- `.planning/phases/01-foundation/01-CONTEXT.md` — D-08 envelope schema (10필드, schema_version=1). Phase 3는 옵션 필드 `term_program` 추가만 (호환).
- `.planning/phases/01-foundation/01-02-SUMMARY.md` — `Reporter/cab-report.sh` 동작. Phase 3는 `TERM_PROGRAM` env var 캡처 1줄 추가.

### Research (Phase 3 직접 관련)
- `.planning/research/PITFALLS.md` #1 — Floating widget focus stealing. Phase 3 jump 코드도 동일하게 `NSApp.activate` 금지 (D3-10 회귀 가드).
- `.planning/research/PITFALLS.md` #3 — Apple Events first-run TCC. Phase 2 D2-33/35/36이 이미 흡수 — Phase 3는 권한 회복 UX에 PermissionBannerView/PermissionDeepLink 재사용.
- `.planning/research/PITFALLS.md` #4 — `ITERM_SESSION_ID` 환경 안정성. **정정 적용:** D3-06~08 단일 UUID 매칭으로 단순화. v2 후보 항목으로 별도 표기.
- `.planning/research/PITFALLS.md` #10 — AppleScript main-thread block. Phase 2 02-05 패턴(serial queue + AppleScript-side timeout) 인계, 3s 적용.
- `.planning/research/STACK.md` §"iTerm2 control" — `NSAppleScript` compile-many 권고. AppleScriptHelper actor가 이미 따름.
- `.planning/research/ARCHITECTURE.md` §"Session Identity" — UUID 우선 매칭 정책. Phase 3에서 단순화된 형태로 잠금.

### External docs (verify during planning)
- [iTerm2 AppleScript Documentation](https://iterm2.com/documentation-scripting.html) — `id of session`, `tty of session`, windows/tabs/sessions hierarchy, `select`, `set frontmost`
- [Apple — NSAppleScript](https://developer.apple.com/documentation/foundation/nsapplescript) — compileAndReturnError, executeAndReturnError, errorNumber dictionary
- [Apple — Carbon.OpenScripting](https://developer.apple.com/documentation/carbon/carbon_open_scripting) — `errAEEventNotPermitted (-1743)`, `errAEEventTimeout (-1712)`
- [Claude Code hooks documentation](https://code.claude.com/docs/en/hooks) — Stop hook envelope schema (envelope 정정 시 호환 검증)
- [TokenEater — AThevon/TokenEater](https://github.com/AThevon/TokenEater) — MIT 라이센스 reference (v1 차용 안 함, README CREDIT 출처 표기만 Phase 6에서)

### Phase 2 carry-over follow-ups (Phase 3가 직접 영향)
- **V-2 (listener uptime polish):** Phase 2에서 일부 closure. Phase 3 SET-05 verifier 시 listener up/down 영향 없는지 재확인.
- **V-7 (cab-test UUID-per-invocation):** Phase 2 verifier에서 1 FAIL로 남은 tooling artifact. Phase 3 verifier 작성 시 같은 패턴 회피.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (Phase 1+2에서 이미 존재)
- `App/AppleScriptHelper.swift` — actor + compile-once + serial queue + classify(-1743/-1712) 패턴. Phase 3는 컴파일 스크립트 2개 추가(jump-by-uuid, focus-frontmost) + `testConnection()` actor 메서드 추가.
- `App/WidgetPopoverController.swift:97` — `onRowClick(sessionID:)`가 D2-08 hook 자리. Phase 3에서 `Task { await SessionRegistry.shared.clearOne(...) }` 줄을 `await jumper.jump(to: session)` 분기 + 결과별 row state 전환으로 교체.
- `App/SettingsView.swift` — Phase 2 D2-35 Path A `.onAppear` 트리거 위치. SET-05 버튼은 같은 View에 Section 추가.
- `App/SettingsStore.swift` — `@AppStorage` 패턴. `lastConnectionTestAt: Date?` 필드 추가만.
- `App/PermissionBannerView.swift` + `App/PermissionDeepLink.swift` — denied 상태 회복 UX 이미 동작. ONB-02/03 Phase 3 요구사항을 그대로 흡수.
- `App/SessionRegistry.swift` — `clearOne(sessionID:)` 이미 존재. Phase 3는 jump 결과(성공/missing) 모두에서 호출.
- `App/SessionRecord.swift` — `itermSessionID: String?` 필드 그대로. **의미만 재정의** (UUID-only). 마이그레이션은 SessionStore.load 단계.
- `Reporter/cab-report.sh:22-36` — env 캡처 위치. `TERM_PROGRAM` 추가 1줄만.
- `App/HookListener.swift:116` — `frontmostMatches` 호출 closure. UUID 정규화 적용 위치 후보 1.
- `App/HookEvent.swift` — D-08 envelope decoder. UUID 정규화 적용 위치 후보 2 (decode 직후).

### Established Patterns
- **AppleScript compile-once + serial queue + AppleScript-side timeout:** Phase 2 02-05 파일 그대로. Phase 3 jump/focus 스크립트도 동일.
- **T-COPY-DRIFT-01 한국어 카피 락:** Phase 2 02-10에서 확립. SET-05 + 도리도리 UX(텍스트 없으니 적용 불필요) + 실패 라벨 모두 같은 패턴.
- **T-INJECTION-01 정적 AppleScript source:** Phase 2 02-05. Phase 3 jump 스크립트도 정적 — UUID는 외부 변수 또는 Swift-side post-매칭.
- **swift `actor` + serial queue 직렬화:** Phase 2 SessionRegistry, AppleScriptHelper. Phase 3 추가 코드도 actor 안에서.
- **WidgetHoverDelegate 패턴:** weak + protocol 분리 (02-07). 동일하게 TerminalJumper도 protocol + 주입.
- **OSLog `[*-prefix*]` 포맷:** D2-08 `[would-jump session=...]` → Phase 3 `[jumped session=...]` / `[jump-missed session=...]`. log show 필터 호환.
- **Pitfall #11 부팅 순서:** AppDelegate가 의존성 retain. ITerm2Jumper retain 위치는 plan-phase에서 결정(WidgetPopoverController init 주입이 자연스러움).

### Integration Points
- **WidgetPopoverController → TerminalJumper.jump:** 새 dispatch edge. `onRowClick(sessionID:)` 안에서 row state 전환 + jump 호출 + 결과별 분기.
- **TerminalJumper(ITerm2Jumper) → AppleScriptHelper.jump(itermSessionID:):** ITerm2Jumper는 thin orchestrator — UUID 정규화 확인 + AppleScriptHelper 호출 + 결과 매핑.
- **SettingsView → AppleScriptHelper.testConnection():** SET-05 버튼 액션. async 호출 + UI에 결과 반영.
- **HookListener/SessionRegistry → iTermSessionID.uuid(fromRaw:):** UUID 정규화 입구. 한 곳에서만 strip.
- **SessionStore.load → 마이그레이션:** `:` 포함 ID 발견 시 strip 후 in-memory 업데이트. 다음 persist 사이클에서 자동 정규화 저장.

### 관찰된 잠재 버그 (Phase 3가 해소)
- `App/AppleScriptHelper.swift:56` — `s == target` 비교가 D2-14/D2-15에서 항상 false. iTerm2 AppleScript `id of session` = UUID-only vs 저장된 `itermSessionID` = `wXtYpZ:UUID-XXXX` 풀 형식. D3-01..04로 자동 해소 + 회귀 테스트.

</code_context>

<specifics>
## Specific Ideas

- **사용자 결정 1:** "어댑터 자리만 만들고 v1은 iTerm2 단일 구현" → D-ADAPTER. v2 멀티-터미널(VSCode/JetBrains/Warp/Ghostty)은 `term_program` 분기 키 자리만 envelope에 마련.
- **사용자 결정 2:** "사용하던 세션이 꺼지면 클로드로 하고있던 작업도 중지되는거라 굳이 그 세션을 찾을라고 할필요가 있을까" → TTY 폴백 v1 제외. 터미널 사망 = Claude 사망 = Stop hook 미발사. 위젯이 떠 있는 상태에서 강제 종료 케이스만 좁은 예외. v2 후보(env-stripped shell만 추가).
- **사용자 결정 3:** "애니메이션 효과라던가 그런거로 넣을게" → "세션 없음" UX는 도리도리(±12° 0~0.3s) + collapse/fade(0.3~0.7s) 애니메이션 단일 처리. 텍스트 라벨 / 사운드 / 시스템 알림 모두 없음.
- **사용자 시나리오:** "켜져있는 iterm의 작업 완료를 알고싶은거" — 핵심 가치를 살아있는 iTerm2 탭 한정으로 정의. UUID 단일 매칭 충분 근거.
- **카운터팩트(귀여움 표현):** 사용자 본인이 "귀엽게 표현할 방법" 일찍 고민 → 결국 텍스트 대신 애니메이션 자체로 캐릭터성 살림. quick-260508-001(아이콘 통통 튀기) 톤과 일관.
- **UI 카피 톤 (memory 룰):** 위젯/팝오버/status 라벨은 minimal English + macOS-system tone, "session" 용어 (tab/terminal 대신). 이모지·체크마크·컬러 dot 등 데코 요소 지양. 권한 banner / 온보딩 같은 기존 한국어 영역은 톤 일관성으로 한국어 유지. D3-19 status 라벨이 이 룰의 1차 적용 대상.

</specifics>

<deferred>
## Deferred Ideas

### v2 (멀티-터미널 / TTY 폴백)
- **TTY 폴백 매칭** — env-stripped shell(nix-shell/devbox/컨테이너) 환경에서 `ITERM_SESSION_ID` 누락 시 hook envelope의 `tty` 필드로 iTerm2 sessions walk 매칭. v2 새 요구사항 제안 (`JUMP-FALLBACK-01`).
- **TokenEater 차용** (`kp_eproc.e_tdev` getProcessTTY / `osascript` -1743 subprocess 폴백 / `resolveHostApp`). v2에서 PID 역추적이 필요해질 때 검토. MIT 라이센스 출처는 README CREDIT (Phase 6 README 작성 시).
- **멀티-터미널 dispatch** (MTERM-01..04) — VSCode/JetBrains/Warp/Ghostty. D-ADAPTER seam이 마련되어 있으니 v2는 `TerminalJumper` 새 구현체 추가만.
- **PID 역추적** (envelope `tty` 누락 케이스). v2.

### Phase 4+
- **카운터 배지 UI** — Phase 4 명시 영역.
- **5+ 동시 완료 dedup, 10-hooks-in-100ms 스트레스** — Phase 4.

### Phase 6
- **TokenEater MIT 출처 README CREDIT 표기** — 차용 안 했어도 ROADMAP reference로 명시되었으니 출처 표기.
- **자체 클로드 아이콘 자산** — D2-12 그대로.

### 폴리싱 (Phase 6 직전)
- **위젯 아이콘 idle bob / 클릭 spring 등 추가 모션** — D2-11 그대로.

</deferred>

---

*Phase: 3-Click-to-iTerm2*
*Context gathered: 2026-05-08*
