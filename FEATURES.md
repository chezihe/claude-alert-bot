# Claude Alert Bot v2 — 기능 정리

> 레퍼런스 프로토타입: `Claude Alert Bot - Prototype v2.html`
> 시각/모션/인터랙션은 HTML이 진실의 원천. 본 문서는 기능 단위 체크리스트.

---

## 1. 메뉴바 위젯 (Status Item)

| 기능 | 설명 |
|---|---|
| **Status item glyph** | 메뉴바 우측에 떠있는 픽셀 아트 글리프 (Claude 오렌지 `#D97757`) |
| **Idle 애니메이션** | Bounce / Heart / Ring / Roam — 사용자 선택, 무한 루프 |
| **Rage 애니메이션** | 맥북을 포물선으로 던지고 충격 이펙트 발생. **자동 트리거 없음**, 사용자가 선택할 때만 반복 |
| **새 알림 모먼트** | 글리프 펄스(scale + rotate) + 소나 링 1회 발사 |
| **+N 배지** | 큐에 2건 이상 있을 때 우상단에 카운트 (1건이면 숨김) |
| **위치 선택** | 4 코너 중 선택 (top-left/top-right/bottom-left/bottom-right) |

## 2. Quiet Hours 모드

- 모든 idle 애니메이션 정지
- 새 알림 모먼트(펄스/소나) 발사 안 함
- 사운드 음소거
- **+N 배지 숨김** → 그 자리에 만화 스타일 정적 **Zzz** 표시
- 알림은 큐에 계속 누적됨 (드러나지 않을 뿐)

## 3. 알림 큐 (팝오버 패널)

### 행 (Session Row)
| 기능 | 설명 |
|---|---|
| **프로젝트명** | 큐에 들어온 세션의 cwd basename |
| **상태 닷** | 🟠 Success / 🔴 Error / 🟡 Waiting input (펄스) |
| **중복 프로젝트** | 같은 프로젝트가 2+ 있을 때 행에 시간(`14:32`) 표기 |
| **Orphan** | duration 모를 때 `?` 마크 |
| **Just-arrived ripple** | 새로 들어온 행 닷 주변 링 ×3 (3초간) |
| **Aged 행** | stoppedAt 기준 60분 초과 시 saturation 0.4 (이진 on/off, opacity 무관) |
| **Unavailable** | iTerm 세션 사라지면 프로젝트명 strikethrough + 빈 링 닷 |
| **그룹 접기** | 같은 프로젝트 3+ 개일 때 헤더로 접고 카운트 배지 + 캐럿 토글 |

### 패널
- **최대 4행** 표시, 그 이상은 세로 스크롤
- **스크롤 페이드** — 상/하단 부드러운 페이드 어포던스
- **빈 상태 온보딩** — `queue.isEmpty && !everHadAlerts` 일 때 "Listening to iTerm" 표시
- **Clear All 버튼** — 큐 2건 이상일 때만 노출
- **설정 톱니** — 헤더 우측, Preferences 창 오픈

### 인터랙션
| 액션 | 동작 |
|---|---|
| 행 클릭 | 해당 iTerm 세션으로 점프 (`async_activate()`), 행 제거 |
| 행 우클릭 | 컨텍스트 메뉴: **Mute this project for 1h** / **Pin alert (don't auto-clear)** |
| Esc | 팝오버 닫기 |
| 외부 클릭 | 팝오버 닫기 |

## 4. 동작 모드 / 환경설정

- **Reduce Motion** — 시스템 설정 따라가거나 수동. 모든 무한 루프 / 스프링 → 0.15s 페이드로 대체
- **Mute project (1h)** — 해당 프로젝트 알림 1시간 동안 큐 진입 차단
- **Pin alert** — 자동 정리/타임아웃에서 제외, 재시작 후에도 유지
- **Theme** — Light / Dark (시스템 따라가기 옵션 권장)

## 5. iTerm2 연동

### 이벤트 수신
- **방식**: iTerm2 Python API (`iterm2` 패키지) 헬퍼 스크립트 상주
- **구독**: session-end / prompt-detected
- **필터**: 실행 명령어가 `claude` / `claude code` 인 세션만
- **전송**: Unix domain socket / XPC / local HTTP 중 택 1

### Payload 스펙
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

### 세션 점프
```swift
session = await iterm2.Session.async_get(session_id)
await session.async_activate()
```
세션 부재 시 `available = false` 처리.

## 6. 영속성 (Persistence)

- `UserDefaults` — corner, theme, quiet, animation, reduceMotion
- `~/Library/Application Support/AlertBot/queue.json` — Codable 큐 스냅샷
- `mutedProjects: [String: Date]` — 프로젝트별 unmute 시각

## 7. 시각 토큰 (요약)

| 토큰 | Light | Dark |
|---|---|---|
| Accent | `#D97757` | `#D97757` |
| Error | `#E5484D` | `#E5484D` |
| Waiting | `#F5A623` | `#F5A623` |
| Popover bg | `rgba(248,247,245,0.55)` + NSVisualEffect | `rgba(38,38,42,0.55)` + NSVisualEffect |

- Popover: **270pt × auto**, 14pt radius
- Row: 36pt min, 12pt H / 8pt V padding
- Status dot: 7pt (hollow ring 1.5pt stroke)
- Font: SF Pro (UI), SF Mono (terminal flash, kbd)

## 8. 프로토타입 전용 (실제 앱에서 제거)

- Dev controls 패널 (우측 하단)
- "v2" 칩 배너
- 가짜 macOS 데스크탑/메뉴바 배경
- 행 클릭 시 가짜 iTerm 플래시 오버레이 → 실제로는 그냥 `async_activate()`
- 픽셀 데스크탑 별, 그라디언트 배경

## 9. 빌드 순서 (권장)

1. NSStatusItem + NSPopover 셸 + 하드코딩된 큐 → 프로토타입 룩 매칭
2. 애니메이션 — Breathe → Bounce → New-alert pulse → Rage(이스터에그)
3. iTerm2 브릿지 — 실제 알림 1건 end-to-end
4. 행 인터랙션 — 클릭 점프 / 컨텍스트 메뉴 / mute / pin
5. Preferences 창 + 영속성
6. Quiet Hours / Reduce Motion / aging / grouping 폴리시
7. 사운드 + Focus filter 통합

---

**구현자 확인사항**
- App Sandbox 적용 여부 (iTerm2 브릿지는 Apple Events 권한 필요)
- Sparkle 자동 업데이트 여부
- 코드 사이닝 / 노터라이제이션 계획
