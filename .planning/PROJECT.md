# Claude Alert Bot

## What This Is

Claude Code 작업이 끝났을 때 macOS 화면에 클로드 아이콘 플로팅 위젯으로 알려주는 네이티브 macOS 앱. 위젯을 클릭하면 해당 작업이 실행됐던 iTerm2 탭/창으로 즉시 점프한다. 본인 사용 + 다른 macOS Claude Code 사용자에게도 배포할 목적의 도구.

## Core Value

**Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 바로 그 터미널로 복귀할 수 있다.** 알림이 떠도 어느 세션 것인지 헷갈리거나 클릭이 잘못된 터미널을 여는 순간 가치가 무너진다 — "정확한 그 세션으로의 점프"가 핵심.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. -->

- [ ] Claude Code의 `Stop` hook과 `UserPromptSubmit` hook을 받아 작업 시작/종료 이벤트를 수신한다 (경과 시간 계산용)
- [ ] 작업 소요 시간을 측정하고, 사용자가 설정한 임계값(기본 30초) 이상인 경우에만 알림을 발생시킨다
- [ ] 알림 시 화면에 플로팅 클로드 아이콘 위젯이 팝업된다 (평소에는 보이지 않음)
- [ ] 위젯에는 작업한 폴더(프로젝트)명이 함께 표시된다
- [ ] 여러 세션이 거의 동시에 완료되면 위젯 1개에 카운터 배지로 묶여 표시된다
- [ ] 카운터 위젯을 클릭하면 완료된 세션 목록이 펼쳐지고, 사용자가 원하는 세션을 선택할 수 있다
- [ ] 위젯을 클릭(또는 목록에서 세션 선택)하면 해당 작업을 실행한 iTerm2 탭/창으로 포커스가 이동한다
- [ ] 위젯은 사용자가 클릭할 때까지 화면에 잔존한다 (자동 사라짐 없음)
- [ ] 알림 발생 시 사운드를 한 번 재생한다
- [ ] 시간 임계값, 사운드 on/off, 위젯 위치 등을 사용자가 설정할 수 있다
- [ ] 다른 macOS 사용자에게 `.dmg`로 배포 가능하다 (서명 없이; 첫 실행 우클릭 → 열기)
- [ ] Claude Code의 `settings.json` hook 설정을 자동으로 등록하거나 명확한 설치 가이드를 제공한다

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- **Terminal.app / Warp / Ghostty 등 다른 터미널 지원** — MVP는 iTerm2만. 사용자 본인이 iTerm2 사용 중이고, AppleScript API가 가장 풍부함. 추후 milestone
- **Apple Developer Program 코드 서명/공증** — $99/년 비용 회피. 사용자가 첫 실행 시 우클릭→열기 한 번만 하면 됨
- **Mac App Store 배포** — 코드 서명 필요 + 샌드박스 제약 + 심사. 위 정책과 동일 사유
- **Windows / Linux 지원** — 본 도구는 macOS 전용. 플로팅 위젯 + iTerm2 통합이 핵심이라 의미 없음
- **알림 시 Claude의 마지막 응답 미리보기** — 위젯에는 폴더명만. 본문은 터미널에서 확인
- **메뉴바 상시 표시 / Dock 상시 표시** — 평소에는 완전히 숨김. 완료 시에만 등장
- **자동 사라짐 / 알림 센터 통합** — 사용자가 명시적으로 클릭할 때까지 잔존
- **자동 업데이트(Sparkle 등)** — v1에서는 사용자가 수동으로 새 .dmg 받기. 사용자 수가 늘면 재검토
- **하나의 작업에 대한 진행률 / 중간 알림** — `Stop` 시점만. 진행 중 알림은 노이즈
- **iCloud 동기화 / 멀티 디바이스 설정 동기** — 단일 머신 도구
- **세션 간 통계 / 히스토리 대시보드** — v1은 알림에만 집중

## Context

- **사용자**: 본인 = Claude Code를 iTerm2에서 자주 사용하며, 동시에 여러 세션을 돌리는 macOS 사용자. 배포 대상도 동일 프로필
- **트리거 메커니즘**: Claude Code의 hook 시스템 (`settings.json`의 `Stop` hook)을 통해 작업 완료 이벤트를 받는다. Hook은 환경 변수로 cwd 등 컨텍스트를 전달함 — 이를 활용해 폴더명/세션 식별
- **세션 ↔ 터미널 연결**: 각 Claude Code 세션이 어느 iTerm2 탭에 있는지를 추적해야 함. 후보 방법: (1) hook 발생 시점의 부모 프로세스 PID → iTerm2 AppleScript로 PID 매칭 탭 검색, (2) hook이 세션 ID를 파일/소켓에 등록하고 클릭 시 조회. 플랜 단계에서 결정
- **iTerm2 제어**: iTerm2는 Python API와 AppleScript 양쪽을 지원. Swift에서는 `NSAppleScript` 또는 `Process` + `osascript`로 호출
- **플로팅 위젯**: `NSPanel` (level: `.floating` 또는 `.statusBar`) + `collectionBehavior` 조합으로 모든 Space에 따라다니게 가능. macOS의 표준 알림 센터는 사용하지 않음 (요구사항이 더 강한 시각적 잔존성 요구)
- **배포**: 서명 미적용 빌드는 첫 실행 시 macOS Gatekeeper가 차단 → 우클릭 → "열기" 한 번으로 통과. 명확한 README 안내 필요
- **선행 탐색 없음**: 현재 디렉터리는 비어 있고 spike/sketch findings 없음. 처음부터 시작

## Constraints

- **OS**: macOS 14 Sonoma 이상 (`MenuBarExtra` 안정성, `SMAppService.mainApp`, `Network.framework` UDS endpoint 모두 14에서 안정)
- **터미널**: iTerm2 only — MVP 범위
- **Tech stack**: Swift / SwiftUI + AppKit interop (NSPanel + NSHostingView). 외부 Swift 의존성 0. `Network.framework` AF_UNIX 소켓으로 hook ↔ App IPC
- **빌드 환경**: Xcode 15.4+ 필요 (Mac 개발자만 빌드 가능). 사용자는 빌드 산출물만 받음
- **서명**: Apple Developer Program 미가입. **Apple Silicon에서 실행되려면 ad-hoc 서명(`codesign --force --deep --sign -`)은 필수** (없으면 실행 자체 불가 — Gatekeeper 이전의 로드 단계 차단). Apple Developer 가입 없이 무료로 가능
- **Gatekeeper 우회**: macOS 15+ 에서는 우클릭 → "열기" 단축이 제거됨. 사용자는 **System Settings → Privacy & Security → "Open Anyway"** 절차를 1회 거쳐야 하며, DMG에 포함된 `bypass-gatekeeper.command` 헬퍼(`xattr -cr` 실행)로 대안 제공 가능
- **외부 의존**: Claude Code 설치 + iTerm2 설치 필수
- **Hook 등록**: Claude Code의 `Stop` hook + `UserPromptSubmit` hook **둘 다** 필요 (시작/종료 상관으로 경과 시간 계산). App이 `~/.claude/settings.json`에 멱등 병합으로 자동 등록
- **AppleScript 자동화 권한**: 첫 사용 시 macOS가 "Claude Alert Bot이 iTerm2를 제어하려 합니다" 권한 다이얼로그를 띄움 — 사용자가 허용해야 함. `NSAppleEventsUsageDescription` Info.plist 키 필수

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift / SwiftUI 네이티브 | 배포 용이(.dmg 드래그), 플로팅 위젯의 macOS 디테일이 가장 깔끔, 멀티 세션에서 메모리 우위 | — Pending |
| iTerm2만 지원 (MVP) | 사용자 본인이 iTerm2 사용. AppleScript API 가장 풍부. 멀티터미널은 v2 검토 | — Pending |
| 시간 임계값 기본 30초 + 설정 가능 | 짧은 대화에 알림 노이즈 방지. 사용자별 작업 패턴 차이 흡수 | — Pending |
| 위젯은 완료 시점에만 등장, 클릭까지 잔존 | "놓치지 않는다"는 Core Value를 직접 구현. 자동 사라짐은 그 가치를 깎음 | — Pending |
| 동시 완료 = 카운터 배지 + 클릭 시 목록 펼침 | 화면 가리는 위젯 폭주 방지하면서도 모든 세션 접근 가능 | — Pending |
| Apple Developer Program 미가입, ad-hoc 서명 + .dmg 배포 | $99/년 비용 회피. ad-hoc 서명은 무료지만 Apple Silicon 실행에 필수. macOS 15+ 사용자는 시스템 설정 1회 우회 절차 필요 | — Pending |
| `Stop` hook으로만 트리거 (진행 중 알림 없음) | Claude Code가 표준으로 제공하는 진입점. 진행률은 노이즈 위험 | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-07 after initialization (research findings incorporated)*
