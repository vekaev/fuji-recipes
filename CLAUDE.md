# Fuji Recipes: working rules

Fujifilm custom slots (C1–C7) over USB + a recipe library, for the owner and their agents. Swift package:
`FujiKit` (camera, library, Doctor; shared by everything), `fuji` (CLI + `fuji mcp`), and the Mac app in `App/`
(XcodeGen `project.yml`, target `FujiRecipes`, depends on the local FujiKit package).

- **The library format is shared** with the `/recipe` skill in skills/fuji-recipes: field names and
  value spellings in skills/fuji-recipes/references/schema.md. Change both together.
- **Camera writes are plan → preview → approve → apply**, always with a backup of every slot first and a read-back
  after. Never add a tool that writes to the camera without that.
- **Test without the owner's camera first:** `swift test` and `fuji --simulate …` (a simulated X-E5 that refuses
  what real bodies refuse). Real camera: only read (`fuji status`, `fuji slots`) unless the owner asked to write.
- After changes: `scripts/dev-install.sh` (rebuild, re-sign, re-register the MCP server, link the skill). Claude Desktop also lists
  `fuji` in claude_desktop_config.json.
- Design for the app: Photo Minimalist's Mac style (monochrome, 38 pt top bar with square tabs, sidebar list,
  photo pane with chips and an info card, 280 pt editor with tick dials). Mockup:
  docs/mockup/index.html (sample photos are local only, gitignored).
- Protocol notes and sources: docs/research/notes/opensource-protocol.md; the research brief is docs/research/brief.md.

## Connecting the camera (tell the owner exactly this)

Full guide: docs/CONNECT.md. The camera is reachable only in **USB RAW CONV./BACKUP RESTORE** mode; the factory
default **USB CARD READER** shows the photos, not the settings.

- **Once, on the camera (X-E5 wording):** MENU/OK ▸ network/USB tab ▸ CONNECTION MODE ▸ USB RAW CONV./BACKUP
  RESTORE, and on the same tab USB POWER SUPPLY/COMM SETTING ▸ AUTO (POWER SUPPLY ON/COMM OFF blocks data).
  Older bodies: SET UP ▸ CONNECTION SETTING ▸ PC CONNECTION MODE.
- **Every time:** camera off ▸ USB-C *data* cable straight into the Mac ▸ camera on. The mode is chosen when the
  cable goes in, so after changing it, reconnect with the camera off. The camera's menu is locked while connected;
  unplug to shoot.
- **Check:** `fuji doctor` (MCP: `fuji_doctor`) — five steps USB → camera → session → mode → slots, stops at the
  first failure with its fix. Then `fuji slots`. Preview / Photos offering to import = still a card reader; quit them.
- **The owner's X-E5 (fw 1.12)** needed *both* settings plus camera off → plug → on before step 4 passed
  (2026-11-04). Card reader: 5 properties advertised. RAW CONV.: 61, C1–C7 readable.
- **MCP:** Claude Code (user scope, via the installer or scripts/dev-install.sh) and the Claude desktop app
  (claude_desktop_config.json `mcpServers.fuji`, restart Claude after editing) both run `fuji mcp`. Each app starts
  its own server, so avoid driving the camera from both at once.
- **Using the slots on the camera:** docs/USING-SLOTS.md. The film simulation dial wins: a custom setting's film
  applies only with the dial on C (dial on C ▸ Q ▸ SELECT CUSTOM SETTING ▸ C1–C7).

## Shipping (the `/ship` flow, adapted to a CLI)

- `scripts/install.sh` is the **public one-liner** (`curl -fsSL https://raw.githubusercontent.com/vekaev/fuji-recipes/main/scripts/install.sh | sh`):
  latest release → SHA-256 check → `~/Library/Application Support/FujiRecipes/bin/fuji` + skill → Claude Code and
  Claude desktop MCP registration. It must stay POSIX `sh` and work on a Mac with nothing installed. Test with
  `scripts/release.sh X.Y.Z --local` + `FUJI_BASE_URL` / `FUJI_HOME` / `FUJI_NO_LINKS` / `FUJI_NO_CLAUDE` / `FUJI_DESKTOP_CONFIG`.
- `scripts/release.sh X.Y.Z [notes.md]` publishes (ask the owner first: releases are public). Never replace a
  release asset; a fix is a new patch release. Updates: `fuji update` reruns the installer.
- `scripts/dev-install.sh` builds from the checkout for development.
- When the Mac app exists: DMG + Sparkle per the ship skill (iPhone: n/a, App Store / TestFlight).

## The Mac app

- Build + restart: `scripts/install-mac.sh` (xcodegen → Release build → ~/Applications/Fuji Recipes.app → relaunch).
  Restart it after every change, like Photo Minimalist. `scripts/build-app.sh` makes a DMG (the ship-mac-app
  skill adds the white DMG window, Sparkle and the release flow when it's time to publish the app).
- Views (`App/`): `RootView` (38 pt top bar: camera tab like a memory card, Recipes tab, status, ⋯), `SetupView`
  (no camera: the camera's menu steps + the live Doctor check, polled every 3 s and on plug-in), `SlotsView` (slot
  list, pane with chip + info card, read-only FS1–FS3), `SlotEditor` (280 pt, segments + `FineDial` tick rulers,
  Revert / Write with confirm), `RecipesView` (filters, List | Grid, your sample photos), `Sheets` (C1–C7 help with
  the dial, troubleshooting, backups). State: `AppModel` (@Observable): the only place the app writes to the camera
  is `AppModel.write()` (backup of every slot → writeBank → read-back report).
- The owner may have the app open with the camera connected: look (computer-use screenshot), don't click in it
  without asking, and never write a slot to verify something.
- iPhone / iPad: not yet. ImageCaptureCore works there (needs Control + Contents authorization); add an iOS target
  when the Mac app settles, with a parity table like Photo Minimalist's.
