# Claude Alert Bot

[English](README.md)

Claude Alert Bot은 iTerm2에서 Claude Code 또는 Codex를 사용하는 사람을 위한 네이티브 macOS 유틸리티입니다.
오래 걸리는 세션이 끝나거나, 에이전트가 사용자 입력을 기다리며 멈추면 바탕화면에 플로팅 위젯이 나타나고, 그 이벤트를 만든 정확한 iTerm2 탭 또는 창으로 바로 돌아갈 수 있게 해줍니다.

핵심은 단순합니다.
알림이 떠도 원래 작업하던 터미널로 정확하게 돌아가지 못하면 실사용 가치가 없습니다.
Claude Alert Bot은 잠깐 나타났다 사라지는 시스템 배너보다, 정확한 세션 복귀에 초점을 맞춥니다.

## 예시 화면

![Claude Alert Bot overview](docs/images/claude-alert-bot-overview.png)

![Claude Alert Bot menu controls](docs/images/claude-alert-bot-menu.png)

## 어떤 앱인가

- 조건을 만족한 세션 완료 또는 대기 이벤트가 생기면 플로팅 Claude 위젯을 띄웁니다.
- 사용자가 직접 정리하거나 터미널로 돌아갈 때까지 대기 중인 세션 큐를 유지합니다.
- 행을 클릭하면 해당 iTerm2 세션으로 정확히 점프합니다.
- 알림 임계값을 설정해서 너무 짧은 실행은 걸러낼 수 있습니다.
- Claude의 권한 요청 / elicitation dialog 같은 입력 대기 알림도 받을 수 있습니다.
- 중요한 행을 고정하거나, 특정 프로젝트를 1시간 동안 음소거하거나, 고정되지 않은 행만 한 번에 지울 수 있습니다.
- 같은 프로젝트에서 반복된 알림은 그룹으로 묶고 카운트 배지로 보여줍니다.
- `Notification > Alert Details > Last Output`을 켜면 Claude Code 또는 Codex 행 아래에 최신 assistant 메시지/출력 preview 1줄을 표시할 수 있습니다.
- 메뉴 막대에서 사운드, Quiet Hours, 알림 임계값, 알림 상세 표시, 위젯 위치, 애니메이션, 테마, Reduce Motion, 로그인 시 실행, 음소거된 프로젝트, 테스트 알림, iTerm2 연결 테스트를 제어할 수 있습니다.
- 앱 실행 시 번들된 hook reporter를 자동으로 설치하고 유지합니다.

## 요구사항

- macOS 14 Sonoma 이상
- iTerm2
- Claude Code 또는 Codex CLI
- 소스 빌드가 필요하다면 Xcode 15.4 이상
- 소스 빌드가 필요하다면 XcodeGen

## 빠른 시작

반복해서 소스 빌드할 때도 macOS 권한을 유지할 수 있도록 개인용 로컬 서명을 먼저 설정합니다. Apple 계정은 필요하지 않습니다.

```bash
scripts/setup-local-signing.sh
xcodegen generate
scripts/build.sh
open build/export/ClaudeAlertBot.app
```

빌드 결과는 `build/export/ClaudeAlertBot.app`에 생성됩니다. 일반적인 앱 설치 형태로 쓰려면 `/Applications`로 옮길 수 있습니다.

### 최초 권한 설정

앱은 메뉴 막대의 벨 아이콘에서 제어합니다. 처음 실행한 뒤 다음 순서로 권한을 설정합니다.

1. 벨 메뉴에서 `iTerm2 Connection > Test iTerm2 connection`을 실행하고 Automation 권한을 허용합니다.
2. `Grant Accessibility…`를 누릅니다.
3. `시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용`에서 `ClaudeAlertBot`을 켭니다.
4. 앱을 한 번 종료하고 다시 실행합니다.

이후 bundle identifier와 로컬 인증서가 유지되는 동안에는 재빌드해도 같은 권한을 재사용합니다. 자세한 서명 관리, ad-hoc 빌드, 권한 복구 방법은 [로컬 서명 및 손쉬운 사용 권한](docs/local-signing.ko.md)을 참고하세요.

앱이 실행되면 번들된 reporter 스크립트를 아래 경로로 복사합니다.

```text
~/Library/Application Support/ClaudeAlertBot/cab-report.sh
```

그 다음 아래 설정 파일에 hook 등록을 병합합니다.

- `~/.claude/settings.json`
- `~/.codex`가 있으면 `~/.codex/hooks.json`과 `~/.codex/config.toml`

설치되는 hook 구성은 다음을 포함합니다.

- Claude Code용 `Stop`, `UserPromptSubmit`
- `~/.codex`가 있을 때 Codex용 `Stop`, `UserPromptSubmit`
- Claude 권한 요청 / elicitation dialog용 `Notification`

## 사용 흐름

1. Claude Alert Bot을 메뉴 막대에서 실행 상태로 둡니다.
2. iTerm2 안에서 Claude Code 또는 Codex를 실행합니다.
3. 알림 조건을 만족한 세션이 생기면 플로팅 위젯과 카운트 배지가 나타납니다.
4. 위젯에 마우스를 올리면 세션 목록 팝오버가 열립니다.
5. 행을 클릭하면 정확한 터미널 세션으로 되돌아갑니다.
6. 행을 우클릭하면 고정하거나, 그 프로젝트를 1시간 동안 음소거할 수 있습니다.

팝오버에서 더 많은 맥락을 보고 싶다면 벨 메뉴에서 `Notification > Alert Details > Last Output`을 선택합니다.
사용 가능한 최신 assistant 메시지나 출력이 있으면 첫 번째 non-empty line이 행 아래에 표시됩니다.

## 주요 기능

### 유지되는 세션 큐

Claude Alert Bot은 사용자가 직접 처리할 때까지 알림을 남겨 둡니다.
그래서 잠깐 나타났다 사라지는 배너보다, 자리를 비운 뒤 돌아오는 워크플로에 더 잘 맞습니다.

### 알림 임계값

얼마나 오래 실행된 작업만 알릴지 정할 수 있습니다.
짧고 자주 도는 실행은 걸러내고, 의미 있는 완료만 남길 수 있습니다.
실패한 실행은 임계값보다 짧아도 알림을 남깁니다.
stop 이벤트의 exit code가 0이 아니면 실패한 실행으로 취급합니다.
입력 대기 알림은 임계값과 관계없이 즉시 나타납니다.

### 행 표시 규칙

상태 dot은 알림 종류를 나타냅니다. 성공은 초록색, 오류는 빨간색, 입력 대기는 노란색입니다.
행에는 보통 완료된 실행 시간이 표시됩니다.
실행 시간을 특정할 수 없으면 시간 표시 자리에 `?`가 표시됩니다.
`Last Output`을 켜면 Claude Code와 Codex 행 아래에 보조 preview 1줄을 표시할 수 있습니다.
빈 출력은 표시하지 않고, 여러 줄 출력은 첫 번째 non-empty line만 사용하며, 긴 내용은 행 너비에 맞춰 잘립니다.

### Quiet Hours

Quiet Hours를 켜면 사운드와 강조 애니메이션은 꺼지지만, 큐와 카운트 배지는 계속 유지됩니다.
알림을 잃지 않으면서도 조용하게 앱을 켜 둘 수 있습니다.

### 큐 제어

행을 고정하면 일괄 삭제에서도 살아남습니다.
프로젝트 단위로 1시간 음소거할 수 있고, 같은 프로젝트의 반복 알림은 그룹으로 묶여 팝오버가 덜 복잡해집니다.

### iTerm2 점프 정확도

앱은 hook 이벤트에 담긴 iTerm2 세션 식별자를 추적하고, AppleScript와 창 올리기 로직을 조합해 정확한 위치로 되돌아갑니다.
권한이나 연결 상태를 확인할 수 있도록 메뉴 막대에 연결 테스트도 들어 있습니다.

## 개발 및 테스트

빌드와 최초 실행은 위의 [빠른 시작](#빠른-시작)을 따릅니다. 로컬 identity 상태 확인, 일회성 ad-hoc 빌드, 인증서 삭제와 권한 복구는 [로컬 서명 및 손쉬운 사용 권한](docs/local-signing.ko.md)에 분리해 두었습니다.

전체 테스트는 다음 명령으로 실행합니다.

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'
```

## 문제 해결

### 알림이 보이지 않을 때

- Claude Alert Bot이 실행 중인지 확인합니다.
- 에이전트 세션이 iTerm2 안에서 돌고 있는지 확인합니다.
- `~/.claude/settings.json` 또는 `~/.codex/hooks.json`에 hook이 병합됐는지 확인합니다.
- 세션이 너무 짧다면 메뉴 막대에서 알림 임계값을 낮춥니다.

### 행을 클릭해도 점프하지 않을 때

- 벨 메뉴에서 `iTerm2 Connection > Test iTerm2 connection`을 실행합니다.
- 이 테스트가 실패하면 Automation/iTerm2 연결 문제입니다. macOS가 묻는다면 Automation 권한을 허용하고, 필요할 때만 AppleEvents 권한을 초기화한 뒤 연결 테스트를 다시 실행합니다.
  ```bash
  tccutil reset AppleEvents com.claudealert.bot
  ```
- 연결 테스트는 통과하지만 클릭한 행이 정확한 창을 앞으로 못 올린다면 [손쉬운 사용 문제 복구](docs/local-signing.ko.md#손쉬운-사용-문제-복구)를 확인합니다.
- iTerm2가 이미 실행 중인지 확인합니다.

### 클릭한 세션이 아닌 다른 세션으로 이동할 때

듀얼 모니터, 또는 여러 iTerm2 창이 동시에 떠있는 환경에서 행을 클릭했는데 엉뚱한 세션으로 포커스가 가는 경우입니다. 대부분 Accessibility 권한이 비어 있을 때 나타납니다. 권한이 없으면 앱은 단순한 앱 단위 활성화만 시도하고, macOS가 임의의 창(보통 마우스가 있는 화면의 창)을 위로 올리기 때문입니다.

먼저 `scripts/build.sh --signing-status`로 현재 빌드가 `mode=local`인지 확인하세요. 로컬 서명이라면 TCC를 초기화하기 전에 기존 앱을 종료하고 새 빌드를 다시 실행합니다. ad-hoc이거나 권한 상태가 계속 잘못된 경우의 단계별 복구와 로그 확인 방법은 [로컬 서명 및 손쉬운 사용 권한](docs/local-signing.ko.md#손쉬운-사용-문제-복구)에 정리되어 있습니다.

### Hook 재설치

개발 중 reporter 스크립트와 hook 설정을 수동으로 다시 적용하고 싶다면:

```bash
scripts/dev-install-hook.sh --apply
```

### macOS가 앱 실행을 차단할 때

외부에서 받은 앱이 Gatekeeper에 차단되면 [앱 실행이 차단될 때](docs/local-signing.ko.md#앱-실행이-차단될-때)를 참고하세요. 직접 만든 로컬 빌드는 일반적으로 quarantine 제거가 필요하지 않습니다.

## 현재 범위

- iTerm2 전용
- macOS 14+
- Developer ID 공증 없이 로컬 self-signed 또는 ad-hoc 소스 빌드
- 외부 Swift 의존성 없음

## 라이선스

MIT. [LICENSE](LICENSE)를 참고하세요.
