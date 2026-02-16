#!/usr/bin/env bash
# 功能：统一构建图标与分发产物（icon/app/dmg）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DIST_DIR="$ROOT_DIR/dist"
DIST_APP="$DIST_DIR/BatteryCap.app"
DIST_DMG="$DIST_DIR/BatteryCap.dmg"
DMG_STAGE_DIR="$ROOT_DIR/.build/dist-dmg"

CONTENTS_DIR="$DIST_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DIST_RESOURCES_DIR="$RESOURCES_DIR"
DIST_INFO_PLIST="$CONTENTS_DIR/Info.plist"

MAIN_INFO_PLIST="$ROOT_DIR/Sources/BatteryCap/Info.plist"
MAIN_RESOURCES_DIR="$ROOT_DIR/Sources/BatteryCap/Resources"
HELPER_PACKAGE_DIR="$ROOT_DIR/Subpackages/BatteryCapHelper"

MAIN_SCRATCH_PATH="$ROOT_DIR/.build/dist-main"
HELPER_SCRATCH_PATH="$ROOT_DIR/.build/dist-helper"

ICON_SOURCE="$ROOT_DIR/assets/BatteryCap.icon"
ICON_BUILD_DIR="$ROOT_DIR/.build/icon-assets"
PARTIAL_INFO_PLIST="$ICON_BUILD_DIR/partial-info.plist"

VERBOSE_MODE=0
DIST_COMMAND="app"
APP_ICON_STATUS="未执行"
APP_CODESIGN_STATUS="未执行"

log() {
  echo "[BatteryCap] $*"
}

warn() {
  echo "[BatteryCap] 警告：$*" >&2
}

fatal() {
  echo "[BatteryCap] 错误：$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法:
  build-dist.sh [子命令] [选项]

子命令:
  icon   编译应用图标，并在存在 dist app 时写入其 Resources
  app    构建 dist/BatteryCap.app
  dmg    构建 dist/BatteryCap.app 并生成 dist/BatteryCap.dmg
  help   显示帮助
  -h     显示帮助

选项:
  --verbose  输出可选步骤完整日志

默认子命令: app
EOF
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fatal "未找到命令：$command_name"
  fi
}

require_file() {
  local file_path="$1"
  local description="$2"
  if [[ ! -f "$file_path" ]]; then
    fatal "缺少${description}：$file_path"
  fi
}

require_dir() {
  local dir_path="$1"
  local description="$2"
  if [[ ! -d "$dir_path" ]]; then
    fatal "缺少${description}：$dir_path"
  fi
}

run_optional_step() {
  local step_name="$1"
  shift

  local output_file
  output_file="$(mktemp)"
  if "$@" >"$output_file" 2>&1; then
    if [[ "$VERBOSE_MODE" -eq 1 && -s "$output_file" ]]; then
      cat "$output_file"
    fi
    rm -f "$output_file"
    return 0
  fi

  warn "$step_name 失败。"
  if [[ -s "$output_file" ]]; then
    warn "$step_name 输出（最后 20 行）："
    tail -n 20 "$output_file" >&2
  fi
  rm -f "$output_file"
  return 1
}

build_release() {
  swift build -c release "$@"
}

show_release_bin_path() {
  swift build -c release "$@" --show-bin-path
}

copy_dist_resources() {
  local resources=(
    "batterycap-service.sh"
    "com.batterycap.helper.plist"
  )
  local resource_name

  for resource_name in "${resources[@]}"; do
    require_file "$MAIN_RESOURCES_DIR/$resource_name" "资源文件"
    cp "$MAIN_RESOURCES_DIR/$resource_name" "$RESOURCES_DIR/$resource_name"
  done
}

print_dist_app_summary() {
  local app_size
  app_size="$(du -sh "$DIST_APP" | awk '{print $1}')"

  log "已生成App：$DIST_APP"
  log "App大小：$app_size"
  log "图标编译：$APP_ICON_STATUS"
  log "代码签名：$APP_CODESIGN_STATUS"
}

cleanup_dmg_stage() {
  rm -rf "$DMG_STAGE_DIR"
}

print_dist_dmg_summary() {
  local dmg_size
  dmg_size="$(du -sh "$DIST_DMG" | awk '{print $1}')"
  log "已生成DMG：$DIST_DMG"
  log "DMG大小：$dmg_size"
}

preflight_app() {
  require_command swift
  require_file "$MAIN_INFO_PLIST" "Info.plist"
  require_dir "$MAIN_RESOURCES_DIR" "主程序资源目录"
  require_dir "$HELPER_PACKAGE_DIR" "Helper 子包目录"
}

parse_args() {
  local command_set=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      app|dmg|icon|help)
        if [[ "$command_set" -eq 1 ]]; then
          fatal "只能指定一个子命令。"
        fi
        DIST_COMMAND="$1"
        command_set=1
        ;;
      -h|--help)
        DIST_COMMAND="help"
        command_set=1
        ;;
      --verbose)
        VERBOSE_MODE=1
        ;;
      *)
        fatal "未知参数：$1"
        ;;
    esac
    shift
  done
}

compile_app_icon() {
  if [[ ! -d "$ICON_SOURCE" ]]; then
    echo "error: missing icon source: $ICON_SOURCE" >&2
    return 1
  fi

  if ! mkdir -p "$ICON_BUILD_DIR"; then
    return 1
  fi

  if ! xcrun actool \
    --compile "$ICON_BUILD_DIR" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --target-device mac \
    --app-icon BatteryCap \
    --output-partial-info-plist "$PARTIAL_INFO_PLIST" \
    "$ICON_SOURCE"
  then
    return 1
  fi

  echo "compiled icon assets: $ICON_BUILD_DIR/Assets.car"
  echo "generated fallback icon: $ICON_BUILD_DIR/BatteryCap.icns"

  if [[ -d "$DIST_RESOURCES_DIR" ]]; then
    if ! cp "$ICON_BUILD_DIR/Assets.car" "$DIST_RESOURCES_DIR/Assets.car"; then
      return 1
    fi
    if ! cp "$ICON_BUILD_DIR/BatteryCap.icns" "$DIST_RESOURCES_DIR/BatteryCap.icns"; then
      return 1
    fi

    if [[ -f "$DIST_INFO_PLIST" ]]; then
      if /usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$DIST_INFO_PLIST" >/dev/null 2>&1; then
        if ! /usr/libexec/PlistBuddy -c "Set :CFBundleIconName BatteryCap" "$DIST_INFO_PLIST"; then
          return 1
        fi
      else
        if ! /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string BatteryCap" "$DIST_INFO_PLIST"; then
          return 1
        fi
      fi
    fi
    echo "updated dist resources: $DIST_RESOURCES_DIR"
  else
    echo "note: dist app not found, skipped copy to dist"
  fi
}

build_dist_app() {
  local show_summary="${1:-1}"
  mkdir -p "$DIST_DIR"

  APP_ICON_STATUS="未执行"
  APP_CODESIGN_STATUS="未执行"

  log "构建主程序（release）"
  build_release --scratch-path "$MAIN_SCRATCH_PATH"

  log "构建 Helper（release）"
  build_release --package-path "$HELPER_PACKAGE_DIR" --scratch-path "$HELPER_SCRATCH_PATH"

  local main_bin_dir helper_bin_dir main_exec helper_exec
  main_bin_dir="$(show_release_bin_path --scratch-path "$MAIN_SCRATCH_PATH")"
  helper_bin_dir="$(show_release_bin_path --package-path "$HELPER_PACKAGE_DIR" --scratch-path "$HELPER_SCRATCH_PATH")"
  main_exec="$main_bin_dir/BatteryCap"
  helper_exec="$helper_bin_dir/BatteryCapHelper"

  if [[ ! -f "$main_exec" ]]; then
    fatal "未找到主程序可执行文件：$main_exec"
  fi

  if [[ ! -f "$helper_exec" ]]; then
    fatal "未找到 Helper 可执行文件：$helper_exec"
  fi

  rm -rf "$DIST_APP"
  mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

  cp "$MAIN_INFO_PLIST" "$CONTENTS_DIR/Info.plist"
  cp "$main_exec" "$MACOS_DIR/BatteryCap"
  chmod 755 "$MACOS_DIR/BatteryCap"

  copy_dist_resources
  cp "$helper_exec" "$RESOURCES_DIR/BatteryCapHelper"
  chmod 755 "$RESOURCES_DIR/BatteryCapHelper"
  chmod 755 "$RESOURCES_DIR/batterycap-service.sh"

  if command -v xcrun >/dev/null 2>&1; then
    if run_optional_step "编译应用图标" compile_app_icon; then
      APP_ICON_STATUS="成功"
    else
      APP_ICON_STATUS="失败"
    fi
  else
    APP_ICON_STATUS="跳过（未找到 xcrun）"
  fi

  if command -v codesign >/dev/null 2>&1; then
    if run_optional_step "应用签名" codesign --force --deep --sign - "$DIST_APP"; then
      APP_CODESIGN_STATUS="成功（Ad-Hoc）"
    else
      APP_CODESIGN_STATUS="失败"
    fi
  else
    APP_CODESIGN_STATUS="跳过（未找到 codesign）"
  fi

  if [[ "$show_summary" -eq 1 ]]; then
    print_dist_app_summary
  fi
}

build_dist_dmg() {
  build_dist_app
  require_command hdiutil

  rm -f "$DIST_DMG"
  cleanup_dmg_stage
  trap cleanup_dmg_stage RETURN
  mkdir -p "$DMG_STAGE_DIR"
  cp -R "$DIST_APP" "$DMG_STAGE_DIR/BatteryCap.app"
  ln -s /Applications "$DMG_STAGE_DIR/Applications"

  if [[ "$VERBOSE_MODE" -eq 1 ]]; then
    hdiutil create -volname "BatteryCap" -srcfolder "$DMG_STAGE_DIR" -ov -format UDZO "$DIST_DMG"
  else
    hdiutil create -volname "BatteryCap" -srcfolder "$DMG_STAGE_DIR" -ov -format UDZO "$DIST_DMG" >/dev/null
  fi

  trap - RETURN
  cleanup_dmg_stage
  print_dist_dmg_summary
}

main() {
  parse_args "$@"

  case "$DIST_COMMAND" in
    app)
      preflight_app
      build_dist_app
      ;;
    dmg)
      preflight_app
      build_dist_dmg
      ;;
    icon)
      require_command xcrun
      if ! compile_app_icon; then
        fatal "编译应用图标失败"
      fi
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      fatal "未知子命令：$DIST_COMMAND"
      ;;
  esac
}

main "$@"
