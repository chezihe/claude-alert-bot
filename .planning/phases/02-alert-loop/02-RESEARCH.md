# Phase 2: Alert Loop - Research

**Researched:** 2026-05-07
**Domain:** macOS native UI (NSPanel + SwiftUI interop), Swift `actor` concurrency, AppleScript permission flow, atomic file persistence
**Confidence:** MEDIUM-HIGH (stack pre-locked; two material gaps surfaced — Focus/DnD API + NSPopover-on-nonactivatingPanel composability — flagged as blocking spikes for Wave 0)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Reporter UserPromptSubmit (HOOK-02)
- **D2-01:** 같은 `Reporter/cab-report.sh`가 `claude_alert_bot_event` 환경변수 또는 첫 인자로 분기 — Stop과 UserPromptSubmit 분리 hook 등록은 같은 스크립트의 두 파라미터화 호출. D-08 envelope의 `event` 필드만 다르게. 새 스크립트 만들지 않음.
- **D2-02:** UserPromptSubmit 도착 시 App은 in-flight start로 등록. 동일 session_id의 pending Stop alert이 큐에 있으면 **조용히 큐에서 제거** (자동 정리 — D2-13 참조).

#### Widget visual + multi-pending UX
- **D2-03:** 위젯은 **단일 floating NSPanel** 1개. 화면에 동시에 위젯이 여러 개 뜨지 않음. 보류 세션이 N≥2일 때 **+N 텍스트 배지**가 우상단 모서리에 작게.
- **D2-04:** 위젯 본체는 **아이콘만** 표시 (프로젝트명/경과시간 평소 노출 없음). 라벨 노출은 hover 트리거 전용.
- **D2-05:** **Hover popover** — 마우스가 위젯 위에 들어가면 옆/아래로 작은 popover 슬라이드 인. popover는 보류 큐를 FIFO 순으로 row 리스트.
- **D2-06:** popover row 표시 규칙: 기본은 프로젝트명만 (cwd basename 또는 CLAUDE_PROJECT_DIR basename). 같은 프로젝트의 세션이 큐에 ≥2개 보류 중일 때만 그 row들에 한해 Stop 시각 보조 라벨 추가. row hover 시 살짝 강조.
- **D2-07:** popover 우상단에 **"Clear all"** 버튼 (N≥2일 때만).
- **D2-08:** Phase 2에서 row 클릭 = dismiss + 로그 (`[would-jump session=<uuid>]`). Phase 3가 인계.
- **D2-09:** 큐가 비면 위젯 자연스럽게 사라짐. 큐에 1개만 남으면 +N 배지 사라짐.
- **D2-10:** popover row의 hover 미리보기는 Phase 2 단순 강조만, Phase 3 결정 영역.

#### 위젯 시각 보강
- **D2-11:** 아이콘 자체의 애니메이션 / 화면 내 모션 Phase 2 제외 (Phase 6 검토).
- **D2-12:** 아이콘 아셋은 **placeholder SF Symbol** (`bell.badge.fill`). Phase 6에서 자체 제작 chat-bubble glyph로 교체. Anthropic 로고 금지.

#### 자동 정리 + Stop 시점 suppress — 3계층
- **D2-13:** UserPromptSubmit auto-clear (passive) — 새 UserPromptSubmit으로 도착 session_id의 pending Stop alert을 SessionRegistry actor 내에서 조용히 제거. False-positive 0.
- **D2-14:** Stop 도착 시점 cheap-query suppress — 백그라운드 큐에서 AppleScript read-only 쿼리 (현재 frontmost iTerm2 탭의 unique ID) → pending session의 `iterm_session_id`와 매칭하면 alert 큐 추가 안 함 + OSLog `pre-suppress`. visual + 사운드 둘 다 안 뜸.
- **D2-15:** NSWorkspace activate observer — 큐에 있는 alert에 대해, frontmost 앱 변경 순간(`NSWorkspace.didActivateApplicationNotification`) 재쿼리 → frontmost가 그 세션 탭이 되면 자동 정리.
- **D2-15a:** 3계층 모두 실패 case는 +N 배지로 누적 시각화 + Clear all 버튼이 안전망.

#### Apple Events 권한 도입 (Phase 3 → Phase 2 당김)
- **D2-33:** `NSAppleEventsUsageDescription` Info.plist 키 도입 (한국어 user-trustworthy 문구).
- **D2-34:** AppleScript read-only 쿼리 helper. 단일 컴파일된 `NSAppleScript` 인스턴스. 백그라운드 DispatchQueue + **1초 hard timeout**. Pitfall #10 차단.
- **D2-35:** 첫 권한 trigger 시점 — App 첫 launch 직후 cheap-query 1회 발사.
- **D2-36:** Denial 상태 처리 — errAEEventNotPermitted (-1743) → `applescript_permission = .denied` 영속, Settings 배너 + System Settings 딥링크, denied 상태에서 D2-14/D2-15 layer silent skip, README troubleshooting.
- **D2-37:** OSLog category `applescript` 추가.

#### Phase 3로 잔존하는 범위
실제 jump (focus tab) AppleScript 명령, TTY-기반 fallback lookup, 3초 hard timeout · 클릭 debounce, Tab-not-found 친절한 에러, "iTerm2 connection test" 버튼, popover row hover 즉시 점프 미리보기.

#### THR-02 fallback (start 누락)
- **D2-16:** Stop이 매칭 UserPromptSubmit 없이 도착 시 → 임계값 필터 우회하고 항상 alert. 경과시간 `?` 표시.
- **D2-17:** 추정 경과 시도하지 않음.

#### Sound during Focus/DnD
- **D2-18:** 시스템 존중 + 사용자 Settings 우선. `NSWorkspace.shared.focusStatus` (macOS 14+) 또는 동등 API로 cheap check. DnD 중에도 visual 잔존.
- **D2-19:** UNNotificationSound 채널은 사용 안 함. AVAudioPlayer 직접 재생.

#### AUD-01 "사운드 1회" dedupe
- **D2-20:** dedupe 키 = `(session_id, ts_round_to_2s)`.

#### Test notification UX
- **D2-21:** Settings의 "Test notification" 버튼은 socket 우회, SessionRegistry actor에 합성 CompletedSession 직접 inject. 자동 정리: 30초 후 또는 사용자 클릭 시.
- **D2-22:** Test 알림은 sessions.json에 영속되지 않음 (in-memory only).

#### sessions.json 영속성 atomicity
- **D2-23:** atomic rename pattern. `sessions.json.tmp`에 write → `rename(2)`. throttle 없음.
- **D2-24:** App 시작 시 `sessions.json.tmp` 잔재 무시.
- **D2-25:** 파일 위치: `~/Library/Application Support/ClaudeAlertBot/sessions.json` (권한 0700).

#### 위젯 위치 (WIDG-06,07)
- **D2-26:** 기본 코너: Top-Right.
- **D2-27:** 기본 오프셋: 16pt inset. 1pt 단위 stepper.
- **D2-28:** `NSScreen.safeAreaInsets` (macOS 12+) 사용. 위젯 등장 시점 main display 기준 고정.

#### Settings 아키텍처
- **D2-29:** SwiftUI `Settings { … }` scene + `@AppStorage`. 외부 의존성 0.
- **D2-30:** `SettingsStore` ObservableObject가 도메인 로직 보유. View → Store → Registry 단방향. UserDefaults 직접 접근은 Store 안에서만.

#### Logging / 디버깅
- **D2-31:** OSLog subsystem `com.claudealert.bot.hook` 그대로 확장. category 추가: `registry`, `notification`, `widget`, `settings`, `applescript`.
- **D2-32:** `~/Library/Logs/ClaudeAlertBot/hook.log`는 Reporter 전용 그대로 유지. App 측 로그는 OSLog만.

### Claude's Discretion
- 위젯 그림자/배경: `.thinMaterial` blur background, subtle drop shadow, macOS 표준 floating panel look
- 위젯 모서리 둥글기: 14pt
- 등장/퇴장 애니메이션: 200ms ease-in-out fade + 4pt slide
- popover slide-in 방향: 위젯 코너에 따라 자동
- 사운드 파일: `/System/Library/Sounds/Funk.aiff`
- UserPromptSubmit hook timeout: Stop hook과 동일 5초

### Deferred Ideas (OUT OF SCOPE)
- 위젯 아이콘 애니메이션 / 화면 내 모션 ("귀여운 클로드"): Phase 6 (D2-11)
- 자체 제작 chat-bubble glyph 아이콘 아셋: Phase 6 (D2-12)
- Counter badge UI (Phase 4 owning): +N 텍스트 배지는 임시 형태
- 다중 디스플레이 동적 추적: Phase 4+ (D2-28)
- 추정 경과 시간 (start 누락 시): `?` 그대로 (D2-17)
- 카운터 배지 + 동시 다중 위젯 / 5+ 동시 dedup / 10-hooks-in-100ms 스트레스: Phase 4
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HOOK-02 | Reporter가 UserPromptSubmit hook으로도 실행되어 작업 시작 시점 전달 | Pattern 1 (Reporter argv branch) — 기존 `cab-report.sh`에 `EVENT="${1:-stop}"` 이미 존재; settings.json 등록 한 줄 추가만 필요 |
| SESS-01 | Swift `actor` SessionRegistry — 단일 진실 source | Pattern 2 (SessionRegistry actor) — Phase 1 HookListener pattern 확장; isolation으로 Pitfall #9 race 차단 |
| SESS-02 | 시작/종료 이벤트를 session_id로 상관 → 경과 시간 계산 | Pattern 2 — actor 내부 `inFlightStarts: [SessionID: Date]` dict; Stop 도착 시 lookup + 차감 |
| SESS-03 | sessions.json 원자적 영속화 | Pattern 5 (atomic-write) — `Data.write(to:options:[.atomic])` 사용. APFS 레벨에서 temp+rename |
| SESS-04 | 6h 이상 in-flight 세션 GC | Pattern 6 (GC across sleep) — DispatchSourceTimer + `NSWorkspace.didWakeNotification` + 이벤트 ingress 시 lazy 검사 (Pitfall #5 — sleep중 timer 정지) |
| THR-01 | 임계값 30s 기본 + 사용자 변경 가능 | Pattern 4 (SettingsStore single direction) — threshold 값을 actor 메서드 호출 시 인자로 전달 |
| THR-02 | start 누락 fallback — 임계값 우회, `?` duration | Pattern 2 — actor 내 "no start match → emit anyway with duration=nil" 분기 |
| WIDG-01 | NSPanel `canJoinAllSpaces` + `fullScreenAuxiliary` + `stationary` + `level=.floating` | Pattern 7 (FloatingWidgetPanel subclass) |
| WIDG-02 | 포커스 비탈취 (`.nonactivatingPanel`, `becomesKeyOnlyIfNeeded`) | Pattern 7 — style mask + `canBecomeKey/Main` override |
| WIDG-03 | 클로드 아이콘 + 작업 폴더명 표시 | Pattern 8 (NSHostingView SwiftUI host) — UI-SPEC: 위젯 본체는 아이콘만, 폴더명은 hover popover에서 |
| WIDG-04 | 사용자가 클릭할 때까지 잔존 | Pattern 7 — auto-dismiss 코드 없음, 큐 비면만 사라짐 (D2-09) |
| WIDG-05 | 평소 보이지 않음 | Pattern 7 — 초기 `orderOut(nil)`, 큐 비면 `orderOut(nil)` |
| WIDG-06 | 4 코너 + 오프셋 사용자 설정 | Pattern 9 (corner+offset positioning) — SettingsStore에서 enum + 두 stepper |
| WIDG-07 | 노치/멀티 디스플레이 안전 영역 | Pattern 9 — `NSScreen.safeAreaInsets` (macOS 12+) clamp |
| AUD-01 | 사운드 1회 재생 | Pattern 10 (AVAudioPlayer load-once) — dedupe key `(session_id, ts/2s)` actor 내 set |
| AUD-02 | 사운드 on/off 토글 | Pattern 4 — `@AppStorage("sound_enabled")` |
| SET-01 | SwiftUI Settings scene + @AppStorage | Pattern 4 — App lifecycle에 `Settings { ... }` 추가 |
| SET-02 | 설정 항목: 임계값 / 사운드 / 위젯 위치 | Pattern 4 |
| SET-03 | 설정 변경 즉시 반영 + 영속 | Pattern 4 — `@AppStorage` + `ObservableObject` `@Published` |
| SET-04 | "Test notification" 버튼 | Pattern 11 (synthetic injection) — actor에 합성 `CompletedSession` 주입 + 30s 자동 dismiss |
</phase_requirements>

## Summary

Phase 2는 Phase 1의 verified hook → AF_UNIX listener 파이프 위에 **(1) Swift actor SessionRegistry — 시작/종료 상관 + 임계값 필터 + dedupe + GC**, **(2) 단일 NSPanel floating widget + NSPopover hover UX + 사운드**, **(3) SwiftUI Settings scene + @AppStorage 영속**, **(4) AppleScript read-only "cheap-query" helper로 D2-13/14/15 3계층 자동 정리** 를 얹는다. 새 외부 의존성은 0 — AppKit / SwiftUI / AVFoundation / Foundation / Network.framework / `NSAppleScript` (Carbon 잔존 API) 모두 macOS 14 SDK에 포함.

**핵심 리스크 영역 3개 (실 구현 전 spike 권장):**
1. **CONTEXT D2-18의 `NSWorkspace.shared.focusStatus`는 공개 API가 아님** [VERIFIED: Apple 공개 SDK 헤더, hackingwithswift forum, Apple Developer Forums]. macOS Focus 상태는 **공개 API 부재** (iOS/iPadOS는 `INFocusStatusCenter`만 존재). Phase 2는 사운드 토글 단일 권한으로 fallback하거나, UNUserNotificationCenter 채널을 별도 사운드 통로로 도입해야 함 — D2-19 ("UNNotificationSound 채널 사용 안 함")와 충돌. **Discuss-phase round 2에서 사용자 확인 필수.**
2. **NSPopover는 비-activating panel에서도 포커스를 가져갈 수 있음** [VERIFIED: 다수 Apple Developer Forum 보고]. `.transient` behavior로 완화되지만 NSTextField가 들어가면 first responder 거부됨. Phase 2 popover는 텍스트 입력 없이 row 리스트만이라 영향 작지만, 위젯 NSPanel `.nonactivatingPanel` 본문이 hover 시 일시적으로 활성화될 수 있음 — Wave 0 spike에서 행동 검증 + 실패 시 "sibling NSPanel 두 번째" fallback 패턴 (참고: Pattern 8a).
3. **System Settings 딥링크 URL이 macOS Sequoia(15)에서 변경됨** [VERIFIED: GitHub StellarSand/privacy-settings, Apple Developer Forums #761193]. Ventura form `com.apple.preference.security?Privacy_Automation` (CONTEXT D2-36 명시) 대신 Sequoia form `com.apple.settings.PrivacySecurity.extension?Privacy_Automation`을 시도해야 함. Phase 2는 두 URL을 순차 시도하는 helper 패턴 권장.

**Primary recommendation:** Wave 0(테스트 + 환경 + 위 3개 spike)을 먼저 통과시킨 뒤, Wave 1=Reporter UserPromptSubmit 분기 + SessionRegistry actor + sessions.json, Wave 2=NSPanel + NSHostingView + Popover + 위치 계산, Wave 3=AVAudioPlayer + Settings UI + cheap-query helper + Test notification, Wave 4=NSWorkspace observer + 시작-시 권한 trigger + 실 hook e2e. 각 Wave 끝에 phase 1 hook→listener 파이프가 그대로 동작하는지 회귀 가드.

## Architectural Responsibility Map

Phase 2는 단일-process desktop app 구조 (Reporter shell + App). "Tier"는 프로세스/도메인 경계로 대응:

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| UserPromptSubmit envelope 송신 (HOOK-02) | Reporter shell (POSIX `sh`) | — | hook은 Phase 1과 동일하게 thin shell. event 분기는 argv 한 글자 추가로 충분. App에 새 코드 X |
| 시작/종료 상관, 임계값, dedupe, GC, 영속 (SESS, THR, AUD-01 dedupe) | App 도메인 actor (SessionRegistry) | App persistence (sessions.json) | mutable shared state는 actor 단일 진실. 외부 노출은 await API. 영속은 actor 내부 구현 디테일 |
| 위젯 표시 + hover UX (WIDG, popover) | App UI tier (AppKit NSPanel) | App UI tier (SwiftUI inside NSHostingView) | 비-activating + multi-Space + hover = AppKit window primitive 필수. 컨텐츠는 SwiftUI |
| 사운드 재생 (AUD) | App UI tier (AVFoundation) | — | 위젯 표시와 같은 NotificationOrchestrator 안에서 트리거 |
| Settings UI + @AppStorage 저장 (SET) | App UI tier (SwiftUI Settings scene) | OS storage (UserDefaults via @AppStorage) | SwiftUI scene이 표준; 도메인 로직은 SettingsStore ObservableObject로 격리 |
| Apple Events read-only query (D2-14, 권한 trigger D2-35) | App AppleScript helper (background queue) | macOS TCC | NSAppleScript은 not-thread-safe — 전용 serial DispatchQueue. 결과는 actor에 await로 전달 |
| Frontmost app 감시 (D2-15) | App AppKit observer | NSWorkspace.shared.notificationCenter | NSWorkspace 표준 NotificationCenter 옵저버 |
| Persistence (sessions.json — SESS-03) | App storage (Foundation atomic write) | APFS | `Data.write(.atomic)`이 temp+rename을 내부적으로 수행 |

**Cross-cutting:**
- **OSLog logging:** 모든 tier가 Phase 1 subsystem `com.claudealert.bot.hook` 재사용, category만 분기 (`registry`, `notification`, `widget`, `settings`, `applescript`). 직접 stdout/stderr 출력 금지 (Phase 1 invariant).
- **Concurrency:** `actor` (registry) ↔ `MainActor` (UI/Settings) ↔ 전용 DispatchQueue (AppleScript) 3개 도메인 명확 분리. `NSWorkspace.didWakeNotification` 같은 외부 콜백은 항상 actor `await` boundary 통해 진입.

## Standard Stack

### Core (Phase 2 — all macOS 14 SDK, zero new external deps)

| Library / API | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| AppKit `NSPanel` (subclass) | macOS 14 SDK | Floating widget window primitive | SwiftUI `Window`/`MenuBarExtra`로 `canJoinAllSpaces`+`stationary`+`fullScreenAuxiliary` 동시 만족 불가 [VERIFIED: CLAUDE.md TL;DR row 2; Apple Forums; Cindori blog] |
| AppKit `NSHostingView` | macOS 14 SDK | SwiftUI 뷰를 NSPanel contentView로 호스팅 | NSPanel 안에 SwiftUI를 그리는 표준 다리 [VERIFIED: Apple docs] |
| AppKit `NSPopover` | macOS 14 SDK | Hover-revealed 보류 큐 row 리스트 | 표준 transient popover. **위험: 비-activating panel 위에서 포커스 동작 검증 필요** |
| AppKit `NSTrackingArea` | macOS 14 SDK | NSHostingView mouse-enter/exit 감지 | SwiftUI `.onHover`는 비-activating panel 안에서 신뢰 못함 — Wave 0 검증 권장 |
| AppKit `NSScreen.safeAreaInsets` | macOS 12+ | 노치/Dock/메뉴바 회피 위치 계산 | macOS 12 도입. 위젯 좌표 clamp의 표준 [CITED: developer.apple.com/documentation/appkit/nsscreen/3852476-safeareainsets] |
| AppKit `NSWorkspace.shared.notificationCenter` | macOS 14 SDK | `didActivateApplicationNotification` 옵저버 (D2-15) | 표준 — Phase 3가 같은 메커니즘 재사용 |
| AppKit `NSWorkspace.shared.notificationCenter` | macOS 14 SDK | `didWakeNotification` (GC 트리거) | sleep 중 DispatchSourceTimer 정지 보완 |
| Swift `actor` (Foundation) | Swift 5.10 | SessionRegistry — race-free 큐/state | Phase 1 HookListener에서 입증된 패턴 (PITFALLS.md #9 mitigation) |
| Swift `Codable` + `JSONEncoder/Decoder` | Foundation 14 | sessions.json 직렬화 | 표준; D-08 envelope decoder 이미 존재 |
| `Data.write(to:options:[.atomic])` | Foundation 14 | sessions.json atomic save | 내부적으로 temp+rename(2). APFS atomic. throttle 불필요 [CITED: developer.apple.com/documentation/foundation/data/3126839-write] |
| AVFoundation `AVAudioPlayer` | macOS 10.7+ | 1회 사운드 재생 | NSSound macOS 26 CoreAudio init crash 회피 [LOCKED: CLAUDE.md TL;DR row 6] |
| Carbon `NSAppleScript` (compile-once) | macOS 10.0+ | iTerm2 read-only 쿼리 (D2-14) — `tell application "iTerm2" to return id of current session of current tab of current window` | iTerm2 자동화 표준 surface; ScriptingBridge 헤더 churn 회피 [LOCKED: CLAUDE.md TL;DR row 5] |
| SwiftUI `Settings { … }` scene | macOS 13+ | 설정 윈도우 | 표준 — 외부 의존성 0 [LOCKED: CLAUDE.md TL;DR row 7] |
| SwiftUI `@AppStorage` | macOS 13+ | UserDefaults 영속 + ObservableObject 노출 | 4-5개 설정 항목에 적정 (Defaults 라이브러리 과잉) |
| Foundation `os.Logger` | macOS 11+ | 모든 App 로깅 | Phase 1 subsystem 재사용 |
| Foundation `Timer` / `DispatchSourceTimer` | macOS 14 SDK | 6h GC + Test notification 30s 자동 dismiss | sleep 시 정지 — `didWakeNotification` 보완 필수 |

### Supporting

| Library / API | Version | Purpose | When to Use |
|---------------|---------|---------|-------------|
| `NSVisualEffectView` (`.hudWindow`) | macOS 14 SDK | NSPanel HUD 머터리얼 (UI-SPEC) | NSHostingView 뒤에 한 장 — drop shadow는 시스템이 그려줌 |
| `NSAppearance` system colors | macOS 14 SDK | `controlAccentColor`, `systemRed`, `secondaryLabelColor` 등 | 다크모드 자동 적응 — 하드코드 hex 금지 (UI-SPEC) |
| `UNUserNotificationCenter` | macOS 14 SDK | (조건부) Focus/DnD 인지 사운드 채널 | **D2-19는 사용 안 함이지만, `NSWorkspace.focusStatus` 부재로 fallback 시 도입 검토 — discuss-phase 결정 필요** |
| `INFocusStatusCenter` (Intents) | iOS only / macOS X | macOS에서 사용 불가 [VERIFIED] | (대안 없음) |

### Alternatives Considered

(Stack의 대다수가 CONTEXT/CLAUDE.md에 잠금 — alternative 표는 잠금되지 않은 영역에만)

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `NSPopover` (D2-05 명시) | 두 번째 sibling NSPanel + NSTrackingArea로 popover 흉내 | NSPopover-on-nonactivatingPanel 행동이 Wave 0에서 깨질 경우 fallback. UI-SPEC 동일 시각 유지 가능. **MEDIUM 권고 — spike 결과로 결정** |
| `Data.write(.atomic)` | `FileManager.replaceItemAt(...)` | replaceItem은 fsync + 더 명시적 rename 시퀀스. 추가 안전성 미미. atomic 옵션이 표준 [LOW 권고] |
| `Timer.scheduledTimer` for 6h GC | `DispatchSourceTimer` only | Timer는 RunLoop 주기 의존. DispatchSourceTimer가 GCD 정밀도 우위. 둘 다 sleep 시 정지 → `didWakeNotification` 보완 필수 — 차이 사실상 0 |
| `NSWorkspace.focusStatus` (D2-18 명시) | 사운드 토글 단일 권한 + UNNotificationSound 채널 분리 (D2-19 번복) | **D2-18 자체가 존재하지 않는 API에 의존 — discuss-phase 재논의 필요** |

**Installation (Phase 2 추가 의존성):** **없음.** macOS 14 SDK + 기존 ad-hoc codesign 파이프라인으로 충분. Reporter shell은 Phase 1 그대로.

**Version verification (Phase 2 도입 신규 패키지):** N/A — 외부 패키지 0개.

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────┐  Stop hook
│ Claude Code      │ ─────────────►  Reporter (POSIX sh, Phase 1)
│ (in iTerm2 tab)  │  UserPromptSubmit (NEW — HOOK-02)
└──────────────────┘ ─────────────►   │
                                       │ printf JSON | nc -U $SOCK
                                       ▼
                                  AF_UNIX socket  (Phase 1, unchanged)
                                       │
                                       ▼
            ┌──────────────────────────────────────────────────┐
            │  HookListener (Phase 1 actor)                     │
            │  - decode HookEvent (D-08 envelope)               │
            │  - schema_version=1 guard                          │
            └────────────────┬─────────────────────────────────┘
                             │  await dispatch by event type
                             ▼
            ┌──────────────────────────────────────────────────┐
            │  SessionRegistry  (NEW Phase 2 actor)             │
            │  - inFlightStarts: [SessionID: Date]              │
            │  - completedQueue: [CompletedSession]              │
            │  - dedupeSet: Set<DedupeKey>  ((sid, ts/2s))       │
            │  - registerStart(...) / recordStop(...)           │
            │  - clearAll() / clearOne(...) / GC pass            │
            │  - persistTo(file) / restoreFrom(file)            │
            └──────┬─────────────┬──────────────────┬────────────┘
                   │             │                  │
       (D2-14 only)│             │                  │
                   ▼             ▼                  ▼
        ┌──────────────────┐  ┌────────────────┐  ┌──────────────────┐
        │ AppleScriptHelper│  │ NotificationOrch.│ │ Persistence       │
        │ (background      │  │ (MainActor)      │ │ (atomic write)    │
        │  serial queue,   │  │                  │ │ sessions.json     │
        │  1s timeout)     │  │  - showWidget()  │ │                   │
        └────────┬─────────┘  │  - playSound()   │ └──────────────────┘
                 │            │  - testInject() │
                 │ pre-suppress└──────┬───────────┘
                 │ result               │
                 ▼                      ▼
            ┌─────────────────────────────────────────┐
            │  FloatingWidgetWindowController          │
            │  - NSPanel subclass (.nonactivatingPanel)│
            │  - NSHostingView ← SwiftUI WidgetIcon    │
            │  - NSTrackingArea  → NSPopover (rows)    │
            │  - corner+offset positioning              │
            └─────────────────────────────────────────┘
                             ▲
                             │  NSWorkspace.didActivateApplicationNotification (D2-15)
                             │  → trigger AppleScriptHelper re-query
                             │
            ┌────────────────┴──────────────────────────────┐
            │  SettingsStore (ObservableObject, MainActor)   │
            │  - @AppStorage threshold/sound/corner/offset    │
            │  - applescript_permission status                │
            └──────────────────┬──────────────────────────────┘
                               │  bound via @StateObject
                               ▼
            ┌─────────────────────────────────────────┐
            │  SwiftUI Settings { ... } scene          │
            │  - Form with 4-5 sections                 │
            │  - PermissionBanner (conditional)         │
            └─────────────────────────────────────────┘
```

데이터 흐름 정리: **Reporter→listener→SessionRegistry actor→NotificationOrch.→FloatingWidget**가 정주류. 곁다리 두 개 — (1) AppleScriptHelper 가 Stop 도착 시 actor가 깨운 background query → 결과 actor에 await. (2) NSWorkspace observer가 frontmost 변경 알리면 actor에 await로 진입. SettingsStore 는 단방향 — actor와 NotificationOrch.가 임계값/사운드 토글을 *호출 시점에* 인자로 받아 읽음 (actor가 store ref를 보유하지 않음 — actor↔MainActor 경계 단순화).

### Recommended Project Structure

```
App/
├── (existing Phase 1)
│   ├── main.swift
│   ├── AppDelegate.swift           # +SessionRegistry boot, +NSWorkspace observer wire-up
│   ├── HookListener.swift          # +dispatch to SessionRegistry by event type
│   ├── HookEvent.swift             # unchanged (D-08 schema covers user_prompt_submit)
│   ├── SocketPaths.swift           # +sessionsJsonPath (~/Library/Application Support/...)
│   └── Info.plist                  # NSAppleEventsUsageDescription updated to D2-33 한국어 문구
├── Domain/                          # NEW
│   ├── SessionRegistry.swift       # actor — core of SESS-01..04, THR-01..02
│   ├── CompletedSession.swift      # struct — Codable; sessions.json row
│   ├── DedupeKey.swift             # AUD-01 key
│   └── SettingsStore.swift         # ObservableObject — @AppStorage adapters
├── Persistence/                     # NEW
│   └── SessionsPersistence.swift   # atomic load/save JSON
├── Notification/                    # NEW
│   ├── NotificationOrchestrator.swift  # MainActor — shows widget, plays sound
│   └── SoundPlayer.swift           # AVAudioPlayer wrapper
├── AppleScript/                     # NEW
│   ├── AppleScriptHelper.swift     # NSAppleScript compile-once, 1s timeout, BG queue
│   └── PermissionStatus.swift      # enum + System Settings deep-link helper
├── UI/                              # NEW (UI-SPEC components)
│   ├── FloatingWidgetPanel.swift          # NSPanel subclass (WIDG-01,02)
│   ├── FloatingWidgetWindowController.swift
│   ├── WidgetIconView.swift               # SwiftUI: SF Symbol + +N badge
│   ├── PopoverContentView.swift           # SwiftUI: rows + Clear all
│   ├── PopoverRowView.swift               # SwiftUI
│   ├── SettingsView.swift                 # SwiftUI: Form { Section x4-5 }
│   └── PermissionBannerView.swift
└── Lifecycle/                       # NEW
    └── WakeObserver.swift          # didWakeNotification → GC kick

CabTest/
└── main.swift                       # +UserPromptSubmit synthesizer (multi-event sequence test)

Reporter/
└── cab-report.sh                    # unchanged (argv branch already supports user_prompt_submit)

scripts/
├── dev-install-hook.sh              # +UserPromptSubmit hook block (Phase 2 dev-install)
└── verify-phase-2.sh                # NEW (Wave 0/4 verifier)

.planning/phases/02-alert-loop/      # plans, validation
```

### Pattern 1: Reporter argv Branch (HOOK-02)

**What:** 기존 `cab-report.sh`는 이미 `EVENT="${1:-stop}"`로 분기 구조를 가지고 있음. settings.json 등록 한 줄 추가만 필요.

```json
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh", "timeout": 5 }
      ]}
    ],
    "UserPromptSubmit": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh user_prompt_submit", "timeout": 5 }
      ]}
    ]
  }
}
```

[VERIFIED: code.claude.com/docs/en/hooks — UserPromptSubmit 이벤트는 매뉴얼에 문서화되어 있고 Stop과 동일한 stdin JSON shape (session_id, transcript_path, cwd, hook_event_name="UserPromptSubmit"). timeout 필드도 동일.]

**왜 Phase 2가 새 코드 추가 거의 없음:** 기존 Reporter가 첫 인자로 event 분기, D-08 envelope의 `event` 필드만 다르게 송출 — Phase 1 검증 끝.

**Phase 5 install (out of scope):** `dev-install-hook.sh`에 UserPromptSubmit 블럭 추가는 Phase 2 dev convenience이지만, 정식 멱등 병합은 Phase 5 INST-01..04.

### Pattern 2: SessionRegistry actor — single source of truth (SESS-01..04, THR-01..02)

**What:** Phase 1 `HookListener` actor와 동일 패턴. 모든 mutable shared state를 actor 안에. `await` boundary가 race를 차단 (Pitfall #9 mitigation).

```swift
// Domain/SessionRegistry.swift
import Foundation
import os

actor SessionRegistry {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "registry")
    private let persistence: SessionsPersistence
    private weak var notifier: NotificationOrchestrator?  // assigned post-init

    private struct InFlightStart { let startedAt: Date; let cwd: String? }
    private var inFlight: [String: InFlightStart] = [:]      // key=session_id
    private var completed: [CompletedSession] = []           // FIFO 큐
    private var dedupe: Set<DedupeKey> = []                  // (sid, ts/2s)

    init(persistence: SessionsPersistence) {
        self.persistence = persistence
    }

    func bind(notifier: NotificationOrchestrator) {
        self.notifier = notifier
    }

    /// HookListener → 여기로 진입 (await)
    func ingest(_ event: HookEvent, thresholdSeconds: Int, soundEnabled: Bool, suppressIfFrontmost: @Sendable (String?) async -> Bool) async {
        switch event.event {
        case "user_prompt_submit":
            handleStart(event)
        case "stop":
            await handleStop(event, thresholdSeconds: thresholdSeconds, soundEnabled: soundEnabled, suppressIfFrontmost: suppressIfFrontmost)
        default:
            log.warning("unknown event=\(event.event, privacy: .public)")
        }
    }

    private func handleStart(_ event: HookEvent) {
        guard let sid = event.session_id, let ts = parseTS(event.ts) else { return }
        // D2-13: 같은 sid의 pending Stop alert 조용히 제거
        let removed = completed.removeAll(where: { $0.sessionID == sid })
        // (실제: removeAll은 Bool 반환 X. count diff 사용)
        inFlight[sid] = InFlightStart(startedAt: ts, cwd: event.cwd)
        Task { await persistence.save(inFlight: inFlight, completed: completed) }
        // UI 업데이트는 notifier?.refreshFromRegistry() — actor → MainActor hop
        Task { await notifier?.refreshQueueState(completed: completed, count: completed.count) }
    }

    private func handleStop(_ event: HookEvent,
                            thresholdSeconds: Int,
                            soundEnabled: Bool,
                            suppressIfFrontmost: @Sendable (String?) async -> Bool) async {
        guard let sid = event.session_id, let stoppedAt = parseTS(event.ts) else { return }

        // D2-14 cheap-query suppress (only if grant; D2-36 — denied skips this layer)
        if await suppressIfFrontmost(event.iterm_session_id) {
            log.notice("pre-suppress session=\(sid, privacy: .public)")
            inFlight.removeValue(forKey: sid)
            return
        }

        // dedupe (AUD-01) — same (sid, ts/2s) seen?
        let key = DedupeKey(sessionID: sid, bucketedTS: Int(stoppedAt.timeIntervalSince1970) / 2)
        let isDup = !dedupe.insert(key).inserted

        // threshold + THR-02 fallback
        let durationSec: Int? = {
            guard let start = inFlight.removeValue(forKey: sid)?.startedAt else { return nil }
            return Int(stoppedAt.timeIntervalSince(start))
        }()
        let passes: Bool = {
            switch durationSec {
            case .some(let d): return d >= thresholdSeconds   // THR-01
            case .none:        return true                     // THR-02 — start 누락 시 항상 alert
            }
        }()
        guard passes else { return }

        let session = CompletedSession(sessionID: sid,
                                       projectName: deriveProjectName(event),
                                       stoppedAt: stoppedAt,
                                       durationSec: durationSec,
                                       itermSessionID: event.iterm_session_id,
                                       tty: event.tty,
                                       cwd: event.cwd)
        completed.append(session)
        await persistence.save(inFlight: inFlight, completed: completed)

        // UI/sound — single hop to MainActor via notifier
        await notifier?.present(session: session, playSoundOnce: soundEnabled && !isDup)
    }

    /// SESS-04 — caller가 wake/timer/ingress 시 호출
    func runGC(now: Date = Date()) async {
        let sixHours: TimeInterval = 6 * 3600
        let stale = inFlight.filter { now.timeIntervalSince($0.value.startedAt) > sixHours }
        for (sid, _) in stale {
            inFlight.removeValue(forKey: sid)
            log.notice("GC stale in-flight session=\(sid, privacy: .public)")
        }
        if !stale.isEmpty { await persistence.save(inFlight: inFlight, completed: completed) }
    }

    /// D2-13 / D2-15 / Clear all
    func clearOne(sessionID: String) async {
        completed.removeAll(where: { $0.sessionID == sessionID })
        await persistence.save(inFlight: inFlight, completed: completed)
        await notifier?.refreshQueueState(completed: completed, count: completed.count)
    }
    func clearAll() async {
        completed.removeAll()
        await persistence.save(inFlight: inFlight, completed: completed)
        await notifier?.refreshQueueState(completed: completed, count: completed.count)
    }

    /// D2-21 — Test notification (in-memory only, NOT persisted)
    func injectTest(soundEnabled: Bool) async {
        let session = CompletedSession.testFixture()
        completed.append(session)
        // NOT persisted (D2-22)
        await notifier?.present(session: session, playSoundOnce: soundEnabled)
        // 30s 후 자동 정리 (D2-21)
        let sid = session.sessionID
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            await self?.clearOne(sessionID: sid)
        }
    }
}
```

**Threshold 전달 규칙 (advisor 권고):** SettingsStore는 `@MainActor` ObservableObject. actor가 store 참조를 보유하면 actor 메서드 안에서 store 접근이 actor 경계 위반. **해결:** 호출 시점에 MainActor에서 값을 읽어 actor 메서드 인자로 전달 — 위 시그니처대로.

```swift
// HookListener.swift (Phase 2 patch — dispatch part)
private func handle(buffer: Data) {
    do {
        let event = try JSONDecoder().decode(HookEvent.self, from: buffer)
        guard event.schema_version == 1 else { /* drop */ return }
        Task { @MainActor in
            let threshold = SettingsStore.shared.thresholdSeconds
            let soundOn = SettingsStore.shared.soundEnabled
            let permGranted = SettingsStore.shared.applescriptPermission == .granted
            let helper = AppleScriptHelper.shared
            await SessionRegistry.shared.ingest(event,
                thresholdSeconds: threshold,
                soundEnabled: soundOn,
                suppressIfFrontmost: { iTermID async in
                    guard permGranted, let iTermID else { return false }
                    return await helper.frontmostMatches(itermSessionID: iTermID)
                })
        }
    } catch { /* log */ }
}
```

`@Sendable` closure는 MainActor에서 캡처한 `helper`/`permGranted` 값을 통해 actor 안에서 호출 가능 (helper 내부는 자체 dispatch queue로 격리).

### Pattern 3: NSAppleScript helper — compile-once, BG serial queue, hard timeout (D2-34)

**What:** AppleScript는 main thread 이외의 스레드에서 안전하지 않다 ([VERIFIED: Stairways Software 2014, 그러나 Apple 공식 가이드 문서는 부재]). **현실 운영 패턴:** AppleScript 전용 단일 *serial* DispatchQueue (concurrent global queue 사용 금지)를 만들고 모든 호출을 거기로 넣음. 컴파일된 NSAppleScript 인스턴스도 이 큐 안에서만 사용.

`executeAndReturnError`는 동기 + **timeout 없음** [VERIFIED: developer.apple.com/documentation/foundation/nsapplescript/1410034]. 1초 hard timeout은 두 층으로:

1. **AppleScript 자체의 `with timeout of 1 second ... end timeout`** — 스크립트 본문에 둠. 초과 시 errAEEventTimeout (-1712) 반환.
2. **Swift 측 `DispatchSemaphore.wait(timeout:)`** — AppleScript-side가 hang 시 Swift가 풀어줌 (단, 백그라운드 스크립트는 leak).

```swift
// AppleScript/AppleScriptHelper.swift
import Foundation
import os
import Carbon.OpenScripting   // for errAEEventNotPermitted (-1743), errAEEventTimeout (-1712)

actor AppleScriptHelper {
    static let shared = AppleScriptHelper()
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "applescript")
    private let queue = DispatchQueue(label: "com.claudealert.bot.applescript", qos: .userInitiated)
    private var compiled: NSAppleScript?
    private(set) var lastKnownPermission: PermissionStatus = .unknown

    /// One-time compile. Call from MainActor at app launch.
    private func ensureCompiled() {
        guard compiled == nil else { return }
        let src = """
        with timeout of 1 second
            tell application "iTerm2"
                if (count of windows) is 0 then return ""
                return id of current session of current tab of current window
            end tell
        end timeout
        """
        compiled = NSAppleScript(source: src)
        _ = compiled?.compileAndReturnError(nil)  // pre-compile
    }

    /// D2-14 — returns true iff frontmost iTerm2 session id matches `target`.
    /// Hard 1s timeout. Permission denial → returns false (silent skip per D2-36).
    func frontmostMatches(itermSessionID target: String) async -> Bool {
        ensureCompiled()
        guard let script = compiled else { return false }

        // run on dedicated queue with semaphore-based outer timeout
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            queue.async { [weak self] in
                guard let self else { cont.resume(returning: false); return }
                var errInfo: NSDictionary?
                let result = script.executeAndReturnError(&errInfo)
                if let err = errInfo {
                    let code = err[NSAppleScript.errorNumber] as? Int ?? 0
                    if code == -1743 {
                        Task { await self.markDenied() }
                        self.log.error("permission denied (-1743)")
                    } else if code == -1712 {
                        self.log.warning("AppleScript timeout (-1712)")
                    } else {
                        self.log.warning("AppleScript error code=\(code)")
                    }
                    cont.resume(returning: false); return
                }
                let s = result.stringValue ?? ""
                Task { await self.markGranted() }
                cont.resume(returning: !s.isEmpty && s == target)
            }
        }
    }

    /// D2-35 — first-launch permission trigger. Same script, no target match.
    func triggerPermissionPrompt() async {
        _ = await frontmostMatches(itermSessionID: "<no-match>")
    }

    private func markGranted() { lastKnownPermission = .granted }
    private func markDenied() { lastKnownPermission = .denied }
}
```

**Trade-off (advisor 권고 명시):** Swift 측 `DispatchSemaphore.wait(timeout:)`을 추가로 두면 AppleScript-side timeout이 실패해도 Swift 측이 풀려나지만, **그 호출은 BG queue에 leak**된다. Phase 2는 우선 AppleScript-side `with timeout of 1 second`만 사용 (가장 단순) → Wave 0 spike에서 실 hang 빈도 측정 → 필요 시 Swift-측 layer 추가. CONTEXT D2-34 "1초 hard timeout"는 양쪽 모두로 만족.

[VERIFIED: developer.apple.com/forums/thread/730884 — AppleScript safety thread; appscript.sourceforge.io/nsapplescript.html — compile-once recommended.]

### Pattern 4: SettingsStore + @AppStorage — single direction, no actor coupling

```swift
// Domain/SettingsStore.swift
import SwiftUI
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("threshold_seconds") var thresholdSeconds: Int = 30
    @AppStorage("sound_enabled") var soundEnabled: Bool = true
    @AppStorage("widget_corner") private var cornerRaw: String = WidgetCorner.topRight.rawValue
    @AppStorage("widget_offset_x") var offsetX: Int = 16
    @AppStorage("widget_offset_y") var offsetY: Int = 16

    var widgetCorner: WidgetCorner {
        get { WidgetCorner(rawValue: cornerRaw) ?? .topRight }
        set { cornerRaw = newValue.rawValue }
    }

    @Published var applescriptPermission: PermissionStatus = .unknown
    // ^ persisted separately via UserDefaults string (not @AppStorage to allow programmatic update from helper)
}
```

**Why MainActor singleton:** SwiftUI views 바인딩 + actor에서 호출 시점에 MainActor hop으로 값 한 번 읽기. actor가 store 참조를 보유하지 않음 → 경계 단순.

### Pattern 5: Atomic sessions.json persistence (SESS-03)

```swift
// Persistence/SessionsPersistence.swift
struct SessionsSnapshot: Codable {
    let schema: Int = 1
    let inFlight: [String: PersistedStart]
    let completed: [CompletedSession]
}

actor SessionsPersistence {
    private let url: URL
    init(url: URL) { self.url = url }

    func save(inFlight: [String: SessionRegistry.InFlightStart],
              completed: [CompletedSession]) async {
        let snap = SessionsSnapshot(...)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        // atomic = NSData writeToFile:options:NSDataWritingAtomic — temp + rename(2) on APFS
        try? data.write(to: url, options: [.atomic])
        // D2-25: directory perms 0700 already set in Phase 1 AppDelegate.ensureDirectories
    }

    func load() async -> SessionsSnapshot? {
        // D2-24 — *.tmp 잔재는 무시 (Foundation .atomic이 commit 전에는 .tmp 이름만 존재)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionsSnapshot.self, from: data)
    }
}
```

[VERIFIED: developer.apple.com/documentation/foundation/data/3126839-write — `.atomic` option: "An option to write data to an auxiliary file first and then exchange the files. This option is useful only for protecting the file's contents."]

**handler for corrupt file (UI-SPEC):** load 실패 시 OSLog `.error` + `sessions.json` → `sessions.json.corrupt-{ts}` rename + 빈 큐로 부팅 (UI에는 표시 안 함).

### Pattern 6: 6h GC across system sleep (SESS-04)

DispatchSourceTimer는 sleep 중 정지 [VERIFIED: Apple Developer Forums]. 따라서 **세 트리거** 조합:

1. **DispatchSourceTimer**: 30분 주기 GC kick (정상 가동 시 충분)
2. **`NSWorkspace.didWakeNotification` 옵저버**: wake 시 즉시 GC 1회 (밤새 sleep 후 회복)
3. **이벤트 ingress 시 lazy GC**: SessionRegistry.ingest의 첫 줄에서 마지막 GC 시점 확인 후 30분 이상이면 inline 호출

```swift
// Lifecycle/WakeObserver.swift
final class WakeObserver {
    private var token: NSObjectProtocol?
    init(onWake: @escaping () -> Void) {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in onWake() }
    }
    deinit { if let t = token { NSWorkspace.shared.notificationCenter.removeObserver(t) } }
}
```

### Pattern 7: FloatingWidgetPanel — NSPanel subclass (WIDG-01,02,04,05)

```swift
// UI/FloatingWidgetPanel.swift
import AppKit

final class FloatingWidgetPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.becomesKeyOnlyIfNeeded = true     // WIDG-02
        self.hidesOnDeactivate = false          // WIDG-04 — 다른 앱 활성화 시 사라지지 않음
        self.isMovableByWindowBackground = false
        self.hasShadow = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.acceptsMouseMovedEvents = true     // NSTrackingArea 보조
    }
    override var canBecomeKey: Bool  { false }   // WIDG-02 — 키 윈도우 자체가 안 됨
    override var canBecomeMain: Bool { false }
}
```

**왜 모든 플래그가 필요한지 다시:**
- `.borderless`: 타이틀바 / 시그널 영역 제거 — 둥근 14pt body만 노출
- `.nonactivatingPanel`: 패널 활성화가 앱 활성화로 번지지 않음 (Pitfall #1 mitigation)
- `level=.floating`: regular window들 위
- `.canJoinAllSpaces`: 모든 Space에 따라옴
- `.fullScreenAuxiliary`: Full Screen 앱 위에도 표시
- `.stationary`: Mission Control "이동하지 않음" 그룹 — Space 전환 시 위치 흔들림 방지
- `becomesKeyOnlyIfNeeded = true`: text input 등 명시적으로 필요한 경우만 키 (popover 안 텍스트 필드 가정 시 필요할 수 있으나 Phase 2 popover는 read-only)
- `canBecomeKey = false` override: 위 플래그를 belt-and-suspenders로 강제

[VERIFIED: developer.apple.com/documentation/appkit/nspanel; CLAUDE.md TL;DR row 2; Cindori "Make a floating panel" blog.]

### Pattern 8: NSHostingView로 SwiftUI 컨텐츠 + NSTrackingArea hover (WIDG-03)

```swift
// UI/FloatingWidgetWindowController.swift
final class FloatingWidgetWindowController: NSWindowController {
    private let registry: SessionRegistry
    private let store: SettingsStore
    private var trackingArea: NSTrackingArea?
    private var popover: NSPopover?
    private var hostingView: NSHostingView<WidgetIconView>?

    func updateContent(pendingCount: Int) {
        let view = WidgetIconView(pendingCount: pendingCount)
        if let hv = hostingView {
            hv.rootView = view
        } else {
            let hv = NSHostingView(rootView: view)
            hv.frame = NSRect(x: 0, y: 0, width: 44, height: 44)
            window?.contentView = hv
            installTrackingArea(on: hv)
            hostingView = hv
        }
    }

    private func installTrackingArea(on view: NSView) {
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let ta = NSTrackingArea(rect: .zero, options: opts, owner: self, userInfo: nil)
        view.addTrackingArea(ta)
        self.trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        // 150ms hover-intent delay (UI-SPEC)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
            self?.showPopoverIfStillHovered()
        }
    }
    override func mouseExited(with event: NSEvent) {
        // 250ms grace
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            self?.dismissPopoverIfNotInside()
        }
    }
}
```

**왜 SwiftUI `.onHover` 대신 NSTrackingArea:** advisor 권고 — `.onHover`는 비-activating panel + NSHostingView 조합에서 신뢰 못함 (mouseEntered 이벤트가 first responder 체인에 도달 못 할 수 있음). `NSTrackingArea(.activeAlways)` 명시 attach가 안전.

### Pattern 8a: NSPopover composability fallback (advisor flagged risk)

NSPopover가 `.transient` behavior + 비-activating panel 위에서 정상 동작하는지는 **Wave 0에서 spike 검증.** 실패 케이스 ("popover 띄우는 순간 Cmd-Tab에 앱이 등장한다"):

```swift
// Fallback: 두 번째 sibling NSPanel ("popoverPanel")
//  - 같은 styleMask (.nonactivatingPanel + .borderless)
//  - 위젯의 corner-relative 좌표로 자체 계산 위치
//  - SwiftUI ScrollView { rows } 그대로 호스팅
//  - 자체 NSTrackingArea로 mouseExited 시 orderOut(nil)
```

UI-SPEC의 모든 시각 사양은 동일 유지. 결정은 Wave 0 spike 결과 후.

### Pattern 9: Corner+offset positioning with safeAreaInsets clamp (WIDG-06,07)

```swift
// Inside FloatingWidgetWindowController
func reposition() {
    guard let panel = window, let screen = NSScreen.main else { return }
    let f = screen.visibleFrame                // Dock/MenuBar 자동 제외
    let safe = screen.safeAreaInsets           // notch
    let size = panel.frame.size
    let ox = max(CGFloat(store.offsetX), 0)
    let oy = max(CGFloat(store.offsetY), 0)
    let pos: NSPoint = {
        switch store.widgetCorner {
        case .topRight:    return NSPoint(x: f.maxX - size.width - max(ox, safe.right),
                                           y: f.maxY - size.height - max(oy, safe.top))
        case .topLeft:     return NSPoint(x: f.minX + max(ox, safe.left),
                                           y: f.maxY - size.height - max(oy, safe.top))
        case .bottomRight: return NSPoint(x: f.maxX - size.width - max(ox, safe.right),
                                           y: f.minY + max(oy, safe.bottom))
        case .bottomLeft:  return NSPoint(x: f.minX + max(ox, safe.left),
                                           y: f.minY + max(oy, safe.bottom))
        }
    }()
    panel.setFrameOrigin(pos)
}
```

[VERIFIED: developer.apple.com/documentation/appkit/nsscreen/3852476-safeareainsets — macOS 12+. Notch는 top inset ~38pt.]

### Pattern 10: AVAudioPlayer load-once

```swift
// Notification/SoundPlayer.swift
import AVFoundation

@MainActor
final class SoundPlayer {
    private var player: AVAudioPlayer?
    init() {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Funk.aiff")
        self.player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
    }
    func playOnce() {
        // 재생 중이어도 currentTime=0으로 다시 재생; 중복은 actor의 dedupe set이 차단
        player?.currentTime = 0
        player?.play()
    }
}
```

**Focus/DnD respect (advisor flagged blocker):** D2-18은 `NSWorkspace.shared.focusStatus` 참조하지만 **이 API는 macOS에서 공개되지 않음** [VERIFIED: hackingwithswift.com forums; Apple Developer Forums #682143; Apple AppKit headers]. `INFocusStatusCenter`는 iOS/iPadOS 전용. **Phase 2 가능한 path 3개:**

| Option | 동작 | Trade-off |
|--------|------|-----------|
| A. 사용자 토글 단일 권한 (D2-18 일부 폐기) | Settings 사운드 토글이 절대 권한. Focus/DnD 자동 무음 X | 단순. CONTEXT D2-18의 "DnD 자동 음소거" 약속 깨짐 |
| B. UNUserNotificationCenter 사운드 채널 분리 (D2-19 폐기) | UN sound는 Focus/DnD 자동 존중 + visual은 NSPanel 그대로 | CONTEXT D2-19와 정면 충돌 |
| C. private darwin notification 옵저빙 (`com.apple.donotdisturbActive`) | Focus 상태 추정 가능 | 비공개 API, macOS 버전 별 신뢰성 미보장. App Store 부적합 (out-of-scope) |

**Recommended path: A — 사용자 토글 단일 권한.** D2-18의 시스템 자동 음소거 부분만 폐기, AVAudioPlayer + 사용자 토글로 단순화. **이 결정은 discuss-phase round 2에서 사용자에게 surface 필수.** 본 RESEARCH는 A로 가정하고 진행하되, B 옵션도 코드 동등 비용으로 가능함을 명시.

### Pattern 11: Test notification synthetic injection (SET-04)

위 SessionRegistry `injectTest(soundEnabled:)` 메서드가 표준 알림 경로를 그대로 탐. project="Test", session_id="test-{uuid}", 30s 후 자동 정리. 하지만 sessions.json에 영속 안 함 (D2-22) — 위 코드의 `// NOT persisted` 주석 위치.

### Pattern 12: System Settings 딥링크 (D2-36)

macOS Sequoia(15)에서 URL 스킴이 변경됨. **Phase 2 helper는 두 형태를 순차 시도:**

```swift
enum PermissionDeepLink {
    static func openAutomationPreferences() {
        // Sequoia (15+) form, then Ventura/Sonoma (13/14) form
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
        ]
        for s in urls {
            if let u = URL(string: s), NSWorkspace.shared.open(u) { return }
        }
    }
}
```

[VERIFIED: github.com/StellarSand/privacy-settings (Sequoia URL list) + github.com/jaywcjlove/SystemSettings-URLs-macOS + Apple Developer Forums #761193 (URL scheme이 Settings extension 모델로 이동).]

### Anti-Patterns to Avoid

- **`@MainActor` ObservableObject가 `actor` reference를 직접 보유** — actor 메서드 호출 시 매번 `await` 필요한데 ObservableObject 프로퍼티 접근이 sync. 결과: SwiftUI 바인딩에서 actor 호출이 어색. → 위 Pattern 4의 단방향 (View → Store → 메서드 인자) 패턴으로 우회.
- **NSPopover의 contentViewController 안에 SwiftUI `Button` 클릭 → actor 메서드 직접 호출** — `Button`은 MainActor, actor는 `await`. SwiftUI에서 `Task { await ... }` 필수. 컴파일은 안 깨지지만 runtime에 클릭 → 무반응 함정. → 모든 row click 핸들러는 `Task { @MainActor in await registry.clearOne(...) }` 패턴.
- **NSHostingView에 SwiftUI `.onHover` 만으로 hover 처리** — advisor 권고: NSTrackingArea 명시 (Pattern 8). `.onHover`는 비-activating panel + LSUIElement 조합에서 mouseEntered가 first responder chain 도달 보장 X.
- **DispatchSourceTimer + 수면 후 자동 catch-up 가정** — sleep 중 timer 정지. wake 시 1회 GC가 안 돌면 하루 누적된 stale in-flight session이 남음. → Pattern 6의 3-트리거 조합.
- **`Process` + `osascript` subprocess 사용** — 매 호출 30-100ms 추가 + 전역 dispatch queue 위반. NSAppleScript 컴파일-once가 비교 불가하게 빠르고 안전. (CLAUDE.md TL;DR row 5 잠금)
- **위젯 등장 시 `NSApp.activate(ignoringOtherApps: true)`** — Phase 1 anti-pattern과 동일. Phase 2도 절대 금지. NSPanel `.nonactivatingPanel`이 정확히 이를 위한 것.
- **`Timer.scheduledTimer`로 30초 Test notification dismiss** — wake/sleep 영향. `Task.sleep(nanoseconds:)`가 Swift concurrency 표준. 위 SessionRegistry.injectTest 참조.
- **위젯 클릭에서 `Task` 안에 `await registry.clearOne(...)` 후 즉시 `panel.orderOut`** — actor await가 아직 미완 상태에서 UI 변경. 항상 await 결과를 기다리고 (또는 actor가 notifier로 다시 broadcast) UI 변경.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-Space-following floating window | SwiftUI `Window`/`WindowGroup` + 직접 level/collectionBehavior 시도 | NSPanel subclass (Pattern 7) | SwiftUI scene types는 `.canJoinAllSpaces` 등 핵심 플래그 미지원 (CLAUDE.md TL;DR + 다수 사례) |
| Mutable shared state across event sources | `@Published var queue` + DispatchQueue.main lock | Swift `actor` (Pattern 2) | Pitfall #9 — actor isolation이 race를 컴파일 타임에 차단 |
| Atomic file write | FileHandle + manual rename(2) wrapper | `Data.write(to:options:[.atomic])` | Foundation이 정확히 temp+rename을 수행. APFS atomic 보장 |
| AppleScript timeout | Swift Task.sleep + cancel | AppleScript-side `with timeout of 1 second ... end timeout` (Pattern 3) | 스크립트 본문 타임아웃은 AppleScript engine 내부에서 정확. Swift cancel은 BG queue leak 위험 |
| Hover detection on AppKit window | SwiftUI `.onHover` only | NSTrackingArea(.activeAlways) + override mouseEntered/Exited (Pattern 8) | 비-activating panel + NSHostingView 조합에서 SwiftUI hover 신뢰 X |
| Settings persistence | SQLite/Realm/직접 plist 읽기 | `@AppStorage` (Pattern 4) | 4개 키에 과잉. UserDefaults가 표준 |
| Sound playback | `NSSound("Funk").play()` | AVAudioPlayer (Pattern 10) | NSSound macOS 26 CoreAudio init crash; AVAudioPlayer가 안정 |
| iTerm2 query | iTerm2 Python API daemon, ScriptingBridge | NSAppleScript compile-once (Pattern 3) | Python API는 외부 daemon 운영 필요; ScriptingBridge 헤더 churn |
| Focus/DnD detection | private API darwin notification + heuristics | (None — public API 부재) → 사용자 토글 단일 권한 | 안정적 공개 API 부재; 사용자 토글이 Apple HIG 부합 |
| Multi-display tracking | Display reconfig observer + frame migration | 위젯 등장 시점 main display 고정 (D2-28) | Phase 4+로 미루는 것이 명시 결정 |
| 6h timer with sleep awareness | DispatchSource only | DispatchSource + didWakeNotification + ingress lazy GC (Pattern 6) | Timer가 sleep 중 정지 — 단일 트리거로는 상관 보장 X |
| Permission deep link | Hardcoded `com.apple.preference.security?Privacy_Automation` only | Sequoia + legacy 순차 시도 helper (Pattern 12) | URL 스킴이 macOS 15에서 변경됨 |

**Key insight:** Phase 2의 모든 신규 코드는 macOS 14 SDK가 이미 제공하는 surface로 100% 커버됨. 외부 의존성을 추가하면 ad-hoc codesign + LSUIElement + 외부 의존성 0 invariant 모두 깨질 위험. 모든 "Don't Build" 항목은 SDK 표준으로 1:1 매핑됨.

## Runtime State Inventory

> Phase 2는 신규 기능 추가 phase이며 rename/refactor가 아님 — 이 섹션은 SKIP 가능하지만, **새로 도입하는 runtime state 일람으로 활용**:

| Category | Items Introduced (Phase 2) | Action |
|----------|----------------------------|--------|
| Stored data | `~/Library/Application Support/ClaudeAlertBot/sessions.json` (NEW; D-25; 0700; atomic write); `~/Library/Application Support/ClaudeAlertBot/sessions.json.tmp` (transient — Foundation atomic write 내부 artifact) | Pattern 5; D2-24 무시 로직 |
| Live service config | UserDefaults keys: `threshold_seconds`, `sound_enabled`, `widget_corner`, `widget_offset_x`, `widget_offset_y`, `applescript_permission` (com.claudealert.bot domain) | `defaults delete com.claudealert.bot` 로 reset 가능; uninstall 시 (Phase 6 영역) 처리 |
| OS-registered state | `~/.claude/settings.json`의 UserPromptSubmit hook 항목 (Phase 2 dev-install-hook.sh가 추가; Phase 5 INST가 정식 멱등) | Phase 5 owning |
| Secrets/env vars | 없음 — Phase 2는 추가 secret 없음 | None |
| Build artifacts | `App/Domain/`, `App/Persistence/`, `App/Notification/`, `App/AppleScript/`, `App/UI/`, `App/Lifecycle/` (NEW Xcode targets / 새 .swift 파일 다수) | Xcode project에 add file; build.sh 변경 없음 |
| TCC permission | `tccutil` Apple Events DB에 `com.claudealert.bot → com.googlecode.iterm2` 항목 (D2-35 trigger) | Phase 2 README troubleshooting에 `tccutil reset AppleEvents com.claudealert.bot` 1줄 추가 |

## Common Pitfalls

### Pitfall 1: NSPanel `canJoinAllSpaces`가 macOS Stage Manager에서 깨짐 (해결됨)

**What goes wrong:** Stage Manager 활성 시 `.canJoinAllSpaces` 만으로는 Stage 전환 시 위젯이 따라가지 않음.

**Why it happens:** macOS 13에서 Stage Manager가 새로운 window scope를 도입했고 `.fullScreenAuxiliary` + `.stationary` 조합이 추가로 필요.

**How to avoid:** Pattern 7의 정확한 collectionBehavior 3-flag 조합. 하나라도 빠지면 깨짐.

**Warning signs:** Stage Manager 토글 + 위젯 등장 → 위젯이 다른 Stage에서 안 보임.

[VERIFIED: CLAUDE.md TL;DR row 2; ROADMAP locked decision.]

### Pitfall 2: NSPopover가 NSPanel `.nonactivatingPanel`에서 포커스를 일시적으로 가져감

**What goes wrong:** 위젯 hover → popover 등장 순간 NSApp이 active로 전환되어 Cmd-Tab에 등장. LSUIElement 가치 훼손.

**Why it happens:** NSPopover는 contentViewController hosting 시 자체 window를 만들고, `.transient` behavior에도 일시적으로 first responder chain을 형성함 [VERIFIED: 다수 Apple Developer Forum 보고 + frankrausch gist workarounds].

**How to avoid:**
- Wave 0 spike: 빈 NSPopover에 비어있는 `NSViewController` 띄우고 LSUIElement 앱이 Cmd-Tab에 나타나는지 확인
- 필요 시 Pattern 8a fallback: 두 번째 sibling NSPanel로 popover 흉내
- `popover.behavior = .transient`는 click-outside 자동 dismiss만 보장. focus 행동은 보장 X
- contentViewController 안 SwiftUI 뷰는 read-only — TextField 절대 금지 (first responder 충돌 외에도 search field는 NSPopover에서 첫 글자 후 키 빼앗김 알려진 버그)

**Warning signs:** popover 등장 시 Cmd-Tab 영구 등장 / 다른 앱 키보드 입력 빼앗김 / 위젯 자체가 활성화 후 그대로 머무름.

### Pitfall 3: NSAppleScript의 main-thread 호출이 main runloop을 spin함 (Pitfall #10 직접)

**What goes wrong:** Stop hook이 들어오자마자 SessionRegistry가 ingest 하면서 cheap-query를 main thread에서 호출 → iTerm2가 busy 상태면 1초 hang. Settings/widget UI가 동결.

**How to avoid:** Pattern 3의 전용 serial DispatchQueue + AppleScript-side `with timeout`. 호출 결과는 actor에 await로 전달. main thread는 await suspend point에서 자유롭게 양보.

**Warning signs:** Stop hook 처리 중 위젯이 늦게 등장 / Settings 클릭 무반응 1초+.

[VERIFIED: developer.apple.com/forums/thread/730884; stairways.com NSAppleScript not thread safe.]

### Pitfall 4: `Data.write(.atomic)` 직후 `defaults` cmd로 동시 변경 시 race

**What goes wrong:** sessions.json은 atomic이지만 UserDefaults 변경은 별도 store. 두 영속이 분리되어 일관성 없는 시점이 짧게 존재.

**How to avoid:** Phase 2는 둘이 의미적으로 독립 — sessions.json = 큐 상태, UserDefaults = 사용자 설정. 동시 변경 race는 시각적으로 안 보임. 그러나 SettingsStore.threshold 변경이 in-flight Stop 처리 도중에 일어나도 문제 없음 — 호출 시점 인자로 캡처 (Pattern 2).

### Pitfall 5: 6h GC가 sleep 후 catch up 안 됨

**What goes wrong:** 22시 in-flight 시작 → 노트북 닫음 → 다음 날 09시 열음. timer는 sleep 중 정지 → 6h 경과 detection이 wake 시 즉시 안 일어남 (다음 30분 tick까지 대기).

**How to avoid:** Pattern 6 — `didWakeNotification` 옵저버 + 이벤트 ingress 시 lazy GC.

**Warning signs:** 다음 날 새 UserPromptSubmit이 들어오는데 같은 session_id의 stale start가 어딘가에 남아 경과시간이 음수 / 비정상적 큰 값.

### Pitfall 6: NSPanel 위치가 디스플레이 detach 후 음수 좌표

**What goes wrong:** 외장 모니터에서 등장한 위젯의 좌표가 detach 후 main display 기준으로 -1200 등이 되어 invisible.

**How to avoid:** D2-28 결정대로 *위젯 등장 시점 main display 기준 고정*. Display reconfig observer는 Phase 2에서 도입 안 함. 단, 매 등장 직전 reposition 호출 → 등장 시점 NSScreen.main 기준으로 정상 좌표 재계산.

### Pitfall 7: SwiftUI `@AppStorage`가 nested struct 인코딩 X

**What goes wrong:** `WidgetCorner` enum을 `@AppStorage`에 직접 바인딩 시도 → 컴파일 X (RawRepresentable conformance 필요).

**How to avoid:** Pattern 4 — String raw value로 저장하고 computed var로 enum 변환. enum이 `String: RawRepresentable` 채택 시 직접 바인딩 가능하나 macOS 14에서 일관성 위해 String raw 저장이 안전.

### Pitfall 8: 첫 launch 권한 trigger가 사용자 컨텍스트 없는 다이얼로그 폭격

**What goes wrong (advisor 권고 surfacing):** D2-35 "App 첫 launch 직후 cheap-query 1회 발사" — 사용자 입장에서 앱을 처음 켜자마자 "Claude Alert Bot이 iTerm2 제어를 원함" 다이얼로그가 *아무 컨텍스트 없이* 등장. 신뢰감 낮음 → "Don't Allow" 클릭률 높음 (Pitfall #3 직접).

**Recommendation:** D2-35를 변경 검토 — 다음 두 트리거 중 하나에서 발사:
1. 사용자가 처음 Settings 윈도우 열었을 때 (또는 "Test notification" 클릭)
2. 첫 실 hook 이벤트 도착 시점 (실 작업 컨텍스트 있음)

D2-35 그대로 유지하면 D2-36 deny 처리 UI가 high-traffic이 됨 — 즉 **권한 거부는 정상 흐름이 되고, 배너가 자주 보이게 됨.** discuss-phase round 2에서 surface 권장.

### Pitfall 9: `applescript_permission` 영속이 actor 경계와 어긋남

**What goes wrong:** AppleScriptHelper는 `actor` (위 Pattern 3). lastKnownPermission은 actor isolation 안. SettingsView가 표시할 때는 ObservableObject `applescriptPermission`. 두 store 사이 sync 안 되면 배너가 stale.

**How to avoid:** AppleScriptHelper가 상태 전환 시 항상 MainActor hop으로 SettingsStore.applescriptPermission 업데이트:

```swift
private func markDenied() {
    lastKnownPermission = .denied
    Task { @MainActor in SettingsStore.shared.applescriptPermission = .denied }
}
```

### Pitfall 10: NSWorkspace activate observer가 wake 후 안 unsubscribe

**What goes wrong:** WakeObserver(token)을 deinit 시 remove 하나, AppDelegate가 NSWorkspace 옵저버 attach 후 weak self 캡처 안 하면 retain cycle.

**How to avoid:** observer block에서 `[weak self] _ in self?.handleActivate(...)` 명시. Phase 1 lifecycle 패턴 그대로.

### Pitfall 11 (Phase 1 carry-over V-2): Listener uptime / SessionRegistry boot race

**What goes wrong:** AppDelegate.applicationDidFinishLaunching에서 listener.start() 후 SessionRegistry.shared.bind(notifier:)가 끝나기 전에 hook 이벤트가 도착하면 ingress 시점에 notifier가 nil → silent drop.

**How to avoid:** boot 순서 명시:
1. SessionRegistry 인스턴스화
2. SessionsPersistence에서 restore (sessions.json → completed 큐 + inFlight)
3. NotificationOrchestrator 인스턴스화
4. registry.bind(notifier:)
5. listener.start()  ← 모든 의존성 wire-up 후

이 순서를 Phase 2 plan에 명시 + AppDelegate boot 시 순차 검증 (cab-test로 boot 직후 1ms 안에 fake event 보냄).

[Phase 1 follow-up V-2 reference: STATE.md → Phase-2-prep owning.]

### Pitfall 12: Stop dedupe key가 timestamp bucket 경계에서 깨짐

**What goes wrong:** D2-20 dedupe = `(session_id, ts/2s)`. 2초 경계에서 사용자가 정말 다른 두 작업을 빠르게 끝내면 다른 bucket → dedupe 안 됨 (의도된 동작). 그러나 *재시도* (Reporter retry) 가 정확히 2초 경계를 넘으면 dedupe 실패.

**How to avoid:** Phase 2는 의도대로 `ts_round_to_2s` 그대로 (Phase 4가 transcript_path 추가로 보강). Reporter는 retry 로직 없음 → 같은 hook fire에서 두 번 도착 사례 0. dedupe 의도는 "App 측에서 같은 hook의 빠른 중복 fire" 정도만 차단.

## Code Examples

(주요 코드는 위 Pattern 1~12에 인라인. 추가 — Settings UI 골격)

### SettingsView (Form, sections, banner) — UI-SPEC 매핑

```swift
// UI/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @StateObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            if store.applescriptPermission == .denied {
                Section { PermissionBannerView() }
            }
            Section("알림 임계값") {
                Stepper(value: $store.thresholdSeconds, in: 5...600, step: 5) {
                    Text("\(store.thresholdSeconds) 초")
                }
                Text("이 시간 이상 걸린 작업만 알려요")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("사운드") {
                Toggle("알림 사운드 재생", isOn: $store.soundEnabled)
            }
            Section("위젯 위치") {
                Picker("코너", selection: $store.cornerBinding) {
                    ForEach(WidgetCorner.allCases, id: \.self) { c in
                        Text(c.localizedLabel).tag(c)
                    }
                }
                Stepper("가로 오프셋: \(store.offsetX) pt", value: $store.offsetX, in: 0...64)
                Stepper("세로 오프셋: \(store.offsetY) pt", value: $store.offsetY, in: 0...64)
            }
            Section("테스트") {
                Button("테스트 알림 보내기") {
                    Task { await SessionRegistry.shared.injectTest(soundEnabled: store.soundEnabled) }
                }.buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, 32).padding(.horizontal, 24)
    }
}
```

### App entry — Settings scene + AppDelegate

```swift
// main.swift (Phase 2 변경)
@main
struct ClaudeAlertBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { SettingsView() }   // SwiftUI Settings scene → ⌘, 자동
    }
}
```

**Important:** 기존 main.swift은 pure-AppKit `app.run()`. Phase 2가 SwiftUI App life cycle 도입 시 LSUIElement + `setActivationPolicy(.accessory)` 동시 유지 검증 필요 (Pitfall #1). 또는 main.swift은 그대로 두고 AppDelegate.applicationDidFinishLaunching에서 NSWindow를 직접 만들어 Settings 윈도우 호스팅하는 비-Scene 패턴도 가능 — Phase 2 plan에서 결정.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSSound("Funk")` | `AVAudioPlayer(contentsOf: ...)` | macOS 26 (CoreAudio init crash 보고) | NSSound 신규 코드 회피; 기존 코드 audit |
| `Process` + `osascript` | `NSAppleScript` compile-once | 항시 (50-100ms 절감) | NSAppleScript 우선 |
| SwiftUI Window scene + windowLevel | NSPanel subclass | macOS 14까지도 SwiftUI scene이 collectionBehavior 미노출 | 모든 floating widget은 NSPanel |
| `NSWorkspace.shared.focusStatus` (없음) | (Public API 부재) | 항시 | macOS Focus는 사용자 토글 단일 권한 권장 |
| URL `com.apple.preference.security?Privacy_Automation` | `com.apple.settings.PrivacySecurity.extension?Privacy_Automation` | macOS 15 Sequoia | helper에 두 형태 순차 fallback |
| `--deep` codesign | per-Mach-O explicit codesign | TN3127 (deprecated since 13) | Phase 1 build.sh 이미 적용 |

**Deprecated/outdated:**
- NSSound for new code (macOS 26 crash; AVAudioPlayer만 사용)
- ScriptingBridge generated headers (iTerm2 자동화에서 churn — NSAppleScript만 사용)
- `Process` + `osascript` (NSAppleScript에 모두 outperformed)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | NSPopover가 `.transient` behavior + 비-activating parent panel에서 LSUIElement 안정성을 유지 | Pattern 8 (Wave 0 spike 권장) | 높음 — Cmd-Tab에 앱 등장. fallback Pattern 8a 필요 |
| A2 | macOS 14에 `NSWorkspace.shared.focusStatus` 공개 API 존재 (CONTEXT D2-18 명시) | Summary, Pattern 10, Don't Hand-Roll | **높음 — 검증 결과 존재 안 함**. discuss-phase 재논의. 추천 path: 사용자 토글 단일 권한 |
| A3 | `tell application "iTerm2" to return id of current session of current tab of current window`이 frontmost iTerm2 창의 ITERM_SESSION_ID와 정확히 매칭하는 UUID를 반환 | Pattern 3 (Wave 0 spike 권장) | 중간 — D2-14 자동 정리 동작 안 함. fallback: 사용자 토글 단일 권한 |
| A4 | macOS Sequoia(15+)에서 `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation` URL이 Automation pane을 직접 연다 | Pattern 12 | 중간 — UX 마찰. fallback: 일반 Privacy & Security 페이지 열기 |
| A5 | `Data.write(.atomic)`이 APFS에서 partial-write/crash 시점에 일관성을 보장 | Pattern 5 | 낮음 — Apple 공식 문서 명시. 단 외장 디스크 이외 |
| A6 | NSAppleScript `with timeout of 1 second` 블럭이 errAEEventTimeout (-1712)으로 정확히 1초 후 반환 | Pattern 3 | 낮음 — AppleScript engine 표준 동작. Wave 0 측정으로 확인 |
| A7 | UserPromptSubmit hook도 Stop과 동일한 envelope 5초 timeout 정책 | Pattern 1 | 낮음 — claude.com 공식 docs에 명시 |
| A8 | NSTrackingArea(.activeAlways)가 LSUIElement 앱 + 비-activating panel에서 mouseEntered/Exited를 수신 | Pattern 8 (Wave 0 spike) | 중간 — fallback: SwiftUI .onHover 시도. 둘 다 실패 시 timer-based polling |
| A9 | `NSScreen.safeAreaInsets`가 노치 없는 디스플레이에서 모두 0 반환 | Pattern 9 | 낮음 — Apple 문서 명시 |

## Open Questions (RESOLVED)

1. **D2-18 Focus/DnD 자동 음소거 — public API 부재**
   - What we know: `NSWorkspace.shared.focusStatus`는 macOS 공개 API가 아님. iOS/iPadOS의 `INFocusStatusCenter`는 macOS에 없음. private darwin notification 경로(`com.apple.donotdisturbActive`)는 신뢰성/공개성 부족.
   - What's unclear: 사용자 의도가 "Focus/DnD 자동 무음" 였는지 vs. "사운드 토글 + 사용자가 직접 끔" 만으로 충분한지.
   - Recommendation: discuss-phase round 2에서 사용자 surface. Phase 2는 우선 path A (사용자 토글 단일 권한)로 진행 가정.
   - **RESOLVED:** D2-18 RETRACTed in CONTEXT.md (commit 0e0b441) — public API does not exist; sound 재생은 사용자 사운드 토글 단일 권한으로 결정 (D2-19). Focus/DnD 자동 음소거는 Phase 2 범위에서 제외.

2. **D2-35 첫 launch 권한 trigger UX**
   - What we know: App 첫 실행 직후 cheap-query → macOS 권한 다이얼로그가 사용자 컨텍스트 없이 등장.
   - What's unclear: 사용자가 의도한 trigger 시점이 정말 "처음 실행 즉시"인지, 아니면 "첫 Settings 열기" / "첫 hook 도착" 인지.
   - Recommendation: discuss-phase round 2 surface. Pitfall #3 (Apple Events deny rate)가 직접 결정 변수.
   - **RESOLVED:** D2-35 hybrid locked in CONTEXT.md (commit 0e0b441) — Path A (Settings 첫 열림 trigger) implemented in plan 02-10 SettingsView.onAppear; Path B (첫 Stop hook lazy trigger) implemented in plan 02-11 HookListener dispatch. 사용자 컨텍스트 안에서 다이얼로그 등장.

3. **NSPopover composability with `.nonactivatingPanel`**
   - What we know: 다수 보고가 NSPopover focus 동작 결함을 시사.
   - What's unclear: `.transient` + read-only contentView 조합에서 LSUIElement 안정성 정확한 행동.
   - Recommendation: Wave 0 spike (1-2시간 prototype). 결과에 따라 Pattern 8 vs 8a 선택.
   - **RESOLVED:** D2-38 Wave 0 spike locked in CONTEXT.md (commit 0e0b441) — plan 02-01 = spike + checkpoint, 결과를 plan 02-08의 popover topology 결정으로 사용. Pattern 8 (NSPopover `.transient`) primary; Pattern 8a (custom NSWindow popover) as documented fallback.

4. **Phase 1 V-2 follow-up — listener boot ↔ SessionRegistry boot race**
   - What we know: STATE.md에 Phase-2-prep owning으로 명시.
   - What's unclear: 실 race window 크기 (μs ~ ms).
   - Recommendation: AppDelegate boot 순서 (Pitfall #11) 명시 + cab-test에서 boot-직후-1ms fake event burst test.
   - **RESOLVED:** Plan 02-11 AppDelegate boot order (Pitfall #11) — `await SessionRegistry.shared.restore()`가 `listener.start()` 이전에 동일 MainActor Task 안에서 실행되어 race window 닫힘. boot smoke + 02-11-99 Phase 1 회귀가 가드.

5. **macOS 14/15/26 Privacy_Automation deep link 행동 차이**
   - What we know: Sequoia URL 변경됨 + 일부 anchor가 OS별로 다름.
   - What's unclear: 정확히 어떤 macOS 버전에서 어떤 URL이 안전한가.
   - Recommendation: Pattern 12의 순차 fallback 패턴으로 강건. Wave 0에서 dev 머신 (실 macOS 버전) 1회 검증.
   - **RESOLVED:** D2-36 Pattern 12 sequential fallback locked. Plan 02-02가 `PermissionDeepLink` helper 구현 — Sequoia anchor URL 시도 → 실패 시 일반 Privacy & Security 페이지로 fallback. Wave 0 spike 4가 dev host 1회 검증.

6. **위젯 click handler의 actor await 완료 전 UI 상태**
   - What we know: 위젯 클릭 → actor.clearOne(...) await 완료 후 NotificationOrch가 refreshQueueState로 큐 비면 widget orderOut.
   - What's unclear: await 동안 사용자가 다시 클릭하면? (debounce는 Phase 3 JUMP-05의 영역; Phase 2 dismiss는 idempotent라 두 번 제거해도 안전 — 그러나 click 핸들러 시각 상태 검토 필요)
   - Recommendation: Phase 2는 click 핸들러에서 즉시 row를 popover에서 시각적으로 fade out + actor await 결과로 최종 상태 동기화. visual-vs-state 분리.
   - **RESOLVED:** Plan 02-08 idempotent click handler — row 즉시 fade-out (시각) + async actor.clearOne await (state). 두 번 클릭해도 actor가 idempotent라 안전. visual-vs-state 분리 명시.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 15.4+ | Build (Phase 2 Swift code) | (build host 가정) | 15.4+ | — |
| macOS 14+ runtime | NSPanel + Network.framework + NSScreen.safeAreaInsets + AVFoundation | (Phase 1 검증됨, dev host) | 14+ | LSMinimumSystemVersion=14 차단 (Info.plist 이미 설정) |
| iTerm2.app (running) | D2-14 cheap-query, D2-35 first-launch trigger | (CONSTRAINT 잠금: 사용자 환경) | 어떤 최신 버전이든 (AppleScript surface 안정) | 권한 미부여 / iTerm2 미설치 시 D2-14/D2-15 silent skip; visual 알림은 그대로 동작 (PROJECT.md 외부 의존 정책) |
| TCC Apple Events DB | NSAppleEventsUsageDescription 권한 부여 | (사용자 1회 dialog) | macOS 14+ | denied 시 D2-36 배너 + 시스템 설정 딥링크 |
| `~/.claude/settings.json` UserPromptSubmit 등록 | HOOK-02 trigger | (Phase 2 dev-install-hook.sh가 추가) | — | Phase 5 INST가 정식 멱등 등록 |
| Node `create-dmg` / Apple Developer ID | (Phase 6 영역) | N/A — Phase 2 무관 | — | — |

**Missing dependencies with no fallback:** 없음.

**Missing dependencies with fallback:**
- iTerm2 권한 거부 (denied) — D2-36 배너 + 시각 알림은 정상 동작 (cheap-query만 skip)

## Validation Architecture

> Validation strategy moved to `02-VALIDATION.md` (extracted by plan-checker fix-up).
> Phase 1 shape: see `.planning/phases/01-foundation/01-VALIDATION.md` as the template.

## Security Domain

(security_enforcement = true; security_asvs_level = 1)

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | 알림 도구. 사용자 인증 없음 |
| V3 Session Management | no | HTTP/web session 부재 |
| V4 Access Control | yes (제한적) | TCC Apple Events 권한 (D2-33,36). 시스템이 access control 담당 — 앱은 denial 처리만 |
| V5 Input Validation | yes (중요) | (a) D-08 envelope schema_version=1 거부 (Phase 1 invariant); (b) sessions.json load 시 corrupt 처리 → rename + 빈 큐로 시작; (c) UserDefaults 값에 enum/range guard (corner enum, threshold 5...600 스테퍼); (d) Reporter shell python json.dumps escape (Phase 1) |
| V6 Cryptography | no | 암호화 사용 없음. **절대 hand-roll 금지** |
| V7 Error Handling | yes | AppleScript denial silent skip + Settings 배너; sessions.json corrupt → OSLog .error + rename; SessionRegistry actor 에러는 항상 OSLog로 흘러나감 (silent failure 금지) |
| V8 Data Protection | yes (제한적) | sessions.json + UserDefaults 모두 user home 디렉토리 0700 perms. 패스워드/토큰 미저장. Application Support 디렉토리 perms는 Phase 1에서 0700 enforce 됨 |
| V9 Communication | yes (제한적) | AF_UNIX socket (Phase 1 0600 perm), 외부 네트워크 통신 0 |
| V10 Malicious Code | yes | 외부 의존성 0 (CLAUDE.md invariant). Phase 2도 npm/pip/SPM/CocoaPods 추가 안 함 |

### Known Threat Patterns for {macOS LSUIElement / Apple Events / atomic-write}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| sessions.json corruption mid-write (crash/disk full) | Tampering / Repudiation | `Data.write(.atomic)` — temp + rename(2). load 시 corrupt 검출 → rename + 빈 큐 |
| Malicious envelope inject via socket (third-party process bind) | Tampering / Spoofing | Socket file 0600 perm (user-only). schema_version 거부. 64KB cap (Phase 1) |
| AppleScript injection (envelope value를 AppleScript source 안으로) | Tampering | Pattern 3의 AppleScript은 read-only 쿼리, envelope 값을 source에 삽입 안 함 (target match는 Swift 측에서) |
| TCC bypass — denied 상태에서 D2-14 silent skip | Information Disclosure | denial 영속 + 배너 (D2-36) — 사용자에게 가시화 |
| Race condition (Pitfall #9 / SESS-01) | Tampering | actor isolation. Pattern 2 |
| @AppStorage value out-of-range (예: corner="invalid") | Tampering | enum init? + computed var fallback (Pattern 4) |
| sessions.json schema 변경 후 downgrade | Tampering | SessionsSnapshot.schema 필드 검사. 미래 schema는 빈 큐로 부팅 (또는 backup) |

## Project Constraints (from CLAUDE.md)

- **OS minimum:** macOS 14 Sonoma (Phase 2 모든 API가 14에서 안정)
- **터미널 지원:** iTerm2 only (D2-14 cheap-query는 iTerm2.app 가정)
- **Tech stack:** Swift / SwiftUI + AppKit interop (NSPanel + NSHostingView). **외부 Swift 의존성 0** (Phase 2도 sindresorhus/Defaults, KeyboardShortcuts 등 도입 안 함)
- **빌드 환경:** Xcode 15.4+. Phase 1 build.sh 그대로 사용
- **서명:** ad-hoc codesign (`codesign --force --sign - --options=runtime` per-Mach-O). Phase 1 적용 패턴 — 새 .swift 파일은 main 바이너리에 포함되어 자동 적용. cab-test도 그대로
- **Hook 등록:** Phase 2 dev convenience는 `dev-install-hook.sh`. 정식 멱등 자동 등록은 Phase 5 INST
- **AppleScript 권한:** D2-33 한국어 NSAppleEventsUsageDescription 강 권장 (현재 영문에서 번역 필요)
- **GSD Workflow Enforcement:** Edit/Write 전 GSD command로 시작. Phase 2는 `/gsd-execute-phase 2` 진입.

## Sources

### Primary (HIGH confidence — Apple official / Phase 1 verified)

- [Apple — NSPanel](https://developer.apple.com/documentation/appkit/nspanel) — `.nonactivatingPanel`, `becomesKeyOnlyIfNeeded`
- [Apple — NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) — `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`
- [Apple — NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/3852476-safeareainsets) — macOS 12+
- [Apple — NSAppleScript executeAndReturnError](https://developer.apple.com/documentation/foundation/nsapplescript/1410034-executeandreturnerror) — synchronous, no built-in timeout
- [Apple — Data.write options](https://developer.apple.com/documentation/foundation/data/3126839-write) — `.atomic` semantics
- [Apple — AVAudioPlayer](https://developer.apple.com/documentation/avfaudio/avaudioplayer)
- [Apple — SwiftUI Settings scene](https://developer.apple.com/documentation/swiftui/settings)
- [Apple — NSPopover](https://developer.apple.com/documentation/appkit/nspopover) — `.transient` behavior
- [Apple — NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) — notification center observers
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) — UserPromptSubmit shape, timeout, exit-code semantics
- `.planning/phases/01-foundation/01-RESEARCH.md` — Pattern 4 (NWListener), Pitfall #9, #10 anchors
- `.planning/phases/01-foundation/01-VERIFICATION.md` — Phase 1 phase_gate green 증거 (HookListener boot + envelope decode 검증됨)

### Secondary (MEDIUM confidence — community / multi-source verified)

- [Cindori — Make a floating panel in SwiftUI for macOS](https://cindori.com/developer/floating-panel)
- [Itsuki — SwiftUI/MacOS: Floating Window/Panel](https://levelup.gitconnected.com/swiftui-macos-floating-window-panel-4eef94a20647)
- [Stairways Software — NSAppleScript is Really Not Thread Safe (2014)](https://www.stairways.com/blog/2014-04-24-nsapplescript-not-thread-safe) — main thread + serial queue 권고
- [appscript — Using NSAppleScript](https://appscript.sourceforge.io/nsapplescript.html) — compile-once, error dictionary
- [github.com/StellarSand/privacy-settings — MacOS-Sequoia](https://github.com/StellarSand/privacy-settings/blob/main/Privacy%20Settings/MacOS-Sequoia.md) — Sequoia URL scheme 변경
- [Apple Developer Forums #761193 — SystemPreferences URL Scheme](https://developer.apple.com/forums/thread/761193) — extension 모델 변경
- [github.com/jaywcjlove/SystemSettings-URLs-macOS](https://github.com/jaywcjlove/SystemSettings-URLs-macOS) — URL scheme 매핑 표
- [Apple Developer Forums #730884 — How do I run AppleScript Safely inside my Swift app](https://developer.apple.com/forums/thread/730884) — main queue 권고
- [Apple Developer Forums — Where is the Focus Status API](https://developer.apple.com/forums/thread/682143) — macOS Focus public API 부재
- [hackingwithswift forums — API to detect focus mode](https://www.hackingwithswift.com/forums/swiftui/api-to-detect-focus-mode-personal-work-sleep-etc/25818) — INFocusStatusCenter는 iOS 전용

### Tertiary (LOW confidence — single source, Wave 0 spike로 검증 권장)

- NSPopover focus-stealing 보고서들 (frankrausch gist; MacRumors threads; dagronf blog) — 다수 일치하지만 macOS 14/15에서 명시 검증 부재
- `tell application "iTerm2" to return id of current session ...`이 ITERM_SESSION_ID 형식과 정확히 매칭하는지 — Wave 0 spike 필수
- private darwin notification `com.apple.donotdisturbActive` — macOS 14/15에서 신뢰성 — 본 RESEARCH는 사용 안 함 권고

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — CONTEXT/CLAUDE.md/ROADMAP 잠금 + Phase 1 검증된 패턴 재사용
- Architecture (SessionRegistry actor / NSPanel / SwiftUI Settings): HIGH — Apple 공식 docs + Phase 1 actor 패턴 직접 적용
- AppleScript helper (Pattern 3): MEDIUM — compile-once + serial queue + AppleScript-side timeout이 표준이지만 macOS 14에서 errAEEventTimeout 정확 동작은 Wave 0 측정 권고
- NSPopover composability (Pattern 8): MEDIUM-LOW — 다수 보고서 + Wave 0 spike 필수. fallback 8a 준비됨
- Focus/DnD (D2-18 path): LOW — public API 부재 명시 검증됨; **discuss-phase 재논의 필수**
- Pitfalls: HIGH — Phase 1 RESEARCH의 검증된 anti-patterns 직접 상속

**Research date:** 2026-05-07
**Valid until:** 2026-06-07 (30일 — macOS 14 SDK 안정 영역). 단 macOS Sequoia URL scheme 변경 같은 OS 업데이트 발생 시 Pattern 12 즉시 재확인 필요.
