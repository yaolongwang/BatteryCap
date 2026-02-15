#!/usr/bin/env bash
set -euo pipefail

LAUNCH_LABEL="com.batterycap.helper"
PLIST_DEST="/Library/LaunchDaemons/${LAUNCH_LABEL}.plist"
BIN_DEST="/Library/PrivilegedHelperTools/${LAUNCH_LABEL}"
SWIFT_TOOL="swift"

log() {
  echo "[BatteryCap] $*"
}

fatal() {
  echo "[BatteryCap] 错误：$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_MODE=0

if [[ "$SCRIPT_DIR" == *".app/Contents/Resources"* ]]; then
  BUNDLE_MODE=1
fi

if [[ "$BUNDLE_MODE" -eq 1 ]]; then
  HELPER_EXEC="${SCRIPT_DIR}/BatteryCapHelper"
  PLIST_SOURCE="${SCRIPT_DIR}/com.batterycap.helper.plist"
else
  ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
  HELPER_DIR="${ROOT_DIR}/Subpackages/BatteryCapHelper"
  BUILD_DIR="${HELPER_DIR}/.build"
  HELPER_EXEC="${BUILD_DIR}/release/BatteryCapHelper"
  PLIST_SOURCE="${ROOT_DIR}/Sources/BatteryCap/Resources/com.batterycap.helper.plist"
fi

INSTALL_ONLY=0
if [[ "$BUNDLE_MODE" -eq 0 ]]; then
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
fi

if [[ ! -f "$PLIST_SOURCE" ]]; then
  fatal "缺少 helper plist：$PLIST_SOURCE"
fi

if ! /usr/bin/plutil -lint "$PLIST_SOURCE" >/dev/null 2>&1; then
  fatal "helper plist 校验失败：$PLIST_SOURCE"
fi

if [[ "$BUNDLE_MODE" -eq 0 ]]; then
  if ! command -v "$SWIFT_TOOL" >/dev/null 2>&1; then
    fatal "未找到 Swift 工具链，请先安装 Xcode 或 Command Line Tools。"
  fi
fi

if [[ "$(id -u)" -eq 0 && "$BUNDLE_MODE" -eq 0 && "$INSTALL_ONLY" -ne 1 ]]; then
  fatal "请在非 root 用户下运行脚本，root 仅用于安装阶段。"
fi

if [[ "$(id -u)" -ne 0 ]]; then
  if [[ "$BUNDLE_MODE" -eq 0 ]]; then
    BUILD_DIR="$HELPER_DIR/.build-user"
    HELPER_EXEC="$BUILD_DIR/release/BatteryCapHelper"
    ( cd "$HELPER_DIR" && "$SWIFT_TOOL" build -c release --scratch-path "$BUILD_DIR" )
    log "构建完成：$HELPER_EXEC"
    exec /usr/bin/sudo "$0" --install-only --build-dir "$BUILD_DIR"
  fi

  exec /usr/bin/sudo "$0" "$@"
fi

if [[ "$BUNDLE_MODE" -eq 0 ]]; then
  if [[ "$INSTALL_ONLY" -ne 1 ]]; then
    ( cd "$HELPER_DIR" && "$SWIFT_TOOL" build -c release --scratch-path "$BUILD_DIR" )
    log "构建完成：$HELPER_EXEC"
  fi
fi

if [[ ! -f "$HELPER_EXEC" ]]; then
  if [[ "$BUNDLE_MODE" -eq 1 ]]; then
    fatal "未找到内置 Helper：$HELPER_EXEC"
  fi
  fatal "未找到 Helper 可执行文件：$HELPER_EXEC"
fi

mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons

install -m 755 -o root -g wheel "$HELPER_EXEC" "$BIN_DEST"
install -m 644 -o root -g wheel "$PLIST_SOURCE" "$PLIST_DEST"

log "已安装 Helper：$BIN_DEST"
log "已安装 LaunchDaemon：$PLIST_DEST"

if [[ -n "${SUDO_USER-}" && "$BUNDLE_MODE" -eq 0 ]]; then
  chown -R "$SUDO_USER":staff "$BUILD_DIR" 2>/dev/null || true
fi

launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DEST"
launchctl enable system/$LAUNCH_LABEL
launchctl kickstart -k system/$LAUNCH_LABEL || true

log "Helper installed"
