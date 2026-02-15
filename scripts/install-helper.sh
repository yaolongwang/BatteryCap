#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCE_SCRIPT="$ROOT_DIR/Sources/BatteryCap/Resources/install-helper.sh"

if [[ ! -f "$RESOURCE_SCRIPT" ]]; then
  echo "[BatteryCap] 错误：未找到安装脚本：$RESOURCE_SCRIPT" >&2
  exit 1
fi

exec /bin/bash "$RESOURCE_SCRIPT" "$@"
