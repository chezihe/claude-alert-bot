#!/bin/bash
# scripts/build.sh — Phase 1 build pipeline (DIST-01).
# Produces a signed build/export/ClaudeAlertBot.app from a clean checkout.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/ClaudeAlertBot.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_NAME="ClaudeAlertBot.app"
ENTITLEMENTS="$ROOT/App/ClaudeAlertBot.entitlements"
IDENTITY_NAME="ClaudeAlertBot Local Development"
SECURITY_BIN="${CAB_SECURITY_BIN:-/usr/bin/security}"
OPENSSL_BIN="${CAB_OPENSSL_BIN:-/usr/bin/openssl}"
SIGN_KEYCHAIN="${CAB_KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"
LOCAL_CONFIG="${CAB_LOCAL_SIGNING_CONFIG_PATH:-$ROOT/Config/LocalSigning.xcconfig}"

normalize_fingerprint() {
    printf '%s' "$1" | /usr/bin/tr -d ':' | /usr/bin/tr '[:lower:]' '[:upper:]'
}

is_valid_fingerprint() {
    [[ "$1" =~ ^[0-9A-F]{40}$ ]]
}

config_value() {
    local key="$1"
    /usr/bin/awk -v key="$key" '
        {
            separator = index($0, "=")
            if (separator == 0) next
            name = substr($0, 1, separator - 1)
            gsub(/^[ \t]+|[ \t]+$/, "", name)
            if (name != key) next
            value = substr($0, separator + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", value)
            print value
            exit
        }
    ' "$LOCAL_CONFIG"
}

identity_available() {
    local expected="$1"
    local output line fingerprint
    output=$("$SECURITY_BIN" find-identity -v -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null || true)
    while IFS= read -r line; do
        if [[ "$line" == *"\"$IDENTITY_NAME\"" ]]; then
            fingerprint=$(normalize_fingerprint "$(printf '%s\n' "$line" | /usr/bin/awk '{print $2}')")
            if [[ "$fingerprint" == "$expected" ]]; then
                return 0
            fi
        fi
    done <<< "$output"
    return 1
}

SIGN_IDENTITY="-"
SIGN_MODE="ad-hoc"

if [[ -f "$LOCAL_CONFIG" ]]; then
    SIGN_IDENTITY=$(normalize_fingerprint "$(config_value CAB_CODE_SIGN_IDENTITY)")
    if ! is_valid_fingerprint "$SIGN_IDENTITY"; then
        echo "FAIL: local signing config has an invalid certificate fingerprint" >&2
        exit 1
    fi

    configured_keychain=$(config_value CAB_CODE_SIGN_KEYCHAIN)
    if [[ -n "$configured_keychain" ]]; then
        SIGN_KEYCHAIN="$configured_keychain"
    fi
    if ! identity_available "$SIGN_IDENTITY"; then
        echo "FAIL: local signing is configured but the identity is unavailable: $SIGN_IDENTITY" >&2
        exit 1
    fi
    SIGN_MODE="local"
fi

if [[ "${1:-}" == "--signing-status" ]]; then
    echo "mode=$SIGN_MODE identity=$SIGN_IDENTITY"
    if [[ "$SIGN_MODE" == "local" ]]; then
        echo "keychain=$SIGN_KEYCHAIN"
    fi
    exit 0
fi

sign_code() {
    if [[ "$SIGN_MODE" == "local" ]]; then
        codesign --force --sign "$SIGN_IDENTITY" --keychain "$SIGN_KEYCHAIN" "$@"
    else
        codesign --force --sign "$SIGN_IDENTITY" "$@"
    fi
}

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "FAIL: entitlements file missing: $ENTITLEMENTS" >&2
    exit 1
fi

# Clean prior artifacts
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 1. Archive
echo "=== Archiving ==="
xcodebuild \
    -project "$ROOT/ClaudeAlertBot.xcodeproj" \
    -scheme ClaudeAlertBot \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    archive

# 2. Export the .app
mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME" "$EXPORT_DIR/"
APP="$EXPORT_DIR/$APP_NAME"

# 3. Sign each Mach-O explicitly (Pitfall #9 — Apple deprecated the recursive flag)
# --entitlements is required because hardened runtime + missing
# `com.apple.security.automation.apple-events` causes macOS to silently deny the
# AppleEvents permission prompt with -1743 (errAEEventNotPermitted) instead of showing
# the user the TCC dialog. The bundle-seal step also takes --entitlements because
# `codesign --force` on the bundle re-signs the inner main executable and would
# strip entitlements if not re-supplied.
echo "=== $SIGN_MODE signing ==="
if [ -f "$APP/Contents/MacOS/cab-test" ]; then
    sign_code --options=runtime "$APP/Contents/MacOS/cab-test"
fi
sign_code --options=runtime --entitlements "$ENTITLEMENTS" "$APP/Contents/MacOS/ClaudeAlertBot"
# Bundle seal LAST
sign_code --options=runtime --entitlements "$ENTITLEMENTS" "$APP"

# 4. Verify each binary
echo "=== Verifying signatures ==="
BUNDLE_SIG=$(codesign -dv --verbose=4 "$APP" 2>&1 | grep -E '^Signature=' | head -1 || true)
MAIN_SIG=$(codesign -dv --verbose=4 "$APP/Contents/MacOS/ClaudeAlertBot" 2>&1 | grep -E '^Signature=' | head -1 || true)

CABTEST_SIG=""
if [ -f "$APP/Contents/MacOS/cab-test" ]; then
    CABTEST_SIG=$(codesign -dv --verbose=4 "$APP/Contents/MacOS/cab-test" 2>&1 | grep -E '^Signature=' | head -1 || true)
fi

if [[ "$SIGN_MODE" == "ad-hoc" ]]; then
    if ! echo "$BUNDLE_SIG" | grep -q "Signature=adhoc"; then
        echo "FAIL: bundle is not ad-hoc signed: $BUNDLE_SIG" >&2
        exit 1
    fi
    if ! echo "$MAIN_SIG" | grep -q "Signature=adhoc"; then
        echo "FAIL: main executable is not ad-hoc signed: $MAIN_SIG" >&2
        exit 1
    fi
    if [[ -n "$CABTEST_SIG" ]] && ! echo "$CABTEST_SIG" | grep -q "Signature=adhoc"; then
        echo "FAIL: cab-test is not ad-hoc signed: $CABTEST_SIG" >&2
        exit 1
    fi
else
    verify_local_signature() {
        local label="$1"
        local path="$2"
        local details certificate_dir certificate_prefix fingerprint_output actual_fingerprint
        details=$(codesign -dv --verbose=4 "$path" 2>&1)
        if ! echo "$details" | grep -Fq "Authority=$IDENTITY_NAME"; then
            echo "FAIL: $label was not signed by $IDENTITY_NAME" >&2
            exit 1
        fi

        certificate_dir=$(mktemp -d "${TMPDIR:-/tmp}/claude-alert-bot-certificates.XXXXXX")
        certificate_prefix="$certificate_dir/cert"
        codesign -d --extract-certificates "$certificate_prefix" "$path" >/dev/null 2>&1
        fingerprint_output=$("$OPENSSL_BIN" x509 -inform DER -in "${certificate_prefix}0" -noout -fingerprint -sha1)
        rm -rf "$certificate_dir"
        actual_fingerprint=$(normalize_fingerprint "${fingerprint_output#*=}")
        if [[ "$actual_fingerprint" != "$SIGN_IDENTITY" ]]; then
            echo "FAIL: $label certificate fingerprint changed: $actual_fingerprint" >&2
            exit 1
        fi
    }

    verify_local_signature "bundle" "$APP"
    verify_local_signature "main executable" "$APP/Contents/MacOS/ClaudeAlertBot"
    if [ -f "$APP/Contents/MacOS/cab-test" ]; then
        verify_local_signature "cab-test" "$APP/Contents/MacOS/cab-test"
    fi
fi

codesign --verify --verbose=4 "$APP"

echo
echo "=== Build complete ==="
echo "App: $APP"
echo "Bundle: $BUNDLE_SIG"
echo "Main:   $MAIN_SIG"
[ -n "${CABTEST_SIG:-}" ] && echo "CabTest: $CABTEST_SIG"
