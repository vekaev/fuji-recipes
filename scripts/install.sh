#!/usr/bin/env bash
# Builds `fuji` (CLI + MCP server), installs it to a stable place, links it into ~/.local/bin, and registers the MCP
# server with Claude Code (user scope). Re-run after changes. Claude Desktop: see README ("Claude Desktop").
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --product fuji 2>&1 | tail -1
DEST="$HOME/Library/Application Support/FujiRecipes/bin"
mkdir -p "$DEST" "$HOME/.local/bin"
rm -f "$DEST/fuji"
cp .build/release/fuji "$DEST/fuji"
"$ROOT/scripts/sign.sh" "$DEST/fuji" com.vekaev.fuji-recipes.cli
ln -sfn "$DEST/fuji" "$HOME/.local/bin/fuji"
echo "Installed $DEST/fuji (and ~/.local/bin/fuji)"
# The /recipe skill (reel → recipe) for Claude Code, Codex and other agents that read ~/.agents/skills.
for dir in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.agents/skills"; do
  [[ -d "$dir" ]] && ln -sfn "$ROOT/skills/fuji-recipes" "$dir/fuji-recipes"
done
echo "Linked the fuji-recipes skill"
if command -v claude >/dev/null; then
  claude mcp remove -s user fuji >/dev/null 2>&1 || true
  claude mcp add -s user fuji -- "$DEST/fuji" mcp
fi
