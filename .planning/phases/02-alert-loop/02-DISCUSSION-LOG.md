# Phase 2: Alert Loop - Discussion Log

> **Audit trail only.** Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-07
**Phase:** 02-alert-loop
**Areas discussed:** 위젯 시각/레이아웃 + 다중 보류 disambiguation + 자동 정리, THR-02 fallback, Sound during Focus/DnD + AUD dedupe, Test notification + 영속성 atomicity

---

## 위젯 시각 + 다중 보류 disambiguation + 자동 정리 (가장 큰 토론)

### 라운드 1 — 위젯 레이아웃
| Option | Description | Selected |
|--------|-------------|----------|
| 아이콘 + 하단 라벨 | 정사각 아이콘 아래 프로젝트명 1줄 | |
| 알약형 (아이콘 + 우측 라벨) | 일제 파악 쉬움 + 쿠킹마렐 | |
| 아이콘만 + tooltip | 최소 방해 | |
| 아이콘 + 경과시간 배지 + 라벨 | 정보 밀도 최대 | |

**User 응답:** 사용자가 "아이콘만 넣고 선택에 따라 프로젝트명을 보여주게 하자. 그리고 아이콘이 귀엽게 돌아다녔으면 좋겠다." 라며 옵션 재구성 요청.

### 라운드 2 — 라벨 노출 방식 + 움직이는 아이콘 의미
**제기된 질문:** "선택에 따라"의 트리거 (hover / click / Settings 토글), "돌아다닌다"의 정도 (idle bob / 등장 애니 / 코너 주변 배회 / 화면 전체 자유 이동).

**User 응답:** "사실 여러 터미널에서 작업중인게 비슷한 타이밍에 끝나면 조금 애매해. 그래서 아이콘만 나오고 클릭했을때 어떤 터미널을 먼저가게할지를 고민하는게 맞을듯."

→ 사용자가 우선순위 명시: 시각 폴리싱(애니메이션, 라벨) 보다 **다중 세션 disambiguation**이 핵심 가치 보존에 결정적. 애니메이션은 deferred.

### 라운드 3 — 다중 보류 disambiguation 정책
| Option | Description | Selected |
|--------|-------------|----------|
| 세션당 아이콘 1개 (스택) | 각 alert = 독립 작은 NSPanel | |
| 최근 1개 + +N 배지 + 클릭 시 popover 리스트 | Phase 4 UI를 의미있게 Phase 2로 당김 | ✓ |
| 최근 1개 + 다음은 클릭 후 자동 등장 (큐) | 사용자가 원하는 세션 먼저 못 고름 | |

**User 응답:** "2번이 좋고 클릭하면 FIFO로 하고 숫자가 줄어들게 하자. 근데 사용자가 아이콘 안누르고 바로 터미널로 가버리면 문제긴하네."

### 라운드 4 — 자동 정리 (사용자가 직접 터미널로 갔을 때)
| Option | Description | Selected |
|--------|-------------|----------|
| UserPromptSubmit 기반 (passive, 권한 불필요) | 다음 prompt = 그 세션 engaged 신호 | ✓ (final) |
| iTerm2 전체 frontmost 감지 (NSWorkspace, 코스) | 권한 불필요지만 false-positive 큼 | |
| tab-level 정확 감지 (AppleScript, Phase 3 권한 당겨옴) | 정확도 최상이지만 ROADMAP 잠금 깸 | |
| 1+2 hybrid | 디디어한 안전망 | |

**User 응답:** "아 생각보다 복잡한거 같네. 그냥 +N 배지 + hover 선택 + 클릭 후 사라짐 이렇게만 할까? 좋은 제안해줘."

→ Claude가 통합 제안: **단일 아이콘 + +N 배지 + hover popover + UserPromptSubmit auto-clear + Clear all 버튼 안전망**.

**User 최종 응답:** "추가 안전망까지해서 하자. 좋은거같아."

### 라운드 5 — 같은 프로젝트 다중 세션 보정
**User 추가 지적:** "경과시간은 안보여줘도 될거같아. 그리고 같은 프로젝트내에 여러세션이 있을수도 있어!"

→ popover row 표시 규칙 보정: 기본은 프로젝트명만, **같은 프로젝트 ≥2 보류 시에만 그 row들에 한해 Stop 시각(HH:MM) 보조 라벨**. UserPromptSubmit auto-clear는 session_id 기준이므로 같은 프로젝트 다중 세션도 정확히 그 하나만 클리어 (수정 불필요).

**User 최종 응답:** "좋은거같아."

**최종 잠금 (CONTEXT.md D2-03~D2-15 참조):**
- 단일 NSPanel 아이콘 + +N 텍스트 배지 (N≥2)
- Hover popover, FIFO row 정렬
- 기본은 프로젝트명만, 같은 프로젝트 다중 보류 시 row에 Stop 시각 보조 라벨
- Clear all 버튼 우상단
- 클릭 = dismiss + 로그 (Phase 3에서 jump 인계)
- UserPromptSubmit auto-clear (session_id 기준)
- 아이콘 애니메이션은 Phase 6 직전 deferred

---

## THR-02 fallback

| Option | Description | Selected |
|--------|-------------|----------|
| 항상 alert with `?` duration | ROADMAP 기본값. silently drop 안 함 | ✓ |
| 무시 | 깔끔하지만 핵심 가치 위반 | |
| ppid 기반 추정 경과 | 정확도 낮음 + 복잡도 추가 | |

**잠금:** ROADMAP 기본값 그대로. CONTEXT.md D2-16,17.

---

## Sound during Focus/DnD + AUD-01 "사운드 1회" dedupe

### Sound during Focus/DnD
| Option | Description | Selected |
|--------|-------------|----------|
| 시스템 존중 (Focus/DnD 시 자동 음소거, visual은 유지) | macOS 표준 매너 + 핵심 가치 보존 | ✓ |
| 무시 (사용자 Settings만 권한) | 가치 보존 강하지만 시스템 매너 위반 | |
| UNNotificationSound 채널 | 시스템에 위임하지만 배너 dismiss 위험 | |

### AUD-01 dedupe key
| Option | Description | Selected |
|--------|-------------|----------|
| `(session_id, ts_round_2s)` | Phase 4 dedupe key와 호환 확장 가능 | ✓ |
| `session_id` only | 같은 세션 빠른 재발사 시 중복 사운드 | |
| `(session_id, transcript_path)` | Phase 4 본격 dedupe key — 지금은 과한 정의 | |

**잠금:** CONTEXT.md D2-18,19,20.

---

## Test notification UX + sessions.json atomicity

### Test notification
| Option | Description | Selected |
|--------|-------------|----------|
| in-process 합성 이벤트 (SessionRegistry inject) | 정상 알림 경로 그대로, 30s/click 자동 정리 | ✓ |
| 진짜 cab-test 흐름 재사용 (socket roundtrip) | 더 충실하지만 결합도 높음 | |

### sessions.json atomicity
| Option | Description | Selected |
|--------|-------------|----------|
| atomic rename (write tmp + rename) | macOS APFS atomic, 인간 빈도라 throttle 불필요 | ✓ |
| throttled write (debounce N ms) | 복잡도 추가 + 충돌 시 손실 위험 | |
| append-only journal | 과한 엔지니어링 (Phase 2 범위 초과) | |

**잠금:** CONTEXT.md D2-21~25.

---

## Claude's Discretion

다음 항목은 사용자가 명시 지시하지 않은 영역 — 합리적 기본값으로 잠금 (CONTEXT.md):

- 위젯 기본 코너 (Top-Right) + 16pt inset offset (D2-26,27)
- 노치/멀티 디스플레이 안전 영역 (NSScreen.safeAreaInsets, main display 고정) (D2-28)
- Settings 아키텍처 (SwiftUI Settings scene + @AppStorage, 외부 의존성 0) (D2-29,30)
- Logging (OSLog subsystem 확장, 새 categories registry/notification/widget/settings) (D2-31,32)
- 위젯 그림자/배경 (.thinMaterial blur), 모서리 14pt, 200ms fade+slide 애니
- popover slide-in 방향 (코너 자동), Funk.aiff 시스템 사운드 placeholder
- UserPromptSubmit hook timeout 5초 (Stop과 동일)
- 아이콘 placeholder SF Symbol (`bell.badge.fill` 또는 `bubble.left.fill`) (D2-12)

---

## Deferred Ideas

- **위젯 아이콘 애니메이션 / 화면 내 모션:** Phase 6 직전 폴리싱 라운드. (D2-11)
- **자체 제작 chat-bubble glyph 아이콘:** Phase 6 직전. (D2-12)
- **iTerm2 frontmost / tab-level 감지 기반 auto-clear:** Phase 3 Apple Events 권한 도입 후 Phase 4 검토. (D2-15)
- **Counter badge UI:** Phase 4 명시 영역. Phase 2의 +N 텍스트 배지는 임시.
- **다중 디스플레이 동적 추적:** Phase 4+ 검토. (D2-28)
- **추정 경과 시간 휴리스틱:** 도입 안 함, `?` 그대로. (D2-17)
