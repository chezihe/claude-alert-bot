# Motion Rework — Design

**Date:** 2026-05-11
**Source of truth:** internal motion prototype
**Affected SPEC:** `SPEC.md` §4 Motion

## Problem

`SPEC.md` §4 Motion 표가 HTML 프로토타입의 keyframe 정보를 압축하면서 손실이 발생했고, codex가 SPEC만 보고 Swift로 구현한 결과 실제 동작이 의도와 어긋난다. 가장 큰 두 항목:

1. **Bounce 캐릭터 부재** — HTML의 `bounce-cute`는 5-keyframe 2축 비대칭 squash-and-stretch (바닥 `scale(1.04, 0.94)` → 정점 `scale(0.97, 1.05)`)인데, 현 Swift 구현은 단일 `scaleEffect(bounceScale)` 사인파라 "통통 튀는" 캐릭터가 통째로 사라짐.
2. **Heart 박동 어색함** — HTML `heartbeat`는 14%/28%/42%/56% 키프레임의 단일 keyframe-animation이지만, 현 구현은 `DispatchQueue.main.asyncAfter` 4-step 호출이라 step 사이 보간이 끊겨 리듬이 망가짐.

기타 갭(row dismiss slide 부재, popover open spring 부재, sonar 박스 clipping, SPEC §4 표 자체의 불일치)도 존재. 본 문서는 **한 스펙으로 묶고 단계적으로 구현**한다.

## Goals

- HTML 프로토타입의 motion을 진실의 원천으로 삼아, Swift 구현을 keyframe-기반으로 재작업한다.
- 본 사이클에는 **Phase 1만 코드 작업** (Bounce + Heart). Phase 2~4는 후속.
- `SPEC.md` §4 Motion 표를 HTML과 일치하도록 Phase 4에서 정정한다.

## Non-Goals

- Breathe / Ring / Roam / Drift / New-alert pulse / Sonar / Status dot ripple 의 시각 동작 변경 — Phase 1 스코프 밖.
- 새 애니메이션 추가 (Rage 등).
- External Swift dependency 도입.

## Scope (4-phase delivery, all phases captured in this spec)

| Phase | 작업 | 본 사이클 |
|---|---|---|
| **1** | Bounce + Heart keyframe 재구현 | ✅ |
| 2 | Row dismiss slide (클릭→점프 후 0.18s ease slide+collapse) | 다음 |
| 3 | Popover open spring (위젯 원점 → overshoot) | 다음 |
| 4 | Sonar 박스 확장 + new-alert pulse 정리 + SPEC §4 표 정정 | 다음 |

## Architecture

### New file: `App/MotionKeyframes.swift`

Keyframe 데이터를 순수 데이터로 정의. `MotionTokens`와 같이 SPEC 추적 가능. 외부 의존 0.

```swift
struct BounceKeyframe {
    let percent: Double       // 0...100
    let translateY: CGFloat   // pt (위로 음수)
    let scaleX: CGFloat
    let scaleY: CGFloat
}

struct HeartKeyframe {
    let percent: Double
    let scale: CGFloat
}

enum MotionKeyframes {
    static let bouncePeriod: TimeInterval = 0.9
    static let bounceCycle: [BounceKeyframe] = [
        .init(percent: 0,   translateY:  0, scaleX: 1.04, scaleY: 0.94),
        .init(percent: 18,  translateY: -2, scaleX: 1.01, scaleY: 0.99),
        .init(percent: 50,  translateY: -5, scaleX: 0.97, scaleY: 1.05),
        .init(percent: 82,  translateY: -2, scaleX: 1.01, scaleY: 0.99),
        .init(percent: 100, translateY:  0, scaleX: 1.04, scaleY: 0.94),
    ]

    static let heartPeriod: TimeInterval = 1.4
    static let heartCycle: [HeartKeyframe] = [
        .init(percent: 0,   scale: 1.0),
        .init(percent: 14,  scale: 1.14),
        .init(percent: 28,  scale: 1.0),
        .init(percent: 42,  scale: 1.08),
        .init(percent: 56,  scale: 1.0),
        .init(percent: 100, scale: 1.0),
    ]
}
```

### `WidgetIconView` 변경

- Bounce/Heart 경로를 `KeyframeAnimator` 멀티트랙으로 교체.
- `bounceOffset`, `bounceScale`, `heartScale`, `heartGeneration`, `heartBeatStepDuration` 사용처 제거.
- `KeyframeAnimator(initialValue:repeating:true)`로 무한 루프. `repeating:` 동작은 macOS 14 SDK 동작에 의존 — 구현 진입 직후 mini-POC로 검증.
- Quiet Hours / Reduce Motion 게이팅: KeyframeAnimator를 outer `if` 분기로 swap (정적 글리프 vs 애니메이션).
- 트랜스폼 anchor:
  - Bounce: `.bottom` (HTML `transform-origin: 50% 100%`)
  - Heart: `.center` (HTML `transform-origin: 50% 50%`)

### Bounce 적용 예시

```swift
KeyframeAnimator(
    initialValue: BounceValue.start,
    repeating: true
) { value in
    Image("ClaudeCodeIcon")
        .resizable()
        .scaledToFit()
        .frame(width: 36, height: 36)
        .scaleEffect(x: value.scaleX, y: value.scaleY, anchor: .bottom)
        .offset(y: value.translateY)
} keyframes: { _ in
    KeyframeTrack(\.translateY) {
        for kf in MotionKeyframes.bounceCycle.dropFirst() {
            CubicKeyframe(kf.translateY,
                          duration: MotionKeyframes.bouncePeriod * (kf.percent - prev) / 100)
        }
    }
    KeyframeTrack(\.scaleX) { /* same shape */ }
    KeyframeTrack(\.scaleY) { /* same shape */ }
}
```

(실제 듀레이션 계산은 인접 keyframe 차이로 — 0%→18%는 0.18×0.9 = 0.162s 등.)

### Heart 적용 예시

```swift
KeyframeAnimator(initialValue: HeartValue(scale: 1.0), repeating: true) { value in
    Image("ClaudeCodeIcon")
        .resizable()
        .scaledToFit()
        .frame(width: 36, height: 36)
        .scaleEffect(value.scale, anchor: .center)
} keyframes: { _ in
    KeyframeTrack(\.scale) {
        CubicKeyframe(1.14, duration: 1.4 * 0.14)  // 0→14
        CubicKeyframe(1.0,  duration: 1.4 * 0.14)  // 14→28
        CubicKeyframe(1.08, duration: 1.4 * 0.14)  // 28→42
        CubicKeyframe(1.0,  duration: 1.4 * 0.14)  // 42→56
        CubicKeyframe(1.0,  duration: 1.4 * 0.44)  // 56→100 idle
    }
}
```

## Compatibility / Migration

- 제거 대상 토큰 (호환 shim 없음):
  - `MotionTokens.bounceAnimation(reduceMotion:)`
  - `MotionTokens.heartBeatAnimation(reduceMotion:)`
  - `MotionTokens.bounceOffset`, `bounceStretchScale`, `bounceSquashScale`, `bounceDuration`
  - `MotionTokens.heartBeatStepDuration`, `heartPeakScale`, `heartSecondScale`, `heartDuration`
- 새 토큰:
  - `MotionKeyframes.bouncePeriod`, `bounceCycle`
  - `MotionKeyframes.heartPeriod`, `heartCycle`
- `WidgetIconView` 의 `@State` 변수 중 Bounce/Heart 관련 4개 제거: `bounceOffset`, `bounceScale`, `heartScale`, `heartGeneration`.
- 외부 의존성 없음 → 직접 삭제 안전.

## SPEC §4 Correction (Phase 4)

Phase 4에서 `SPEC.md` §4 표를 다음과 같이 정정:

| Animation | Current SPEC | Corrected (HTML 진실의 원천) |
|---|---|---|
| Bounce (idle) | `0.45s autoreverse infinite easeInOut, 5pt + 1.04↔0.94 squash` | `0.9s easeInOut infinite, 5-keyframe 2축 squash-and-stretch (바닥 1.04×0.94 → 정점 0.97×1.05, 5pt up)` |
| Heart | (표에 없음 — FEATURES.md에만 존재) | `1.4s easeInOut infinite, double-pulse (14% 1.14 / 42% 1.08)` 행 추가 |
| Ring | `0.55s easeInOut ±10°` | HTML은 1.4s ±15° — 본 사이클 후속에서 reconcile |

(나머지 motion 행은 Phase 2/3에서 다룬 뒤 정정.)

## Testing

### Unit (Phase 1)

- 신규 `ClaudeAlertBotTests/MotionKeyframesTests.swift`
  - `bounceCycle.first?.percent == 0`, `.last?.percent == 100`
  - `percent` 단조증가
  - `bounceCycle.first?.translateY == bounceCycle.last?.translateY` (루프 연속성)
  - 동일하게 `heartCycle` 검증
  - `bouncePeriod == 0.9`, `heartPeriod == 1.4` (HTML 일치)

### Visual (수동, 사용자 sign-off 게이트)

- HTML 프로토타입을 브라우저 한쪽, 앱을 다른 쪽에 띄움.
- Bounce: 정점/바닥에서 글리프 모양 비교 (정점에서 세로로 길어지는지, 바닥에서 가로로 퍼지는지).
- Heart: 1.4s 사이클 내 두 번의 박동 정점이 14% / 42% 위치에 오는지.
- Reduce Motion ON: 둘 다 정적.
- Quiet Hours ON: 둘 다 정적.

## Risks

- **`KeyframeAnimator(repeating: true)` 동작 검증** — macOS 14 SDK의 `repeating` 무한 루프와 `trigger:` 상호작용 확인. 구현 진입 직후 30분 mini-POC. 실패 시 fallback: outer `if quietHours/reduceMotion { 정적 } else { KeyframeAnimator(...) }`로 view swap.
- **글리프 anchor 좌표** — SwiftUI `scaleEffect(x:y:anchor:)`와 `offset(y:)`의 합성 결과가 HTML `transform: translateY() scale()` 순서와 같은지 시각 검증으로만 확인 가능. 어긋나면 `GeometryEffect` 직접 구현으로 대체.
- **Phase 1만 손대고 끝나는 위험** — Phase 2~4가 잊혀짐. 본 spec이 4-phase 모두 캡처하므로 후속 사이클 진입 시 같은 문서 재사용.

## Acceptance Criteria (Phase 1)

- `App/MotionKeyframes.swift` 신설, 위 키프레임 데이터 정확.
- `WidgetIconView` Bounce/Heart 경로가 `KeyframeAnimator` 사용.
- 제거 대상 토큰 모두 삭제 (grep 결과 0건).
- `MotionKeyframesTests.swift` 통과.
- 사용자 시각 sign-off: "HTML 프로토타입과 Bounce/Heart 캐릭터 일치".
