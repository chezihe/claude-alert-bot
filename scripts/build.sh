#!/bin/bash
# scripts/build.sh — Phase 1 build pipeline (DIST-01).
# Produces an ad-hoc-signed build/export/ClaudeAlertBot.app from a clean checkout.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/ClaudeAlertBot.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_NAME="ClaudeAlertBot.app"

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

# 3. Ad-hoc sign each Mach-O explicitly (Pitfall #9 — Apple deprecated the recursive flag)
echo "=== Ad-hoc signing ==="
if [ -f "$APP/Contents/MacOS/cab-test" ]; then
    codesign --force --sign - --options=runtime "$APP/Contents/MacOS/cab-test"
fi
codesign --force --sign - --options=runtime "$APP/Contents/MacOS/ClaudeAlertBot"
# Bundle seal LAST
codesign --force --sign - --options=runtime "$APP"

# 4. Verify each binary
echo "=== Verifying signatures ==="
BUNDLE_SIG=$(codesign -dv --verbose=4 "$APP" 2>&1 | grep -E '^Signature=' | head -1 || true)
MAIN_SIG=$(codesign -dv --verbose=4 "$APP/Contents/MacOS/ClaudeAlertBot" 2>&1 | grep -E '^Signature=' | head -1 || true)

if ! echo "$BUNDLE_SIG" | grep -q "Signature=adhoc"; then
    echo "FAIL: bundle is not ad-hoc signed: $BUNDLE_SIG" >&2
    exit 1
fi
if ! echo "$MAIN_SIG" | grep -q "Signature=adhoc"; then
    echo "FAIL: main executable is not ad-hoc signed: $MAIN_SIG" >&2
    exit 1
fi

CABTEST_SIG=""
if [ -f "$APP/Contents/MacOS/cab-test" ]; then
    CABTEST_SIG=$(codesign -dv --verbose=4 "$APP/Contents/MacOS/cab-test" 2>&1 | grep -E '^Signature=' | head -1 || true)
    if ! echo "$CABTEST_SIG" | grep -q "Signature=adhoc"; then
        echo "FAIL: cab-test is not ad-hoc signed: $CABTEST_SIG" >&2
        exit 1
    fi
fi

codesign --verify --verbose=4 "$APP"

echo
echo "=== Build complete ==="
echo "App: $APP"
echo "Bundle: $BUNDLE_SIG"
echo "Main:   $MAIN_SIG"
[ -n "${CABTEST_SIG:-}" ] && echo "CabTest: $CABTEST_SIG"
