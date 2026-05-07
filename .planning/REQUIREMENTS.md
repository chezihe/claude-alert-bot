# Requirements: Claude Alert Bot

**Defined:** 2026-05-07
**Core Value:** Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Hook (이벤트 수신)

- [x] **HOOK-01**: Reporter shell script가 Claude Code의 `Stop` hook으로 실행되어 JSON 이벤트를 stdin으로 받아 App에 전달한다
- [ ] **HOOK-02**: Reporter shell script가 Claude Code의 `UserPromptSubmit` hook으로도 실행되어 작업 시작 시점을 App에 전달한다
- [ ] **HOOK-03**: Reporter는 항상 `exit 0`으로 종료한다 (Claude Code가 hook 실패로 멈추거나 무한 루프에 빠지지 않도록)
- [ ] **HOOK-04**: Reporter가 `session_id`, `cwd`, `ITERM_SESSION_ID`, `tty`, `CLAUDE_PROJECT_DIR`, `ppid`, 타임스탬프를 캡처한다
- [ ] **HOOK-05**: Reporter는 App이 실행 중이지 않을 때도 가만히 0으로 종료한다 (전송 실패해도 Claude Code 영향 없음)
- [ ] **HOOK-06**: 디버깅용 hook 로그를 `~/Library/Logs/ClaudeAlertBot/hook.log`에 기록한다 (env 스냅샷, ppid 체인, tty 포함)

### IPC (App ↔ Hook 통신)

- [x] **IPC-01**: App이 `Network.framework`의 `NWListener`로 AF_UNIX 소켓 서버를 띄우고 hook의 JSON 이벤트를 수신한다
- [x] **IPC-02**: 소켓 경로는 사용자 home 디렉토리 하위 (예: `~/Library/Application Support/ClaudeAlertBot/sock`) 를 사용한다
- [x] **IPC-03**: App 다중 인스턴스 실행을 방지한다 (소켓 점유 검사 등)

### Session (세션 추적)

- [ ] **SESS-01**: Swift `actor` 기반 SessionRegistry가 in-flight 세션과 완료-미클릭 큐를 단일 진실의 원천으로 보관한다
- [ ] **SESS-02**: 시작(UserPromptSubmit)과 종료(Stop) 이벤트를 `session_id`로 상관시켜 경과 시간을 계산한다
- [ ] **SESS-03**: 세션 상태를 `sessions.json`에 원자적으로 영속화하여 App 재시작 후에도 복원된다
- [ ] **SESS-04**: 6시간 이상 지난 in-flight 세션은 GC하여 메모리 누수를 방지한다

### Threshold (시간 임계값 필터)

- [ ] **THR-01**: 사용자가 설정한 임계값 (기본 30초) 이상 걸린 작업만 알림을 발생시킨다
- [ ] **THR-02**: 시작 이벤트가 누락되어 경과 시간을 계산할 수 없는 경우의 fallback 정책을 정의한다 (옵션: 항상 알림 / 무시 / 추정 경과)

### Widget (플로팅 위젯)

- [ ] **WIDG-01**: `NSPanel` 기반 플로팅 위젯이 모든 Spaces / 풀스크린 / Stage Manager 위에 표시된다 (`canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`, `level=.floating`)
- [ ] **WIDG-02**: 위젯이 등장할 때 현재 앱의 포커스를 빼앗지 않는다 (`.nonactivatingPanel`, `becomesKeyOnlyIfNeeded`)
- [ ] **WIDG-03**: 위젯에 클로드 아이콘과 작업 폴더(프로젝트)명이 표시된다
- [ ] **WIDG-04**: 위젯은 사용자가 클릭할 때까지 화면에 잔존한다 (자동 사라짐 없음)
- [ ] **WIDG-05**: 평소(이벤트 없을 때)에는 위젯이 화면에 보이지 않는다
- [ ] **WIDG-06**: 위젯 화면 위치 (네 모서리 중 하나 + 오프셋) 를 사용자가 설정할 수 있다
- [ ] **WIDG-07**: 위젯 위치가 노치/멀티 디스플레이 환경에서도 안전 영역을 침범하지 않는다 (`NSScreen.safeAreaInsets`)

### Aggregate (다중 세션 집계)

- [ ] **AGG-01**: 약 500ms~2초의 배칭 윈도우 내 거의 동시에 완료된 세션은 단일 카운터 위젯으로 집계된다
- [ ] **AGG-02**: 카운터 위젯은 클로드 아이콘 위에 완료 개수 배지를 표시한다
- [ ] **AGG-03**: 카운터 위젯을 클릭하면 완료된 세션 목록이 popover로 펼쳐진다
- [ ] **AGG-04**: 목록의 각 항목은 폴더(프로젝트)명, 경과 시간을 표시한다
- [ ] **AGG-05**: 사용자가 목록에서 항목을 선택하면 해당 iTerm2 세션으로 점프한다 (JUMP 요구사항으로 위임)

### Jump (iTerm2 세션 점프)

- [ ] **JUMP-01**: 위젯(또는 목록 항목) 클릭 시 작업이 실행된 정확한 iTerm2 탭/창에 포커스가 이동한다
- [ ] **JUMP-02**: 세션 매칭은 다단계 fallback으로 동작한다: ① `ITERM_SESSION_ID` UUID, ② `tty` 경로, ③ "세션이 더 이상 존재하지 않습니다" 친절한 에러 (잘못된 탭으로 이동하지 않음)
- [ ] **JUMP-03**: AppleScript는 컴파일 1회 + 다회 실행(`NSAppleScript`)으로 백그라운드 큐에서 호출된다
- [ ] **JUMP-04**: AppleScript 호출에 3초 하드 타임아웃을 둔다
- [ ] **JUMP-05**: 클릭 이벤트가 디바운스되어 동일 세션을 중복 호출하지 않는다

### Audio (사운드)

- [ ] **AUD-01**: 알림 발생 시 사운드를 1회 재생한다
- [ ] **AUD-02**: 사운드 on/off 토글이 설정에 있다
- [ ] **AUD-03**: 배칭 윈도우 안의 동시 완료에 대해 사운드는 1번만 재생된다 (dedupe)

### Settings (사용자 설정)

- [ ] **SET-01**: SwiftUI `Settings` scene + `@AppStorage`로 설정 윈도우 제공
- [ ] **SET-02**: 설정 가능 항목: 시간 임계값, 사운드 on/off, 위젯 위치
- [ ] **SET-03**: 설정 변경은 즉시 반영되며 App 재시작 후에도 유지된다
- [ ] **SET-04**: "테스트 알림" 버튼이 존재하여 위젯·사운드를 즉시 검증할 수 있다
- [ ] **SET-05**: "iTerm2 연결 테스트" 버튼이 존재하여 AppleScript 권한 프롬프트를 의도적으로 트리거할 수 있다

### Install (Hook 설치)

- [ ] **INST-01**: App이 `~/.claude/settings.json`에 Stop + UserPromptSubmit hook 항목을 멱등적으로(중복 추가 없이) 자동 병합한다
- [ ] **INST-02**: 자동 편집을 거부하는 사용자를 위해 설정 UI에 "Hook JSON 복사" 수동 fallback 버튼을 제공한다
- [ ] **INST-03**: 언인스톨/제거 시 본 앱이 추가한 hook 항목만 깨끗이 제거하고 사용자의 다른 hook 설정은 보존한다
- [ ] **INST-04**: `~/.claude/settings.json`이 JSON5 (주석 포함) 형식이어도 안전하게 파싱한다

### Onboarding (첫 실행 경험)

- [ ] **ONB-01**: 첫 실행 시 3-스크린 위저드 (Hook 설치 → Automation 권한 부여 → 테스트 알림) 가 자동 실행된다
- [ ] **ONB-02**: Automation 권한 프롬프트는 `NSAppleEventsUsageDescription`이 설정된 상태에서 결정적으로 트리거된다
- [ ] **ONB-03**: AppleScript에서 `errAEEventNotPermitted (-1743)` 발생 시 복구 다이얼로그를 표시하고 시스템 설정 → Privacy & Security → Automation 으로 딥링크한다
- [ ] **ONB-04**: README/도움말에 `tccutil reset AppleEvents <bundle-id>` 트러블슈팅 안내가 있다

### Distribution (배포)

- [x] **DIST-01**: 빌드 파이프라인이 ad-hoc 서명한다 (Apple Silicon 실행 필수). RESEARCH Pitfall #9 적용: `--deep` 대신 per-Mach-O `codesign --force --sign - --options=runtime` (cab-test → main → bundle 순)
- [ ] **DIST-02**: 릴리즈 산출물은 `create-dmg`로 빌드된 `.dmg`이다
- [ ] **DIST-03**: README가 macOS 14 / 15+ 별 Gatekeeper 우회 절차를 정확히 안내한다 (System Settings → Privacy & Security → Open Anyway 경로 포함)
- [ ] **DIST-04**: DMG 안에 `bypass-gatekeeper.command` 헬퍼가 포함되어 `xattr -cr`로 quarantine을 제거할 수 있다
- [x] **DIST-05**: App이 accessory 모드 (`LSUIElement=true`) 로 실행되어 Dock 아이콘 / 메뉴바 항목이 보이지 않는다
- [ ] **DIST-06**: 신선한 macOS (테스트 사용자 계정) 에서 .dmg 다운 → 드래그 → 1회 우회 → 정상 동작이 검증된다

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Multi-Terminal

- **MTERM-01**: Terminal.app 지원 (탭 매칭 + 포커스)
- **MTERM-02**: Warp 지원
- **MTERM-03**: Ghostty 지원
- **MTERM-04**: Alacritty / kitty 지원

### Per-Project Customization

- **PPC-01**: 프로젝트별 임계값 오버라이드
- **PPC-02**: 프로젝트별 사운드 / 색상 / 아이콘 틴트

### Quiet Hours / Focus

- **QH-01**: 시간대 기반 알림 비활성화 ("22:00–08:00 무음")
- **QH-02**: AFK 감지 기반 알림 ("자리 비운 지 2분 이상일 때만")
- **QH-03**: macOS Focus 상태 존중 (UNNotificationSound 채널 사용)

### History & Notification

- **HIST-01**: 최근 완료 10건 ring buffer 보존 (메뉴바 / 설정에서 조회)
- **NOTI-01**: Claude Code의 `Notification` hook (권한 프롬프트) 도 알림 대상에 포함

### Distribution Polish

- **DPOL-01**: Sparkle 자동 업데이트
- **DPOL-02**: Apple Developer Program 가입 + 공증 (사용자 마찰 0)
- **DPOL-03**: Homebrew Cask 등록

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Mac App Store 배포 | 코드 서명 + 샌드박스 + 심사 부담. 무료 ad-hoc 서명 정책과 충돌 |
| Windows / Linux 지원 | 플로팅 위젯 + iTerm2 통합이 핵심이라 의미 없음 |
| 알림 시 Claude의 마지막 응답 미리보기 | 위젯에는 폴더명만. 본문은 터미널에서 확인 — 단순함이 미덕 |
| 메뉴바 상시 표시 / Dock 상시 표시 | 평소에는 완전히 숨김. 완료 시에만 등장 |
| 자동 사라짐 / 알림 센터 통합 | 사용자가 명시적으로 클릭할 때까지 잔존 — Core Value의 일부 |
| 진행 중 알림 / 진행률 표시 | `Stop` 시점만. 진행 중 알림은 노이즈 |
| iCloud 동기화 / 멀티 디바이스 설정 동기 | 단일 머신 도구 |
| 세션 간 통계 / 히스토리 대시보드 | v1은 알림에만 집중 (v2 ring buffer로 최소 보존만) |
| Slack / Discord / Webhook 외부 전송 | 본 도구는 로컬 macOS UI에 국한 |
| 위젯에서 답장 / Quick Action | UX 복잡도 폭발. 터미널이 권한 |
| 위젯 드래그로 자유 위치 지정 | v1은 프리셋 모서리만. 자유 드래그는 노치/safe area 처리 비용이 큼 |
| 멀티 모니터 위젯 분산 표시 | v1은 메인 화면 1곳에 표시 |
| Touch ID / 비밀번호 보호 | 알림 도구에 과잉 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| HOOK-01 | Phase 1 | Satisfied (e2e verified Plan 01-03: Reporter `1458693` → listener `04d1004` → OSLog ingress with reporter-supplied session_id) |
| HOOK-02 | Phase 2 | Pending |
| HOOK-03 | Phase 1 | Pending (Reporter-side shipped in 01-02 commit `1458693`; 100x burst PASS; full Phase 1 verification in 01-06) |
| HOOK-04 | Phase 1 | Pending (Reporter-side shipped in 01-02 commit `1458693` — D-08 envelope all 10 fields; full verification in 01-06) |
| HOOK-05 | Phase 1 | Pending (Reporter-side shipped in 01-02 commit `1458693` — silent no-op when socket missing; full verification in 01-06) |
| HOOK-06 | Phase 1 | Pending (Reporter-side shipped in 01-02 commit `1458693` — hook.log via O_APPEND; full verification in 01-06) |
| IPC-01 | Phase 1 | Satisfied (Plan 01-03 commit `04d1004` — NWListener.start with NWEndpoint.unix; ingress decode verified e2e via cab-test and Reporter) |
| IPC-02 | Phase 1 | Satisfied (Plan 01-03 commit `04d1004` — SocketPaths.socketPath = ~/Library/Application Support/ClaudeAlertBot/sock; sun_path validator) |
| IPC-03 | Phase 1 | Satisfied (Plan 01-03 commit `04d1004` — D-09 bind exclusivity → NSApp.terminate(nil) on .failed; Pattern 6 stale-socket reclaim) |
| SESS-01 | Phase 2 | Pending |
| SESS-02 | Phase 2 | Pending |
| SESS-03 | Phase 2 | Pending |
| SESS-04 | Phase 2 | Pending |
| THR-01 | Phase 2 | Pending |
| THR-02 | Phase 2 | Pending |
| WIDG-01 | Phase 2 | Pending |
| WIDG-02 | Phase 2 | Pending |
| WIDG-03 | Phase 2 | Pending |
| WIDG-04 | Phase 2 | Pending |
| WIDG-05 | Phase 2 | Pending |
| WIDG-06 | Phase 2 | Pending |
| WIDG-07 | Phase 2 | Pending |
| AGG-01 | Phase 4 | Pending |
| AGG-02 | Phase 4 | Pending |
| AGG-03 | Phase 4 | Pending |
| AGG-04 | Phase 4 | Pending |
| AGG-05 | Phase 4 | Pending |
| JUMP-01 | Phase 3 | Pending |
| JUMP-02 | Phase 3 | Pending |
| JUMP-03 | Phase 3 | Pending |
| JUMP-04 | Phase 3 | Pending |
| JUMP-05 | Phase 3 | Pending |
| AUD-01 | Phase 2 | Pending |
| AUD-02 | Phase 2 | Pending |
| AUD-03 | Phase 4 | Pending |
| SET-01 | Phase 2 | Pending |
| SET-02 | Phase 2 | Pending |
| SET-03 | Phase 2 | Pending |
| SET-04 | Phase 2 | Pending |
| SET-05 | Phase 3 | Pending |
| INST-01 | Phase 5 | Pending |
| INST-02 | Phase 5 | Pending |
| INST-03 | Phase 5 | Pending |
| INST-04 | Phase 5 | Pending |
| ONB-01 | Phase 5 | Pending |
| ONB-02 | Phase 3 | Pending |
| ONB-03 | Phase 3 | Pending |
| ONB-04 | Phase 5 | Pending |
| DIST-01 | Phase 1 | Satisfied (Plan 01-05 commit `97de952` — scripts/build.sh runs xcodebuild archive + per-Mach-O ad-hoc codesign + verify; canonical output build/export/ClaudeAlertBot.app; bundle + main + cab-test all `Signature=adhoc`; launches on Apple Silicon with no `cs_invalid_page`) |
| DIST-02 | Phase 6 | Pending |
| DIST-03 | Phase 6 | Pending |
| DIST-04 | Phase 6 | Pending |
| DIST-05 | Phase 1 | Complete |
| DIST-06 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 53 total
- Mapped to phases: 53
- Unmapped: 0
- 100% coverage validated against ROADMAP.md

**Phase distribution:**
- Phase 1 (Foundation): 9 requirements
- Phase 2 (Alert Loop): 20 requirements
- Phase 3 (Click-to-iTerm2): 8 requirements
- Phase 4 (Multi-Session UX): 6 requirements
- Phase 5 (Hook Installer & Onboarding): 6 requirements
- Phase 6 (Distribution): 4 requirements
- **Total:** 53 (matches v1 count)

---
*Requirements defined: 2026-05-07*
*Last updated: 2026-05-07 — Traceability populated by roadmap creation*
