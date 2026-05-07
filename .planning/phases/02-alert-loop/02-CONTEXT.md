# Phase 2: Alert Loop - Context

**Gathered:** 2026-05-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1의 hook → AF_UNIX listener 파이프 위에 시작/종료 상관, 임계값 필터, 영구 floating 위젯, 사운드, Settings를 얹어 "31초 Claude 턴이 끝나면 영구 위젯이 뜬다"를 처음으로 사용자가 눈으로 보게 만든다.

In scope:
- Reporter shell의 UserPromptSubmit hook 변형 (HOOK-02). D-08 envelope의 `event: "user_prompt_submit"` 변종을 같은 socket으로 송신
- App 측 SessionRegistry actor — in-flight 시작 + 완료-미클릭 큐의 단일 진실 source (SESS-01,02)
- sessions.json 영속화 — App 재시작 후 미클릭 alert 복원 (SESS-03)
- 6h 이상 in-flight 세션 GC (SESS-04)
- 임계값 필터 (default 30s, 사용자 변경 가능) (THR-01)
- THR-02 fallback: start 누락 Stop은 임계값 우회하고 항상 alert (`?` duration)
- Floating NSPanel 위젯 (`canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`, `level=.floating`, `.nonactivatingPanel`) (WIDG-01,02,04,05)
- 위젯 hover popover로 다중 보류 disambiguation (WIDG-03)
- 사용자 설정 가능 코너 + 오프셋, 노치/멀티 디스플레이 안전 영역 (WIDG-06,07)
- 사운드 1회 재생 + Settings 토글 (AUD-01,02)
- SwiftUI Settings scene + @AppStorage, 즉시 반영 + 영속 (SET-01,02,03), Test notification 버튼 (SET-04)

Out of scope (다른 Phase 명시 owning):
- iTerm2 jump 실제 동작 (Phase 3 ITermBridge)
- Apple Events 권한 다이얼로그 / NSAppleEventsUsageDescription 흐름 (Phase 3)
- 카운터 배지 (Phase 4 — Phase 2는 +N 텍스트 배지로 다중 표시)
- 5+ 동시 완료 dedup, 10-hooks-in-100ms 스트레스 (Phase 4)
- 자동 hook installer / first-run wizard / 멱등 JSON5 병합기 (Phase 5)
- .dmg 패키징 (Phase 6)

</domain>

<decisions>
## Implementation Decisions

### Reporter UserPromptSubmit (HOOK-02) (DISCUSSED — 잠금)
- **D2-01:** 같은 `Reporter/cab-report.sh`가 `claude_alert_bot_event` 환경변수 또는 첫 인자로 분기 — Stop과 UserPromptSubmit 분리 hook 등록은 같은 스크립트의 두 파라미터화 호출. D-08 envelope의 `event` 필드만 다르게. 새 스크립트 만들지 않음.
- **D2-02:** UserPromptSubmit 도착 시 App은 in-flight start로 등록. 동일 session_id의 pending Stop alert이 큐에 있으면 **조용히 큐에서 제거** (자동 정리 — D2-13 참조).

### Widget visual + multi-pending UX (DISCUSSED — 잠금)
- **D2-03:** 위젯은 **단일 floating NSPanel** 1개. 화면에 동시에 위젯이 여러 개 뜨지 않음. 보류 세션이 N≥2일 때 **+N 텍스트 배지**가 우상단 모서리에 작게.
- **D2-04:** 위젯 본체는 **아이콘만** 표시 (프로젝트명/경과시간 평소 노출 없음). 라벨 노출은 hover 트리거 전용.
- **D2-05:** **Hover popover** — 마우스가 위젯 위에 들어가면 옆/아래로 작은 popover 슬라이드 인. popover는 보류 큐를 FIFO 순으로 row 리스트.
- **D2-06:** popover row 표시 규칙:
  - **기본:** 프로젝트명만 (cwd basename 또는 CLAUDE_PROJECT_DIR basename)
  - **같은 프로젝트의 세션이 큐에 ≥2개 보류 중일 때만 그 row들에 한해:** Stop 시각을 작은 보조 라벨로 추가 (예: `claude_alert_bot · 10:42`). 다른 row는 깔끔하게 프로젝트명만 유지
  - row hover 시 살짝 강조 (배경색 미세 변화) — 마우스로 어느 row가 활성인지 명확
- **D2-07:** popover 우상단에 **"Clear all"** 버튼. 누적된 stale alert을 한 번에 비울 수 있는 안전망.
- **D2-08:** Phase 2에서 row 클릭 = dismiss + 로그 (`[would-jump session=<uuid>]`). Phase 3 ITermBridge가 이 자리 인계 (시그니처 보존).
- **D2-09:** 큐가 비면 위젯 자연스럽게 사라짐. 큐에 1개만 남으면 +N 배지 사라짐 (단순 아이콘만).
- **D2-10:** popover row의 hover 미리보기(터미널 활성 표시)는 Phase 3 결정 영역 — Phase 2에서는 미루지 말고 단순 강조만.

### 위젯 시각 보강 (DISCUSSED — 일부 뒤로)
- **D2-11:** **아이콘 자체의 애니메이션 (idle bob, 클릭 spring 등) 및 화면 내 "돌아다니는" 모션**은 Phase 2 범위에서 제외 (deferred — 기능 가치보다 폴리싱). Phase 6 직전에 다시 검토. Phase 2는 정적 위젯 + 등장/퇴장만 자연스러운 fade/slide.
- **D2-12:** 아이콘 아셋은 **placeholder SF Symbol** (`bell.badge.fill` 또는 `bubble.left.fill`)로 시작. Phase 6 직전에 자체 제작 chat-bubble glyph로 교체. D-06(Anthropic 로고 금지) 준수.

### 자동 정리 + Stop 시점 suppress — 3계층 (DISCUSSED — 잠금)
사용자가 이미 그 세션을 보고 있는 경우와 이미 끝난 세션으로 돌아간 경우 양쪽을 cover. ROADMAP 변경 — Apple Events 권한 도입을 Phase 2로 당김 (D2-33 참조).

- **D2-13 (1차 — UserPromptSubmit auto-clear, passive):** 새 UserPromptSubmit이 어떤 session_id로 도착하면, 그 session_id의 pending Stop alert을 SessionRegistry actor 내에서 조용히 큐에서 제거. visual 알림 없음. 큐가 비면 위젯이 자연스럽게 사라짐. False-positive 0 — UserPromptSubmit = 사용자가 명백히 그 세션을 다시 활용 중.
- **D2-14 (2차 — Stop 도착 시점 cheap-query suppress):** Stop 이벤트 도착 시 백그라운드 큐에서 AppleScript read-only 쿼리 (현재 frontmost iTerm2 탭의 unique ID) 실행 → pending session의 `iterm_session_id`와 매칭하면 alert을 큐에 추가하지 않고 즉시 dismiss + OSLog `pre-suppress`. visual + 사운드 둘 다 안 뜸. 사용자 입장에서 "이미 보고 있던 작업이 끝났을 때는 알람이 침묵".
- **D2-15 (3차 — NSWorkspace activate observer):** 이미 큐에 있는 alert에 대해, frontmost 앱이 변경되는 순간(`NSWorkspace.didActivateApplicationNotification`) 재쿼리 → frontmost가 그 세션 탭이 되면 자동 정리. 사용자가 alert 뜬 후 그 터미널로 직접 이동한 경우를 cover.
- **D2-15a:** 3계층 모두 실패하는 case ("그저 읽고자 탭 전환만 + 입력 안 함 + Apple Events denied" 등): +N 배지로 누적 시각화 + Clear all 버튼이 안전망.

### Apple Events 권한 도입 (Phase 3 → Phase 2 당김) (DISCUSSED — 잠금)
ROADMAP 원안은 NSAppleEventsUsageDescription을 Phase 3에 두었으나, "사용자가 보고 있는 터미널의 알림 침묵"이 Phase 2의 핵심 가치 보존(노이즈 vs 놓치지 않음 균형)에 결정적이라 도입 시점을 Phase 2로 이동.

- **D2-33:** **`NSAppleEventsUsageDescription` Info.plist 키 도입.** 사용자에게 신뢰감 있는 한국어 문구: 예시 — "Claude Alert Bot이 iTerm2의 현재 탭을 확인해서 이미 보고 있는 작업의 알림을 끄고, 클릭 시 정확한 탭으로 이동하기 위해 사용합니다." (Phase 3에서 jump가 추가될 때를 미리 포함하는 표현).
- **D2-34:** **AppleScript read-only 쿼리 helper.** 단일 컴파일된 `NSAppleScript` 인스턴스 (Phase 1 D-07 패턴 재사용). 쿼리 형태: `tell application "iTerm2" to return id of current session of current tab of current window` (또는 동등). 호출은 항상 백그라운드 DispatchQueue + **1초 hard timeout** (Stop 알림 latency 예산 보호 — Phase 3의 jump-시 3초보다 훨씬 짧아야 함). Pitfall #10 (main-thread block) 차단.
- **D2-35:** **첫 권한 trigger 시점.** App 첫 launch 직후 cheap-query 1회 발사 → macOS가 권한 다이얼로그 표시. 사용자가 첫 alert을 받기 전에 권한 결정이 끝난 상태가 이상적. Settings → "Test notification" 버튼은 이미 권한이 grant된 상태에서 동작.
- **D2-36:** **Denial 상태 처리.**
  - cheap-query가 errAEEventNotPermitted (-1743) 반환 → SettingsStore에 `applescript_permission = .denied` 영속.
  - Settings 윈도우 상단에 배너: "Automation 권한 없음 — alert이 이미 보고 있는 작업에서도 뜹니다. 클릭으로 시스템 설정 열기 →" (System Settings → Privacy & Security → Automation deep link).
  - denied 상태에서는 D2-14/D2-15 layer가 silent skip (Pitfall #4 안전망). D2-13(UserPromptSubmit)은 권한 무관하게 동작.
  - README troubleshooting에 `tccutil reset AppleEvents <bundle-id>` 명령 추가 (Phase 5 ONB-04와 동일 텍스트).
- **D2-37:** **OSLog category 추가:** `applescript`. 모든 cheap-query 시도/성공/실패/timeout/permission-denied 기록. Phase 4 stress 디버깅 시 필요.

### Phase 3로 잔존하는 범위 (정정)
ROADMAP Phase 3는 여전히 **focus-jump 자체** + 그 주변 폴리싱을 owning. Phase 2가 Apple Events 권한·read-only 쿼리만 가져옴.
- 실제 jump (focus tab) AppleScript 명령 (Phase 3)
- TTY-기반 fallback lookup — `iterm_session_id`가 hook 시점에 캡처되지 않은 경우 (Phase 3, JUMP-05)
- 3초 hard timeout, 클릭 debounce (500ms), background queue 디테일 (Phase 3, Pitfall #10)
- Tab-not-found 친절한 에러 ("That terminal is gone") (Phase 3, JUMP-02)
- popover row hover 시 즉시 점프 미리보기 등 UX 폴리싱 (Phase 3 검토)
- Settings의 "iTerm2 connection test" 버튼 (Phase 3 — JUMP-04, 당기지 않음. Phase 2의 첫 launch trigger가 그 역할 일부 흡수)

### THR-02 fallback (start 누락) (DISCUSSED — 잠금)
- **D2-16:** Stop이 매칭 UserPromptSubmit 없이 도착 시 → **임계값 필터 우회하고 항상 alert**. 경과시간은 `?`로 표시. ROADMAP 성공 기준 #6 default 그대로. "절대 silently drop 안 함"이 PROJECT.md "놓치지 않는다" 가치 직접 구현.
- **D2-17:** 추정 경과 (예: ppid lifetime 기반)는 시도하지 않음 — 정확도 부족 + 복잡도 추가. `?`가 정직.

### Sound during Focus/DnD (DISCUSSED — 잠금)
- **D2-18:** **시스템 존중 + 사용자 Settings 우선:**
  - 사용자 Settings의 사운드 토글이 1차 권한 (off면 무조건 무음)
  - 사운드 on이라도 macOS Focus/DnD 활성 시 자동 음소거 (위젯 visual은 유지). `NSWorkspace.shared.focusStatus` (macOS 14+) 또는 동등 API로 cheap check
  - DnD 중에도 알림 자체는 visual로 잔존 → 핵심 가치 보존, 청각만 정중하게 양보
- **D2-19:** UNNotificationSound 채널은 사용 안 함 (배너 자동 dismiss 위험). AVAudioPlayer 직접 재생.

### AUD-01 "사운드 1회" dedupe (DISCUSSED — 잠금)
- **D2-20:** dedupe 키 = `(session_id, ts_round_to_2s)`. 같은 세션의 Stop이 2초 내 두 번 들어와도 사운드는 한 번. Phase 4의 광범위 dedupe key (transcript_path 포함)는 호환되게 확장 가능 — 같은 자리에서 추가 component만 붙임.

### Test notification UX (DISCUSSED — 잠금)
- **D2-21:** Settings의 "Test notification" 버튼은 **socket 우회**, SessionRegistry actor에 합성 CompletedSession을 직접 inject → 정상 알림 경로(위젯 + 사운드 + popover)를 탄다. 프로젝트명은 `"Test"`로, session_id는 `test-{uuid}` prefix로 식별 가능. **자동 정리: 30초 후 또는 사용자 클릭 시.**
- **D2-22:** Test 알림은 sessions.json에 영속되지 않음 (in-memory only) — 재시작 후 복원되면 혼란.

### sessions.json 영속성 atomicity (DISCUSSED — 잠금)
- **D2-23:** **atomic rename pattern.** 매 상태 변경 시 `sessions.json.tmp`에 write → `rename(2)` 시스템 콜로 atomic swap (NSFileManager의 atomic write 옵션 또는 직접 FileHandle + rename). macOS APFS rename은 atomic. throttle 없음 (인간 이벤트 빈도라 충분).
- **D2-24:** App 시작 시 `sessions.json.tmp` 잔재 발견 시 무시하고 정식 파일 로드 (fsync 직전 충돌 흔적).
- **D2-25:** 파일 위치: `~/Library/Application Support/ClaudeAlertBot/sessions.json` (D-10 socket과 동일 디렉터리, 권한 0700).

### 위젯 위치 (WIDG-06,07) (Claude's Discretion — 합리적 기본값 잠금)
- **D2-26:** **기본 코너: Top-Right.** macOS 시스템 토스트/알림 관습 + iTerm2/Xcode 등 좌상단 점유 회피. 사용자가 Settings에서 4코너 중 1개 선택 가능.
- **D2-27:** 기본 오프셋: 코너에서 inset 16pt (top/right 각각). 사용자가 1pt 단위 슬라이더 또는 stepper로 조정.
- **D2-28:** **노치/멀티 디스플레이 안전 영역 처리:** `NSScreen.safeAreaInsets`(macOS 12+) 사용 + 사용자 오프셋 합산 시 항상 safe area 안에 clamp. 다중 디스플레이는 *위젯이 등장한 시점의 main display* 기준으로 고정 (이후 디스플레이 추가/제거에는 반응 안 함, Phase 4+ 검토).

### Settings 아키텍처 (Claude's Discretion — 잠금)
- **D2-29:** SwiftUI `Settings { … }` scene + `@AppStorage`. 외부 의존성 0 (sindresorhus/Defaults 등 채택 안 함 — 4개 설정으로 과도).
- **D2-30:** `SettingsStore` ObservableObject가 도메인 로직(임계값 적용, dedupe key 빌드 등) 보유. View → Store → Registry로 단방향 의존. UserDefaults 직접 접근은 Store 안에서만.

### Logging / 디버깅 (Claude's Discretion — 잠금)
- **D2-31:** Phase 1의 OSLog subsystem `com.claudealert.bot.hook`을 그대로 확장. category 추가: `registry`, `notification`, `widget`, `settings`. log show 명령으로 디버깅 가능.
- **D2-32:** `~/Library/Logs/ClaudeAlertBot/hook.log`는 Reporter 전용 디버그 로그 그대로 유지 (Phase 1 D-07 #2). App 측 로그는 OSLog만.

### Claude's Discretion
다음은 사용자가 별도 지시하지 않은 항목 — 합리적 기본값으로 진행:

- 위젯 그림자/배경: `.thinMaterial` blur background, subtle drop shadow. macOS 표준 floating panel look.
- 위젯 모서리 둥글기: 14pt (macOS 14 NSPanel 표준).
- 등장/퇴장 애니메이션: 200ms ease-in-out fade + 4pt slide-down (등장) / fade-up (퇴장).
- popover slide-in 방향: 위젯 코너에 따라 자동 (TR 코너면 왼쪽, TL이면 오른쪽 등).
- 사운드 파일: macOS 시스템 사운드 한 종 (예: `/System/Library/Sounds/Funk.aiff`). 자체 사운드 자산은 Phase 6에서.
- UserPromptSubmit hook timeout: Stop hook과 동일 5초 (Phase 1 D-08 정책 재사용).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level (always read)
- `.planning/PROJECT.md` — Core value (정확한 그 세션으로의 점프), Constraints, Out of Scope
- `.planning/REQUIREMENTS.md` — 53 v1 REQ-IDs; Phase 2가 cover하는 20개: HOOK-02, SESS-01..04, THR-01..02, WIDG-01..07, AUD-01..02, SET-01..04
- `.planning/ROADMAP.md` §"Phase 2: Alert Loop" — 6개 success criteria + Locked Architectural Decisions

### Prior phase (Phase 1, 직접 의존)
- `.planning/phases/01-foundation/01-CONTEXT.md` — D-08 envelope schema, D-09 single-instance lock, D-10 socket path. Phase 2는 이 결정들 위에 그대로 올림.
- `.planning/phases/01-foundation/01-VERIFICATION.md` — Phase 1 phase_gate green 증거. Phase 2는 이 파이프가 동작한다고 전제.
- `.planning/phases/01-foundation/01-RESEARCH.md` — NWListener 패턴, Pitfall #9 (concurrency race), Pitfall #10 (AppleScript main-thread block — Phase 3에서 본격 등장)
- `.planning/phases/01-foundation/01-03-SUMMARY.md` §"HookListener.swift" — actor 기반 리스너 코드. Phase 2의 SessionRegistry actor가 이 패턴 모델로 사용

### Research (Phase 2 직접 관련)
- `.planning/research/STACK.md` §"Floating widget" — `NSPanel` 서브클래스, `level=.floating`, `collectionBehavior` 조합
- `.planning/research/STACK.md` §"Sound" — AVAudioPlayer 추천, NSSound 경고 (macOS 26 CoreAudio init crash)
- `.planning/research/STACK.md` §"Settings UI" — SwiftUI Settings scene + @AppStorage 표준
- `.planning/research/ARCHITECTURE.md` §"Two-process architecture" — Reporter ↔ App 분리 그대로, SessionRegistry는 App 내부
- `.planning/research/ARCHITECTURE.md` §"Session Identity" — session_id 매칭 정책 (Phase 3에서 더 깊이 다룸, Phase 2는 큐 키만)
- `.planning/research/PITFALLS.md` #1 (NSPanel `.nonactivatingPanel`) — WIDG-02 직접 매핑
- `.planning/research/PITFALLS.md` #6 — Settings → Registry 단방향 의존
- `.planning/research/PITFALLS.md` #9 — concurrency race; Phase 4에서 본격 stress 테스트, Phase 2는 actor 적용으로 사전 대응

### External docs (verify during planning)
- [Apple — NSPanel](https://developer.apple.com/documentation/appkit/nspanel) — `.nonactivatingPanel`, `becomesKeyOnlyIfNeeded`
- [Apple — NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) — `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`
- [Apple — NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/3852476-safeareainsets) — 노치 처리
- [Apple — NSWorkspace focusStatus](https://developer.apple.com/documentation/appkit/nsworkspace/focusstatus) — Focus/DnD 감지 (macOS 14+)
- [Apple — AVAudioPlayer](https://developer.apple.com/documentation/avfaudio/avaudioplayer) — 사운드 재생
- [Apple — SwiftUI Settings scene](https://developer.apple.com/documentation/swiftui/settings) — Settings 윈도우
- [Claude Code hooks: UserPromptSubmit](https://code.claude.com/docs/en/hooks) — payload shape, timeout 정책 검증

### Phase 1 carry-over follow-ups (Phase 2가 인계)
- **V-2 (listener uptime polish):** Phase 1 verifier review에서 식별. Phase 2 실 구현 중 SessionRegistry 부팅 ~ HookListener bind 사이의 race window를 close. (Phase 2가 명시적으로 owning)
- **V-7 (hook command path quoting):** 1de1c8e에서 dev-install-hook.sh 핫픽스 + verify_1_04_02 회귀 가드 완료. Phase 5의 정식 INST-01..04 in-app installer 작성 시 같은 quoting 패턴 적용 필수.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (Phase 1에서 이미 존재)
- `App/HookListener.swift` — NWListener AF_UNIX 구현. Phase 2의 새 코드는 이게 받은 envelope을 SessionRegistry actor로 dispatch만 하면 됨.
- `App/HookEvent.swift` — D-08 envelope decoder. Phase 2는 `event: "user_prompt_submit"` variant를 같은 decoder로 처리.
- `App/SocketPaths.swift` — `~/Library/Application Support/ClaudeAlertBot/`를 anchor로 사용. sessions.json도 같은 디렉터리에.
- `App/AppDelegate.swift` — App lifecycle. Settings scene 추가 + 위젯 WindowController 부착 자리.
- `CabTest/main.swift` — synthetic envelope sender. Phase 2의 통합 테스트 (UserPromptSubmit + Stop 시퀀스 시뮬)에 재사용.
- `Reporter/cab-report.sh` — Stop hook 동작 검증됨. Phase 2는 같은 스크립트의 UserPromptSubmit 분기 추가만.

### Established Patterns
- **Swift `actor`로 mutable shared state:** Phase 1 HookListener가 actor (race-free). Phase 2 SessionRegistry도 같은 패턴.
- **OSLog subsystem `com.claudealert.bot.hook`:** Phase 2는 categories 추가만 (`registry`, `notification`, `widget`, `settings`).
- **Atomic file ops:** Phase 1은 socket bind exclusivity로 single-instance. Phase 2는 sessions.json도 atomic rename으로.
- **D-08 envelope schema_version 검증:** Phase 1 listener가 unknown schema_version reject. Phase 2는 그대로 활용 + UserPromptSubmit 분기 처리.
- **ad-hoc codesign + LSUIElement=true:** Phase 1 이래 invariant. Phase 2는 새 Settings 윈도우가 등장해도 LSUIElement 유지 (Settings는 명시적 사용자 액션 시에만 표시).

### Integration Points
- **HookListener → SessionRegistry:** 새 dispatch edge. event 타입에 따라 `registerStart(session_id, ts)` 또는 `recordStop(session_id, ts, cwd)` 호출.
- **SessionRegistry → NotificationOrchestrator:** Stop이 임계값 통과하면 NotificationOrchestrator에 alert 위임. Settings 변경 즉시 반영을 위해 SettingsStore 주입.
- **NotificationOrchestrator → FloatingWidgetWindowController + AVAudioPlayer:** 위젯 표시 + 사운드 재생.
- **AppDelegate → SessionRegistry (재시작 복원):** App 시작 시 sessions.json 로드, 미클릭 alert 큐 복원, 6h+ in-flight GC.
- **SettingsStore ↔ @AppStorage:** UserDefaults 키는 Store 내부에 한정. ObservableObject로 Registry/Orchestrator/Widget에 broadcast.

</code_context>

<specifics>
## Specific Ideas

- 사용자 의지: "위젯이 귀엽게 돌아다녔으면 좋겠다" 라는 정성적 선호 → Phase 2에서는 deferred (D2-11), Phase 6 직전 폴리싱 라운드에서 재검토. "정확한 세션 disambiguation"이 그보다 우선이라는 사용자 본인의 prioritization 결정.
- 사용자 시나리오: "여러 터미널에서 작업이 비슷한 타이밍에 끝나는 경우" — 같은 프로젝트 다중 세션을 명시적으로 가정한 popover row 표시 규칙(D2-06)이 이 시나리오 직접 대응.
- 사용자 시나리오: "사용자가 아이콘 클릭 안 하고 터미널로 바로 가버리는 경우" — UserPromptSubmit auto-clear (D2-13) + Clear all 버튼(D2-07)으로 stale alert 누적 방지.

</specifics>

<deferred>
## Deferred Ideas

- **위젯 아이콘 애니메이션 / 화면 내 모션 ("귀여운 클로드"):** Phase 2 범위에서 제외. Phase 6 직전 폴리싱 라운드에서 재검토. (D2-11)
- **자체 제작 chat-bubble glyph 아이콘 아셋:** Phase 2는 SF Symbol placeholder. 실 아이콘 자산은 Phase 6 직전. (D2-12)
- ~~iTerm2 frontmost / tab-level 감지 기반 자동 정리: Phase 2에 도입 안 함~~ — **결정 번복 (D2-13~15, D2-33~37):** Apple Events 권한 도입을 Phase 2로 당김. 3계층 정리(UserPromptSubmit + Stop 시점 cheap-query + NSWorkspace activate observer) 모두 Phase 2 범위. Phase 3는 **jump 자체**와 주변 폴리싱만 owning.
- **Counter badge UI (Phase 4 owning):** Phase 2의 +N 텍스트 배지는 임시 형태. Phase 4가 정식 카운터 배지 + 더 풍부한 popover로 교체.
- **다중 디스플레이 동적 추적:** 위젯 등장 시점 main display 고정. 디스플레이 추가/제거 반응은 Phase 4+ 검토. (D2-28)
- **추정 경과 시간 (start 누락 시):** ppid lifetime 등 휴리스틱 도입하지 않음. `?` 그대로. (D2-17)
- **카운터 배지 + 동시 다중 위젯:** Phase 4 명시 영역 (5+ 동시 완료 dedup, 10-hooks-in-100ms 스트레스).

</deferred>

---

*Phase: 2-Alert Loop*
*Context gathered: 2026-05-07*
