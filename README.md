<div align="center">

# Fuji Recipes

**Your Fujifilm's custom slots and your recipes. For you and your agents.**

Plug a Fujifilm X camera into the Mac, see what's in C1–C7, and write film-simulation recipes into the slots,
with a backup first and a read-back after. Keep a recipe library of your own recipes (found in your photos'
EXIF), recipes from reels and websites, and kits of seven for a trip. Ask Claude to do any of it through MCP.
Native Swift, on-device, nothing uploaded.

[![Swift](https://img.shields.io/badge/Swift-native-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS%2014%2B-native-000000?style=flat-square&logo=apple&logoColor=white)](#get-started)
[![MCP](https://img.shields.io/badge/MCP-for%20agents-3a3a3a?style=flat-square)](#for-agents-mcp)
[![License: MIT](https://img.shields.io/badge/license-MIT-3a3a3a?style=flat-square)](LICENSE)
[![Status: early](https://img.shields.io/badge/status-early-d69e2e?style=flat-square)](#status)

</div>

## Status

Early. The `fuji` CLI and MCP server work end to end against a simulated X-E5, which refuses what real bodies
refuse; real-camera testing is next. The Mac app comes after, in [Photo Minimalist](https://github.com/vekaev/photo-minimalist)'s
style ([mockup](docs/mockup/index.html); its sample photos stay local) and on the same `FujiKit`. Why this app and not another
iPhone one: [the research brief](docs/research/brief.md).

## Get started

```sh
git clone https://github.com/vekaev/fuji-recipes && cd fuji-recipes
scripts/install.sh      # builds, installs to ~/Library/Application Support/FujiRecipes/bin/fuji,
                        # links ~/.local/bin/fuji and the /recipe skill, registers the MCP server with Claude Code
fuji status             # is the camera there, and in the right USB mode?
fuji slots              # what's in C1–C7
fuji mine               # the recipes you actually shot with (your JPEGs' EXIF; --write files them)
fuji --simulate slots   # try everything against a simulated X-E5
```

On the camera (X-E5 wording, from Fujifilm's manual): **MENU/OK ▸ network/USB tab ▸ CONNECTION MODE ▸ USB RAW
CONV./BACKUP RESTORE**, and **USB POWER SUPPLY/COMM SETTING ▸ AUTO** (POWER SUPPLY ON/COMM OFF blocks data). Switch
the camera off, connect a USB-C data cable, switch it on. In the default card-reader mode the camera answers only a handful of properties (`fuji probe` shows them). The camera's menu is locked while it's connected in that mode.

## For agents (MCP)

`fuji mcp` is an MCP server over stdio. `scripts/install.sh` adds it to Claude Code (user scope). For the Claude
desktop app add this to `~/Library/Application Support/Claude/claude_desktop_config.json` and restart Claude:

```json
{ "mcpServers": { "fuji": { "command": "/Users/<you>/Library/Application Support/FujiRecipes/bin/fuji", "args": ["mcp"] } } }
```

Any other MCP client: run `fuji mcp`.

| Tool | Does |
|---|---|
| `fuji_camera` | connected camera, firmware, USB mode, number of slots, what to fix if it isn't found |
| `fuji_slots` | every slot: name, settings, summary, matching library recipe |
| `fuji_recipes`, `fuji_recipe` | the library, one recipe in full with the text to dial it in |
| `fuji_compare` | two recipes or slots ("C3"), field by field |
| `fuji_kits`, `fuji_backups`, `fuji_guide` | kits, saved snapshots, every field's values and the camera's rules |
| `fuji_save_recipe`, `fuji_set_status`, `fuji_save_kit`, `fuji_save_slot` | library edits (checked against what the camera accepts; duplicates refused) |
| `fuji_import_photos` | recipes from your Fujifilm JPEGs' EXIF (needs `brew install exiftool`) |
| `fuji_backup` | snapshot every slot into the library |
| `fuji_plan_write` → `fuji_apply_write` | camera writes: a preview of every change first; apply only after you approve. Apply backs up all slots, writes only what differs in the camera's order, reads each slot back and reports anything refused |

Reads change nothing. Restore any backup with `fuji_plan_write {"operations": [{"restore": "latest"}]}`.
Every tool also runs from the shell: `fuji call <tool> '<json>'`, `fuji tools` lists them.

## Recipes from reels (`/recipe`)

`skills/fuji-recipes` is an agent skill (Claude Code, Codex): give it an Instagram reel, TikTok or YouTube link,
screenshots or a caption, and it reads the recipe from the frames, caption, comments and speech. It shows you
every value with where it came from, marks the ones to check, credits the creator and saves the recipe through
`fuji`. `scripts/install.sh` links it; `/recipe mine` files the recipes you shot with.

## The library

`~/Documents/FujiRecipes` (or `$FUJI_RECIPES`), shared with the `/recipe` skill (reels → recipes):

```
recipes/<slug>.json    one recipe; the source of truth (skills/fuji-recipes/references/schema.md)
kits/<slug>.json       {name, slots: {C1: slug, …}}
backups/<date>-<model>.json   every slot before each write
library.md             generated index
```

## Cameras

Slot writes work over plain USB on X-T5, X-H2/H2S, X100VI, X-T50, **X-E5**, X-S20, X-M5, X-S10, X-T30 II, GFX100S,
GFX100 II, GFX100RF; X100V partly. Not on X-T3, X-T30 and older (no slot properties) or X-Pro3. X-T4 and X-E4:
untested. FS1–FS3 on a film simulation dial can't be written over USB.

**Warranty:** Fujifilm reportedly says connecting unlicensed software may void the warranty. Slot writes are
ordinary PTP property sets, no bricked camera has been reported, and a stuck camera recovers by switching it off
and on. You decide.

## Under the hood

- `Sources/FujiKit`: recipe model and checks, the slot codec (`Bank.swift`), PTP over ImageCaptureCore
  (`ImageCaptureTransport.swift`, no libusb, so no fight with `ptpcamerad`), the camera protocol (`Camera.swift`),
  a simulated X-E5, the library folder, EXIF import.
- `Sources/fuji`: the CLI and the MCP server.
- `swift test`: codec round trips, grain/NR/×10 encodings, write order, read-back on the simulated camera.

Protocol facts from [zgrimz/fujifilm-ptp-reference](https://github.com/zgrimz/fujifilm-ptp-reference) (CC BY 4.0),
[ILFforever/fujifilm-ptp-recipes](https://github.com/ILFforever/fujifilm-ptp-recipes), FilmKit and libfuji (MIT).
Thank you. MIT licence.
