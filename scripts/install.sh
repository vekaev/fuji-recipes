#!/bin/sh
# Installs (or updates) Fuji Recipes — the `fuji` CLI + MCP server and the /recipe skill — from the latest release:
#
#   curl -fsSL https://raw.githubusercontent.com/vekaev/fuji-recipes/main/scripts/install.sh | sh
#
# What it does:
#   • ~/Library/Application Support/FujiRecipes/bin/fuji (+ a link in ~/.local/bin), checked against the release's SHA-256
#   • the /recipe skill into ~/.claude/skills, ~/.codex/skills, ~/.agents/skills (where those folders exist)
#   • registers the MCP server with Claude Code (`claude mcp add`) and the Claude desktop app (its config file,
#     backed up first; quit and reopen Claude afterwards)
# A download by curl carries no "downloaded from the internet" mark, so macOS runs it without an Open Anyway step.
# Testing: FUJI_BASE_URL=<folder URL with the tarball>, FUJI_HOME=<folder>, FUJI_NO_LINKS=1, FUJI_NO_CLAUDE=1,
# FUJI_DESKTOP_CONFIG=<a copy of claude_desktop_config.json>.
set -eu

REPO="vekaev/fuji-recipes"
BASE="${FUJI_BASE_URL:-https://github.com/$REPO/releases/latest/download}"
HOME_DIR="${FUJI_HOME:-$HOME/Library/Application Support/FujiRecipes}"
TAR="fuji-macos.tar.gz"

[ "$(uname -s)" = "Darwin" ] || { echo "Fuji Recipes runs on macOS."; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Fuji Recipes…"
curl -fL --progress-bar "$BASE/$TAR" -o "$TMP/$TAR"
curl -fsSL "$BASE/$TAR.sha256" -o "$TMP/sum"
expected=$(cut -d' ' -f1 "$TMP/sum")
actual=$(shasum -a 256 "$TMP/$TAR" | cut -d' ' -f1)
[ "$expected" = "$actual" ] || { echo "The download doesn't match its checksum; nothing was installed. Try again."; exit 1; }
mkdir -p "$TMP/x" && tar -xzf "$TMP/$TAR" -C "$TMP/x"

mkdir -p "$HOME_DIR/bin" "$HOME_DIR/skills"
rm -f "$HOME_DIR/bin/fuji"
cp "$TMP/x/bin/fuji" "$HOME_DIR/bin/fuji"
chmod +x "$HOME_DIR/bin/fuji"
rm -rf "$HOME_DIR/skills/fuji-recipes"
cp -R "$TMP/x/skills/fuji-recipes" "$HOME_DIR/skills/fuji-recipes"
FUJI="$HOME_DIR/bin/fuji"
VERSION=$("$FUJI" --version 2>/dev/null || cat "$TMP/x/VERSION")

if [ -z "${FUJI_NO_LINKS:-}" ]; then
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$FUJI" "$HOME/.local/bin/fuji"
  [ -d "$HOME/.claude" ] && mkdir -p "$HOME/.claude/skills"
  for dir in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills"; do
    [ -d "$dir" ] || continue
    link="$dir/fuji-recipes"
    # A developer's link into a checkout of the repo stays.
    if [ -L "$link" ] && [ -f "$(readlink "$link")/../../Package.swift" ]; then continue; fi
    rm -rf "$link"
    ln -s "$HOME_DIR/skills/fuji-recipes" "$link"
  done
fi

if [ -z "${FUJI_NO_CLAUDE:-}" ]; then
  if command -v claude >/dev/null 2>&1; then
    claude mcp remove -s user fuji >/dev/null 2>&1 || true
    claude mcp add -s user fuji -- "$FUJI" mcp >/dev/null && echo "Added the fuji MCP server to Claude Code."
  fi
  CFG="${FUJI_DESKTOP_CONFIG:-$HOME/Library/Application Support/Claude/claude_desktop_config.json}"
  if [ -d "$(dirname "$CFG")" ]; then
    [ -f "$CFG" ] && cp "$CFG" "$CFG.bak-fuji"
    # JavaScript for Automation ships with macOS: merge {mcpServers: {fuji: …}} without touching the rest.
    FUJI_CFG="$CFG" FUJI_BIN="$FUJI" osascript -l JavaScript >/dev/null <<'JS'
ObjC.import('Foundation')
const env = $.NSProcessInfo.processInfo.environment
const path = ObjC.unwrap(env.objectForKey('FUJI_CFG')), bin = ObjC.unwrap(env.objectForKey('FUJI_BIN'))
const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null)
let cfg = {}
try { cfg = text.isNil() ? {} : JSON.parse(ObjC.unwrap(text)) } catch (e) { cfg = {} }
cfg.mcpServers = cfg.mcpServers || {}
cfg.mcpServers.fuji = { command: bin, args: ['mcp'] }
$(JSON.stringify(cfg, null, 2)).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)
JS
    echo "Added the fuji MCP server to the Claude desktop app (quit and reopen Claude)."
  fi
fi

echo "Installed Fuji Recipes $VERSION: $FUJI"
echo "Next: plug in your camera (https://github.com/$REPO/blob/main/docs/CONNECT.md), then run: fuji doctor"
command -v exiftool >/dev/null 2>&1 || echo "Optional, for recipes from your photos: brew install exiftool"
