#!/usr/bin/env bash
# 功能：构建可分发的 dist/BatteryCap.app（含主程序、Helper 与安装资源）。
set -euo pipefail


ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_APP="$ROOT_DIR/dist/BatteryCap.app"
CONTENTS_DIR="$DIST_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MAIN_INFO_PLIST="$ROOT_DIR/Sources/BatteryCap/Info.plist"
MAIN_RESOURCES_DIR="$ROOT_DIR/Sources/BatteryCap/Resources"
HELPER_PACKAGE_DIR="$ROOT_DIR/Subpackages/BatteryCapHelper"
MAIN_SCRATCH_PATH="$ROOT_DIR/.build/dist-main"
HELPER_SCRATCH_PATH="$ROOT_DIR/.build/dist-helper"

log() {
  echo "[BatteryCap] $*"
}

main_bin_path() {
  local bin_dir
  bin_dir="$(swift build -c release --scratch-path "$MAIN_SCRATCH_PATH" --show-bin-path)"
  echo "$bin_dir/BatteryCap"
}

helper_bin_path() {
  local bin_dir
  bin_dir="$(swift build -c release --package-path "$HELPER_PACKAGE_DIR" --scratch-path "$HELPER_SCRATCH_PATH" --show-bin-path)"
  echo "$bin_dir/BatteryCapHelper"
}

log "构建主程序（release）"
swift build -c release --scratch-path "$MAIN_SCRATCH_PATH"

log "构建 Helper（release）"
swift build -c release --package-path "$HELPER_PACKAGE_DIR" --scratch-path "$HELPER_SCRATCH_PATH"

MAIN_EXEC="$(main_bin_path)"
HELPER_EXEC="$(helper_bin_path)"

if [[ ! -f "$MAIN_EXEC" ]]; then
  echo "[BatteryCap] 错误：未找到主程序可执行文件：$MAIN_EXEC" >&2
  exit 1
fi

if [[ ! -f "$HELPER_EXEC" ]]; then
  echo "[BatteryCap] 错误：未找到 Helper 可执行文件：$HELPER_EXEC" >&2
  exit 1
fi

rm -rf "$DIST_APP"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$MAIN_INFO_PLIST" "$CONTENTS_DIR/Info.plist"
cp "$MAIN_EXEC" "$MACOS_DIR/BatteryCap"
chmod 755 "$MACOS_DIR/BatteryCap"

cp -R "$MAIN_RESOURCES_DIR/." "$RESOURCES_DIR/"
cp "$HELPER_EXEC" "$RESOURCES_DIR/BatteryCapHelper"
chmod 755 "$RESOURCES_DIR/BatteryCapHelper"
chmod 755 "$RESOURCES_DIR/batterycap-service.sh"

if command -v xcrun >/dev/null 2>&1; then
  "$ROOT_DIR/scripts/compile-app-icon.sh" || true
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$DIST_APP" >/dev/null 2>&1 || true
fi

log "已生成分发包：$DIST_APP"
log "请将 BatteryCap.app 拷贝到 /Applications 后首次手动放行再运行。"
