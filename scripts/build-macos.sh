#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build --configuration release

APP_BUNDLE="$ROOT/dist/LaunchpadApp.app"

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$ROOT/.build/release/LaunchpadApp" "$APP_BUNDLE/Contents/MacOS/LaunchpadApp"
cp "$ROOT/app-resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT/Launchpad.icns" "$APP_BUNDLE/Contents/Resources/Launchpad.icns"
chmod +x "$APP_BUNDLE/Contents/MacOS/LaunchpadApp"

plutil -lint "$APP_BUNDLE/Contents/Info.plist"
touch "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents" "$APP_BUNDLE"

ditto -c -k --sequesterRsrc --keepParent \
    "$APP_BUNDLE" \
    "$ROOT/dist/LaunchpadApp-mac-x64.zip"

printf 'Built %s\n' "$APP_BUNDLE"
printf 'Archived %s\n' "$ROOT/dist/LaunchpadApp-mac-x64.zip"
