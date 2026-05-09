# WO-003: Widget corner position picker (4 corners)

## Goal
사용자가 floating widget (alert glyph) 의 화면 코너 위치를 설정에서 선택할 수 있게 한다. 기본값 `topRight`. 선택 즉시 반영. 재시작 후에도 유지.

## Context

(FEATURES.md §1 발췌)
> **위치 선택**: 4 코너 중 선택 (top-left / top-right / bottom-left / bottom-right)

(BACKLOG.md 발췌 — 이번 WO 가 닫는 항목)
- 신규 항목. BACKLOG 에는 위치 선택 항목이 없음 → FEATURES.md §1 의 누락분 보강.

(시각/거동 진실의 원천 — 반드시 함께 참조)
- `Claude Alert Bot - Prototype v2.html` — 프로토타입 v2. **floating widget 의 코너 anchor 거동/여백/등장 모션의 시각 기준**. 이 HTML 의 거동을 거스르지 말 것.
- `SPEC.md` — 최신 구조 스펙.

(AGENTS.md / SPEC (1).md 발췌)
- Floating widget: `NSPanel` + `NSHostingView`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`. 이 WO 는 panel 의 origin 만 코너별로 옮긴다.
- Settings: SwiftUI `Settings { … }` scene + `@AppStorage` (또는 본 프로젝트의 `SettingsStore` 패턴). 외부 의존성 추가 금지.
- macOS 14 타깃, Swift 5.10+, Sandbox 안 씀, ad-hoc 서명, zero external Swift dependencies.

(스코프 명확화)
- 이번 WO 는 **floating widget panel** 의 위치를 다룬다. `MenuBarExtra` 의 status-item 위치는 macOS 가 관리하므로 변경 불가 — 손대지 않음.
- 다중 디스플레이 정책: **현재 main display 의 visibleFrame 기준**으로 코너 anchor. 다중 모니터 추적/이동은 이번 WO 범위 아님.

## Inputs

분석/수정 대상 (정확한 파일명은 Codex 가 확인 후 수정):
- `App/SettingsStore.swift` — `widgetCorner` 필드 추가 (`@AppStorage` 또는 동등 패턴, 기본값 `topRight`)
- `App/SettingsView.swift` — 코너 4개 picker 컨트롤 추가
- `App/FloatingWidgetWindowController.swift` — panel 표시 시 `widgetCorner` 를 읽어 origin 계산. 설정 변경 시 reposition.
- (필요시) `App/ClaudeAlertBotApp.swift` — `SettingsStore` 주입/관찰 경로

읽어볼 것 (수정 X):
- `AGENTS.md` — 모든 룰의 출처 (binding)
- `FEATURES.md` §1 위치 선택, §4 Reduce Motion (스프링 → 0.15s 페이드 규칙은 이번 WO 와 무관하나 panel 등장 애니메이션이 있으면 영향 있음)
- `Claude Alert Bot - Prototype v2.html` — floating widget 의 코너 anchor 시각 기준
- `SPEC.md` — 최신 구조 스펙

## Deliverables

- [ ] **모델/영속**: `SettingsStore` 에 `widgetCorner` 필드 추가. 타입은 `enum WidgetCorner: String, CaseIterable, Codable { case topLeft, topRight, bottomLeft, bottomRight }`. 기본값 `.topRight`. 기존 데이터에 키가 없으면 자연스럽게 기본값 폴백 (`@AppStorage` 의 default 인자 사용). 기존 다른 설정 마이그레이션·키 변경 금지.
- [ ] **Settings UI**: `SettingsView` 에 코너 picker 한 개 추가. SwiftUI `Picker` (segmented or menu) 사용 권장. 라벨은 영어 미니멀 톤 (예: `Widget Position`, options: `Top Left / Top Right / Bottom Left / Bottom Right`). 이모지 금지, 컬러 dot 금지 (AGENTS.md "UI Copy").
- [ ] **위치 적용**: `FloatingWidgetWindowController` 가 panel 을 표시할 때, `NSScreen.main?.visibleFrame` 기준으로 코너에 anchor. 가장자리에서 **16pt inset** (panel 이 메뉴바/Dock 에 닿지 않도록). panel size 는 변경 금지 — origin 만 계산.
- [ ] **반응성**: 사용자가 Settings 에서 코너를 바꾸면 **현재 표시 중인 panel 이 즉시 새 위치로 이동**. SwiftUI 의 `@AppStorage` 또는 `Combine` publisher 등 본 프로젝트의 기존 패턴을 따른다. polling 추가 금지. 신규 NotificationCenter 글로벌 이벤트 추가 금지.
- [ ] **테스트**: 가능하면 `SettingsStoreTests` (또는 동등한 위치) 에 다음 1-2 개 테스트 추가
  - `test_widgetCorner_defaultIsTopRight`
  - `test_widgetCorner_persistsAcrossInit` (UserDefaults suite 분리하여)
  - panel origin 계산 함수가 분리 가능하면 4 코너 × 임의 visibleFrame 에 대해 origin 계산 단위 테스트 1 개. 분리 불가하면 생략.
- [ ] **Reduce Motion**: 위치 변경 시 panel 이동에 애니메이션을 새로 추가하지 않는다 (즉시 이동). 기존 등장/퇴장 애니메이션은 유지.

## Constraints

- AGENTS.md 의 모든 룰은 binding. 특히 "Code Change Discipline (No Over-Editing)" — 최소 변경, 무관 리팩터·rename·import 정렬 금지.
- macOS 14 타깃, Swift 5.10+, no Sandbox, ad-hoc 서명, zero external Swift dependencies.
- If you cannot read `AGENTS.md` / `FEATURES.md` / `SPEC.md`, use only the inlined Context above as the canonical fallback.
- **MenuBarExtra status-item 위치는 손대지 말 것** (OS 가 관리, 변경 불가).
- **다중 디스플레이 추적/이동 로직 추가 금지** — 이번 WO 는 main display 기준만.
- **WO-002 의 파일들 손대지 말 것**: `App/SessionRecord.swift`, `App/SessionRegistry.swift`/`SessionStore.swift`, `App/WidgetPopoverController.swift`, `App/PopoverRowView.swift`, `App/DesignTokens.swift`, `App/PopoverContentView.swift`. 단, 빌드를 위해 import/접근이 필요한 read-only 참조는 허용.
- **Idle/Rage 애니메이션, 빈 상태 온보딩, 톱니 아이콘, popover 너비/행수 변경, ripple/aged/grouping 손대지 말 것** — 별도 WO.
- 함수 시그니처/기본 인자/docstring 변경은 본 Deliverables 가 명시적으로 요구하는 경우에만.

## Verification

- 빌드: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` 성공
- 단위 테스트: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` 모두 통과
- 수동 시각 검증:
  1. Settings 열기 → `Widget Position` 컨트롤 4개 옵션 노출, 현재 값 표시
  2. 알림 1건 발생시켜 panel 이 기본 `Top Right` 코너 (메뉴바 아래) 에 16pt inset 으로 표시되는지
  3. Settings 에서 `Bottom Left` 선택 → panel 이 즉시 좌하단으로 이동, 16pt inset 유지
  4. 앱 재시작 후 마지막 선택값이 유지되는지
- 커밋: WO-003 단위로 atomic commit. 권장 메시지: `feat(WO-003): widget corner position picker (4 corners)`. 모델 → UI → window placement 순으로 분리하면 더 좋음.

## Output format (Codex 환경에 맞춰 택)

(A) Unified diff 권장 — 변경 파일 4개 이내. (B) 또는 (C) 가능. 새 파일 생성은 없을 가능성 큼.

## Out of scope

- 다중 모니터 추적·panel 이동 정책
- `MenuBarExtra` status-item 위치 변경
- WO-002 파일들 (SessionRecord, PopoverRowView, WidgetPopoverController, DesignTokens, PopoverContentView, SessionRegistry/Store)
- Idle 애니메이션 종류 (Bounce/Heart/Ring/Roam) 선택 — 별도 WO
- Rage 애니메이션 — 별도 WO (이스터에그)
- Quiet Hours Zzz 표시 — 별도 WO
- Popover 너비 270pt / 최대 4행 변경 — WO-002 종료 후 별도 WO
- 빈 상태 온보딩 "Listening to iTerm" — WO-002 종료 후 별도 WO
- Popover 헤더 톱니 아이콘 (Preferences 진입) — WO-002 종료 후 별도 WO
- Mute / pin / right-click context menu — WO-004 예정
- Hook payload 확장 (`exit_code`, `kind`, `started_at`, `last_output`) — 별도 WO
- iTerm2 Python API 도입 — **금지** (AGENTS.md: NSAppleScript 유지)
- Reporter / scripts / CabTest / 기존 테스트 픽스처 무관 변경
