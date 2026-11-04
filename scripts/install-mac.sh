#!/usr/bin/env bash
# Builds the Mac app, installs it to ~/Applications and restarts it so the newest version is always running.
# The running copy is asked to quit normally first, so its state is saved.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project FujiRecipes.xcodeproj -scheme FujiRecipes -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath build -quiet build

APP="$HOME/Applications/Fuji Recipes.app"
RUNNING='Fuji Recipes\.app/Contents/MacOS/'
if pgrep -f "$RUNNING" >/dev/null; then
  osascript -e 'tell application id "app.fujirecipes.mac" to quit' || true
  # Saving can take a while; wait until it has really exited (up to 2 minutes).
  for _ in $(seq 1 480); do pgrep -f "$RUNNING" >/dev/null || break; sleep 0.25; done
  if pgrep -f "$RUNNING" >/dev/null; then echo "The running copy didn't quit; not replacing it."; exit 1; fi
fi

mkdir -p "$HOME/Applications"
rm -rf "$APP"
cp -R "build/Build/Products/Release/Fuji Recipes.app" "$APP"
# Builds are ad-hoc signed, and macOS ties a permission (folders, camera) to an ad-hoc app's exact hash, so every
# reinstall asked again. Signed with a certificate, the permission belongs to the bundle ID + certificate and stays.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -Eo '"(Developer ID Application|Apple Development): [^"]+"' | head -1 | tr -d '"' || true)}"
if [[ -n "$IDENTITY" ]] && codesign --force --deep -s "$IDENTITY" "$APP" 2>/dev/null; then
  echo "Signed with $IDENTITY: macOS keeps its permissions across rebuilds"
else
  echo "No signing certificate: macOS may ask for permissions again after this install" >&2
fi
open "$APP"
for _ in $(seq 1 40); do pgrep -f "$RUNNING" >/dev/null && break; sleep 0.25; done
pgrep -f "$RUNNING" >/dev/null || { echo "Failed to start"; exit 1; }
echo "Fuji Recipes restarted with the new build"
