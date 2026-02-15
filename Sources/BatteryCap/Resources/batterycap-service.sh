#!/usr/bin/env bash
# 功能：统一管理安装/卸载 Helper 与卸载清理流程的服务脚本。
set -euo pipefail

LAUNCH_LABEL="com.batterycap.helper"
PLIST_DEST="/Library/LaunchDaemons/${LAUNCH_LABEL}.plist"
BIN_DEST="/Library/PrivilegedHelperTools/${LAUNCH_LABEL}"
PREFERENCES_DOMAIN="com.batterycap.app"
SWIFT_TOOL="swift"

log() {
  echo "[BatteryCap] $*"
}

fatal() {
  echo "[BatteryCap] 错误：$*" >&2
  exit 1
}

clear_quarantine_if_present() {
  local target_path="$1"
  if ! command -v xattr >/dev/null 2>&1; then
    return
  fi
  xattr -d com.apple.quarantine "$target_path" 2>/dev/null || true
}

usage() {
  cat <<'EOF'
用法:
  batterycap-service.sh <子命令> [选项]

子命令:
  install         安装并启动 Helper 服务
  uninstall       卸载 Helper 服务
  purge-config    清理当前用户配置（不卸载 App）
  full-uninstall  完整卸载（卸载 Helper + 删除 App + 清理用户配置）
  help            显示帮助
  -h              显示帮助

选项:
  --install-only  仅执行安装阶段（内部参数）
  --build-dir DIR 指定 Helper 构建目录（内部参数）
EOF
}

ensure_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    exec /usr/bin/sudo "$0" "$@"
  fi
}

resolve_target_user() {
  local target_user
  target_user="${SUDO_USER:-}"
  if [[ -z "$target_user" ]]; then
    target_user="$(stat -f%Su /dev/console 2>/dev/null || true)"
  fi
  if [[ -z "$target_user" || "$target_user" == "root" || "$target_user" == "loginwindow" ]]; then
    log "未能确定需要清理的用户，请在普通用户下运行。"
    return 1
  fi
  echo "$target_user"
}

purge_user_preferences() {
  local target_user user_home pref_plist pref_lock
  target_user="$(resolve_target_user)" || return 0
  user_home="$(eval echo "~${target_user}")"
  if [[ -z "$user_home" || ! -d "$user_home" ]]; then
    log "未能定位用户目录：$target_user"
    return 0
  fi
  pref_plist="${user_home}/Library/Preferences/${PREFERENCES_DOMAIN}.plist"
  pref_lock="${pref_plist}.lockfile"
  rm -f "$pref_plist" "$pref_lock"
  log "已清理用户配置：${PREFERENCES_DOMAIN} (${target_user})"
}

remove_app_bundle() {
  local target_user user_home app_path
  target_user="$(resolve_target_user)" || return 0
  user_home="$(eval echo "~${target_user}")"
  /usr/bin/sudo -u "$target_user" /usr/bin/osascript -e 'tell application "BatteryCap" to quit' 2>/dev/null || true
  for app_path in "/Applications/BatteryCap.app" "${user_home}/Applications/BatteryCap.app"; do
    if [[ -d "$app_path" ]]; then
      rm -rf "$app_path"
      log "已移除应用：$app_path"
    fi
  done
  rm -rf "${user_home}/Library/Application Support/BatteryCap"
  rm -rf "${user_home}/Library/Caches/${PREFERENCES_DOMAIN}"
}

disable_app_controls_for_uninstall() {
  local target_user user_home app_path app_exec
  target_user="$(resolve_target_user)" || return 0
  user_home="$(eval echo "~${target_user}")"

  /usr/bin/sudo -u "$target_user" /usr/bin/defaults write "$PREFERENCES_DOMAIN" BatteryCap.isLimitControlEnabled -bool false || true
  /usr/bin/sudo -u "$target_user" /usr/bin/defaults write "$PREFERENCES_DOMAIN" BatteryCap.launchAtLoginEnabled -bool false || true

  for app_path in "/Applications/BatteryCap.app" "${user_home}/Applications/BatteryCap.app"; do
    app_exec="${app_path}/Contents/MacOS/BatteryCap"
    if [[ -x "$app_exec" ]]; then
      /usr/bin/sudo -u "$target_user" "$app_exec" --disable-controls-for-uninstall >/dev/null 2>&1 || true
      break
    fi
  done
}

uninstall_helper_core() {
  if [[ -f "$PLIST_DEST" ]]; then
    launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
  else
    launchctl bootout system/"$LAUNCH_LABEL" 2>/dev/null || true
  fi
  launchctl disable system/"$LAUNCH_LABEL" 2>/dev/null || true
  rm -f "$PLIST_DEST" "$BIN_DEST"
  log "Helper removed"
}

install_helper() {
  local script_dir bundle_mode install_only root_dir helper_dir build_dir helper_exec plist_source
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  bundle_mode=0
  install_only=0

  if [[ "$script_dir" == *".app/Contents/Resources"* ]]; then
    bundle_mode=1
  fi

  if [[ "$bundle_mode" -eq 1 ]]; then
    helper_exec="${script_dir}/BatteryCapHelper"
    if [[ ! -f "$helper_exec" && -f "${script_dir}/../MacOS/BatteryCapHelper" ]]; then
      helper_exec="${script_dir}/../MacOS/BatteryCapHelper"
    fi
    plist_source="${script_dir}/com.batterycap.helper.plist"
  else
    root_dir="$(cd "${script_dir}/../../.." && pwd)"
    helper_dir="${root_dir}/Subpackages/BatteryCapHelper"
    build_dir="${helper_dir}/.build"
    helper_exec="${build_dir}/release/BatteryCapHelper"
    plist_source="${root_dir}/Sources/BatteryCap/Resources/com.batterycap.helper.plist"
  fi

  shift || true
  if [[ "$bundle_mode" -eq 0 ]]; then
    while [[ "${1-}" =~ ^-- ]]; do
      case "$1" in
        --install-only)
          install_only=1
          shift
          ;;
        --build-dir)
          build_dir="$2"
          helper_exec="$build_dir/release/BatteryCapHelper"
          shift 2
          ;;
        *)
          fatal "未知 install 参数：$1"
          ;;
      esac
    done
  fi

  if [[ ! -f "$plist_source" ]]; then
    fatal "缺少 helper plist：$plist_source"
  fi
  if ! /usr/bin/plutil -lint "$plist_source" >/dev/null 2>&1; then
    fatal "helper plist 校验失败：$plist_source"
  fi
  if [[ "$bundle_mode" -eq 0 ]] && ! command -v "$SWIFT_TOOL" >/dev/null 2>&1; then
    fatal "未找到 Swift 工具链，请先安装 Xcode 或 Command Line Tools。"
  fi

  if [[ "$(id -u)" -eq 0 && "$bundle_mode" -eq 0 && "$install_only" -ne 1 ]]; then
    fatal "请在非 root 用户下运行脚本，root 仅用于安装阶段。"
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    if [[ "$bundle_mode" -eq 0 ]]; then
      build_dir="$helper_dir/.build-user"
      helper_exec="$build_dir/release/BatteryCapHelper"
      ( cd "$helper_dir" && "$SWIFT_TOOL" build -c release --scratch-path "$build_dir" )
      log "构建完成：$helper_exec"
      exec /usr/bin/sudo "$0" install --install-only --build-dir "$build_dir"
    fi
    exec /usr/bin/sudo "$0" install "$@"
  fi

  if [[ "$bundle_mode" -eq 0 && "$install_only" -ne 1 ]]; then
    ( cd "$helper_dir" && "$SWIFT_TOOL" build -c release --scratch-path "$build_dir" )
    log "构建完成：$helper_exec"
  fi

  if [[ ! -f "$helper_exec" ]]; then
    if [[ "$bundle_mode" -eq 1 ]]; then
      fatal "未找到内置 Helper：$helper_exec"
    fi
    fatal "未找到 Helper 可执行文件：$helper_exec"
  fi

  mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons
  install -m 755 -o root -g wheel "$helper_exec" "$BIN_DEST"
  install -m 644 -o root -g wheel "$plist_source" "$PLIST_DEST"
  clear_quarantine_if_present "$BIN_DEST"
  clear_quarantine_if_present "$PLIST_DEST"
  log "已安装 Helper：$BIN_DEST"
  log "已安装 LaunchDaemon：$PLIST_DEST"

  if [[ -n "${SUDO_USER-}" && "$bundle_mode" -eq 0 ]]; then
    chown -R "$SUDO_USER":staff "$build_dir" 2>/dev/null || true
  fi

  launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
  local bootstrap_output
  if ! bootstrap_output="$(launchctl bootstrap system "$PLIST_DEST" 2>&1)"; then
    if launchctl print system/"$LAUNCH_LABEL" >/dev/null 2>&1; then
      log "bootstrap 返回非零，但服务已加载：$bootstrap_output"
    else
      fatal "bootstrap 失败：$bootstrap_output"
    fi
  fi
  launchctl enable system/"$LAUNCH_LABEL"
  launchctl kickstart -k system/"$LAUNCH_LABEL" || true
  log "Helper installed"
}

main() {
  local command
  command="${1:-help}"
  case "$command" in
    install)
      install_helper "$@"
      ;;
    uninstall)
      ensure_root "$@"
      uninstall_helper_core
      ;;
    purge-config)
      ensure_root "$@"
      purge_user_preferences
      ;;
    full-uninstall)
      ensure_root "$@"
      disable_app_controls_for_uninstall
      uninstall_helper_core
      purge_user_preferences
      remove_app_bundle
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      fatal "未知子命令：$command"
      ;;
  esac
}

main "$@"
