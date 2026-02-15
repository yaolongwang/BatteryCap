#!/usr/bin/env bash
# 功能：统一管理安装/卸载 Helper 与卸载清理流程的服务脚本。
set -euo pipefail

LAUNCH_LABEL="com.batterycap.helper"
PLIST_DEST="/Library/LaunchDaemons/${LAUNCH_LABEL}.plist"
BIN_DEST="/Library/PrivilegedHelperTools/${LAUNCH_LABEL}"
PREFERENCES_DOMAIN="com.batterycap.app"
SWIFT_TOOL="swift"
SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
INSTALL_BUNDLE_MODE=0
INSTALL_ONLY=0
INSTALL_HELPER_DIR=""
INSTALL_BUILD_DIR=""
INSTALL_HELPER_EXEC=""
INSTALL_PLIST_SOURCE=""

log() {
  echo "[BatteryCap] $*"
}

fatal() {
  echo "[BatteryCap] 错误：$*" >&2
  exit 1
}

warn() {
  echo "[BatteryCap] 警告：$*" >&2
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
    exec /usr/bin/sudo "$SELF_PATH" "$@"
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

is_safe_user_home_path() {
  local user_home="$1"
  [[ -n "$user_home" ]] || return 1
  case "$user_home" in
    "/"|"/Users"|"/var"|"/private"|"/private/var")
      return 1
      ;;
  esac
  return 0
}

resolve_user_home() {
  local target_user="$1"
  local user_home=""

  if [[ -n "${SUDO_HOME-}" && "${SUDO_USER-}" == "$target_user" ]]; then
    user_home="$SUDO_HOME"
  fi

  if [[ -z "$user_home" ]]; then
    user_home="$(
      dscl . -read "/Users/$target_user" NFSHomeDirectory 2>/dev/null \
        | awk 'NR == 1 { print $2 }'
    )"
  fi

  if [[ -z "$user_home" ]]; then
    warn "未能定位用户目录：$target_user"
    return 1
  fi

  if [[ ! -d "$user_home" ]]; then
    warn "用户目录不存在：$user_home"
    return 1
  fi

  if ! is_safe_user_home_path "$user_home"; then
    warn "用户目录路径不安全，跳过：$user_home"
    return 1
  fi

  echo "$user_home"
}

purge_user_preferences() {
  local target_user user_home pref_plist pref_lock
  target_user="$(resolve_target_user)" || return 0
  user_home="$(resolve_user_home "$target_user")" || return 0
  pref_plist="${user_home}/Library/Preferences/${PREFERENCES_DOMAIN}.plist"
  pref_lock="${pref_plist}.lockfile"
  rm -f "$pref_plist" "$pref_lock"
  log "已清理用户配置：${PREFERENCES_DOMAIN} (${target_user})"
}

remove_app_bundle() {
  local target_user user_home app_path
  target_user="$(resolve_target_user)" || return 0
  user_home="$(resolve_user_home "$target_user")" || return 0
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
  user_home="$(resolve_user_home "$target_user")" || return 0

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

install_helper_resolve_context() {
  local script_dir="$1"
  INSTALL_BUNDLE_MODE=0
  INSTALL_ONLY=0
  INSTALL_HELPER_DIR=""
  INSTALL_BUILD_DIR=""
  INSTALL_HELPER_EXEC=""
  INSTALL_PLIST_SOURCE=""

  if [[ "$script_dir" == *".app/Contents/Resources"* ]]; then
    INSTALL_BUNDLE_MODE=1
  fi

  if [[ "$INSTALL_BUNDLE_MODE" -eq 1 ]]; then
    INSTALL_HELPER_EXEC="${script_dir}/BatteryCapHelper"
    if [[ ! -f "$INSTALL_HELPER_EXEC" && -f "${script_dir}/../MacOS/BatteryCapHelper" ]]; then
      INSTALL_HELPER_EXEC="${script_dir}/../MacOS/BatteryCapHelper"
    fi
    INSTALL_PLIST_SOURCE="${script_dir}/com.batterycap.helper.plist"
    return
  fi

  local root_dir
  root_dir="$(cd "${script_dir}/../../.." && pwd)"
  INSTALL_HELPER_DIR="${root_dir}/Subpackages/BatteryCapHelper"
  INSTALL_BUILD_DIR="${INSTALL_HELPER_DIR}/.build"
  INSTALL_HELPER_EXEC="${INSTALL_BUILD_DIR}/release/BatteryCapHelper"
  INSTALL_PLIST_SOURCE="${root_dir}/Sources/BatteryCap/Resources/com.batterycap.helper.plist"
}

install_helper_parse_arguments() {
  if [[ "$INSTALL_BUNDLE_MODE" -eq 1 ]]; then
    return
  fi

  while [[ "${1-}" =~ ^-- ]]; do
    case "$1" in
      --install-only)
        INSTALL_ONLY=1
        shift
        ;;
      --build-dir)
        if [[ -z "${2-}" ]]; then
          fatal "参数 --build-dir 缺少目录值"
        fi
        INSTALL_BUILD_DIR="$2"
        INSTALL_HELPER_EXEC="$INSTALL_BUILD_DIR/release/BatteryCapHelper"
        shift 2
        ;;
      *)
        fatal "未知 install 参数：$1"
        ;;
    esac
  done

  if [[ "$#" -gt 0 ]]; then
    fatal "install 不支持位置参数：$*"
  fi
}

install_helper_validate_context() {
  if [[ "$INSTALL_BUNDLE_MODE" -ne 0 && "$INSTALL_BUNDLE_MODE" -ne 1 ]]; then
    fatal "安装上下文无效：bundle_mode=$INSTALL_BUNDLE_MODE"
  fi
  if [[ -z "$INSTALL_HELPER_EXEC" || -z "$INSTALL_PLIST_SOURCE" ]]; then
    fatal "安装上下文不完整：缺少 helper 可执行文件或 plist 路径"
  fi
  if [[ "$INSTALL_BUNDLE_MODE" -eq 0 && ( -z "$INSTALL_HELPER_DIR" || -z "$INSTALL_BUILD_DIR" ) ]]; then
    fatal "安装上下文不完整：缺少 Helper 构建目录"
  fi
}

install_helper_validate_inputs() {
  if [[ ! -f "$INSTALL_PLIST_SOURCE" ]]; then
    fatal "缺少 helper plist：$INSTALL_PLIST_SOURCE"
  fi
  if ! /usr/bin/plutil -lint "$INSTALL_PLIST_SOURCE" >/dev/null 2>&1; then
    fatal "helper plist 校验失败：$INSTALL_PLIST_SOURCE"
  fi
  if [[ "$INSTALL_BUNDLE_MODE" -eq 0 ]] && ! command -v "$SWIFT_TOOL" >/dev/null 2>&1; then
    fatal "未找到 Swift 工具链，请先安装 Xcode 或 Command Line Tools。"
  fi
}

install_helper_validate_invocation() {
  if [[ "$(id -u)" -eq 0 && "$INSTALL_BUNDLE_MODE" -eq 0 && "$INSTALL_ONLY" -ne 1 ]]; then
    fatal "请在非 root 用户下运行脚本，root 仅用于安装阶段。"
  fi
}

install_helper_prepare_non_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return
  fi

  if [[ "$INSTALL_BUNDLE_MODE" -eq 0 ]]; then
    INSTALL_BUILD_DIR="$INSTALL_HELPER_DIR/.build-user"
    INSTALL_HELPER_EXEC="$INSTALL_BUILD_DIR/release/BatteryCapHelper"
    ( cd "$INSTALL_HELPER_DIR" && "$SWIFT_TOOL" build -c release --scratch-path "$INSTALL_BUILD_DIR" )
    log "构建完成：$INSTALL_HELPER_EXEC"
    exec /usr/bin/sudo "$SELF_PATH" install --install-only --build-dir "$INSTALL_BUILD_DIR"
  fi

  exec /usr/bin/sudo "$SELF_PATH" install "$@"
}

install_helper_build_if_needed() {
  if [[ "$INSTALL_BUNDLE_MODE" -eq 0 && "$INSTALL_ONLY" -ne 1 ]]; then
    ( cd "$INSTALL_HELPER_DIR" && "$SWIFT_TOOL" build -c release --scratch-path "$INSTALL_BUILD_DIR" )
    log "构建完成：$INSTALL_HELPER_EXEC"
  fi
}

install_helper_validate_binary() {
  if [[ -f "$INSTALL_HELPER_EXEC" ]]; then
    return
  fi
  if [[ "$INSTALL_BUNDLE_MODE" -eq 1 ]]; then
    fatal "未找到内置 Helper：$INSTALL_HELPER_EXEC"
  fi
  fatal "未找到 Helper 可执行文件：$INSTALL_HELPER_EXEC"
}

install_helper_install_files() {
  mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons
  install -m 755 -o root -g wheel "$INSTALL_HELPER_EXEC" "$BIN_DEST"
  install -m 644 -o root -g wheel "$INSTALL_PLIST_SOURCE" "$PLIST_DEST"
  clear_quarantine_if_present "$BIN_DEST"
  clear_quarantine_if_present "$PLIST_DEST"
  log "已安装 Helper：$BIN_DEST"
  log "已安装 LaunchDaemon：$PLIST_DEST"
}

install_helper_restore_build_owner() {
  if [[ -n "${SUDO_USER-}" && "$INSTALL_BUNDLE_MODE" -eq 0 ]]; then
    chown -R "$SUDO_USER":staff "$INSTALL_BUILD_DIR" 2>/dev/null || true
  fi
}

install_helper_bootstrap_service() {
  launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
  local bootstrap_output
  if ! bootstrap_output="$(launchctl bootstrap system "$PLIST_DEST" 2>&1)"; then
    if launchctl print system/"$LAUNCH_LABEL" >/dev/null 2>&1; then
      log "bootstrap 返回非零，但服务已加载：$bootstrap_output"
    else
      fatal "bootstrap 失败：$bootstrap_output"
    fi
  fi
  if ! launchctl enable system/"$LAUNCH_LABEL"; then
    warn "enable 服务失败：system/$LAUNCH_LABEL"
  fi
  if ! launchctl kickstart -k system/"$LAUNCH_LABEL"; then
    warn "kickstart 服务失败：system/$LAUNCH_LABEL"
  fi
}

install_helper() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  install_helper_resolve_context "$script_dir"

  shift || true
  install_helper_parse_arguments "$@"
  install_helper_validate_context
  install_helper_validate_inputs
  install_helper_validate_invocation
  install_helper_prepare_non_root "$@"
  install_helper_build_if_needed
  install_helper_validate_binary
  install_helper_install_files
  install_helper_restore_build_owner
  install_helper_bootstrap_service
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
