#!/usr/bin/env bash
# 功能：开发态服务入口，支持 install/uninstall/purge-config/full-uninstall 子命令。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 实际执行脚本：Sources/BatteryCap/Resources/batterycap-service.sh
RESOURCE_SCRIPT="$ROOT_DIR/Sources/BatteryCap/Resources/batterycap-service.sh"

if [[ ! -f "$RESOURCE_SCRIPT" ]]; then
  echo "[BatteryCap] 错误：未找到脚本：$RESOURCE_SCRIPT" >&2
  exit 1
fi

exec /bin/bash "$RESOURCE_SCRIPT" "$@"
