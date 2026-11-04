# Connect your Fujifilm to the Mac (and to Claude)

A Fujifilm camera can connect over USB in several modes, and **only one of them lets a computer read and write
the camera's settings**. Out of the box it's the wrong one: the camera connects as a **card reader**, so the Mac
sees your photos, not the camera. This page is everything you need to set it up once, plug it in, check it worked,
and use it from Claude. Menu names are the **X-E5**'s (from Fujifilm's manual, links at the end); other recent
bodies are the same or very close.

## The short version

1. On the camera, once: **MENU/OK ▸ network/USB tab ▸ CONNECTION MODE ▸ USB RAW CONV./BACKUP RESTORE**.
2. Same tab, once: **USB POWER SUPPLY/COMM SETTING ▸ AUTO**.
3. Every time: **camera off ▸ USB-C data cable into the Mac ▸ camera on**.
4. Check: `fuji doctor` in Terminal, or ask Claude *"is my camera connected?"*. All five steps should show ✓.

## Which USB mode does what

The camera picks its mode **when the cable goes in**, from CONNECTION MODE. Changing the setting while plugged in does
nothing until you reconnect.

| CONNECTION MODE | What the Mac sees | Use it for | Recipes / MCP? |
|---|---|---|---|
| **USB CARD READER** (factory default) | your memory card: Preview / Photos offer to import | copying photos over the cable | **No.** The camera answers only ~5 basic settings (battery…), never the slots |
| **USB RAW CONV./BACKUP RESTORE** | a camera with no photos, ~60 settings | this app, the `fuji` MCP server, Fujifilm X RAW Studio, the Fujifilm Tether app's backup / restore | **Yes** |
| **USB WEBCAM** | a webcam (video) | video calls | No |

You can leave the camera on USB RAW CONV./BACKUP RESTORE: Fujifilm's manual says "the camera functions normally when
not connected". The only thing you give up is importing photos *over the cable*; use a card reader for that, or
switch back to USB CARD READER for the import.

**USB POWER SUPPLY/COMM SETTING** decides whether the cable carries data at all:

| Setting | Data? | Notes |
|---|---|---|
| **AUTO** | yes | switches between charging and data by itself. Use this. |
| POWER SUPPLY OFF/COMM ON | yes | data only, the camera doesn't draw power from the Mac |
| POWER SUPPLY ON/COMM OFF | **no** | charges only; the camera may not show up as a camera at all |

## Set up once, on the camera

1. Switch the camera on and press **MENU/OK**.
2. Go to the **network/USB** tab (the last tab; the manual calls it the "I" tab, network/USB setting).
3. Open **CONNECTION MODE** → choose **USB RAW CONV./BACKUP RESTORE**.
4. On the same tab, open **USB POWER SUPPLY/COMM SETTING** → choose **AUTO**.
5. Press **MENU/OK** / **DISP/BACK** to leave the menu. Settings are saved; you won't need to do this again.

Older bodies (X-T4, X100V, X-S10 generation): **SET UP ▸ CONNECTION SETTING ▸ PC CONNECTION MODE ▸ USB RAW
CONV./BACKUP RESTORE**.

## Plug in, every time

1. **Switch the camera off.** (Fujifilm's steps: connect with the camera off, then switch it on.)
2. **Use a USB-C data cable**, straight into a port on the Mac. Charge-only cables look identical and are the most
   common reason nothing shows up; ≤ 1 m is what Fujifilm recommends. Hubs and docks often work, but rule them out
   first when something's wrong.
3. **Switch the camera on.** While connected in this mode the camera's menu is locked (it shows a connection
   screen); that's expected. Unplug the cable to shoot again.
4. **Quit Preview / Photos / Image Capture** if they pop up. They're a sign the camera is still in card-reader mode
   (go back to "Set up once"), and they can hold on to the camera so other apps can't talk to it.

## Check it worked

**On the Mac:** run `fuji doctor`:

```
✓ 1. USB      FUJIFILM X-E5 is on USB
✓ 2. Camera   macOS offers it as a PTP camera
✓ 3. Session  X-E5, firmware 1.12
✓ 4. Mode     USB RAW CONV./BACKUP RESTORE
✓ 5. Slots    C1–C7 readable
```

Then `fuji slots` lists C1–C7 and FS1–FS3. `fuji status` is the one-line version.

**In Claude:** ask *"is my camera connected?"* or *"what's on my camera's slots?"*. Claude calls `fuji_doctor` /
`fuji_slots` and answers in plain words.

## Use it from Claude (MCP)

The `fuji` MCP server is what lets Claude talk to the camera and your recipe library.

- **Claude Code:** `scripts/install.sh` registers it. Check with `claude mcp list`: you should see
  `fuji: … fuji mcp - ✔ Connected`. New sessions pick it up.
- **Claude desktop app:** it's in `~/Library/Application Support/Claude/claude_desktop_config.json` under
  `mcpServers.fuji` (command `…/FujiRecipes/bin/fuji`, args `["mcp"]`). **Quit and reopen Claude** after adding it.
  In a chat, the tools menu lists the `fuji` tools.
- **What to ask:** "is my camera connected?", "read my slots", "save FS1 as a recipe called Strong Neg",
  "put Summer Chrome in C3" (you get a preview first; nothing is written until you say yes), "back up my camera".
- **One app at a time:** each Claude app (Code, desktop) starts its own `fuji` server. Talking to the camera from both
  at the same moment can make one of them wait or fail; use one, or retry.
- The server finds the camera on its own when you plug it in; you don't need to restart anything.

## Unplug, shoot, import

- **To shoot:** unplug the cable. Everything works normally.
- **To import photos over the cable:** CONNECTION MODE ▸ USB CARD READER, reconnect. Remember to switch back for
  recipes. (A card reader in the Mac avoids the switching.)
- **Charging:** with AUTO the cable can also charge the camera; that doesn't change the mode.

## When it doesn't work

`fuji doctor` stops at the first step that fails and says the fix:

| Step fails | What it means | Fix |
|---|---|---|
| 1 USB | The Mac doesn't see a Fujifilm at all | Camera on? Try another cable (charge-only cables are common). USB POWER SUPPLY/COMM SETTING ▸ AUTO. Plug straight into the Mac. |
| 2 Camera | On USB, but macOS doesn't offer it as a camera | Unplug, wait 3 s, plug in. Quit photo apps. Does Image Capture.app list it? |
| 3 Session | Listed, but doesn't answer | Another app holds it (Preview, Photos, Image Capture, X RAW Studio, Fujifilm Tether, Lightroom, Capture One): quit them, then camera off → on. |
| 4 Mode | It answers as a card reader / webcam | CONNECTION MODE ▸ USB RAW CONV./BACKUP RESTORE, then **camera off → plug in → on**. The mode is chosen when the cable goes in. |
| 5 Slots | Right mode, no slots | X-T3, X-T30 and older bodies don't expose slots. Otherwise camera off → on. |

Deeper, all read-only:

- `fuji probe`: what the camera advertises and answers. Card reader: `5001 D303 D406 D407 D041` (≈5 properties).
  RAW CONV.: ≈60, including `D18C…D1A4` (the slots).
- `fuji probe D001 D023 …`: any property by code (the live `0xD0xx` shooting state included).
- `ioreg -p IOUSB -w0 -l | grep -A3 FUJIFILM`: what USB itself reports (Fujifilm's vendor id is 1227 = 0x04CB).
- `/usr/bin/log show --last 10m --predicate 'eventMessage CONTAINS "X-E5"'`: which Mac app grabbed the camera.

## What it looked like the first time (X-E5, firmware 1.12, 2026-11-04)

1. Plugged in with factory settings: `fuji doctor` → step 4 failed, **USB CARD READER**. The camera answered, but
   offered only 5 properties; Preview opened offering to import.
2. After changing CONNECTION MODE and re-plugging: still a card reader. macOS logged the camera as one with files to
   import (Preview again).
3. After setting **both** CONNECTION MODE and USB POWER SUPPLY/COMM SETTING ▸ AUTO, then **camera off → plug in →
   on**: mode 6 (RAW CONV.), 61 properties, C1–C7 readable, and FS1–FS3 read from the camera's settings file.

So if step 4 keeps failing: check both settings, and reconnect with the camera **off**.

## Sources

- [X-E5 network/USB setting menus](https://app.fujifilm-dsc.com/en-int/manual/x-e5/connections/network_usb_menu/): CONNECTION MODE, USB POWER SUPPLY/COMM SETTING
- [X-E5 saving and loading settings](https://app.fujifilm-dsc.com/en-int/manual/x-e5/connections/save_load_setting/): the backup/restore procedure
- [X-E5 connecting via USB](https://app.fujifilm-dsc.com/en-int/manual/x-e5/connections/connect_usb/): cable and power-on order
