
# WO-004: Hook payload extension (kind / exit_code / started_at / last_output)

## Goal
Reporter 가 Claude Code Stop hook 입력에서 `exit_code`, `started_at`, `kind`, `last_output` 필드를 (가능한 경우) 패스스루하도록 확장하고, App 측 (`HookEvent` / `HookListener` / `SessionRecord` / persistence) 이 이를 디코딩·보존하도록 한다. **UI 색상 분기·aging·ripple 은 후속 WO** — 이번 WO 는 데이터 파이프라인만.

## Context

(FEATURES.md §5 발췌 — Payload 스펙 진실의 원천)
```json
{
  "session_id": "...",
  "project_name": "...",
  "started_at": 1730000000,
  "stopped_at": 1730000067,
  "exit_code": 0,
  "kind": "success" | "error" | "waiting",
  "last_output": "..."
}
```

(BACKLOG.md — 이번 WO 가 닫는 항목)
- Step 3: `[PARTIAL] App hook payload differs from SPEC's iTerm event shape — HookEvent.swift. Missing exit_code, kind, last_output, and started_at; duration is correlated internally.` → 이번 WO 로 4개 필드 추가, **legacy decode fallback** 으로 기존 페이로드 호환 유지.
- Step 5: `[PARTIAL] CompletedSession has 'available' (WO-002); kind/pinned/justArrived still missing` → `kind` 만 이번 WO 에서 닫는다 (`pinned`, `justArrived` 는 별도 WO).
- BACKLOG Recommended Next #3: "Reconcile SPEC iTerm payload/API decisions" — 이번 WO 의 일부.

(시각/거동 진실의 원천)
- `FEATURES.md` §3 (행 상태 닷: success/error/waiting/unavailable), §5 (payload 스펙 + 세션 점프). 이번 WO 는 데이터만 — 시각화는 후속.
- `SPEC.md` — 최신 구조 스펙 (state model 의 `kind: AlertKind` 정의).
- `Claude Alert Bot - Prototype v2.html` — 시각 거동 (이번 WO 와 직접 영향 없음. 후속 색상 WO 에서 참조).

(AGENTS.md 발췌 — binding)
- Hook → app IPC: Unix domain socket via `Network.framework`. JSON line protocol.
- Hook reporter: `Reporter/cab-report.sh` (Claude hook reporter shell script).
- Min OS macOS 14, Swift 5.10+, no Sandbox, zero external Swift dependencies.
- Code Change Discipline: 최소 변경. 함수 시그니처/기본 인자/docstring 변경 금지 (단 본 WO 가 명시적으로 요구하면 예외).

(스코프 명확화 — 무엇이 IN, 무엇이 OUT)
- **IN**: Reporter 의 4개 필드 emit (Claude Code hook 입력 JSON 에서 가능한 매핑만 — 예: `tool_use` exit code, `transcript_path` 의 prompt 시작 시각). Claude Code hook 입력에 해당 필드가 없으면 emit 안 함 (Optional). HookEvent 디코딩, SessionRecord 필드 추가, persistence 라운드트립, legacy fallback, 단위 테스트.
- **OUT**: UI 에서 status dot 색상 분기 (PopoverRowView 의 색상 선택은 여전히 WO-002 의 success 단일 — **DesignTokens / PopoverRowView 손대지 말 것**). aging desaturation, just-arrived ripple, error/waiting 시각화. Reporter 의 휴리스틱 kind 추론 (예: exit_code != 0 → error 자동 판정) — 후속 WO. 이번엔 Claude Code 가 전달하는 값만 신뢰.

## Inputs

분석/수정 대상 (정확한 파일명·심볼은 Codex 가 확인 후 수정):
- `Reporter/cab-report.sh` — Claude Code hook stdin JSON 에서 `exit_code`, `started_at`, `kind`, `last_output` 매핑 가능한 키 추출 후 socket 으로 보낼 JSON 에 포함. 추출 불가 시 필드 생략 (Optional).
- `App/HookEvent.swift` (또는 hook payload 모델) — 4개 필드 디코딩 추가. 모두 Optional. 미존재 시 `nil`.
- `App/HookListener.swift` — 디코딩한 값을 `SessionRecord` 생성 경로에 propagate.
- `App/SessionRecord.swift` (또는 `CompletedSession`) — 다음 필드 추가:
  - `kind: AlertKind` — 신규 enum `AlertKind: String, Codable { case success, error, waiting }`. **legacy 데이터·payload 누락 시 `.success` 폴백** (현재 묵시적 동작 보존).
  - `exitCode: Int?` — 누락 시 `nil`.
  - `startedAt: Date?` — Unix timestamp 디코딩. 누락 시 `nil`. 기존 internal duration correlation 은 유지 (이 필드는 supplemental).
  - `lastOutput: String?` — 누락 시 `nil`. **길이 cap 4 KB** (UTF-8 byte 기준; 초과 시 앞 4 KB 만 보관). payload 폭주 방지.
- `App/SessionStore.swift` / `App/SessionRegistry.swift` — Codable 라운드트립 + legacy JSON 디코딩 폴백. 키 rename 금지.
- `App/NotificationOrchestrator.swift` (필요시만) — `kind` 를 사용하지 않는다면 손대지 말 것. 현재 알림 분기에 `kind` 가 영향을 준다면 최소 변경.
- 신규 또는 기존 테스트 (`HookEventTests.swift`, `SessionRecordTests.swift`, `SessionStoreTests.swift`/`SessionRegistryTests.swift`) — fallback / round-trip / lastOutput cap 검증.

읽어볼 것 (수정 X):
- `AGENTS.md` — Hard Constraints, Tech Stack USE/AVOID, Code Change Discipline.
- `FEATURES.md` §5 payload 스펙.
- `SPEC.md` — state model `Session.kind: AlertKind`.
- `scripts/dev-install-hook.sh` (수정 금지, 동작 변경 없음을 확인하기 위함).

## Deliverables

- [ ] **신규 enum**: `AlertKind: String, Codable { case success, error, waiting }`. 디코딩 시 알 수 없는 문자열·누락은 `.success` 폴백 (custom `init(from:)` 또는 `decodeIfPresent ?? .success`).
- [ ] **`SessionRecord` 필드 4개 추가** (`kind` / `exitCode: Int?` / `startedAt: Date?` / `lastOutput: String?`). Codable 누락 폴백: `kind=.success`, 나머지 `nil`. 디스크 영속 라운드트립 보장. `lastOutput` 은 4 KB UTF-8 cap (저장·메모리 양쪽).
- [ ] **`HookEvent` (혹은 hook payload 모델) 디코딩 확장**: 동일 4개 필드 Optional 디코딩. `started_at` 은 Unix epoch (Int 또는 Double) → `Date?` 변환. 알 수 없는 키는 무시.
- [ ] **`HookListener` 전파**: 디코딩한 값을 `SessionRecord` 생성 시 채워 넣기. `kind` 가 hook 에서 오지 않으면 `.success` 유지 (현 동작과 동일).
- [ ] **`Reporter/cab-report.sh` 패스스루**: Claude Code Stop hook stdin JSON 에서 다음을 추출하여 socket 으로 보낼 JSON 에 포함:
  - `exit_code` ← Claude Code hook input 에 직접 있으면 그대로
  - `started_at` ← `transcript_path` 또는 hook input 에 prompt 시작 timestamp 있으면 그대로 (없으면 생략)
  - `kind` ← hook input 에 명시적으로 있으면 그대로 (없으면 생략 — 현재 Claude Code 가 명시적으로 보내지 않을 가능성 큼; 휴리스틱 판정은 OUT)
  - `last_output` ← hook input 의 결과/요약 텍스트가 있으면 앞 4 KB. 없으면 생략
  - **추출 불가하면 필드 생략** (Optional). 기존 emit 키·소켓 protocol 호환 유지.
- [ ] **Codable legacy fallback 테스트**: 이전 JSON (필드 4개 모두 부재) → `kind=.success`, 나머지 `nil` 로 디코딩되는지 1 케이스. 각 필드 개별 부재 케이스도 합리적 범위 내 1-2 추가.
- [ ] **신규 페이로드 라운드트립 테스트**: 4개 필드 모두 채운 JSON → 디코딩 → 인코딩 → 동일 JSON 의 의미적 동치.
- [ ] **`lastOutput` cap 테스트**: 5 KB 입력이 4 KB 로 truncate 되는지.
- [ ] **HookListener 통합 테스트** (가능 시): 가짜 socket 입력 → SessionRecord 생성 → 4개 필드 propagate 확인. 분리 불가하면 단위 테스트로 대체.

## Constraints (WO-specific)

- **PopoverRowView / DesignTokens / WidgetPopoverController / PopoverContentView 손대지 말 것** — `kind` 기반 색상 분기는 후속 WO. 이번엔 모델·persistence·hook 레이어만.
- **`pinned`, `justArrived` 필드 추가 금지** — 별도 WO (mute/pin).
- **현재 `kind` 가 없는 Claude Code hook 입력에 대해 휴리스틱 판정 (예: `exit_code != 0 → error` 자동 매핑) 금지** — payload 가 명시적으로 보내는 값만 신뢰. 휴리스틱은 후속 WO.
- **Reporter 가 emit 하는 기존 필드·키 이름 변경 금지**. 추가만 허용. 소켓 protocol 호환 유지 (기존 App 인스턴스가 새 필드 모르더라도 무시할 수 있어야 함 — 즉 신규 App + 구 Reporter, 구 App + 신규 Reporter 모두 동작).
- **`mutedProjects`, `quietHours`, `reduceMotion` 등 SettingsStore 신규 필드 추가 금지** — 별도 WO.
- **iTerm2 Python API 도입 금지** (AGENTS.md AVOID). 현재 NSAppleScript 유지.
- 함수 시그니처·기본 인자·docstring 변경은 본 Deliverables 가 명시적으로 요구하는 경우에만.

## Verification

- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` 성공
- 단위 테스트: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` 모두 통과 (release 앱 종료 후. 환경 이슈 시 `CI=1 xcrun xctest …` direct 호출 fallback)
- 수동/통합 검증:
  1. 기존 `SessionStore` 디스크 스냅샷 (필드 부재) 을 새 코드로 로드 → 크래시 없이 모든 row 가 정상 렌더 (UI 색상은 그대로 success 단일)
  2. 신규 페이로드 (4개 필드 채움) socket 송신 → `SessionRecord` 에 값이 채워짐 (디버거·로그·테스트로 확인)
  3. `last_output` 5 KB 입력 → 저장된 record 의 `lastOutput` 길이가 4096 byte 이하
  4. `Reporter/cab-report.sh` 가 Claude Code hook 입력에 해당 키 부재 시 그 필드를 emit 하지 않음 (현존 protocol 호환)
- 커밋: WO-004 단위로 atomic commit. 권장 message: `feat(WO-004): hook payload extension (kind/exit_code/started_at/last_output)`. 모델 → 디코딩 → Reporter → 테스트 순으로 분리하면 더 좋음.
- RESULT 문서: `.workorders/004-RESULT.md` — Summary / Verification / Deviations.

## Out of scope

- UI 색상 분기 (`kind` 기반 status dot 색): success/error/waiting 토큰은 `DesignTokens` 에 이미 있으나 적용은 후속 WO. **DesignTokens / PopoverRowView 손대지 말 것**.
- aging desaturation (60분+ 행 desaturate)
- just-arrived ripple, sonar wave, breathe, ring, roam
- Mute / pin / right-click context menu (WO-005 예정)
- Quiet Hours, Reduce Motion 세부 정책
- Reporter 의 `kind` 휴리스틱 자동 판정
- iTerm2 Python API 도입 — **금지**
- `pinned`, `justArrived`, UUID `id` migration (string `sessionID` → UUID) — 별도 WO
- popover 너비 270pt / 최대 4행 / 빈 상태 온보딩 / 헤더 톱니 — 별도 WO
- 무관 리팩터·rename·import 정렬

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

