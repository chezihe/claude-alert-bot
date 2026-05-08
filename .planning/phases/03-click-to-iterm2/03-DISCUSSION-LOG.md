# Phase 3: Click-to-iTerm2 - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-08
**Phase:** 3-Click-to-iTerm2
**Areas discussed:** 어댑터 seam (사용자 선제 질문), 세션 ID 정규화, TTY 폴백 구현 전략, '세션 없음' 친절 에러 UX, SET-05 'iTerm2 연결 테스트' 버튼

---

## 사용자 선제 질문 — 어댑터 seam (멀티-터미널 v2 대비)

사용자 질문: "지금은 iterm만 처리하지만 나중에 intellij vscode등의 터미널이나 플러그인도 트리거링 하고싶은데 어떤 방향이 좋을까?"

| Option | Description | Selected |
|--------|-------------|----------|
| 풀 멀티-터미널 추상화 (TerminalAdapter 프로토콜 + 다중 구현 + dispatch 로직 v1에서) | 미래 옵션 가치 최대 | |
| 어댑터 자리만 + iTerm2 단일 구현 + envelope 분기 키 마련 | 추상화 한 겹으로 잘못된 모양 굳히기 회피, REQUIREMENTS v2 라벨과 일관 | ✓ |
| 어댑터 없이 iTerm2 직접 호출, 멀티-터미널 시점에 리팩터 | 지금 가장 단순, 미래 비용은 큼 | |

**User's choice:** 어댑터 자리만 + iTerm2 단일 구현
**Notes:** D-ADAPTER로 잠금. `TerminalJumper` 프로토콜 + `ITerm2Jumper` 단일 구현. Reporter envelope에 `term_program` 옵션 필드(v2 dispatch 키 자리). schema_version=1 호환.

---

## 영역 1 — 세션 ID 정규화

상황 발견: `ITERM_SESSION_ID` env var = `w0t0p1:UUID` 형식, iTerm2 AppleScript `id of session` = UUID-only 반환. 현재 `AppleScriptHelper.scriptSource`의 `s == target` 비교가 항상 false → Phase 2 D2-14/D2-15 silent-failure.

| Option | Description | Selected |
|--------|-------------|----------|
| A. Reporter 셸이 strip 후 송신 | 단일 source of truth = 순수 UUID | |
| B. App ingest 단계에서 strip (`HookListener` decode 직후 또는 `SessionRegistry.ingest` 전) | Swift 한 곳, Reporter dumb 유지, sessions.json 마이그레이션 필요 | ✓ |
| C. AppleScript-side 양쪽 포맷 비교 | AppleScript 복잡도 ↑, 매 호출 비용 | |

**User's choice:** B (App ingest 정규화)
**Notes:** D3-01~05로 잠금. 추출자 `iTermSessionID.uuid(fromRaw:)`, `SessionRecord.itermSessionID` 의미를 UUID-only로 재정의, `SessionStore.load` 마이그레이션, 회귀 테스트, Reporter `TERM_PROGRAM` 캡처 추가(D-ADAPTER 활용).

---

## 영역 2 — TTY 폴백 구현 전략

| Option | Description | Selected |
|--------|-------------|----------|
| 갈래 B: 순수 AppleScript walk + UUID-우선 → TTY-폴백 (ROADMAP 잠금 그대로) | 외부 사용자 안전(tmux/nix-shell 환경) | |
| 갈래 A: UUID 단일 매칭, TTY 폴백 v1 제외 (사용자 결정 후 채택) | 구현 절반 감소, ROADMAP/REQUIREMENTS 정정 필요 | ✓ |
| TokenEater 풀 차용 (kp_eproc.e_tdev / osascript subprocess / resolveHostApp) | 정확도 ↑, BSD 코드 복잡도 ↑ | |

**User's choice:** 갈래 A (UUID 단일 매칭)
**User's notes:** "사용하던 세션이 꺼지면 클로드로 하고있던 작업도 중지되는거라 굳이 그 세션을 찾을라고 할필요가 있을까. 나는 켜져있는 iterm의 작업 완료를 알고싶은거라 내가 iterm을 종료하고 새로키면 당연히 이전 작업 세션(클로드 대화를 말하는거양)을 보고 어디까지 했는지 보겠지?"

**Claude의 안전 플래그:** ROADMAP "Locked Architectural Decisions"의 multi-strategy fallback과 충돌 + Phase 3 SC#6(TTY fallback)이 명시. 사용자에게 "갈래 A 가시면 ROADMAP/REQUIREMENTS 정정 필요" 명시 후 동의. nix-shell/컨테이너 환경의 `ITERM_SESSION_ID` 누락 케이스는 v2 후보로 deferred.

---

## 영역 3 — '세션 없음' 친절 에러 UX

사용자가 1차 답변 "고민좀 해볼게 귀엽게 표현할 방법이 없는지" → Claude가 카피 8개 + 시각효과 5개 후보 제시 → 사용자 2차 답변 "애니메이션 효과라던가 그런거로 넣을게" (텍스트 최소화).

| Option | Description | Selected |
|--------|-------------|----------|
| 1. Inline row 텍스트 변환 (예: "이 친구 이미 갔어요 👋") + fade | 텍스트 카피 + 시각 | |
| 2. 별도 toast 윈도우 | NSPanel/Window 추가, 임팩트 ↑ | |
| 3. Popover footer 메시지 | 정보 보존 + 일괄 정리 | |
| 4. 도리도리 + collapse 애니메이션 (텍스트 없음) | 캐릭터성, 간결, 코드 부담 최소 | ✓ |

**User's choice:** 4 (애니메이션 단일 처리)
**Notes:** D3-11~14 잠금. 도리도리(±12° 0~0.3s) + collapse/fade(0.3~0.7s) → SessionRegistry.clearOne. 텍스트/사운드/시스템 알림 없음. quick-260508-001(클로드 아이콘 통통 튀기)과 톤 일관.

---

## 영역 4 — SET-05 "iTerm2 연결 테스트" 버튼 의미

| Option | Description | Selected |
|--------|-------------|----------|
| A. frontmost iTerm2 탭 focus (앱이 자동 선택) | 단순, 사용자 사전 설정 불필요, ROADMAP SC#3 충족 | ✓ |
| B. 사용자가 사전에 "테스트 대상 탭" 북마크 | UX 무거움, 부가 설정 필요 | |
| C. 첫 번째 발견 iTerm2 탭 focus (임의) | 동작 의미 모호 | |
| D. focus 안 하고 cheap-query만 (read-only) | ROADMAP SC#3 "real focus operation" 명시와 충돌 | |

**User's choice:** A (frontmost focus)
**Notes:** D3-15~20 잠금. AppleScriptHelper actor가 컴파일 스크립트 3개 보유(cheap-query 1s + jump-by-uuid 3s + focus-frontmost 3s). SettingsStore.lastConnectionTestAt 영속, 5초간 "✓ 연결됨 (HH:mm)" 인라인. 한국어 카피 락 패턴 인계.

---

## Claude's Discretion

사용자가 명시 결정 안 한 항목, 합리적 기본값으로 진행 (CONTEXT.md `<decisions>` § Claude's Discretion 참조):

- 클릭 디바운스 500ms = row 단위 (앱-전역 lock 회피)
- 동시 jump-in-flight = 같은 row 재클릭 무시, 다른 row는 별도 task (actor serial queue가 직렬화)
- Jump 성공 후 popover 즉시 dismiss
- AppleScript jump 스크립트 구조 = T-INJECTION-01 정적 source + Swift-side post-매칭 또는 NSAppleScript 외부 변수 주입 (plan-phase RESEARCH 후 결정)
- TerminalJumper protocol/ITerm2Jumper 파일 분리 + 주입 패턴

---

## Deferred Ideas

### v2 (멀티-터미널 / TTY 폴백)
- TTY 폴백 매칭 (env-stripped shell 환경): nix-shell/devbox/컨테이너에서 `ITERM_SESSION_ID` 누락 시 hook envelope `tty`로 sessions walk. 새 요구사항 제안 `JUMP-FALLBACK-01`.
- TokenEater 차용 (`kp_eproc.e_tdev`, `osascript` -1743 subprocess, `resolveHostApp`).
- MTERM-01..04 멀티-터미널 dispatch (VSCode/JetBrains/Warp/Ghostty) — D-ADAPTER seam 위에 새 `TerminalJumper` 구현체 추가.

### Phase 6
- TokenEater MIT 라이센스 출처 README CREDIT 표기 (차용 안 했지만 ROADMAP reference로 명시).

### Phase 4+
- 카운터 배지 UI(Phase 4 명시), 5+ 동시 완료 dedup, 10-hooks-in-100ms 스트레스(Phase 4).

### 폴리싱
- 위젯 아이콘 idle bob / 클릭 spring 추가 모션 (D2-11 그대로).
