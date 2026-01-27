#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  exec /usr/bin/sudo "$0" "$@"
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_DIR="$ROOT_DIR/Subpackages/BatteryCapHelper"
HELPER_EXEC="$HELPER_DIR/.build/release/BatteryCapHelper"
PLIST_SOURCE="$ROOT_DIR/Sources/BatteryCap/Resources/com.batterycap.helper.plist"
PLIST_DEST="/Library/LaunchDaemons/com.batterycap.helper.plist"
BIN_DEST="/Library/PrivilegedHelperTools/com.batterycap.helper"

if [[ ! -f "$PLIST_SOURCE" ]]; then
  echo "Missing helper plist: $PLIST_SOURCE" >&2
  exit 1
fi

( cd "$HELPER_DIR" && swift build -c release )

if [[ ! -f "$HELPER_EXEC" ]]; then
  echo "Helper executable not found: $HELPER_EXEC" >&2
  exit 1
fi

mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons

install -m 755 -o root -g wheel "$HELPER_EXEC" "$BIN_DEST"
install -m 644 -o root -g wheel "$PLIST_SOURCE" "$PLIST_DEST"

launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DEST"
launchctl enable system/com.batterycap.helper

echo "Helper installed"
