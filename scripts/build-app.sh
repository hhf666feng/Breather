#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_ROOT:?}"
ICON_PATH="${PROJECT_ROOT:?}/Resources/Brand/Mujian.icns"
if [[ ! -f "$ICON_PATH" ]]; then
    printf 'Missing brand icon: %s\nSee docs/BRAND.md for icon generation.\n' "$ICON_PATH" >&2
    exit 1
fi
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"
APP_PATH="${PROJECT_ROOT:?}/dist/Breather.app"
mkdir -p "${APP_PATH:?}/Contents/MacOS" "${APP_PATH:?}/Contents/Resources"
cp "${BIN_PATH:?}/EyeWatch" "${APP_PATH:?}/Contents/MacOS/EyeWatch"
cp Resources/Info.plist "${APP_PATH:?}/Contents/Info.plist"
cp "$ICON_PATH" "${APP_PATH:?}/Contents/Resources/Mujian.icns"
codesign --force --sign - "${APP_PATH:?}"
codesign --verify --deep --strict "${APP_PATH:?}"
printf 'Built %s\n' "$APP_PATH"
