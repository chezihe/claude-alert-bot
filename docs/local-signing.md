# Local Signing And Accessibility Permission

[한국어](local-signing.ko.md)

This document explains how to keep a stable macOS code identity when repeatedly building Claude Alert Bot from source. No Apple account is required.

## Recommended Setup

Create a personal local signing identity once, then generate and build the project from the repository root.

```bash
scripts/setup-local-signing.sh
xcodegen generate
scripts/build.sh
open build/export/ClaudeAlertBot.app
```

The setup script creates a trusted self-signed root named `ClaudeAlertBot Local Root CA v2` and an issued code-signing identity named `ClaudeAlertBot Local Development v2` in the login Keychain. It writes the signing certificate fingerprint to the ignored `Config/LocalSigning.xcconfig`. Do not commit or share the certificate or private key.

This identity is for local development only. It does not replace Developer ID distribution or Apple notarization.

## First Permission Grant

Configure permissions in this order on the first locally signed run.

1. Run `iTerm2 Connection > Test iTerm2 connection` from the bell menu and allow Automation access.
2. Click `Grant Accessibility…`.
3. Enable `ClaudeAlertBot` in `System Settings > Privacy & Security > Accessibility`.
4. Quit and relaunch the app once.

Later rebuilds reuse the same Accessibility permission while the bundle identifier and local certificate remain unchanged. Quit the previous process and open the rebuilt app, but do not remove or toggle the permission entry after every normal rebuild.

## Check Status

Inspect the setup without changing the Keychain or build output.

```bash
scripts/setup-local-signing.sh --status
scripts/build.sh --signing-status
```

With a usable local setup, the second command reports `mode=local` and the certificate fingerprint. If the config exists but its identity is unavailable, the build fails instead of silently falling back to ad-hoc signing.

## One-Off Ad-Hoc Build

For a one-off build without creating a local identity, run:

```bash
xcodegen generate
scripts/build.sh
open build/export/ClaudeAlertBot.app
```

When `Config/LocalSigning.xcconfig` is absent, the build script uses ad-hoc signing. An ad-hoc rebuild can change the app's code identity, so Accessibility permission may need to be granted again.

## Remove The Local Identity

To return to ad-hoc signing, delete only the exact configured identity.

```bash
FINGERPRINT=$(awk -F ' = ' '$1 == "CAB_CODE_SIGN_IDENTITY" { print $2 }' Config/LocalSigning.xcconfig)
KEYCHAIN=$(awk -F ' = ' '$1 == "CAB_CODE_SIGN_KEYCHAIN" { print $2 }' Config/LocalSigning.xcconfig)
security delete-identity -Z "$FINGERPRINT" -t "$KEYCHAIN"
rm -f Config/LocalSigning.xcconfig
xcodegen generate
```

Deleting or recreating the identity changes the app's code identity, so macOS may request permission again.

## Recover Accessibility Permission

If clicking a row activates the wrong iTerm2 window or cannot bring the exact session forward, check the signing mode first.

```bash
scripts/build.sh --signing-status
```

For `mode=local`:

1. Confirm that `scripts/setup-local-signing.sh --status` succeeds.
2. Quit the previously running app.
3. Reopen `build/export/ClaudeAlertBot.app`.
4. Confirm that the existing `ClaudeAlertBot` Accessibility toggle is enabled.

For `mode=ad-hoc`, a rebuild can leave the permission pointing at the previous binary. Switch to the recommended local setup above if you rebuild frequently.

Reset the TCC entry only as a last resort when the signature and app path are correct but the permission state remains stale.

```bash
pkill -x ClaudeAlertBot
tccutil reset Accessibility com.claudealert.bot
open build/export/ClaudeAlertBot.app
```

Click `Grant Accessibility…`, enable the toggle in System Settings, then quit and relaunch the app.

## Inspect Logs

```bash
/usr/bin/log show --predicate 'subsystem == "com.claudealert.bot.hook"' --info --last 5m
```

A working jump logs `[ax-raised ... code=0]` or `[jumped session=...]`. Entries such as `[ax-trust trusted=false ...]` or `[ax-skip reason=not-trusted]` indicate that Accessibility permission is not active. An `[ax-miss ...]` entry means the permission is active but the target window could not be matched; it lists the window IDs and titles that were available.

## If macOS Blocks The App

Locally built apps normally do not have a quarantine attribute. For an externally downloaded app blocked by Gatekeeper, first use `System Settings > Privacy & Security > Open Anyway`.

Only if the app's source is trusted and it still cannot open, clear quarantine explicitly.

```bash
xattr -cr /Applications/ClaudeAlertBot.app
```
