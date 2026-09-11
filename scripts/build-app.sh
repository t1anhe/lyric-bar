#!/usr/bin/env bash
# Builds the SwiftPM executable and wraps it into build/LyricBar.app.
# No Xcode required: the Command Line Tools are enough.
#
#   scripts/build-app.sh            # release build
#   scripts/build-app.sh debug      # debug build
#
# Set CODESIGN_IDENTITY to a self-signed "Code Signing" certificate name to get a
# stable identity across rebuilds (macOS then remembers the Automation permission).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/LyricBar.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/LyricBar" "$APP/Contents/MacOS/LyricBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign "$IDENTITY" --identifier dev.lyricbar.LyricBar "$APP"
echo "Built $APP (config=$CONFIG, identity=$IDENTITY)"
