<div align="center">

# Fuji Recipes

**Your Fujifilm's custom slots and your recipes. For you and your agents.**

Plug a Fujifilm X camera into the Mac, see what's in C1–C7, and write film-simulation recipes into the slots,
with a backup first and a read-back after. Keep a recipe library of your own recipes (found in your photos'
EXIF), recipes from reels and websites, and kits of seven for a trip. Ask Claude to do any of it through MCP.
Native Swift, on-device, nothing uploaded.

[![Swift](https://img.shields.io/badge/Swift-native-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS%2014%2B-native-000000?style=flat-square&logo=apple&logoColor=white)](#install)
[![MCP](https://img.shields.io/badge/MCP-for%20agents-3a3a3a?style=flat-square)](#for-agents-mcp)
[![License: MIT](https://img.shields.io/badge/license-MIT-3a3a3a?style=flat-square)](LICENSE)
[![Status: early](https://img.shields.io/badge/status-early-d69e2e?style=flat-square)](#status)

<br>

[![Download for macOS](https://img.shields.io/badge/Download-macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/vekaev/fuji-recipes/releases/latest)

<sub>One line in Terminal (below) installs the <code>fuji</code> CLI, its MCP server for Claude, and the /recipe skill. Apple Silicon + Intel, macOS 14+.</sub>

</div>

## Status

Early. The `fuji` CLI and MCP server read a real X-E5 (all slots, FS1–FS3, a full settings backup) and write
slots end to end against a simulated X-E5 that refuses what real bodies refuse; the first real write is next. The Mac app comes after, in [Photo Minimalist](https://github.com/vekaev/photo-minimalist)'s
style ([mockup](docs/mockup/index.html); its sample photos stay local) and on the same `FujiKit`. Why this app and not another
iPhone one: [the research brief](docs/research/brief.md).

## Install

**One line in Terminal** (no security prompt):

    curl -fsSL https://raw.githubusercontent.com/vekaev/fuji-recipes/main/scripts/install.sh | sh

It downloads the latest release, checks its SHA-256, installs `fuji` into
`~/Library/Application Support/FujiRecipes/bin` (linked as `~/.local/bin/fuji`), adds the `/recipe` skill, and
registers the MCP server with Claude Code and the Claude desktop app (quit and reopen Claude once). Run it again,
or `fuji update`, to update; `fuji version --check` says whether there's a newer release. Optional:
`brew install exiftool` for recipes from your photos.

From a checkout instead: `scripts/dev-install.sh` builds, signs and installs the same way.

## Get started

```sh
fuji doctor             # is the camera connected, step by step
fuji status             # is the camera there, and in the right USB mode?
fuji slots              # what's in C1–C7
fuji mine               # the recipes you actually shot with (your JPEGs' EXIF; --write files them)
fuji --simulate slots   # try everything against a simulated X-E5
```

### Plug in your camera

The camera must be in **USB RAW CONV./BACKUP RESTORE** mode; out of the box it's a card reader, which shows only
your photos.

1. On the camera, once: **MENU/OK ▸ network/USB tab ▸ CONNECTION MODE ▸ USB RAW CONV./BACKUP RESTORE**.
2. Same tab, once: **USB POWER SUPPLY/COMM SETTING ▸ AUTO**.
3. Every time: **camera off ▸ USB-C data cable into the Mac ▸ camera on**.
4. Check: `fuji doctor`, or ask Claude "is my camera connected?".

**New to this?** [Connect your Fujifilm](docs/CONNECT.md) (the USB mode, step by step, and `fuji doctor` when it
doesn't work) · [Use C1–C7 and FS1–FS3](docs/USING-SLOTS.md) (the dial decides which one you shoot with).

## For agents (MCP)

`fuji mcp` is an MCP server over stdio. The installer adds it to Claude Code (user scope) and the Claude desktop
app. To add it by hand to the desktop app, put this in `~/Library/Application Support/Claude/claude_desktop_config.json` and restart Claude:

```json
{ "mcpServers": { "fuji": { "command": "/Users/<you>/Library/Application Support/FujiRecipes/bin/fuji", "args": ["mcp"] } } }
```

Any other MCP client: run `fuji mcp`.

| Tool | Does |
|---|---|
| `fuji_camera` | connected camera, firmware, USB mode, number of slots, what to fix if it isn't found |
| `fuji_doctor` | the connection checked step by step (USB → camera → session → mode → slots) with the fix for what fails |
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
`fuji`. The installer links it; `/recipe mine` files the recipes you shot with.

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
untested. FS1–FS3 on the X-E5's film simulation dial are **read** from the camera's settings file (`fuji slots`;
`fuji backup --full` saves that whole file, like X Acquire); writing them is not supported yet.

First real-camera run (X-E5 fw 1.12, 2026-11-04): mode detection, all 7 slots, the live settings, the 70,524-byte
settings file and FS1–FS3 read correctly; FS1 matched the recipe in 39 of the owner's JPEGs. No writes yet.

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

## Releasing

`scripts/release.sh X.Y.Z [notes.md]`: tests, a universal build (Apple Silicon + Intel), signs, packs
`fuji-macos.tar.gz` (binary + skill) with its SHA-256, commits "Release X.Y.Z", tags, pushes and creates the GitHub
release. `--local` only builds into `dist/` for testing the installer (`FUJI_BASE_URL=…`). Never replace an asset on
an existing release (installers check its checksum); a fix is a new patch release. The Mac app will add a DMG and
Sparkle auto-update here, like Photo Minimalist.
