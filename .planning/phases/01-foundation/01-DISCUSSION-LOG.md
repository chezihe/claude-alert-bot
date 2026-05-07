# Phase 1: Foundation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-07
**Phase:** 01-foundation
**Areas discussed:** Reporter language & install location

---

## Gray Areas Presented

| Option | Description | Selected for discussion |
|--------|-------------|-------------------------|
| Reporter 언어/배치 | POSIX sh+nc vs 번들된 Swift CLI vs Claude Code의 HTTP hook 타입. 어디에 설치할지 (번들 내부 vs ~/.claude/scripts vs /usr/local/bin) | ✓ |
| 앱 정체성 · 브랜딩 | Bundle ID, 표시 이름, 아이콘 소스 (Anthropic 상표 고려) | (Claude's discretion) |
| Phase 1 테스트 경험 | 위젯 이전에는 눈에 보이는 UI가 없음. 어떻게 Phase 1이 잘 작동함을 확인할지 | (Claude's discretion) |
| JSON 이벤트 계약 | Reporter가 보내는 필드 집합, 스키마 버저닝 전략, 멀티 세션 식별 키 조합 | (Claude's discretion) |

---

## Reporter language & transport

**Initial confusion**: User asked for clarification — first explanation was too technical. Re-explained with everyday analogies (쪽지 + 우체통 / 작은 배달원 / 웹사이트) and concrete distribution implications.

| Option | Description | Selected |
|--------|-------------|----------|
| POSIX sh + /usr/bin/nc -U | 의존성 0, 코드 10줄. /usr/bin/nc 절대 경로로 GNU nc 회피 | ✓ |
| 번들된 Swift CLI 헬퍼 | 연석으로 안정적. .app/Contents/MacOS/cab-report. ad-hoc 서명 범위에 포함됨 | |
| Claude Code HTTP hook 타입 | Reporter 적음. App이 127.0.0.1쪽 포트 열어 직접 수신. 포트 충돌 처리 고민 | |

**User's choice:** POSIX sh + /usr/bin/nc -U
**Notes:** User explicitly requested simplicity. Reinforces "don't over-engineer Reporter" stance — planner should resist Swift CLI temptation unless empirical evidence forces it.

---

## Reporter install location

| Option | Description | Selected |
|--------|-------------|----------|
| 사용자 폴더에 복사 (추천) | ~/Library/Application Support/ClaudeAlertBot/cab-report.sh. 앱 이동/업데이트에도 안정 | ✓ |
| 앱 내부에만 | Claude Alert Bot.app/Contents/Resources/cab-report.sh. 앱 이동 시 hook 깨짐 | |

**User's choice:** Copy to user-data folder
**Notes:** Standard macOS pattern. settings.json points to the stable user-data path. App update overwrites the user-data copy from the freshly bundled version.

---

## Claude's Discretion

User did not select these areas — sensible defaults captured in CONTEXT.md `<decisions>` (D-06 through D-12):

- **App identity / branding**: Bundle ID `com.claudealert.bot`, display name "Claude Alert Bot", original artwork (no Anthropic trademark). Real icon a Phase 2 prerequisite; Phase 1 uses placeholder.
- **Phase 1 verification UX**: OSLog (subsystem `com.claudealert.bot.hook`) + hook.log file + `cab-test` CLI helper for synthetic events.
- **JSON event envelope**: 9-field schema with `schema_version: 1`, missing fields as JSON `null`, locked for Phase 2 to consume.
- **Single-instance enforcement**: AF_UNIX socket bind exclusivity — no PID file, no distributed notification probe.
- **Socket path**: `~/Library/Application Support/ClaudeAlertBot/sock`.
- **Build pipeline**: `scripts/build.sh` runs `xcodebuild archive` + `codesign --force --deep --sign -`. No .dmg in Phase 1.
- **Project layout**: Single Xcode project with App + cab-test targets; Reporter as plain `.sh` in top-level `Reporter/`.

## Deferred Ideas

- Hook auto-installer with idempotent JSON5 merge → Phase 5
- macOS 15+ Gatekeeper "Open Anyway" docs + bypass-gatekeeper.command → Phase 6
- First-run onboarding wizard → Phase 5
- Final app icon artwork (Anthropic-trademark-safe) → Phase 2 prerequisite
- `cab-test` CLI's permanent placement / visibility → Phase 5
- Socket path collision recovery UX → Phase 5
