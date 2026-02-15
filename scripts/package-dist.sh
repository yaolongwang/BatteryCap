#!/usr/bin/env bash
# 功能：构建分发产物（app/dmg），含主程序、Helper 与安装资源。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP="$ROOT_DIR/dist/BatteryCap.app"
DIST_DMG="$ROOT_DIR/dist/BatteryCap.dmg"
DMG_STAGE_DIR="$ROOT_DIR/.build/dist-dmg"
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

usage() {
  cat <<'EOF'
用法:
  package-dist.sh [子命令]

子命令:
  app    构建 dist/BatteryCap.app
  dmg    构建 dist/BatteryCap.app 并生成 dist/BatteryCap.dmg
  help   显示帮助
  -h     显示帮助

默认子命令: app
EOF
}

build_dist_app() {
  mkdir -p "$DIST_DIR"

  log "构建主程序（release）"
  swift build -c release --scratch-path "$MAIN_SCRATCH_PATH"

  log "构建 Helper（release）"
  swift build -c release --package-path "$HELPER_PACKAGE_DIR" --scratch-path "$HELPER_SCRATCH_PATH"

  local main_bin_dir helper_bin_dir main_exec helper_exec
  main_bin_dir="$(swift build -c release --scratch-path "$MAIN_SCRATCH_PATH" --show-bin-path)"
  helper_bin_dir="$(swift build -c release --package-path "$HELPER_PACKAGE_DIR" --scratch-path "$HELPER_SCRATCH_PATH" --show-bin-path)"
  main_exec="$main_bin_dir/BatteryCap"
  helper_exec="$helper_bin_dir/BatteryCapHelper"

  if [[ ! -f "$main_exec" ]]; then
    echo "[BatteryCap] 错误：未找到主程序可执行文件：$main_exec" >&2
    exit 1
  fi

  if [[ ! -f "$helper_exec" ]]; then
    echo "[BatteryCap] 错误：未找到 Helper 可执行文件：$helper_exec" >&2
    exit 1
  fi

  rm -rf "$DIST_APP"
  mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

  cp "$MAIN_INFO_PLIST" "$CONTENTS_DIR/Info.plist"
  cp "$main_exec" "$MACOS_DIR/BatteryCap"
  chmod 755 "$MACOS_DIR/BatteryCap"

  cp -R "$MAIN_RESOURCES_DIR/." "$RESOURCES_DIR/"
  cp "$helper_exec" "$RESOURCES_DIR/BatteryCapHelper"
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
}

build_dist_dmg() {
  build_dist_app
  if ! command -v hdiutil >/dev/null 2>&1; then
    echo "[BatteryCap] 错误：未找到 hdiutil，无法生成 dmg。" >&2
    exit 1
  fi

  rm -f "$DIST_DMG"
  rm -rf "$DMG_STAGE_DIR"
  mkdir -p "$DMG_STAGE_DIR"
  cp -R "$DIST_APP" "$DMG_STAGE_DIR/BatteryCap.app"
  ln -s /Applications "$DMG_STAGE_DIR/Applications"

  hdiutil create -volname "BatteryCap" -srcfolder "$DMG_STAGE_DIR" -ov -format UDZO "$DIST_DMG" >/dev/null
  rm -rf "$DMG_STAGE_DIR"
  log "已生成 dmg：$DIST_DMG"
}

main() {
  local command
  command="${1:-app}"
  case "$command" in
    app)
      build_dist_app
      ;;
    dmg)
      build_dist_dmg
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      echo "[BatteryCap] 错误：未知子命令：$command" >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"
