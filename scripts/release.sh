#!/usr/bin/env bash
# Publishes a release of Fuji Recipes: the Mac app (DMG + Sparkle appcast, so installed copies update through
# "Check for Updates…") and the `fuji` CLI + MCP server (fuji-macos.tar.gz + SHA-256, for scripts/install.sh and
# `fuji update`). One version for both.
#
#   scripts/release.sh 0.3.0                 bump the version, build the DMG, sign it, write appcast.xml,
#                                            commit + tag v0.3.0, push, and create the GitHub release
#   scripts/release.sh 0.3.0 notes.md        the same with your own release notes (Markdown-ish text);
#                                            default: the commit subjects since the last tag
#   scripts/release.sh 0.3.0 --local URL     test only: build + sign into dist/ with the feed and download at
#                                            URL (e.g. http://127.0.0.1:8765); no project.yml change, no git, no GitHub
#
# The update signature uses the EdDSA key in your login keychain (account "fuji-recipes", made once with
# build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account fuji-recipes). Its public half is
# SUPublicEDKey in project.yml. Lose the private key and installed copies can't update any more: back it up with
#   generate_keys --account fuji-recipes -x ~/somewhere-safe/fuji-recipes-sparkle.key
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: scripts/release.sh 0.3.0 [notes.md | --local URL]"; exit 1; }
LOCAL=""; NOTES_FILE=""
if [[ "${2:-}" == "--local" ]]; then LOCAL="${3:?--local needs a base URL, e.g. http://127.0.0.1:8765}"; else NOTES_FILE="${2:-}"; fi

REPO="vekaev/fuji-recipes"
NAME="Fuji Recipes"
DMG_NAME="FujiRecipes-mac.dmg"
KEY="fuji-recipes"
MIN_OS="14.0"
TAG="v$VERSION"
BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION:' project.yml | grep -o '[0-9]\+')
BUILD=$((CURRENT_BUILD + 1))

if [[ -z "$LOCAL" ]]; then
  [[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first."; exit 1; }
  [[ "$(git branch --show-current)" == "main" ]] || { echo "Release from main."; exit 1; }
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists."; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "Sign in to GitHub first: gh auth login"; exit 1; }
  # Both apps share the version (the iPhone app just keeps in step).
  sed -i '' -E "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/; s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
  sed -i '' -E "s/^let version = \"[^\"]*\"/let version = \"$VERSION\"/" Sources/fuji/main.swift
  grep -q "^let version = \"$VERSION\"" Sources/fuji/main.swift || { echo "Couldn't set the CLI version."; exit 1; }
  BASE="https://github.com/$REPO/releases/download/$TAG"
  export BUILD_SETTINGS=""
else
  BASE="$LOCAL"
  export BUILD_SETTINGS="MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD SPARKLE_FEED_URL=$LOCAL/appcast.xml ${EXTRA_SETTINGS:-}"
fi

scripts/build-app.sh
DMG="dist/$DMG_NAME"

# The CLI + MCP server: a universal binary, signed, packed with the /recipe skill (scripts/install.sh installs it).
TAR="fuji-macos.tar.gz"
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
swift build -c release --arch arm64 --arch x86_64 --product fuji 2>&1 | tail -1
CLI="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/fuji"
ARCHS=$(lipo -archs "$CLI"); [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo "Not a universal binary ($ARCHS)."; exit 1; }
mkdir -p dist/stage/bin dist/stage/skills
cp "$CLI" dist/stage/bin/fuji
scripts/sign.sh dist/stage/bin/fuji com.vekaev.fuji-recipes.cli
cp -R skills/fuji-recipes dist/stage/skills/
cp LICENSE dist/stage/
echo "$VERSION" > dist/stage/VERSION
tar -czf "dist/$TAR" -C dist/stage .
(cd dist && shasum -a 256 "$TAR" > "$TAR.sha256")
rm -rf dist/stage
[[ -x "$BIN/sign_update" ]] || { echo "Sparkle tools missing in $BIN (build once with Xcode first)."; exit 1; }
SIGNATURE=$("$BIN/sign_update" --account "$KEY" "$DMG")   # sparkle:edSignature="…" length="…"

# Release notes: the given file, else the commit subjects since the last tag.
NOTES="dist/notes.md"
if [[ -n "$NOTES_FILE" ]]; then cp "$NOTES_FILE" "$NOTES"
else
  LAST=$(git describe --tags --abbrev=0 2>/dev/null || true)
  git log --no-merges --format='- %s' ${LAST:+$LAST..HEAD} | grep -v '^- Release ' > "$NOTES" || true
fi
HTML_NOTES="$(cat "$NOTES")"
cat >> "$NOTES" <<NOTES

**Install or update**

- The Mac app, no security prompt: \`curl -fsSL https://raw.githubusercontent.com/$REPO/main/scripts/install-app.sh | sh\`
  (or download $DMG_NAME below; it updates itself afterwards)
- The CLI + MCP server for Claude: \`curl -fsSL https://raw.githubusercontent.com/$REPO/main/scripts/install.sh | sh\`, then \`fuji update\`

Then plug in your camera: [docs/CONNECT.md](https://github.com/$REPO/blob/main/docs/CONNECT.md).
NOTES
HTML=$(printf '%s\n' "$HTML_NOTES" | sed -E 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/^- (.*)$/<li>\1<\/li>/')

cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$NAME</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>
$HTML
</ul>]]></description>
      <enclosure url="$BASE/$DMG_NAME" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML

if [[ -n "$LOCAL" ]]; then
  echo "Built $DMG and dist/appcast.xml for $VERSION ($BUILD), served from $LOCAL"
  exit 0
fi

git add project.yml Sources/fuji/main.swift
git commit -q -m "Release $VERSION"
git tag "$TAG"
git push -q origin main "$TAG"
# Every file build-app.sh put in dist/ (the DMG, any CLI), plus the appcast; never the notes.
ASSETS=$(find dist -maxdepth 1 -type f ! -name notes.md)
# shellcheck disable=SC2086
gh release create "$TAG" $ASSETS --repo "$REPO" --latest --title "$NAME $VERSION" --notes-file "$NOTES"
echo "Released $VERSION ($BUILD). Installed apps offer it within a day (or Check for Updates…); the CLI: fuji update"
