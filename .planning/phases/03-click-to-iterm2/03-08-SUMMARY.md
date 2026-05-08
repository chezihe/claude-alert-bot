---
phase: 03-click-to-iterm2
plan: 08
subsystem: settings-ui
tags: [phase-3, wave-5, d3-15, d3-16, d3-18, d3-19, d3-20, t-copy-drift-01, set-05]
requires:
  - 03-04 (AppleScriptHelper.testConnection() — focus-frontmost script + JumpResult mapping)
  - 02-02 (PermissionDeepLink.openAutomationPreferences)
  - 02-10 (SettingsView base — Form + locked-copy contract)
provides:
  - SettingsStore.lastConnectionTestAt @Published Date? (UserDefaults-backed, sentinel zero = nil)
  - SettingsView SET-05 Section (Korean button + EN minimal status labels + 5s auto-hide + persisted last-success line)
  - 5 new locked-copy `static let` constants on SettingsView (T-COPY-DRIFT-01 quintet)
  - 5 new XCTAssertEqual verbatim regression guards in SettingsViewTests
affects:
  - SettingsView.body (one new Section appended; existing Sections untouched)
  - SettingsStore.init (one new UserDefaults load appended; existing applescriptPermission load untouched)
tech-stack:
  added: []  # zero new deps; uses existing SwiftUI + Foundation surface only
  patterns:
    - "@Published Date? + UserDefaults TimeInterval bridge (sentinel `> 0`)"
    - "Task<Void, Never>? as cancellable auto-hide timer (cancel-then-replace on each press)"
    - "switch on JumpResult with defensive fallback for unreachable cases (.missing/.timeout/.otherError)"
key-files:
  created:
    - .planning/phases/03-click-to-iterm2/03-08-SUMMARY.md
  modified:
    - App/SettingsStore.swift  # +17 lines (Published lastConnectionTestAt + UserDefaults bridge + init load)
    - App/SettingsView.swift   # +83 lines (5 copy constants + 3 @State + Section + 2 helpers)
    - ClaudeAlertBotTests/SettingsViewTests.swift  # +27 lines (5 new copy assertions)
decisions:
  - "Korean button label + Korean section header + minimal-English status labels — locked split per D3-15/D3-19 + minimal-UI-copy memory rule. Future translation passes MUST update constant + assertion in lockstep."
  - "Date? backed by UserDefaults TimeInterval (key `last_connection_test_at`) with sentinel `> 0` — mirrors the applescriptPermission @Published+UserDefaults bridge in SettingsStore. @AppStorage rejected because Date? has no native conformance."
  - ".permissionDenied path opens the System Settings deep-link AND surfaces the inline label — D3-16 deny path: button + banner + deep-link all visible together so the user has every recovery affordance."
  - "5s auto-hide via a single Task<Void, Never>? stored in @State; each press cancels the prior pending hide before scheduling a new one (cancel-then-replace pattern, not a queue)."
  - "Defensive switch-case for .missing/.timeout/.otherError fallback to `iTerm2 is not running` label — testConnection contractually never returns these (per AppleScriptHelper line 181-196), but JumpResult is exhaustive and Swift requires the cases."
metrics:
  duration: "~3 min (auto-mode, single executor session)"
  tasks_completed: 3
  commits: 3
  files_modified: 3
  files_created: 1  # this SUMMARY
  tests_added: 5
  tests_total: "108/108 pass (was 103 + 5 new); zero regressions"
  build_status: "BUILD SUCCEEDED (xcodebuild -scheme ClaudeAlertBot -destination 'platform=macOS')"
  completed_date: "2026-05-09"
---

# Phase 3 Plan 08: SET-05 Self-Test Button + SettingsStore Persistence Summary

iTerm2 자동화 권한과 연결성을 사용자가 직접 확인할 수 있는 SET-05 자가 진단 버튼을 SettingsView에 추가하고, 마지막 성공 시간을 SettingsStore에 영속화한다. Korean 섹션/버튼 + minimal-English 상태 라벨로 D3-15/D3-19 카피 규칙을 잠그고, T-COPY-DRIFT-01 회귀 가드 5개를 SettingsViewTests에 추가했다.

## 1. What Shipped

### 1.1 `App/SettingsStore.swift` (+17 lines)

`@Published var lastConnectionTestAt: Date?` 추가. 기존 `applescriptPermission`의 `@Published + 수동 UserDefaults` 패턴을 미러링하여 `Date?`를 `TimeInterval` 키 `last_connection_test_at`로 직렬화한다.

```swift
@Published var lastConnectionTestAt: Date? {
    didSet {
        if let d = lastConnectionTestAt {
            UserDefaults.standard.set(d.timeIntervalSince1970, forKey: "last_connection_test_at")
        } else {
            UserDefaults.standard.removeObject(forKey: "last_connection_test_at")
        }
    }
}
```

`init()`에서 `UserDefaults.standard.double(forKey:)`이 키 부재 시 0을 반환하므로 `> 0` 센티널로 nil 대체. `@AppStorage`는 `Date?`에 native 미지원이라 사용 불가.

### 1.2 `App/SettingsView.swift` (+83 lines)

#### 5개 잠금 카피 상수 (verbatim — T-COPY-DRIFT-01 quintet)

```swift
static let connectionTestHeading      = "iTerm2 연결"
static let connectionTestLabel        = "iTerm2 연결 테스트"
static let connectionTestSuccessFmt   = "Connected at %@"
static let iTermNotRunningLabel       = "iTerm2 is not running"
static let connectionDeniedLabel      = "Automation permission denied"
```

#### 3개 @State (transient SET-05 결과 + 자동 hide 타이머)

```swift
@State private var connectionTestResult: JumpResult? = nil
@State private var connectionTestResultAt: Date = Date()
@State private var hideResultTask: Task<Void, Never>? = nil
```

#### 신규 Section (기존 Test Section 뒤, Form 닫는 중괄호 앞)

- 버튼 누르면 `Task { await runConnectionTest() }`
- `connectionTestResult`이 있으면 5s transient 라벨 우선 표시, 없으면 `store.lastConnectionTestAt`이 있을 때 마지막 성공 시간 표시
- 4가지 분기:
  - `.ok` → secondary `Connected at HH:mm`
  - `.iTermNotRunning` → secondary `iTerm2 is not running`
  - `.permissionDenied` → red `Automation permission denied`
  - `.missing | .timeout | .otherError` → 방어적 fallback (testConnection은 이 경우들을 계약적으로 반환하지 않지만 Swift switch는 exhaustive 요구)

#### `runConnectionTest()` 핸들러

- `AppleScriptHelper.shared.testConnection()` 호출 후 MainActor에서 상태 갱신
- `.ok` → `store.lastConnectionTestAt = Date()` 영속화
- `.permissionDenied` → `PermissionDeepLink.openAutomationPreferences()` 자동 호출 (D3-16 deny path: 버튼 + 배너 + 딥링크가 모두 함께 보임)
- 5초 자동 hide: 이전 `hideResultTask?.cancel()` → 새 Task 스케줄 (cancel-then-replace, 큐가 아님). `Task.isCancelled` 가드로 race 방지

#### `hhmm(_:)` 포매터

`HH:mm` 형식의 `DateFormatter` 호출 헬퍼.

### 1.3 `ClaudeAlertBotTests/SettingsViewTests.swift` (+27 lines)

5개 verbatim XCTAssertEqual 추가. 기존 8개는 무손상.

```swift
func test_settingsCopy_connectionTestHeading_isKorean()           // "iTerm2 연결"
func test_settingsCopy_connectionTestLabel_isKoreanVerbatim()     // "iTerm2 연결 테스트"
func test_settingsCopy_connectionTestSuccessFmt_isMinimalEnglish() // "Connected at %@"
func test_settingsCopy_iTermNotRunningLabel_isMinimalEnglish()    // "iTerm2 is not running"
func test_settingsCopy_connectionDeniedLabel_isMinimalEnglish()   // "Automation permission denied"
```

## 2. Verification

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| `xcodebuild build -scheme ClaudeAlertBot` | BUILD SUCCEEDED | BUILD SUCCEEDED | PASS |
| `xcodebuild test … -only-testing SettingsViewTests` | 13/13 pass | 13/13 pass (~0.007s) | PASS |
| Full test target | 108/108 pass | 108/108 pass (~2.732s) | PASS |
| `grep -c connectionTestLabel App/SettingsView.swift` | ≥2 | 2 | PASS |
| `grep -c lastConnectionTestAt App/SettingsStore.swift` | ≥2 | 3 | PASS |
| `grep -c PermissionDeepLink.openAutomationPreferences App/SettingsView.swift` | =1 | 1 | PASS |
| 5 new verbatim copy assertions present | 5 | 5 | PASS |

## 3. Locked-Copy Quintet (verbatim)

| Constant | Value | Source |
|----------|-------|--------|
| `SettingsView.connectionTestHeading` | `iTerm2 연결` | D3-15 (Korean section header — Phase 2 톤 일치) |
| `SettingsView.connectionTestLabel` | `iTerm2 연결 테스트` | D3-15 (Korean button label — testButtonLabel과 톤 일치) |
| `SettingsView.connectionTestSuccessFmt` | `Connected at %@` | D3-19 (minimal English, `%@` = HH:mm) |
| `SettingsView.iTermNotRunningLabel` | `iTerm2 is not running` | D3-19 |
| `SettingsView.connectionDeniedLabel` | `Automation permission denied` | D3-19 |

Future translation pass MUST update both the constant and the matching assertion in lockstep — drift = test fails on next CI run.

## 4. Decisions Made

### 4.1 Korean button + English status (T-COPY-DRIFT-01)
- **Decision**: 섹션 헤더 + 버튼 라벨은 한국어, 상태 라벨 3개는 minimal English.
- **Why**: minimal-UI-copy memory rule + Phase 2 settings UI 톤 (`testButtonLabel = "테스트 알림 보내기"`)과 일치. 상태 라벨은 macOS 시스템 톤(secondary text, 짧고 객관적)에 맞춰 영어.
- **Alternative rejected**: 모두 영어 (Phase 2와 mismatch) / 모두 한국어 (상태 라벨이 시스템 톤에서 벗어남).

### 4.2 Date? via UserDefaults TimeInterval (not @AppStorage)
- **Decision**: `@Published var lastConnectionTestAt: Date?` + 수동 `UserDefaults.set(d.timeIntervalSince1970, ...)` 브리지.
- **Why**: `Date?`에 `@AppStorage` native 지원이 없고 `RawRepresentable` wrapper는 어색. 기존 `applescriptPermission`이 같은 패턴을 사용 (Phase 2 02-10).
- **Sentinel**: `> 0` (UserDefaults.double은 키 부재 시 0 반환; 1970 epoch는 어떤 실제 테스트 시간보다도 이른 값이므로 `!= 0` 대신 `> 0`이 가장 깨끗).

### 4.3 .permissionDenied → 자동 deep-link + inline 라벨 (D3-16 deny path)
- **Decision**: `.permissionDenied` 결과 시 `PermissionDeepLink.openAutomationPreferences()`를 즉시 호출 + inline `Automation permission denied` 라벨도 함께 표시.
- **Why**: 사용자가 명시적으로 "iTerm2 연결 테스트" 버튼을 눌러 denied가 나왔다는 것은 본인의 의지로 점검 중인 상태. 라벨 한 줄만 보여주면 다음 액션이 모호해짐. PermissionBannerView (Phase 2 02-10)는 영구적 surface, SET-05 inline 라벨은 클릭 시점 피드백.
- **Alternative considered**: 라벨만 보여주고 사용자가 별도 클릭하도록 — 클릭 1회 추가 비용 + Phase 2 배너와 중복.

### 4.4 5s auto-hide via cancellable Task<Void, Never>?
- **Decision**: 전역 큐가 아닌 단일 `@State private var hideResultTask: Task<Void, Never>?`. 새 press마다 `hideResultTask?.cancel()` 후 새 Task 스케줄.
- **Why**: 빠른 연속 클릭 시 가장 최근 결과만 5s 표시되어야 함 (이전 결과가 먼저 사라져 새 결과가 잠시 보이다 또 사라지는 race를 방지). cancellation pattern은 SwiftUI에서 idiomatic — `DispatchWorkItem` 기반 hover-intent 패턴(02-08)과 결이 같지만 SwiftUI Task 생명주기 활용.
- **Existing pattern check**: SettingsView 자체에는 hideResultTask 같은 패턴이 이전에는 없었음. WidgetPopoverController가 hover-intent용 cancellable DispatchWorkItem을 가지고 있으나 다른 layer (AppKit) — 직접 mirror가 아니라 동일 철학(cancel-then-replace)의 SwiftUI 변형.

### 4.5 Defensive switch fallback for unreachable JumpResult cases
- **Decision**: `.missing | .timeout | .otherError` → `iTerm2 is not running` 라벨 fallback.
- **Why**: testConnection는 contractually `.ok | .iTermNotRunning | .permissionDenied`만 반환 (AppleScriptHelper 181-196 line의 switch). 그러나 `JumpResult`는 6 case enum이고 Swift switch는 exhaustive를 요구. 미래 누군가 testConnection을 확장해 다른 case를 반환하면 UI가 invariants를 보존하면서 안전한 안내를 제공하도록.

## 5. Deviations from Plan

**None — plan executed exactly as written.**

Plan §verification은 SettingsViewTests의 `connectionTestLabel` grep이 1을 반환하길 기대했으나 실제 2 (테스트 함수 이름 + assertion). 함수 이름 카운트를 plan이 예측하지 못한 사항이며 의미 있는 deviation은 아님 — 5개 assertion이 전부 패스했다는 점이 verbatim copy lock의 결정적 증거.

## 6. Threat Mitigations Applied

| Threat ID | Status |
|-----------|--------|
| T-COPY-DRIFT-01 | **Mitigated** — 5개 verbatim XCTAssertEqual + `static let` constants. 향후 번역 패스가 상수만 바꾸고 assertion을 빠뜨리면 CI에서 즉시 실패. |
| T-PERM-LEAK | Accepted (single-user local app; no real disclosure surface). |
| T-AUTOACTIVATE-01 | Accepted, documented (사용자가 명시 버튼을 눌렀으니 activation은 요청된 동작). |

## 7. Wave 5 Wiring Notes for Downstream

- **02-11 AppDelegate**: 변경 없음. SettingsView는 자기 의존을 singleton(SettingsStore.shared, AppleScriptHelper.shared, PermissionDeepLink)으로 모두 해결. 02-11 boot order에 SET-05 관련 추가 단계 없음.
- **03-09 manual checkpoint** (예정): 실제 macOS에서 첫 press → TCC dialog, 두 번째 press → focus-frontmost 동작, denied 상태에서의 deep-link 열림을 수동 확인.
- **D3-20 lastConnectionTestAt 표시 안정성**: 앱 재시작 후 Settings 재오픈 시 `Connected at HH:mm`이 보이는지 — UserDefaults TimeInterval bridge로 보장 (수동 검증은 03-09 위임).

## 8. Commit Trail

```
8a1a0c9 test(03-08): T-COPY-DRIFT-01 verbatim assertions for SET-05 copy
633e099 feat(03-08): add SET-05 iTerm2 connection-test Section to SettingsView
752218c feat(03-08): add lastConnectionTestAt @Published to SettingsStore (D3-18)
```

## 9. Self-Check: PASSED

- [x] App/SettingsStore.swift 존재, `lastConnectionTestAt` 등장 횟수 3 (≥2 요구).
- [x] App/SettingsView.swift 존재, `connectionTestLabel` 등장 횟수 2 (≥2 요구), `PermissionDeepLink.openAutomationPreferences` 등장 횟수 1 (=1 요구).
- [x] ClaudeAlertBotTests/SettingsViewTests.swift 존재, 5개 새 assertion 함수 모두 grep으로 확인됨.
- [x] 3개 commit 모두 git log에서 확인됨 (`8a1a0c9`, `633e099`, `752218c`).
- [x] xcodebuild build 성공.
- [x] xcodebuild test 108/108 통과, SettingsViewTests 13/13 통과, 0 regression.
- [x] .planning/phases/03-click-to-iterm2/03-08-SUMMARY.md 작성 완료 (이 파일).
