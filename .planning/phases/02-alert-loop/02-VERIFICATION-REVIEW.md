---
phase: 2
slug: alert-loop
review_of: 02-VERIFICATION.md
reviewer: gsd-verifier (independent second-pair-of-eyes)
reviewed: 2026-05-08
final_verdict: phase_2_goal_achieved
phase_gate_concur: green
---

# Phase 2 — Independent Verification Review

목적: executor 가 셀프-리포트한 `phase_gate: green` 을 ROADMAP Phase 2 SC#1..#6 + 20 REQ + 02-REVIEW carry-over 관점에서 코드 직접 grep / read 로 재검증. SUMMARY/VERIFICATION 의 주장은 신뢰하지 않고 산출물 자체를 본다.

**최종 결정:** **Phase 2 goal achieved** — 6/6 ROADMAP success criteria 가 코드 + 테스트 이름 + Pitfall #11 boot-order 직접 확인으로 입증됨. 단 1 개 FAIL (`2-11-02`) 은 cab-test UUID-per-invocation tooling artifact 로 검증되며 (THR-01 유닛 lock 별도 존재) — 코드 회귀 아님. carry-over 5+2개 모두 deferred-or-tracked.

---

## 1. Per-Criterion Verdict (ROADMAP Phase 2 SC#1..#6)

| # | Criterion | 독립 검증 결과 | Verdict |
|---|-----------|----------------|---------|
| #1 | 31s turn → widget (multi-Space / full-screen / Stage Manager / no focus steal) | `App/FloatingWidgetPanel.swift:14` 의 `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` + `:11` `.nonactivatingPanel` styleMask + `:26-27` `canBecomeKey/Main {false}` 직접 확인. SC#3 manual UAT (sub-checks 3, 4, 5, 8) 가 라이브 동작 보증. `verify_2_11_01` PASS — `present session=` OSLog. | **PASS** |
| #2 | 5s turn → no widget, no sound | `SessionRegistryTests.test_ingest_stop_belowThreshold_dropsAlert` (라인 90) 가 paired-session_id 로 below-threshold 경로를 lock — `XCTAssertEqual(snap.completed.count, 0)` + `XCTAssertEqual(notifier.presentCalls.count, 0)` 직접 확인. `2-04-01` PASS 가 이 lock 을 cover. `verify_2_11_02` FAIL 은 `cab-test/main.swift` UUID-per-invocation 으로 인한 e2e 도구 artifact (orphan-stop 경로로 분기) — `02-VERIFICATION.md SC#2 caveat` + V-7 carry-over 에서 정확히 파악됨. | **PASS (unit-locked; e2e tooling deferred V-7)** |
| #3 | Widget remains until clicked across Space / sleep-wake / lid; invisible when idle | `FloatingWidgetPanel.swift:16` `hidesOnDeactivate = false`. `WakeObserver.swift:21-23` 는 GC 만 kick — `hideWidget()` 호출 부재 (전체 grep: hideWidget 호출은 `NotificationOrchestrator.swift:81` `count==0` 분기가 유일). 즉 wake/lid 이벤트가 위젯을 dismiss 하는 코드 경로 자체가 없음 — WIDG-04 보존이 코드로 독립 입증됨. SC#3 11/11 sub-checks 사용자 `approved`. `WIDG-05` 는 `NotificationOrchestrator.refreshQueueState count==0 → hideWidget` 으로 idle invisibility 구현. | **PASS** |
| #4 | Settings change immediately + persist + Test button works | `SettingsStore.swift:13-17` `@AppStorage` 5 키 — UserDefaults backing 으로 즉시 반영 + 재시작 영속. `verify_2_11_04` PASS (defaults read = 120 after kill+restart). `SettingsView` 의 Test 버튼 → `SessionRegistry.injectTest` 경로 = `2-10-01` PASS. ⌘, → SwiftUI `Settings { SettingsView() }` (D2-29) `ClaudeAlertBotApp.swift:14-18` 직접 확인. | **PASS** |
| #5 | Kill+restart with pending → re-render from sessions.json; in-flight >6h GC | `AppDelegate.swift:52-98` 의 `Task { @MainActor in await SessionRegistry.shared.restore(); ...; try l.start() }` 블록에서 **`restore()` 가 `listener.start()` 보다 명시적으로 먼저** — Pitfall #11 코드 레벨 직접 확인. `SessionRegistry.swift:42-51` `restore()` 가 `refreshQueueState` 까지 broadcast. `SessionRegistryTests.test_runGC_removesStaleInFlight_SESS_04` 가 6h GC를 lock. `verify_2_11_05` PASS (`restore: inFlight=0 completed=1` OSLog). | **PASS** |
| #6 | Orphan stop → fallback alert with `?` (never silently dropped) | `SessionRegistry.swift:104-109` 의 `passes` 클로저: `case .none: return true   // THR-02 — never silently drop` 직접 확인. `SessionRegistryTests.test_THR_02_orphanStop_emitsWithNilDuration` 가 `XCTAssertEqual(notifier.presentCalls.count, 1)` + `XCTAssertNil(...durationSec)` lock. `verify_2_11_06` PASS (orphan stop 의 `notification.present` line). | **PASS** |

**6/6 ROADMAP success criteria PASS — independent confirmation.**

---

## 2. Harness vs VALIDATION Map 일치성

`scripts/verify-phase-2.sh` 는 26 row aggregator. 매핑:

| Wave | Rows | Plan-frontmatter REQ 매핑 | 결과 |
|------|------|---------------------------|------|
| 0 | 2-00-01, 02 | HOOK-02 (cab-test scaffold) | PASS, SKIP (rebuild guard) |
| 1 (02-02/03) | 2-02-01, 02, 2-03-01, 02 | WIDG-02 (perm copy/deep-link), domain models | 4× PASS |
| 2 (02-04/05) | 2-04-01, 02, 2-05-01 | SESS-01..04, THR-01/02, AUD-01, AppleScript helper | 3× PASS |
| 3 (02-06/07) | 2-06-01, 02, 2-07-01, 02 | AUD-01/02, WIDG-01/02/04/05/06/07 | 4× PASS |
| 4 (02-08/09) | 2-08-01, 02, 2-09-01, 02 | WIDG-03, SESS-04 | 4× PASS |
| 5 (02-10) | 2-10-01 | SET-01..04 | PASS |
| 6 (02-11) | 2-11-00..06, 99 | SC#1..6 e2e + Phase 1 regression | 6× PASS, 1× FAIL\* (2-11-02), 1× SKIP (2-11-03 manual) |

**관찰:**
- harness 는 **build-then-test** 패턴 (각 row 가 `xcodebuild test -only-testing:` 로 단위 테스트만 실행 또는 `xcodebuild build` + grep anchor) — 빠르고 결정적.
- e2e row (2-11-01, 02, 06) 은 `cab-test --event=...` + `log show --last 5s ... predicate` 으로 OSLog 가시성 의존 — Phase 1 V-2 cold-cache flush race 를 상속하지만 Pitfall #11 wiring 으로 steady-state 는 안정.
- VALIDATION.md 와의 row-by-row diff 는 별도 기록 (02-VERIFICATION.md 본문에 SC#2 caveat 으로 정확히 명시) — 문서 stale 없음.

---

## 3. Adversarial Probes

검증자가 must-haves 를 깨뜨리려 시도한 결과:

### 3a. WR-01 `dedupeSet` 무한 증가 → SC#1 정확성 영향?
**시도:** 같은 (sid, ts/2s bucket) 두 번 → 두 번째 alert 가 drop 되는가? **결과:** 코드(`SessionRegistry.swift:96-128`)는 dedupe 가 **sound 결정만** 게이트 (`playSoundOnce: soundEnabled && !isDup`); `completed.append(session)` 은 dup 여부와 무관하게 항상 실행 → widget present 는 항상 발생. **정확성 영향 없음** — D2-20 sound-only dedupe scope 가 코드로 정확히 구현됨. WR-01 의 leak 은 perf concern only, SC 에 영향 없음.

### 3b. WR-04 `WorkspaceFrontmostObserver` O(N) AppleScript → SC#1/#3 alert drop?
**시도:** N pending 상태에서 iTerm2 frontmost 시 N × 1s 직렬 AppleScript 가 alert 를 drop 하는가? **결과:** `WorkspaceFrontmostObserver.swift:25` `bundleIdentifier == "com.googlecode.iterm2"` 1차 필터 — non-iTerm 활성화는 AppleScript 호출 자체 없음. iTerm 활성화 시 N 회 직렬 호출이 발생하지만 (a) 모두 non-blocking Task, (b) `clearOne` 만 호출 (drop 아님 — 사용자가 정확한 탭으로 돌아왔으므로 dismiss 가 의도된 동작 = D2-15). **alert drop 메커니즘 부재.** Latency concern only.

### 3c. SC#2 cab-test 도구 한계가 진짜 coverage gap 인가?
**시도:** `SessionRegistryTests.swift:90-106` 직접 read — `test_ingest_stop_belowThreshold_dropsAlert` body 가 (i) `seedInFlightForTesting(sessionID: sid, started: t0, ...)` 로 paired in-flight 시드, (ii) `r.ingest(stop, thresholdSeconds: 30, ...)` 로 5초 차 stop 입력, (iii) `XCTAssertEqual(snap.completed.count, 0)` + `presentCalls.count == 0` 로 completed/notifier **양쪽** 검증. THR-01 의 matched-pair below-threshold 경로가 unit 으로 완전히 lock 됨. **SC#2 의 underlying logic 은 unit 으로 정확히 cover.** `2-11-02` 는 `cab-test/main.swift` 가 `--session-id=` argv 미지원 (V-7) 인 도구 한계만 노출.

### 3d. Pitfall #11 boot order 가 실제로 보장되는가?
**시도:** `AppDelegate.swift:52-98` 직접 read — `Task { @MainActor in ... await SessionRegistry.shared.restore(); ... ; try l.start() }` 블록. `await restore()` 가 `try l.start()` 앞에 있고 둘 다 같은 Task 내부 — Swift concurrency suspension semantics 상 `await` 는 반드시 완료 후 다음 statement 진행. `signalSources.append` 만 Task 외부에 (signal handler 는 Phase 2 wiring 무관). **순서 코드 레벨로 보장됨.** OSLog `[lifecycle] Phase 2 components wired` → `listener bound (Phase 2 wiring complete)` 시퀀스가 02-VERIFICATION.md SC#5 evidence 로 캡처.

### 3e. WakeObserver 가 위젯을 dismiss 하지 않음 (SC#3 sleep/wake 반례)
**시도:** `grep -nE "(hide|orderOut|dismiss|fadeOut)" App/WakeObserver.swift` → 0 matches. WakeObserver 는 `onWake: () -> Void` 클로저만 받고 AppDelegate 에서 `{ Task { await SessionRegistry.shared.runGC() } }` 만 주입. **위젯 dismiss 경로 부재** — SC#3 의 sleep/wake 보존이 코드로 입증됨.

**모든 probe 가 must-haves 를 깨뜨리지 못함.**

---

## 4. Carry-over Disposition

02-REVIEW.md 의 5 warnings (1 resolved-on-investigation) + 7 info + 02-VERIFICATION.md 의 V-7, V-8 NEW 모두 점검:

| Carry-over | 분류 | 처리 적절성 | 평가 |
|------------|------|-------------|------|
| **WR-01** dedupeSet unbounded growth | Warning | Phase 4 stress-hardening 으로 자연 흡수 (`runGC` 에 bucket-cutoff 추가) | 적절히 deferred — SC 영향 없음 (probe 3a) |
| **WR-02** sound double-gate | Warning RESOLVED-ON-INVESTIGATION | D2-20 dedupe-scope vs AUD-02 gate 의 분리가 의도적, 4-매트릭스 모두 정확 | 적절히 closed |
| **WR-03** injectTest auto-dismiss Task 누적 | Warning | Phase 4 polish | low-priority — `clearOne` no-op 은 안전 |
| **WR-04** Frontmost observer O(N) AppleScript | Warning | Phase 4 polish (single-query + Swift-side compare) | latency only — drop 없음 (probe 3b) |
| **WR-05** decode-error silent drop | Warning | Phase 5 onboarding 의 user-facing surface 와 함께 처리 | 적절히 deferred |
| **WR-06** popover NSHostingController 재할당 | Warning | Phase 4 polish | UI 깜빡임 정도 — SC 영향 없음 |
| IN-01..07 (7 info) | Info | 코드 위생 — Phase 3+ 자연 진화 | 적절 |
| **V-2** listener-uptime cold-cache | Phase 1 carry-over | Pitfall #11 wiring 으로 steady-state 안정화; cold-cache OSLog flush 만 잔존 | 적절히 흡수 |
| **V-3..V-6** | Phase 5/6 owned | 그대로 carry-forward | 적절 |
| **V-7 NEW** cab-test UUID-per-invocation | Phase 2 신규 | `02-VERIFICATION.md ## Open Follow-ups` 명시 + Phase 3+ verifier polish | 적절히 logged — SC#2 unit lock 우선순위 명확 |
| **V-8 NEW** WIDG-02 premature `[x]` | Phase 2 신규 | `deferred-items.md` + 02-VERIFICATION.md V-8 명시; underlying anchor 가 02-07 에 실재하므로 retroactively 정당화됨 | 적절히 closed-with-note |

**어느 항목도 promotion 필요 없음.** 모두 (a) 의도적 design decision (WR-02), (b) Phase 4/5/6 가 명시적으로 owning, 또는 (c) tooling polish 로 정확히 분류됨.

---

## 5. 추가 관찰

### 5a. D2-29 compliance 직접 확인
- `grep -n '@main' App/*.swift` → `App/ClaudeAlertBotApp.swift:10:@main` 단 1 hit
- `grep -n 'Settings\s*{' App/*.swift` → `App/ClaudeAlertBotApp.swift:15` `Settings { SettingsView() }`
- `grep -n 'NSApp\.activate' App/*.swift` → 주석 1 hit (`AppDelegate.swift:103`), 호출 0 hit. **LSUIElement invariant 보존.**

### 5b. SessionRegistry actor 보존
- `actor SessionRegistry` (라인 20) — single source of truth
- `@MainActor protocol NotifierProtocol` (라인 8) — UI hop 점이 type-system 으로 강제
- `func peekPending() -> [CompletedSession] { Array(completed) }` (라인 154-156) — 외부 iteration race 차단

### 5c. Apple Silicon ad-hoc 서명 보존
- `build/export/ClaudeAlertBot.app/Contents/MacOS/ClaudeAlertBot` (718448 bytes) + `cab-test` (163712 bytes) 모두 존재.
- Phase 1 의 `verify_1_00_02` 가 `verify_2_11_99` 통해 regression-tested (PASS 보고됨).

---

## 6. 최종 판정

### Verdict: **Phase 2 goal achieved.**

근거:
- **6/6 ROADMAP success criteria** 가 직접 코드 read + 단위 테스트 이름 lookup + Pitfall #11 코드-레벨 ordering + manual UAT (사용자 `approved` 11/11 sub-checks) 으로 입증됨.
- **20/20 REQ** (HOOK-02, SESS-01..04, THR-01/02, WIDG-01..07, AUD-01/02, SET-01..04) 가 plan frontmatter + 단위 테스트 + e2e row 로 paired-verified.
- **단 1개 FAIL row (`2-11-02`)** 는 cab-test UUID-per-invocation 도구 한계로 정확히 분류 — underlying THR-01 below-threshold 경로는 `test_ingest_stop_belowThreshold_dropsAlert` 이 `presentCalls.count == 0` 까지 검증하여 lock. V-7 로 Phase 3+ verifier polish 로 추적.
- **5 warnings (1 resolved) + 7 info + 2 NEW carry-over** 모두 (a) 의도된 디자인, (b) Phase 4/5/6 명시 owner, 또는 (c) tooling polish 로 정확히 분류 — Phase 3 entry gate 를 막지 않음.
- **adversarial probes 5 종** 모두 must-haves 를 깨뜨리지 못함.
- executor 의 `phase_gate: green` 결정에 동의 — independent confirmation.

### Concur with executor's gate decision: **green.**

### Phase 3 unblock: **YES.**

Phase 3 는 `WidgetPopoverController.onRowClick(sessionID:)` 의 `[would-jump session=<uuid>]` OSLog anchor 를 실제 AppleScript jump 호출로 교체하는 작업; 그 anchor 는 02-08-PLAN 에서 생성되었고 `verify_2_08_02` 가 lock — Phase 3 의 진입 prerequisite 충족.

---

## 7. 검증자가 직접 실행한 명령 (재현 가능)

```sh
# Pitfall #11 ordering — restore() before listener.start()
grep -n "await SessionRegistry.shared.restore\|try l.start" App/AppDelegate.swift
# → restore() at line 54, l.start() at line 91 — same Task block

# THR-01 below-threshold unit lock
grep -nE "test_ingest_stop_belowThreshold_dropsAlert|presentCalls\.count, 0" \
  ClaudeAlertBotTests/SessionRegistryTests.swift

# THR-02 orphan-stop fallback (never silently drop)
grep -n "case .none:" App/SessionRegistry.swift
# → line 107: `case .none:        return true   // THR-02 — never silently drop`

# WakeObserver does NOT dismiss widget
grep -nE "hide|orderOut|dismiss|fadeOut" App/WakeObserver.swift
# → 0 matches

# WIDG-01 collectionBehavior triple
grep -n "collectionBehavior" App/FloatingWidgetPanel.swift
# → line 14: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

# LSUIElement invariant (no NSApp.activate calls)
grep -n "NSApp.activate" App/*.swift | grep -v "//"
# → empty (only comment hits)

# D2-29 SwiftUI App + Settings scene
grep -nE "^@main|Settings\s*\{" App/ClaudeAlertBotApp.swift

# WorkspaceFrontmostObserver bundle-ID gate
grep -n "com.googlecode.iterm2" App/WorkspaceFrontmostObserver.swift
# → line 25 — non-iTerm activations are filtered before AppleScript dispatch
```

모두 한 세션에서 재현 가능. 기능적 회귀 0건, BLOCKER 0건.

---

*Reviewed by gsd-verifier — 2026-05-08*
