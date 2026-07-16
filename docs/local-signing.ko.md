# 로컬 서명 및 손쉬운 사용 권한

[English](local-signing.md)

이 문서는 Claude Alert Bot을 소스에서 반복 빌드할 때 동일한 macOS 코드 identity를 유지하는 방법을 설명합니다. Apple 계정은 필요하지 않습니다.

## 권장 설정

저장소 루트에서 개인용 로컬 서명 identity를 한 번 생성한 뒤 프로젝트를 빌드합니다.

```bash
scripts/setup-local-signing.sh
xcodegen generate
scripts/build.sh
open build/export/ClaudeAlertBot.app
```

설정 스크립트는 로그인 Keychain에 `ClaudeAlertBot Local Root CA v2`라는 신뢰된 self-signed 루트와 이 루트가 발급한 `ClaudeAlertBot Local Development v2` 코드 서명 identity를 만듭니다. 서명 인증서 지문은 Git에서 제외된 `Config/LocalSigning.xcconfig`에 기록합니다. 인증서와 개인 키를 commit하거나 다른 사용자와 공유하지 마세요.

이 identity는 로컬 개발 전용입니다. Developer ID 배포나 Apple 공증을 대신하지 않습니다.

## 최초 권한 설정

처음 실행한 앱에서 다음 순서로 권한을 설정합니다.

1. 벨 메뉴에서 `iTerm2 Connection > Test iTerm2 connection`을 실행하고 Automation 권한을 허용합니다.
2. `Grant Accessibility…`를 누릅니다.
3. `시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용`에서 `ClaudeAlertBot`을 켭니다.
4. 앱을 한 번 종료하고 다시 실행합니다.

이후 bundle identifier와 로컬 인증서가 유지되는 동안에는 재빌드해도 같은 손쉬운 사용 권한을 재사용합니다. 이전 프로세스는 종료하고 새 빌드를 열어야 하지만, 정상적인 재빌드마다 권한 항목을 삭제하거나 다시 켤 필요는 없습니다.

## 상태 확인

Keychain이나 빌드 결과를 변경하지 않고 설정 상태를 확인할 수 있습니다.

```bash
scripts/setup-local-signing.sh --status
scripts/build.sh --signing-status
```

정상적인 로컬 서명 설정에서는 두 번째 명령이 `mode=local`과 인증서 지문을 표시합니다. 설정 파일은 있지만 identity를 찾지 못하면 빌드는 ad-hoc으로 대체하지 않고 실패합니다.

## 일회성 ad-hoc 빌드

로컬 identity를 만들지 않고 한 번만 빌드하려면 다음 명령을 사용합니다.

```bash
xcodegen generate
scripts/build.sh
open build/export/ClaudeAlertBot.app
```

`Config/LocalSigning.xcconfig`가 없으면 빌드 스크립트는 ad-hoc 서명을 사용합니다. ad-hoc 빌드는 다시 빌드할 때 코드 identity가 바뀌므로 손쉬운 사용 권한을 다시 부여해야 할 수 있습니다.

## 로컬 identity 삭제

ad-hoc 서명으로 돌아가려면 설정된 정확한 identity만 삭제합니다.

```bash
FINGERPRINT=$(awk -F ' = ' '$1 == "CAB_CODE_SIGN_IDENTITY" { print $2 }' Config/LocalSigning.xcconfig)
KEYCHAIN=$(awk -F ' = ' '$1 == "CAB_CODE_SIGN_KEYCHAIN" { print $2 }' Config/LocalSigning.xcconfig)
security delete-identity -Z "$FINGERPRINT" -t "$KEYCHAIN"
rm -f Config/LocalSigning.xcconfig
xcodegen generate
```

identity를 삭제하거나 새로 만들면 앱의 코드 identity도 바뀌므로 macOS가 권한을 다시 요구할 수 있습니다.

## 손쉬운 사용 문제 복구

행을 클릭했을 때 다른 iTerm2 창이 열리거나 정확한 세션을 앞으로 가져오지 못하면 먼저 서명 상태를 확인합니다.

```bash
scripts/build.sh --signing-status
```

`mode=local`이면 다음 순서로 확인합니다.

1. `scripts/setup-local-signing.sh --status`가 성공하는지 확인합니다.
2. 실행 중인 이전 앱을 종료합니다.
3. `build/export/ClaudeAlertBot.app`을 다시 엽니다.
4. 시스템 설정에서 기존 `ClaudeAlertBot` 손쉬운 사용 토글이 켜져 있는지 확인합니다.

`mode=ad-hoc`이면 재빌드 후 권한이 이전 바이너리를 가리킬 수 있습니다. 반복 빌드한다면 위의 권장 로컬 서명 설정으로 전환하세요.

서명과 앱 경로가 정상인데도 권한 상태가 계속 잘못될 때만 마지막 수단으로 TCC 등록을 초기화합니다.

```bash
pkill -x ClaudeAlertBot
tccutil reset Accessibility com.claudealert.bot
open build/export/ClaudeAlertBot.app
```

앱의 `Grant Accessibility…`를 누르고 시스템 설정에서 토글을 켠 다음 앱을 종료하고 다시 실행합니다.

## 로그 확인

```bash
/usr/bin/log show --predicate 'subsystem == "com.claudealert.bot.hook"' --info --last 5m
```

정상 동작에서는 `[ax-raised ... code=0]` 또는 `[jumped session=...]`가 보입니다. `[ax-trust trusted=false ...]`, `[ax-skip reason=not-trusted]`가 보이면 손쉬운 사용 권한이 적용되지 않은 상태입니다. `[ax-miss ...]`는 권한은 살아 있지만 대상 창을 찾지 못한 경우이며, 그때 사용 가능했던 창 ID와 제목이 함께 남습니다.

## 앱 실행이 차단될 때

직접 만든 로컬 빌드에는 일반적으로 quarantine 속성이 붙지 않습니다. 외부에서 받은 앱이 Gatekeeper에 차단되면 먼저 `시스템 설정 > 개인정보 보호 및 보안 > 확인 없이 열기`를 사용합니다.

그래도 열리지 않고 앱의 출처를 신뢰할 수 있을 때만 quarantine 속성을 제거합니다.

```bash
xattr -cr /Applications/ClaudeAlertBot.app
```
