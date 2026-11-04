# Fuji Recipes: working rules

Fujifilm custom slots (C1–C7) over USB + a recipe library, for the owner and their agents. Swift package:
`FujiKit` (shared with the future Mac / iPhone app), `fuji` (CLI + `fuji mcp`).

- **The library format is shared** with the `/recipe` skill in skills/fuji-recipes: field names and
  value spellings in skills/fuji-recipes/references/schema.md. Change both together.
- **Camera writes are plan → preview → approve → apply**, always with a backup of every slot first and a read-back
  after. Never add a tool that writes to the camera without that.
- **Test without the owner's camera first:** `swift test` and `fuji --simulate …` (a simulated X-E5 that refuses
  what real bodies refuse). Real camera: only read (`fuji status`, `fuji slots`) unless the owner asked to write.
- After changes: `scripts/install.sh` (rebuild, re-sign, re-register the MCP server, link the skill). Claude Desktop also lists
  `fuji` in claude_desktop_config.json.
- Design for the app: Photo Minimalist's Mac style (monochrome, 38 pt top bar with square tabs, sidebar list,
  photo pane with chips and an info card, 280 pt editor with tick dials). Mockup:
  docs/mockup/index.html (sample photos are local only, gitignored).
- Protocol notes and sources: docs/research/notes/opensource-protocol.md; the research brief is docs/research/brief.md.
