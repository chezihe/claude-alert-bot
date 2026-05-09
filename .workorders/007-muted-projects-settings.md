# WO-007: Settings 화면에 muted projects 목록 + Unmute 버튼

## Goal
WO-006 에서 추가한 `SettingsStore.mutedProjects: [String: Date]` (project name → expiry Date) 를 사용자가 **Settings 창에서 직접 보고 해제** 할 수 있게 한다. 활성 mute 가 1개 이상일 때만 새 "Muted Projects" 섹션이 보이고, 각 행에 프로젝트명 + 남은 시간 + Unmute 버튼이 표시된다. mute 만료 자동 prune 은 OUT.

## Context

(WO-006 이미 완료 — 이번 WO 의 데이터 기반)
- `SettingsStore.mutedProjects: [String: Date]` `@Published`. project name → expiry Date.
- 헬퍼: `mute(project:duration:now:)` (default 3600초), `unmute(project:)`, `isMuted(project:now:)`.
- 영속화: JSON-encoded Data, UserDefaults key `"muted_projects"`.
- Mute 진입점은 popover row 의 right-click context menu ("Mute this project for 1h"). 해제 진입점은 **현재 동일 contextMenu 만 존재** — 그 프로젝트 행이 popover 에 남아있어야 해제 가능. 본 WO 가 Settings 창의 두 번째 해제 진입점을 추가.

(현재 `SettingsView` 구조 — `App/SettingsView.swift`)
```swift
struct SettingsView: View {
    @StateObject private var store = SettingsStore.shared
    var body: some View {
        Form {
            // Permission banner (조건부)
            // Section "알림 임계값"   (Stepper)
            // Section "사운드"        (Toggle)
            // Section "Widget Position" (Picker + 2 Stepper)
            // Section "테스트"        (Button)
            // Section "iTerm2 연결"   (Button + 결과 라벨)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        ...
    }
}
```
- 새 Section "Muted Projects" 를 **"테스트" 위 또는 "iTerm2 연결" 아래** 중 한 곳에 추가. 권장: "Widget Position" 과 "테스트" 사이 (config 류 → 상태 류 흐름 자연스럽게).

(스타일/카피 — minimal English UI 메모리 정책)
- Section heading: `"Muted Projects"` — 영어. (위 한국어 헤딩들과 섞이지만 minimal English UI 메모리 정책상 OK. WO-006 의 contextMenu copy `"Mute this project for 1h"`, `"Unmute This Project"` 도 영어이므로 일관됨.)
- 행 구성: `[프로젝트명] [· 47 min left] [Spacer] [Unmute 버튼]`
- 빈 상태: section 자체 미표시 (empty placeholder 안 그림).
- 버튼 스타일: `.borderless` (Form 안 행 우측 inline action 관용).

(시간 기준 — 정책 결정)
- `now: Date` 는 SettingsView body 가 렌더될 때마다 `Date()` 로 inline 평가 (WO-010 의 aging 정책과 동일 — timer/DispatchSource 추가 금지).
- 사용자가 Settings 창을 연 채 mute 가 만료되어도 라벨이 자동 갱신되지 않음. 다음 redraw (예: 다른 setting 변경, 창 닫고 다시 열기) 때 갱신. **이는 의도된 한계** — 별도 WO 면접.
- mute 만료된 항목은 **표시에서 제외** (`activeMutes` filter). 그러나 store.mutedProjects 에서 자동 prune 은 안 함. 만료 항목은 다음 mute 호출 / Unmute 호출 / 다음 ingest_stop 시점의 `isMuted` 체크 등에서 자연 정리되거나 stale 상태로 남는다 — prune 은 별도 WO.

(스코프 명확화 — IN / OUT)
- **IN**: 새 helper file `App/MutedProjectsRules.swift` (순수 함수 namespace), `App/SettingsView.swift` 에 새 Section 한 개 추가, 단위 테스트.
- **OUT**: SettingsStore 수정 (이미 모든 헬퍼 존재), mute 만료 자동 prune, mute 시간 조정 UI, 새 mute 추가 UI from Settings, mute 일시정지 / 1주일 옵션, popover 측 변경 일체.

(AGENTS.md — binding)
- Code Change Discipline: 최소 변경. 함수 시그니처·기본 인자·docstring 변경 금지.
- macOS 14 타깃, Swift 5.10+, no Sandbox, zero external Swift dependencies.
- minimal English UI copy.

## Inputs

분석/수정 대상:

- **(신규)** `App/MutedProjectsRules.swift` — 새 파일. SwiftUI import 없음, Foundation 만:
  ```swift
  import Foundation

  /// Pure-function namespace for SettingsView muted-projects section.
  /// Tested without SwiftUI rendering.
  enum MutedProjectsRules {
      /// 활성(만료 안 된) mute 만 알파벳 정렬해서 반환. expiry strict `>` now.
      static func activeMutes(_ mutes: [String: Date], now: Date) -> [(project: String, expiresAt: Date)] {
          mutes
              .filter { $0.value > now }
              .map { (project: $0.key, expiresAt: $0.value) }
              .sorted { $0.project < $1.project }
      }

      /// 남은 시간을 minimal English label 로. floor 분 단위:
      /// - secs <= 0  → "<1 min left"
      /// - 0 < secs < 60 → "<1 min left"
      /// - 60 <= secs < 120 → "1 min left"
      /// - N*60 <= secs < (N+1)*60 → "N min left"
      static func remainingMinutesLabel(expiresAt: Date, now: Date) -> String {
          let secs = expiresAt.timeIntervalSince(now)
          let mins = Int(secs / 60) // floor; negative secs floor toward 0 acceptable since we filter via activeMutes
          if mins < 1 { return "<1 min left" }
          return "\(mins) min left"
      }
  }
  ```
  Tuple 반환 타입이 신경쓰이면 작은 struct (`MutedEntry`) 로 빼도 OK — 본 WO 안에서만 사용.

- `App/SettingsView.swift` — 새 Section 한 개 추가. 권장 삽입 위치: 기존 `Section(Self.widgetPositionHeading) { ... }` 직후, `Section(Self.testHeading) { ... }` 바로 위. 형태:
  ```swift
  // 새로운 정적 카피 (struct top, 다른 카피 상수 옆에)
  static let mutedProjectsHeading = "Muted Projects"
  static let unmuteButtonLabel = "Unmute"
  ```
  ```swift
  // body Form 안, widgetPosition 섹션 이후
  let now = Date()
  let activeMutes = MutedProjectsRules.activeMutes(store.mutedProjects, now: now)
  if !activeMutes.isEmpty {
      Section(Self.mutedProjectsHeading) {
          ForEach(activeMutes, id: \.project) { entry in
              HStack {
                  Text(entry.project)
                  Text("· " + MutedProjectsRules.remainingMinutesLabel(expiresAt: entry.expiresAt, now: now))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  Spacer()
                  Button(Self.unmuteButtonLabel) {
                      store.unmute(project: entry.project)
                  }
                  .buttonStyle(.borderless)
              }
          }
      }
  }
  ```
  다른 Section · 카피 상수 · helper 함수 (`runConnectionTest`, `hhmm`, `widgetCornerLabel`) · `.onAppear` 블록 · `@State` 변수 손대지 말 것.

- 테스트:
  - **(신규)** `ClaudeAlertBotTests/MutedProjectsRulesTests.swift` — 6~8 케이스:
    - `activeMutes` 빈 dict → 빈 배열
    - `activeMutes` 모두 만료 → 빈 배열
    - `activeMutes` mix (만료 1 + 활성 2) → 활성 2 만 반환
    - `activeMutes` strict `>` (정확히 now == expiresAt → 제외)
    - `activeMutes` 알파벳 오름차순 정렬 (역순 입력 → 정렬된 출력)
    - `remainingMinutesLabel` `expiresAt == now` → `"<1 min left"`
    - `remainingMinutesLabel` `expiresAt = now + 59s` → `"<1 min left"`
    - `remainingMinutesLabel` `expiresAt = now + 60s` → `"1 min left"`
    - `remainingMinutesLabel` `expiresAt = now + 119s` → `"1 min left"`
    - `remainingMinutesLabel` `expiresAt = now + 3600s` → `"60 min left"`
  - `ClaudeAlertBotTests/SettingsViewTests.swift` (기존 파일 — append) — source-level audit:
    - source 에 `MutedProjectsRules.activeMutes` 호출 존재
    - source 에 `store.unmute(project:` 호출 존재
    - source 에 `"Muted Projects"` 헤딩 문자열 존재
    - source 에 `"Unmute"` 버튼 라벨 존재
    - 정적 카피 `mutedProjectsHeading == "Muted Projects"`, `unmuteButtonLabel == "Unmute"` 검증

읽어볼 것 (수정 X):
- `AGENTS.md`, `App/SettingsStore.swift` (헬퍼 시그니처 확인), `App/SettingsView.swift` (기존 Section 패턴 확인), `Claude Alert Bot - Prototype v2.html` (시각 톤 참조 — Settings 창 자체는 prototype 에 없을 수 있음).

## Deliverables

- [ ] **`App/MutedProjectsRules.swift`** 신규 파일 — `activeMutes(_:now:)`, `remainingMinutesLabel(expiresAt:now:)` 두 순수 함수.
- [ ] **`SettingsView` 새 Section "Muted Projects"** — 활성 mute 가 1+ 일 때만 표시. ForEach 행에 프로젝트명 + 남은 시간 + Unmute 버튼.
- [ ] **`SettingsView.mutedProjectsHeading == "Muted Projects"`** + **`SettingsView.unmuteButtonLabel == "Unmute"`** 정적 카피 상수.
- [ ] **회귀 안전성**: 기존 모든 Section (permission banner / 알림 임계값 / 사운드 / Widget Position / 테스트 / iTerm2 연결) 거동 / 카피 / 순서 동일. `.onAppear` permission trigger 동일. `runConnectionTest` / `hhmm` / `widgetCornerLabel` 동일. `@State` 변수 (`connectionTestResult`, `connectionTestResultAt`, `hideResultTask`) 동일.
- [ ] **회귀 안전성 (popover 쪽)**: `PopoverRowView`, `PopoverContentView`, `SessionRegistry`, `SettingsStore` 모두 무변경. WO-006 contextMenu 로 mute/unmute 진입점은 그대로.
- [ ] **테스트 추가**: `MutedProjectsRulesTests` 신규 + `SettingsViewTests` source-level audit append. 풀 스위트 통과.

## Constraints (WO-specific)

- **다른 파일 손대지 말 것**: `App/SettingsStore.swift` (헬퍼 이미 충분), `App/SessionRecord.swift`, `App/SessionRegistry.swift`, `App/SessionStore.swift`, `App/PopoverRowView.swift`, `App/PopoverContentView.swift`, `App/WidgetPopoverController.swift`, `App/DesignTokens.swift`, `App/HookEvent.swift`, `App/HookListener.swift`, `App/NotificationOrchestrator.swift`, `App/FloatingWidgetWindowController.swift`, `App/WidgetIconView.swift`, `Reporter/*`, `scripts/*`. 빌드를 위해 read-only 참조는 허용.
- **mute 만료 자동 prune 금지** — `mutedProjects` 에서 만료된 키 제거하는 코드 추가 금지. `activeMutes` 는 표시 필터링만.
- **새 mute 추가 UI from Settings 금지** — 본 WO 는 "기존 mute 보기 + 해제" 만.
- **mute duration 조정 UI 금지** — 1h 고정 (WO-006 의 default 3600).
- **timer / DispatchSource / Task auto-refresh 추가 금지** — `now: Date()` 는 body inline 평가만.
- **새 `@AppStorage` / `@Published` 추가 금지** — 기존 `mutedProjects` 만 사용.
- **새 SwiftPM 의존성 금지** (zero external Swift deps 정책).
- **carry-over 한국어 카피 변경 금지** — `thresholdHeading`, `soundHeading`, `widgetPositionHeading`, `testHeading`, `connectionTestHeading` 및 본문 모두 동일.
- **`SettingsStore` 의 헬퍼 시그니처 변경 금지** — `mute(project:duration:now:)`, `unmute(project:)`, `isMuted(project:now:)` 그대로.
- **iTerm2 Python API 도입 금지** (AGENTS.md AVOID).
- 함수 시그니처·기본 인자·docstring 변경은 본 Deliverables 가 명시적으로 요구하는 경우에만.
- 무관 리팩터·rename·import 정렬·formatting 금지.

## Verification

- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` 성공.
- 단위 테스트: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` 모두 통과. 환경 이슈 시 `CI=1 xcrun xctest <path-to-ClaudeAlertBotTests.xctest>` fallback.
- 수동 검증 (가능 시):
  1. 앱 실행 후 popover row 우클릭 → "Mute this project for 1h" 클릭. Settings (⌘,) 열기 → "Muted Projects" 섹션이 보이고 해당 프로젝트명 + "59 min left" 표시.
  2. 같은 Settings 창에서 "Unmute" 클릭 → 행이 즉시 사라지고, 1행만 남았다면 다음 unmute 후 섹션 자체 사라짐.
  3. 활성 mute 가 0개일 때 Settings 열기 → "Muted Projects" 섹션 자체 미표시.
  4. mute 후 약 60분 대기 → Settings 다시 열기 → 만료 entry 미표시 (자동 prune 안 했지만 표시는 안 됨).
- 커밋: WO-007 단위 atomic commit. 권장 메시지: `feat(WO-007): muted projects list and unmute in settings`. helper-first → view 순으로 분리해도 좋음.
- RESULT 문서: `.workorders/007-RESULT.md` — `## Summary` / `## Verification` / `## Deviations`.

## Out of scope

- mute 만료 자동 prune (mutedProjects 에서 만료 키 제거)
- mute 시간 조정 UI / 1주일 mute / 영구 mute / 일시정지
- Settings 에서 새 프로젝트 mute 추가 UI
- popover row 거동 변경 (WO-006 contextMenu 그대로)
- mute 알림 / 만료 알림
- Quiet Hours / Reduce Motion 추가 정책
- timer / DispatchSource 기반 라벨 자동 refresh
- 한국어 / 영어 외 다국어
- popover 너비·행수·empty state·헤더 톱니 (WO-009 후보)
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

