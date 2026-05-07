---
phase: 2
slug: alert-loop
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-08
extracted_from: 02-RESEARCH.md
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: extracted from 02-RESEARCH.md `## Validation Architecture` section
> by plan-checker fix-up (Phase 1 `01-VALIDATION.md` shape).

---

## Test Framework

| Property | Value |
|----------|-------|
| **Framework** | XCTest (macOS 14 SDK 내장) + bash integration (`scripts/verify-phase-2.sh`) |
| **Config file** | `ClaudeAlertBot.xcodeproj/xcshareddata/xcschemes/ClaudeAlertBotTests.xcscheme` (NEW Wave 0) |
| **Quick run command** | `xcodebuild test -scheme ClaudeAlertBotTests -destination 'platform=macOS'` |
| **Full suite command** | `bash scripts/verify-phase-2.sh` (XCTest + boot smoke + e2e hook simulation) |
| **Estimated runtime** | ~30–90 초 (full); ~10–20s (quick — XCTest only) |

---

## Sampling Rate

- **Per task commit:** `xcodebuild test -only-testing:ClaudeAlertBotTests/<TaskScope>Tests`
- **Per wave merge:** `bash scripts/verify-phase-2.sh` (전체) + Phase 1 회귀 (`bash scripts/verify-phase-1.sh`)
- **Phase gate:** 위 두 스크립트 모두 green + manual checkpoint (WIDG-04 Space/sleep) 사용자 sign-off
- **Max feedback latency:** ≤ 90 seconds (full suite)

---

## Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HOOK-02 | Reporter argv "user_prompt_submit" → envelope `event="user_prompt_submit"` 수신 | integration | `bash scripts/verify-phase-2.sh ::hook02_user_prompt_submit` | ❌ Wave 0 |
| SESS-01 | actor isolation — 100 concurrent ingest 시 race 없음 | unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/SessionRegistryConcurrencyTests` | ❌ Wave 0 |
| SESS-02 | start→stop 경과시간 정확 (±100ms) | unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/SessionRegistryElapsedTests` | ❌ Wave 0 |
| SESS-03 | sessions.json save → kill -9 → restart → restore | integration | `bash scripts/verify-phase-2.sh ::sess03_persist_restore` | ❌ Wave 0 |
| SESS-04 | 7h-stale in-flight session GC | unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/GCTests` | ❌ Wave 0 |
| THR-01 | 5s task → no widget; 31s task → widget | integration | `bash scripts/verify-phase-2.sh ::thr01_threshold` | ❌ Wave 0 |
| THR-02 | start 누락 stop → widget with `?` | integration | `bash scripts/verify-phase-2.sh ::thr02_orphan_stop` | ❌ Wave 0 |
| WIDG-01 | NSPanel collectionBehavior 3-flag 검증 | unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/PanelConfigTests` | ❌ Wave 0 |
| WIDG-02 | LSUIElement + NSApp 비-active 유지 (위젯 등장 후) | manual + visual | `bash scripts/verify-phase-2.sh ::widg02_no_focus_steal` (heuristic: NSApp.isActive false 체크) | ❌ Wave 0 |
| WIDG-03 | popover row에 프로젝트명 표시 | unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/PopoverRowTests` | ❌ Wave 0 |
| WIDG-04 | 위젯이 Space 전환/sleep/lid open 후 잔존 | manual | `verify-phase-2.sh ::widg04_persistence` (manual checkpoint) | ❌ Wave 0 |
| WIDG-05 | 평소 invisible (queue 비면 orderOut) | unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/WidgetVisibilityTests` | ❌ Wave 0 |
| WIDG-06 | 4코너 + offset 변경 → 위치 재계산 | unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/PositioningTests` | ❌ Wave 0 |
| WIDG-07 | safeAreaInsets clamp 검증 | unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/SafeAreaClampTests` | ❌ Wave 0 |
| AUD-01 | 사운드 1회 — dedupe key 동일 시 2번째 안 재생 | unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/DedupeTests` | ❌ Wave 0 |
| AUD-02 | sound_enabled=false 시 재생 안 함 | unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/SoundToggleTests` | ❌ Wave 0 |
| SET-01..03 | @AppStorage 변경 → 즉시 반영 + 재시작 후 영속 | unit + integration | `xcodebuild test -only-testing:ClaudeAlertBotTests/SettingsPersistenceTests` + `verify-phase-2.sh ::set03_persist` | ❌ Wave 0 |
| SET-04 | "Test notification" 버튼 → 위젯 등장 + 30s 자동 정리 | manual + unit | `xcodebuild test -only-testing:ClaudeAlertBotTests/InjectTestTests` + manual visual | ❌ Wave 0 |

---

## Phase 2 Success Criteria → Verification Recipe

(ROADMAP "Phase 2 Success Criteria" 6개 항목 직접 매핑 — verify-phase-2.sh가 1:1 검증):

| # | ROADMAP 기준 | 검증 방법 |
|---|--------------|----------|
| 1 | 31s 턴 → 플로팅 위젯 + 프로젝트명 + multi-Space | `verify-phase-2.sh ::sc01_31s_widget` (cab-test로 31s elapsed 합성 + widget 등장 OSLog grep + manual Space 전환) |
| 2 | 5s 턴 → no widget no sound (default 30s threshold) | `verify-phase-2.sh ::sc02_threshold_5s` (cab-test 5s + ingress 후 30s 동안 widget 등장 X 검증) |
| 3 | 위젯이 클릭까지 잔존 across Space/sleep/lid | manual checkpoint (Phase 1 DIST-05 패턴) |
| 4 | Settings 즉시 반영 + 재시작 영속 + Test notification 동작 | `verify-phase-2.sh ::sc04_settings_full` |
| 5 | kill+restart → 미클릭 alert 복원 + 6h+ in-flight GC | `verify-phase-2.sh ::sc05_restore_and_gc` |
| 6 | start 누락 → fallback `?` alert | `verify-phase-2.sh ::sc06_orphan_alert` |

---

## Wave 0 Gaps

- [ ] `ClaudeAlertBotTests/` XCTest target — 위 모든 *Tests 파일 hosting
- [ ] `ClaudeAlertBotTests/Fixtures/HookEventFactory.swift` — 합성 envelope (event=stop / user_prompt_submit)
- [ ] `ClaudeAlertBotTests/Fixtures/MockNotifier.swift` — NotificationOrchestrator stub for actor unit tests
- [ ] `scripts/verify-phase-2.sh` — bash integration runner (Phase 1의 verify-phase-1.sh 패턴)
- [ ] `scripts/regress-phase-1.sh` (if not already) — Phase 1 회귀 가드
- [ ] **Spike 1 (advisor critical):** NSPopover-on-nonactivatingPanel composability — 1-2시간 prototype, LSUIElement Cmd-Tab 행동 검증
- [ ] **Spike 2 (advisor critical):** AppleScript `tell application "iTerm2" to return id of current session ...` UUID와 hook envelope `iterm_session_id`의 매칭 형식 일치 검증 (Phase 1 hook.log 데이터에 실제 ITERM_SESSION_ID 사례 있음 — `w0t0p1:79C4699F-7C77-4B92-B46A-10F818C00F8D` 형태 → AppleScript의 `id of current session`이 같은 형식인지)
- [ ] **Spike 3 (advisor critical):** D2-18 Focus/DnD 검증 — `NSWorkspace.shared.focusStatus`가 실제로 컴파일/링크되는지 macOS 14 SDK에서 확인 (예상: 컴파일 X) → discuss-phase 재논의 트리거 (RESOLVED via D2-18 RETRACT — 0e0b441)
- [ ] **Spike 4:** macOS 현재 dev host 버전(14/15/26?)에서 Privacy_Automation 두 URL 형태 모두 동작하는지 1회 클릭 검증

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Widget persistence across Space switches / sleep / lid close | WIDG-04 / SC#3 | 사용자 컨텍스트 (Space 전환, lid close, sleep/wake) — headless 자동화 불가 | 02-11 plan Task 3 manual checkpoint 10 sub-checks; resume signal `approved` recorded in 02-VERIFICATION.md |
| LSUIElement no focus steal (Cmd-Tab clean) | WIDG-02 | Cmd-Tab UI 검증은 visual; heuristic 자동화는 NSApp.isActive false 체크만 가능 | 위젯 트리거 후 Cmd-Tab → ClaudeAlertBot 부재 확인 + 텍스트 필드 포커스 유지 |
| Test notification button → widget appears + auto clear after 30s | SET-04 | 30초 wait + visual confirm + auto-clear 동작 | Settings 윈도우 → "Test notification" 클릭 → 위젯 즉시 등장 → 30초 후 자동 사라짐 (또는 클릭 dismiss) |
| First-launch TCC dialog (D2-35) | D2-33/35/36 | macOS TCC 다이얼로그는 사용자만 응답 가능 | 첫 Stop hook 도착 (또는 Settings 첫 열기) 시 "Claude Alert Bot이 iTerm2를 제어..." 다이얼로그 1회 등장 → 허용/거부 → 영속 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (XCTest target, fixtures, verify-phase-2.sh, regress script)
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
