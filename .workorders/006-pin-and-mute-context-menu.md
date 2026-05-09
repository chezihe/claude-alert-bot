# WO-006: Pin / Mute project (right-click context menu)

## Goal
사용자가 popover row 를 우클릭해서 두 가지를 할 수 있게 한다:
1. **Pin / Unpin** — 해당 세션을 popover 상단에 고정. Clear All 에도 살아남는다.
2. **Mute this project for 1h / Unmute this project** — 같은 프로젝트의 후속 알림을 1시간 동안 차단 (위젯 띄우지 않고, 사운드 안 남, 큐에도 추가 안 함).

데이터·상호작용·persistence 한 사이클로 닫는다. Settings 화면의 muted 목록 표시는 별도 WO.

## Context

(FEATURES.md §3 — Row interactions)
> Row 우클릭 시 컨텍스트 메뉴가 뜬다.
> - "Pin" / "Unpin" — 핀된 row 는 popover 상단에 고정, Clear All 에도 남는다.
> - "Mute this project for 1h" — 같은 프로젝트에서 들어오는 후속 알림을 1시간 차단.
> - 정확한 카피는 macOS 시스템 톤 (영어 미니멀, 이모지 금지).

(BACKLOG.md — 이번 WO 가 닫는 항목)
- Step 4 `[TODO] Right-click row menu is missing.` → DONE
- Step 4 `[TODO] "Mute this project for 1h" is missing.` → DONE
- Step 4 `[TODO] Pin/unpin row behavior and persistence are missing.` → DONE
- Step 5 `[PARTIAL] CompletedSession has 'available' (WO-002); kind/pinned/justArrived still missing — SessionRecord.swift.` → `pinned` 만 닫는다 (`justArrived` 별도 WO).
- Step 5 `[TODO] mutedProjects persistence is missing.` → DONE

(WO-004 / WO-005 결과 — 전제)
- `CompletedSession` 에 `available` (WO-002), `kind` / `exitCode` / `startedAt` / `lastOutput` (WO-004) 존재. 이번엔 `pinned: Bool` 추가.
- `Codable` legacy fallback 패턴 이미 자리잡힘 — `decodeIfPresent ?? <default>` 사용.

(현재 SettingsStore — `App/SettingsStore.swift` 발췌)
- `actor`-isolated `SettingsStore` (또는 `@MainActor` `ObservableObject`; Codex 가 확인). 기존 필드: `thresholdSeconds`, `soundEnabled`, `widgetCorner`, `offsetX`, `offsetY`. `applescriptPermission` 은 `Date?` 를 `@Published` + UserDefaults bridge 패턴으로 영속.
- 이번 WO 는 동일 bridge 패턴으로 `mutedProjects: [String: Date]` 추가 (project name → muteUntil timestamp).

(현재 ingest 경로 — `App/SessionRegistry.swift` `ingest_stop` 발췌)
```swift
let session = CompletedSession(
    sessionID: sid, projectName: projectName, stoppedAt: stoppedAt,
    durationSec: durationSec, itermSessionID: …, tty: …, cwd: …,
    kind: event.kind ?? .success, exitCode: …, startedAt: …, lastOutput: …
)
completed.append(session)
await persist()
let n = self.notifier
await n?.present(session: session, playSoundOnce: soundEnabled && !isDup)
```

(현재 Clear All — `App/WidgetPopoverController.swift` + `App/SessionRegistry.swift`)
- Popover 의 Clear All 버튼 → `SessionRegistry.shared.clearAll()` → `completed.removeAll()`.

(시각/거동 진실의 원천)
- `Claude Alert Bot - Prototype v2.html` — 우클릭 컨텍스트 메뉴, 핀 row 시각 (있다면).
- `SPEC.md` §3 row 컨텍스트 메뉴, §5 `mutedProjects` 영속.
- `FEATURES.md` §3 Row interactions, §5 Settings (mutedProjects 영속).

(AGENTS.md — binding)
- Min OS macOS 14, Swift 5.10+, no Sandbox, zero external Swift dependencies.
- Code Change Discipline (No Over-Editing): 최소 변경, 함수 시그니처/기본 인자/docstring 변경 금지 (본 WO 가 명시적으로 요구하지 않는 한).
- UI Copy: 영어 미니멀 톤, 이모지 금지, 컬러 dot 금지.

(스코프 명확화 — IN / OUT)
- **IN**: `pinned: Bool` 모델 필드 + persistence + ordering / Clear All exclusion. `mutedProjects: [String: Date]` SettingsStore 필드 + helpers + ingest_stop gating. 우클릭 contextMenu 와이어링 (4 항목: Pin/Unpin/Mute/Unmute).
- **OUT**: Settings 화면에 muted 프로젝트 목록 UI (별도 WO). Mute 지속시간 picker (1h 고정). 단축키. 드래그 reorder. 핀 시각 강조 (예: 핀 아이콘 prefix) — 별도 WO. justArrived, ripple, aging, Quiet Hours, popover geometry, empty state, gear icon. Reporter / hook payload 변경.

## Inputs

분석/수정 대상 (정확한 파일명·심볼은 Codex 가 확인 후 수정):

**모델·persistence**
- `App/SessionRecord.swift` — `CompletedSession` 에 `pinned: Bool` 추가. 기본값 `false`. Codable 누락 시 `false` 폴백 (`decodeIfPresent ?? false`). init 에 `pinned: Bool = false` 인자 추가 (다른 default 인자 위치·순서 그대로).
- `App/SessionStore.swift` — Codable 라운드트립 + legacy 폴백 (이전 영속 데이터에 `pinned` 키 없음 → 자동 false).
- `App/SettingsStore.swift` — `mutedProjects: [String: Date]` 추가. **`applescriptPermission` 의 `@Published` + UserDefaults bridge 패턴을 그대로 따른다** (Codable Dictionary 를 JSON-encoded `Data` 로 UserDefaults 에 저장). 신규 helpers:
  - `mute(project: String, duration: TimeInterval = 3600, now: Date)` — `mutedProjects[project] = now + duration`. Date injection 으로 테스트 가능하게.
  - `unmute(project: String)` — `mutedProjects.removeValue(forKey:)`.
  - `isMuted(project: String, now: Date) -> Bool` — `(mutedProjects[project] ?? .distantPast) > now`. 만료된 entry 는 read-time 에서 자연 제외.
  - (선택) `pruneExpired(now: Date)` — 만료 entry 청소. 임의 호출 (예: 다음 ingest 직전). 필수는 아님; 메모리 누수 방지용.

**상호작용·라우팅**
- `App/SessionRegistry.swift`:
  - `togglePin(sessionID: String)` 신규 actor-isolated 함수 — `completed[idx].pinned.toggle()`, `persist()`, `refreshQueueState`.
  - `clearAll()` 수정 — `completed.removeAll(where: { !$0.pinned })`. 핀 항목은 보존.
  - `ingest_stop` 수정 — settings 의 `isMuted(project: projectName, now: …)` 가 true 면 **enqueue·notifier present 모두 skip**. 단 in-flight 정리·logging 은 정상. 로그 라인 한 줄 추가 (예: `log.notice("ingest_stop muted project=…")`).
- `App/WidgetPopoverController.swift` (혹은 popover wiring 위치) — popover 의 두 신규 콜백을 SessionRegistry.shared / SettingsStore.shared 로 디스패치:
  - `onTogglePin(sessionID: String)` → `SessionRegistry.shared.togglePin(…)`
  - `onToggleMute(projectName: String)` → settings 가 muted 면 unmute, 아니면 mute 1h
- `App/PopoverContentView.swift` — pinned-first 정렬: `let ordered = queue.sorted { ($0.pinned, $0.stoppedAt) > ($1.pinned, $1.stoppedAt) }` 또는 두 단계 정렬 (`partition` + 안정 정렬). `ForEach(queue)` 를 `ForEach(ordered)` 로 바꾸기. **다른 row 렌더 로직 손대지 말 것**. 신규 콜백 두 개 prop 추가 → row 로 forward.
- `App/PopoverRowView.swift` — `.contextMenu { … }` 추가:
  ```swift
  .contextMenu {
      Button(session.pinned ? "Unpin" : "Pin") { onTogglePin() }
      Button(isMuted ? "Unmute This Project" : "Mute This Project for 1 Hour") { onToggleMute() }
  }
  ```
  카피 정확 매칭은 SPEC/Prototype 우선 — 차이 있으면 거기 맞춤. **다른 row 렌더·접근성·click handler·missing animation 손대지 말 것**.

**테스트**
- `ClaudeAlertBotTests/SessionRecordTests.swift` — `pinned` 누락 시 `false` 폴백, 라운드트립.
- `ClaudeAlertBotTests/SessionStoreTests.swift` — 이전 envelope 형식 (pinned 없음) 디스크 로드 → false.
- `ClaudeAlertBotTests/SettingsStoreTests.swift` — `mute/unmute/isMuted` 1h 만료 경계, 만료된 entry 가 isMuted=false, mute 가 UserDefaults round-trip 됨.
- `ClaudeAlertBotTests/SessionRegistryTests.swift`:
  - `togglePin` 이 persist 후 read 되는지
  - `clearAll` 이 핀 항목 보존
  - `ingest_stop` 이 muted project 일 때 `completed` append 안 함 + notifier present 안 호출됨 (test double / spy 활용)

읽어볼 것 (수정 X):
- `AGENTS.md`, `FEATURES.md` §3 §5, `SPEC.md`, `Claude Alert Bot - Prototype v2.html`.

## Deliverables

- [ ] `CompletedSession.pinned: Bool` (default false), Codable legacy fallback false, 라운드트립 테스트.
- [ ] `SettingsStore.mutedProjects: [String: Date]` 영속 (JSON-encoded UserDefaults via 기존 bridge 패턴) + `mute(project:duration:now:)`, `unmute(project:)`, `isMuted(project:now:)` helpers + 만료 경계 테스트.
- [ ] `SessionRegistry.togglePin(sessionID:)` 신규 + `clearAll` 이 핀 보존 + `ingest_stop` 이 muted 프로젝트 drop + 단위 테스트.
- [ ] PopoverContentView pinned-first 정렬 (안정 정렬, 같은 pinned 그룹 안에서는 stoppedAt desc 유지) + 두 신규 콜백 prop forward.
- [ ] PopoverRowView `.contextMenu` 4 항목 (Pin/Unpin/Mute/Unmute). 카피는 영어 미니멀 (이모지·컬러 dot 금지). 클릭 핸들러는 콜백 호출만 — 비즈 로직 직접 호출 금지.
- [ ] WidgetPopoverController 가 두 콜백을 SessionRegistry.shared / SettingsStore.shared 로 디스패치.
- [ ] 기본 동작 회귀 없음: 정상 `.success` row 클릭이 여전히 `TerminalJumper` 로 dispatch, missing animation 거동 그대로, unavailable hollow ring 그대로, status dot kind 색상 (WO-005) 그대로.

## Constraints (WO-specific)

- **다른 파일 손대지 말 것**: `App/HookEvent.swift`, `App/HookListener.swift`, `App/NotificationOrchestrator.swift`, `App/DesignTokens.swift`, `App/SettingsView.swift`, `App/FloatingWidgetWindowController.swift`, `App/WidgetIconView.swift`, `Reporter/*`, `scripts/*`. 빌드를 위해 import 가 필요한 read-only 참조는 허용.
- **카피**: 영어 미니멀 톤. SPEC/Prototype 에 명시된 라벨이 있으면 거기 정확 일치. 없으면 `"Pin"` / `"Unpin"` / `"Mute This Project for 1 Hour"` / `"Unmute This Project"` 사용. **이모지·컬러 dot 금지**.
- **Mute 지속시간 1h 고정** — picker / Settings UI 추가 금지 (별도 WO).
- **Settings 화면에 muted 목록 / 영구 mute 옵션 추가 금지**.
- **핀 아이콘 prefix·시각 차별화 추가 금지** — 이번엔 ordering + Clear All 보존만. 시각 강조는 별도 WO.
- **`justArrived`, `aging`, ripple, sonar, breathe, ring, roam, drift, Quiet Hours 추가 금지**.
- **`mutedProjects` 외 SettingsStore 신규 필드 추가 금지** (`reduceMotion`, `quietHours` 등은 별도 WO).
- **iTerm2 Python API 도입 금지** (AGENTS.md AVOID).
- 함수 시그니처·기본 인자·docstring 변경은 본 Deliverables 가 명시적으로 요구하는 경우에만.
- 무관 리팩터·rename·import 정렬·formatting 금지.

## Verification

- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` 성공.
- 단위 테스트: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` 모두 통과 (release 앱 종료 후. 환경 이슈 시 `CI=1 xcrun xctest …` fallback 허용).
- 수동 검증 (가능 시):
  1. row 우클릭 → "Pin" / "Mute This Project for 1 Hour" 메뉴 노출
  2. "Pin" 클릭 → 해당 row 가 popover 상단으로 이동, 다음 알림 들어와도 위에 머무름
  3. Clear All 클릭 → 핀 row 만 살아남음
  4. "Mute This Project for 1 Hour" 클릭 → 같은 프로젝트의 다음 Stop hook → 위젯 안 뜸 / 사운드 안 남 / 큐에 추가 안 됨. 1시간 후 (또는 테스트에서 시각 주입) 자동 mute 해제.
  5. 앱 재시작 → 핀 / mute 둘 다 영속.
- 커밋: WO-006 단위로 atomic commit. 권장 메시지: `feat(WO-006): pin and mute via row context menu`.
- RESULT 문서: `.workorders/006-RESULT.md` — `## Summary` / `## Verification` / `## Deviations`.

## Out of scope

- Settings 화면의 muted 프로젝트 목록 / 영구 mute 옵션 / mute 지속시간 picker — 별도 WO
- 핀 아이콘 prefix·시각 차별화 — 별도 WO
- justArrived, ripple, sonar, breathe, ring, roam, drift, aging desaturation
- Quiet Hours, Reduce Motion 추가 정책
- Reporter / hook payload / HookEvent / HookListener / NotificationOrchestrator 변경
- popover 너비·행수·empty state·헤더 톱니
- 단축키, 드래그 reorder
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

