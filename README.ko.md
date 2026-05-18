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
- 메뉴 막대에서 사운드, Quiet Hours, 위젯 위치, 애니메이션, 테마, Reduce Motion, 로그인 시 실행, 음소거된 프로젝트, 테스트 알림, iTerm2 연결 테스트를 제어할 수 있습니다.
- 앱 실행 시 번들된 hook reporter를 자동으로 설치하고 유지합니다.

## 요구사항

- macOS 14 Sonoma 이상
- iTerm2
- Claude Code 또는 Codex CLI
- 소스 빌드가 필요하다면 Xcode 15.4 이상

## 설치와 첫 실행

1. 빌드된 `ClaudeAlertBot.app`을 설치하거나, 이 저장소에서 직접 빌드합니다.
2. 일반적인 앱 설치 형태로 쓰려면 `/Applications`로 옮깁니다.
3. 앱을 실행합니다.

macOS가 서명되지 않은 앱 실행을 막으면 `System Settings > Privacy & Security > Open Anyway`를 사용하세요.
그래도 막히면 quarantine 속성을 직접 지울 수 있습니다.

```bash
xattr -cr /Applications/ClaudeAlertBot.app
```

`MenuBarExtra`는 macOS 메뉴 막대 오른쪽에 붙는 상태 아이콘 메뉴입니다.
Claude Alert Bot은 액세서리 앱으로 동작하므로, 실행 후에는 macOS 메뉴 막대의 벨 아이콘에서 제어합니다.

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

첫 실행 후 벨 메뉴에서 `iTerm2 Connection > Test iTerm2 connection`을 실행해 두는 것이 좋습니다.
이 과정에서 macOS가 다음 권한을 요청할 수 있습니다.

- Automation 권한: 앱이 iTerm2를 제어하기 위해 필요
- Accessibility 권한: 여러 Space를 넘어서도 정확한 iTerm2 창을 앞으로 올리기 위해 필요

## 사용 흐름

1. Claude Alert Bot을 메뉴 막대에서 실행 상태로 둡니다.
2. iTerm2 안에서 Claude Code 또는 Codex를 실행합니다.
3. 알림 조건을 만족한 세션이 생기면 플로팅 위젯과 카운트 배지가 나타납니다.
4. 위젯에 마우스를 올리면 세션 목록 팝오버가 열립니다.
5. 행을 클릭하면 정확한 터미널 세션으로 되돌아갑니다.
6. 행을 우클릭하면 고정하거나, 그 프로젝트를 1시간 동안 음소거할 수 있습니다.

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
완료된 iTerm2 세션이 이미 현재 앞에 있는 세션이면 완료 알림은 만들지 않습니다.

### Quiet Hours

Quiet Hours를 켜면 사운드와 강조 애니메이션은 꺼지지만, 큐와 카운트 배지는 계속 유지됩니다.
알림을 잃지 않으면서도 조용하게 앱을 켜 둘 수 있습니다.

### 큐 제어

행을 고정하면 일괄 삭제에서도 살아남습니다.
프로젝트 단위로 1시간 음소거할 수 있고, 같은 프로젝트의 반복 알림은 그룹으로 묶여 팝오버가 덜 복잡해집니다.

### iTerm2 점프 정확도

앱은 hook 이벤트에 담긴 iTerm2 세션 식별자를 추적하고, AppleScript와 창 올리기 로직을 조합해 정확한 위치로 되돌아갑니다.
권한이나 연결 상태를 확인할 수 있도록 메뉴 막대에 연결 테스트도 들어 있습니다.

## 소스에서 빌드하기

Xcode 프로젝트를 생성하고 앱을 빌드한 뒤, export된 번들을 실행합니다.

```bash
xcodegen generate
scripts/build.sh
open build/export/ClaudeAlertBot.app
```

릴리스 스타일 결과물은 아래에 생성됩니다.

```text
build/export/ClaudeAlertBot.app
```

테스트는 다음 명령으로 실행합니다.

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
- 연결 테스트는 통과하지만 클릭한 행이 정확한 창을 앞으로 못 올린다면 아래 Accessibility 복구 순서를 따릅니다.
- iTerm2가 이미 실행 중인지 확인합니다.

### 클릭한 세션이 아닌 다른 세션으로 이동할 때

듀얼 모니터, 또는 여러 iTerm2 창이 동시에 떠있는 환경에서 행을 클릭했는데 엉뚱한 세션으로 포커스가 가는 경우입니다. 대부분 Accessibility 권한이 비어 있을 때 나타납니다. 권한이 없으면 앱은 단순한 앱 단위 활성화만 시도하고, macOS가 임의의 창(보통 마우스가 있는 화면의 창)을 위로 올리기 때문입니다.

특히 직접 빌드해서 쓰는 경우 자주 발생합니다. 앱이 ad-hoc 서명(개발자 인증서 없이 로컬에서만 통하는 서명 방식)으로 빌드되면, 빌드할 때마다 바이너리 지문(cdhash)이 바뀌어 macOS가 이전 빌드에 부여한 권한을 새 빌드에 자동 적용하지 않습니다.

해결 순서:

1. 실행 중인 앱을 종료합니다.
   ```bash
   pkill -x ClaudeAlertBot
   ```
2. 이전 Accessibility 등록을 지웁니다.
   ```bash
   tccutil reset Accessibility com.claudealert.bot
   ```
3. 방금 빌드한 앱을 다시 엽니다.
   ```bash
   open build/export/ClaudeAlertBot.app
   ```
4. 벨 메뉴에서 `Grant Accessibility…`를 클릭합니다.
5. `시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용`에서 `ClaudeAlertBot` 토글을 켭니다.
6. 앱을 종료 후 다시 실행합니다. 권한 상태는 프로세스 시작 시점에 잡힙니다.
7. 로그를 확인합니다.

`tccutil reset` 직후에는 시스템 설정에 항목이 바로 안 보일 수 있습니다. 이때 앱 메뉴의 `Grant Accessibility…`를 눌러 새 항목을 만든 뒤 토글을 켜야 합니다.

`scripts/build.sh`로 새 ad-hoc 빌드를 만들면 macOS가 새 바이너리로 인식해서 권한이 다시 stale 될 수 있습니다. 같은 증상이 반복되면 위 순서를 다시 진행하세요.

권한이 실제로 적용됐는지 확인하고 싶으면 다음 로그를 봅니다.

```bash
/usr/bin/log show --predicate 'subsystem == "com.claudealert.bot.hook"' --info --last 5m
```

정상 동작에서는 다음과 같은 로그가 보입니다.

- `[ax-raised ... code=0]`
- `[jumped session=...]`
- 필요 시 `[ax-match path=focused-main-fallback ...]`

문제가 남아 있으면 다음 로그가 보일 수 있습니다.

- `[ax-trust trusted=false ...]`
- `[ax-skip reason=not-trusted]`
- `[activate-fallback]`

이 경우 권한 등록이 이전 빌드와 충돌한 상태일 가능성이 높으므로 해결 순서 1단계부터 다시 진행합니다.

### Hook 재설치

개발 중 reporter 스크립트와 hook 설정을 수동으로 다시 적용하고 싶다면:

```bash
scripts/dev-install-hook.sh --apply
```

### 서명되지 않은 앱 경고

`Open Anyway`로도 해결되지 않으면 quarantine 속성을 지웁니다.

```bash
xattr -cr /Applications/ClaudeAlertBot.app
```

## 현재 범위

- iTerm2 전용
- macOS 14+
- unsigned / ad-hoc signed 배포
- 외부 Swift 의존성 없음

## 라이선스

MIT. [LICENSE](LICENSE)를 참고하세요.
