#!/usr/bin/env bash
# Builds the iPhone app and (re)launches it in the "iPhone 17 Pro" simulator (or $SIMULATOR), booting it if needed.
#   scripts/run-ios-sim.sh [launch arguments…]
set -euo pipefail
cd "$(dirname "$0")/.."

# Always the same simulator (other projects may have their own booted ones).
NAME="${SIMULATOR:-iPhone 17 Pro}"
# Prefer one that's already running; several simulators can share a name.
DEVICE=$(xcrun simctl list devices booted | grep -F "    $NAME (" | grep -Eo '[0-9A-F-]{36}' | head -1 || true)
[[ -n "$DEVICE" ]] || DEVICE=$(xcrun simctl list devices available | grep -F "    $NAME (" | grep -Eo '[0-9A-F-]{36}' | head -1)
[[ -n "$DEVICE" ]] || { echo "No simulator named $NAME"; exit 1; }
xcrun simctl list devices booted | grep -q "$DEVICE" || xcrun simctl boot "$DEVICE"

xcodegen generate --quiet
xcodebuild -project FujiRecipes.xcodeproj -scheme FujiRecipes-iOS -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath build -quiet build

xcrun simctl install "$DEVICE" "build/Build/Products/Debug-iphonesimulator/Fuji Recipes.app"
xcrun simctl terminate "$DEVICE" app.fujirecipes.ios 2>/dev/null || true
xcrun simctl launch "$DEVICE" app.fujirecipes.ios "$@" >/dev/null
echo "Fuji Recipes relaunched in the simulator ($DEVICE)"
