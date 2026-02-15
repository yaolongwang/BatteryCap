#!/usr/bin/env bash
# 功能：编译应用图标资源，并在存在 dist app 时写入其 Resources。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_SOURCE="$ROOT_DIR/Sources/BatteryCap/Resources/BatteryCap.icon"
ICON_BUILD_DIR="$ROOT_DIR/.build/icon-assets"
PARTIAL_INFO_PLIST="$ICON_BUILD_DIR/partial-info.plist"
DIST_RESOURCES_DIR="$ROOT_DIR/dist/BatteryCap.app/Contents/Resources"
DIST_INFO_PLIST="$ROOT_DIR/dist/BatteryCap.app/Contents/Info.plist"

if [[ ! -d "$ICON_SOURCE" ]]; then
    echo "error: missing icon source: $ICON_SOURCE" >&2
    exit 1
fi

mkdir -p "$ICON_BUILD_DIR"

xcrun actool \
    --compile "$ICON_BUILD_DIR" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --target-device mac \
    --app-icon BatteryCap \
    --output-partial-info-plist "$PARTIAL_INFO_PLIST" \
    "$ICON_SOURCE"

echo "compiled icon assets: $ICON_BUILD_DIR/Assets.car"
echo "generated fallback icon: $ICON_BUILD_DIR/BatteryCap.icns"

if [[ -d "$DIST_RESOURCES_DIR" ]]; then
    cp "$ICON_BUILD_DIR/Assets.car" "$DIST_RESOURCES_DIR/Assets.car"
    cp "$ICON_BUILD_DIR/BatteryCap.icns" "$DIST_RESOURCES_DIR/BatteryCap.icns"
    if [[ -f "$DIST_INFO_PLIST" ]]; then
        if /usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$DIST_INFO_PLIST" >/dev/null 2>&1; then
            /usr/libexec/PlistBuddy -c "Set :CFBundleIconName BatteryCap" "$DIST_INFO_PLIST"
        else
            /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string BatteryCap" "$DIST_INFO_PLIST"
        fi
    fi
    echo "updated dist resources: $DIST_RESOURCES_DIR"
else
    echo "note: dist app not found, skipped copy to dist"
fi
