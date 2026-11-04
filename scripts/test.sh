#!/usr/bin/env bash
# Every test, end to end, without touching the owner's library or camera:
#   1. FujiKit (codec, settings file, studio, FS writes, DR gate, inbox, history) against the simulated X-E5
#   2. FujiCLITests: the real `fuji mcp` binary driven over JSON-RPC like Claude, simulated camera, throwaway library
#   3. FujiRecipesUITests: the iPhone app in the simulator (-uiTesting: throwaway library, simulated X-E5)
#   4. the Mac app builds
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${SIMULATOR_ID:-$(xcrun simctl list devices available | grep -F "    iPhone 17 Pro (" | grep -Eo '[0-9A-F-]{36}' | head -1)}"
echo "== FujiKit + CLI/MCP"; swift test 2>&1 | grep -E "error:|Test Suite .*\.xctest. (passed|failed)|Executed [0-9]+ tests" | grep -E "xctest|error" 
xcodegen generate --quiet
echo "== iPhone app (UI tests)"
xcodebuild -project FujiRecipes.xcodeproj -scheme FujiRecipes-iOS -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath build test 2>&1 \
  | grep -E "error:|Test Case.*(passed|failed)|TEST (SUCCEEDED|FAILED)"
echo "== Mac app builds"
xcodebuild -project FujiRecipes.xcodeproj -scheme FujiRecipes -configuration Debug -derivedDataPath build -quiet build && echo "Mac build OK"
