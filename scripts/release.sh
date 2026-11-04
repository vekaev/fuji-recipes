#!/usr/bin/env bash
# Publishes a release of the `fuji` CLI + MCP server (and the /recipe skill) that scripts/install.sh installs
# and `fuji update` updates to.
#
#   scripts/release.sh 0.2.0              bump the version, build a universal binary (Apple Silicon + Intel), sign it,
#                                         pack fuji-macos.tar.gz + its SHA-256, commit + tag v0.2.0, push, GitHub release
#   scripts/release.sh 0.2.0 notes.md     the same with your own notes; default: the commit subjects since the last tag
#   scripts/release.sh 0.2.0 --local      test only: build + pack into dist/; no version change, no git, no GitHub
#
# Rule: never replace an asset of an existing release (installers check its SHA-256); a fix is a new patch release.
# The Mac app (when it exists) adds a DMG + Sparkle appcast here, like Photo Minimalist.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: scripts/release.sh 0.2.0 [notes.md | --local]"; exit 1; }
LOCAL=""; NOTES_FILE=""
if [[ "${2:-}" == "--local" ]]; then LOCAL=1; else NOTES_FILE="${2:-}"; fi

REPO="vekaev/fuji-recipes"
TAG="v$VERSION"
TAR="fuji-macos.tar.gz"

if [[ -z "$LOCAL" ]]; then
  [[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first."; exit 1; }
  [[ "$(git branch --show-current)" == "main" ]] || { echo "Release from main."; exit 1; }
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists."; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "Sign in to GitHub first: gh auth login"; exit 1; }
  sed -i '' -E "s/^let version = \"[^\"]*\"/let version = \"$VERSION\"/" Sources/fuji/main.swift
fi
grep -q "^let version = \"$VERSION\"" Sources/fuji/main.swift || [[ -n "$LOCAL" ]] || { echo "Couldn't set the version."; exit 1; }

swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
swift build -c release --arch arm64 --arch x86_64 --product fuji 2>&1 | tail -1
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/fuji"
ARCHS=$(lipo -archs "$BIN"); [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo "Not a universal binary ($ARCHS)."; exit 1; }

rm -rf dist && mkdir -p dist/stage/bin dist/stage/skills
cp "$BIN" dist/stage/bin/fuji
scripts/sign.sh dist/stage/bin/fuji com.vekaev.fuji-recipes.cli
cp -R skills/fuji-recipes dist/stage/skills/
cp LICENSE dist/stage/
echo "$VERSION" > dist/stage/VERSION
tar -czf "dist/$TAR" -C dist/stage .
(cd dist && shasum -a 256 "$TAR" > "$TAR.sha256")
rm -rf dist/stage

NOTES="dist/notes.md"
if [[ -n "$NOTES_FILE" ]]; then cp "$NOTES_FILE" "$NOTES"
else
  LAST=$(git describe --tags --abbrev=0 2>/dev/null || true)
  git log --no-merges --format='- %s' ${LAST:+$LAST..HEAD} | grep -v '^- Release ' > "$NOTES" || true
fi
cat >> "$NOTES" <<EOF

**Install or update** (Terminal, no security prompt):

    curl -fsSL https://raw.githubusercontent.com/$REPO/main/scripts/install.sh | sh

Then plug in your camera: [docs/CONNECT.md](https://github.com/$REPO/blob/main/docs/CONNECT.md).
EOF

if [[ -n "$LOCAL" ]]; then
  echo "Built dist/$TAR ($(du -h "dist/$TAR" | cut -f1)) and its SHA-256. Test: FUJI_BASE_URL=<server serving dist/> sh scripts/install.sh"
  exit 0
fi

git add Sources/fuji/main.swift
git diff --cached --quiet || git commit -q -m "Release $VERSION"   # already at this version: just tag
git tag "$TAG"
git push -q origin main "$TAG"
gh release create "$TAG" "dist/$TAR" "dist/$TAR.sha256" --repo "$REPO" --latest --title "Fuji Recipes $VERSION" --notes-file "$NOTES"
echo "Released $VERSION. Installed copies get it with: fuji update"
