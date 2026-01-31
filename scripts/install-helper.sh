#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_DIR="$ROOT_DIR/Subpackages/BatteryCapHelper"
BUILD_DIR="$HELPER_DIR/.build"
HELPER_EXEC="$BUILD_DIR/release/BatteryCapHelper"
PLIST_SOURCE="$ROOT_DIR/Sources/BatteryCap/Resources/com.batterycap.helper.plist"
PLIST_DEST="/Library/LaunchDaemons/com.batterycap.helper.plist"
BIN_DEST="/Library/PrivilegedHelperTools/com.batterycap.helper"
LAUNCH_LABEL="com.batterycap.helper"
SWIFT_TOOL="swift"

log() {
  echo "[BatteryCap] $*"
}

fatal() {
  echo "[BatteryCap] 错误：$*" >&2
  exit 1
}

if ! command -v "$SWIFT_TOOL" >/dev/null 2>&1; then
  fatal "未找到 Swift 工具链，请先安装 Xcode 或 Command Line Tools。"
fi

if [[ ! -f "$PLIST_SOURCE" ]]; then
  fatal "缺少 helper plist：$PLIST_SOURCE"
fi

if ! /usr/bin/plutil -lint "$PLIST_SOURCE" >/dev/null 2>&1; then
  fatal "helper plist 校验失败：$PLIST_SOURCE"
fi

if [[ "$(id -u)" -eq 0 && "${1-}" != "--install-only" ]]; then
  fatal "请在非 root 用户下运行脚本，root 仅用于安装阶段。"
fi

if [[ "$(id -u)" -ne 0 ]]; then
  BUILD_DIR="$HELPER_DIR/.build-user"
  HELPER_EXEC="$BUILD_DIR/release/BatteryCapHelper"
  ( cd "$HELPER_DIR" && "$SWIFT_TOOL" build -c release --scratch-path "$BUILD_DIR" )
  log "构建完成：$HELPER_EXEC"
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
  ( cd "$HELPER_DIR" && "$SWIFT_TOOL" build -c release --scratch-path "$BUILD_DIR" )
  log "构建完成：$HELPER_EXEC"
fi

if [[ ! -f "$HELPER_EXEC" ]]; then
  fatal "未找到 Helper 可执行文件：$HELPER_EXEC"
fi

mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons

install -m 755 -o root -g wheel "$HELPER_EXEC" "$BIN_DEST"
install -m 644 -o root -g wheel "$PLIST_SOURCE" "$PLIST_DEST"

log "已安装 Helper：$BIN_DEST"
log "已安装 LaunchDaemon：$PLIST_DEST"

if [[ -n "${SUDO_USER-}" ]]; then
  chown -R "$SUDO_USER":staff "$BUILD_DIR" 2>/dev/null || true
fi

launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DEST"
launchctl enable system/$LAUNCH_LABEL
launchctl kickstart -k system/$LAUNCH_LABEL || true

log "Helper installed"
