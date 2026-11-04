# Use your recipes on the camera: C1–C7 and FS1–FS3

Your X-E5 has **ten** places to keep a recipe. They work differently, and the **film simulation dial** decides
which one you're shooting with. Menu names are from Fujifilm's X-E5 manual.

| | Where | How many | Picked with | This app |
|---|---|---|---|---|
| **FS1–FS3** | the film simulation dial | 3 | turning the dial to FS1 / FS2 / FS3 | reads them; writing: not yet |
| **C1–C7** (CUSTOM 1–7) | the IMAGE QUALITY SETTING menu | 7 | the Q button, dial on **C** | reads and writes them |

## The one rule: the dial wins

The dial's positions on the X-E5: PROVIA/STANDARD, Velvia/VIVID, ASTIA/SOFT, CLASSIC CHROME, REALA ACE, ACROS,
**FS1, FS2, FS3**, and **C**.

- On a **named film** (PROVIA … ACROS) you shoot that film, whatever else is set.
- On **FS1–FS3** you shoot the recipe stored on that position.
- Only on **C** does the film simulation come from the menu or from the **custom setting you selected (C1–C7)**.
  Fujifilm's manual: the film simulation "saved in EDIT/SAVE CUSTOM SETTING" is "valid only when the film simulation
  dial is set to [C]".

So **to shoot with a recipe in C3: dial on C, then pick C3.** That's why custom settings feel like they "don't
work": with the dial on a film, the slot's film never applies.

## Shoot with C1–C7

1. Turn the film simulation dial to **C**.
2. Press **Q**. The first item of the Quick Menu is **SELECT CUSTOM SETTING**.
3. Turn the rear command dial to **C1 … C7** (the name shows, e.g. "C2 CLASSIC NEG"). Half-press the shutter.

Or through the menu: **MENU/OK ▸ IMAGE QUALITY SETTING ▸ SELECT CUSTOM SETTING ▸ CUSTOM 1…7**.
"NOTHING SELECTED" means no slot: you're shooting your current settings.

## Put recipes into C1–C7

**With this app (or Claude):** plug in the camera (see [CONNECT.md](CONNECT.md)), then for example
"put Summer Chrome in C3". You see every change first; a backup of all slots is saved before writing and each slot
is read back after. Seven recipes at once: a kit ("load my Iceland kit").

**On the camera, by hand:** set every setting the way the recipe says (film, grain, color chrome, WB + shift, DR,
tone, color, sharpness, NR, clarity), then **MENU/OK ▸ IMAGE QUALITY SETTING ▸ EDIT/SAVE CUSTOM SETTING**, highlight
**C1–C7**, press MENU/OK, choose **OK**: the current settings are saved to that slot.

On the same screen, for a slot:

- **EDIT/CHECK**: change single items; changed ones get a red dot until you **SAVE THE CHANGES** (or **RESET THE CHANGES**).
- **EDIT CUSTOM NAME**: name it after the recipe, so you see it in the Q menu.
- **COPY** to another slot (overwrites it, name included) · **ERASE**.
- Shortcut: press and hold **Q** to jump to EDIT/SAVE CUSTOM SETTING.

**AUTO UPDATE CUSTOM SETTING** (IMAGE QUALITY SETTING): on ENABLE, any setting you change while a slot is selected
is saved into that slot. Leave it on **DISABLE** if your slots hold recipes you want to keep exactly.

What a slot doesn't store: ISO and exposure compensation. Recipes often suggest them; set those yourself.

## FS1–FS3

**MENU/OK ▸ IMAGE QUALITY SETTING ▸ FILM SIMULATION DIAL SETTING ▸ FS1 / FS2 / FS3**: choose the film (with a
filter for ACROS / MONOCHROME), and turn **FS RECIPE** on to keep the other image-quality settings (grain, WB, tone…)
per position. Then the dial position *is* the recipe: no menu needed.

Over USB these three live in the camera's settings file, not in the slot properties: this app reads them
(`fuji slots`), and writing them is not supported yet.

## Which to use

- **Three favourites you switch between all the time** → FS1–FS3: one turn of the dial.
- **More than three, or a set per trip** → C1–C7 with the dial on C, and a kit to swap all seven from the Mac.
