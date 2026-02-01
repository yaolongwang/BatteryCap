#!/usr/bin/env bash
set -euo pipefail

LAUNCH_LABEL="com.batterycap.helper"
PLIST_DEST="/Library/LaunchDaemons/${LAUNCH_LABEL}.plist"
BIN_DEST="/Library/PrivilegedHelperTools/${LAUNCH_LABEL}"
PREFERENCES_DOMAIN="com.batterycap.app"
PURGE_PREFS=0
FULL_UNINSTALL=0

log() {
  echo "[BatteryCap] $*"
}

usage() {
  cat <<'EOF'
用法:
  uninstall-helper.sh [-p] [-x] [-h]

选项:
  -p  清理当前用户配置 (~/Library/Preferences/com.batterycap.app.plist)
  -x  完全卸载（移除 App + 清理用户配置）
  -h  显示帮助

示例:
  scripts/uninstall-helper.sh
  scripts/uninstall-helper.sh -p
  scripts/uninstall-helper.sh -x
EOF
}

while [[ "${1-}" =~ ^- ]]; do
  case "$1" in
    -p)
      PURGE_PREFS=1
      shift
      ;;
    -x)
      FULL_UNINSTALL=1
      PURGE_PREFS=1
      shift
      ;;
    -h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      log "未知参数：$1"
      usage
      exit 2
      ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  exec /usr/bin/sudo "$0" "$@"
fi

if [[ -f "$PLIST_DEST" ]]; then
  launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
else
  launchctl bootout system/"$LAUNCH_LABEL" 2>/dev/null || true
fi

launchctl disable system/"$LAUNCH_LABEL" 2>/dev/null || true

rm -f "$PLIST_DEST" "$BIN_DEST"

log "Helper removed"

if [[ "$PURGE_PREFS" -eq 1 || "$FULL_UNINSTALL" -eq 1 ]]; then
  TARGET_USER="${SUDO_USER:-}"
  if [[ -z "$TARGET_USER" ]]; then
    TARGET_USER="$(stat -f%Su /dev/console 2>/dev/null || true)"
  fi

  if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" || "$TARGET_USER" == "loginwindow" ]]; then
    log "未能确定需要清理的用户，请在普通用户下运行并加 -p 或 -x。"
    exit 0
  fi

  USER_HOME="$(eval echo "~${TARGET_USER}")"
  if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
    log "未能定位用户目录：$TARGET_USER"
    exit 0
  fi

  if [[ "$FULL_UNINSTALL" -eq 1 ]]; then
    /usr/bin/sudo -u "$TARGET_USER" /usr/bin/osascript -e 'tell application "BatteryCap" to quit' 2>/dev/null || true
    APP_PATHS=("/Applications/BatteryCap.app" "${USER_HOME}/Applications/BatteryCap.app")
    for app_path in "${APP_PATHS[@]}"; do
      if [[ -d "$app_path" ]]; then
        rm -rf "$app_path"
        log "已移除应用：$app_path"
      fi
    done
    rm -rf "${USER_HOME}/Library/Application Support/BatteryCap"
    rm -rf "${USER_HOME}/Library/Caches/${PREFERENCES_DOMAIN}"
  fi

  PREF_PLIST="${USER_HOME}/Library/Preferences/${PREFERENCES_DOMAIN}.plist"
  PREF_LOCK="${PREF_PLIST}.lockfile"
  rm -f "$PREF_PLIST" "$PREF_LOCK"
  log "已清理用户配置：${PREFERENCES_DOMAIN} (${TARGET_USER})"
fi
