#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_DIR="$ROOT_DIR/Subpackages/BatteryCapHelper"
BUILD_DIR="$HELPER_DIR/.build"
HELPER_EXEC="$BUILD_DIR/release/BatteryCapHelper"
PLIST_SOURCE="$ROOT_DIR/Sources/BatteryCap/Resources/com.batterycap.helper.plist"
PLIST_DEST="/Library/LaunchDaemons/com.batterycap.helper.plist"
BIN_DEST="/Library/PrivilegedHelperTools/com.batterycap.helper"

if [[ ! -f "$PLIST_SOURCE" ]]; then
  echo "Missing helper plist: $PLIST_SOURCE" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  BUILD_DIR="$HELPER_DIR/.build-user"
  HELPER_EXEC="$BUILD_DIR/release/BatteryCapHelper"
  ( cd "$HELPER_DIR" && swift build -c release --scratch-path "$BUILD_DIR" )
  exec /usr/bin/sudo "$0" --install-only --build-dir "$BUILD_DIR"
fi

while [[ "${1-}" =~ ^-- ]]; do
  case "$1" in
    --install-only)
      INSTALL_ONLY=1
      shift
      ;;
    --build-dir)
      BUILD_DIR="$2"
      HELPER_EXEC="$BUILD_DIR/release/BatteryCapHelper"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${INSTALL_ONLY-0}" -ne 1 ]]; then
  ( cd "$HELPER_DIR" && swift build -c release --scratch-path "$BUILD_DIR" )
fi

if [[ ! -f "$HELPER_EXEC" ]]; then
  echo "Helper executable not found: $HELPER_EXEC" >&2
  exit 1
fi

mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons

install -m 755 -o root -g wheel "$HELPER_EXEC" "$BIN_DEST"
install -m 644 -o root -g wheel "$PLIST_SOURCE" "$PLIST_DEST"

if [[ -n "${SUDO_USER-}" ]]; then
  chown -R "$SUDO_USER":staff "$BUILD_DIR" 2>/dev/null || true
fi

launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DEST"
launchctl enable system/com.batterycap.helper

echo "Helper installed"
