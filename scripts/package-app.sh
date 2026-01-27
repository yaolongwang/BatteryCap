#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$ROOT_DIR/dist/BatteryCap.app"
HELPER_DIR="$ROOT_DIR/Subpackages/BatteryCapHelper"

APP_EXEC="$BUILD_DIR/release/BatteryCap"
HELPER_EXEC="$HELPER_DIR/.build/release/BatteryCapHelper"

echo "==> Building app"
( cd "$ROOT_DIR" && swift build -c release )

echo "==> Building helper"
( cd "$HELPER_DIR" && swift build -c release )

if [[ ! -f "$APP_EXEC" ]]; then
  echo "App executable not found: $APP_EXEC" >&2
  exit 1
fi
if [[ ! -f "$HELPER_EXEC" ]]; then
  echo "Helper executable not found: $HELPER_EXEC" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Library/LaunchServices"

cp "$APP_EXEC" "$APP_DIR/Contents/MacOS/BatteryCap"
cp "$ROOT_DIR/Sources/BatteryCap/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -d "$ROOT_DIR/Sources/BatteryCap/Resources" ]]; then
  cp -R "$ROOT_DIR/Sources/BatteryCap/Resources"/* "$APP_DIR/Contents/Resources/" 2>/dev/null || true
fi

cp "$ROOT_DIR/Sources/BatteryCap/Resources/com.batterycap.helper.plist" \
   "$APP_DIR/Contents/Library/LaunchServices/com.batterycap.helper.plist"
cp "$HELPER_EXEC" "$APP_DIR/Contents/Library/LaunchServices/com.batterycap.helper"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "==> Codesigning helper"
  codesign --force --options runtime --sign "$CODESIGN_IDENTITY" "$APP_DIR/Contents/Library/LaunchServices/com.batterycap.helper"
  echo "==> Codesigning app"
  codesign --force --options runtime --sign "$CODESIGN_IDENTITY" --deep "$APP_DIR"
else
  echo "==> Skipping codesign (set CODESIGN_IDENTITY to enable)"
fi

echo "==> App bundle ready: $APP_DIR"
