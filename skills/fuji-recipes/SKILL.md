---
name: fuji-recipes
description: Fujifilm film-simulation recipe library — pull a recipe out of an Instagram reel / TikTok / YouTube link, screenshots or pasted text, find the recipes the owner actually shot with (EXIF of their Fuji JPEGs), check it against their camera (X-E5) and file it in ~/Documents/FujiRecipes; also "mine", "list", "show", "compare", "tried", "rate".
---

Turn "this reel has a nice recipe" into a checked recipe file the owner can dial in, or that the recipe
app writes to the camera. Input comes from the invocation arguments or the conversation: one or more
links, screenshots, pasted caption text, or a library command (see **Library commands**). With nothing,
ask for the link in one line.

## The library

Everything lands in `$FUJI_RECIPES`, default `~/Documents/FujiRecipes/`:

```
FujiRecipes/
  library.md              generated: one table per status (favorite, mine, tried, to-try, rejected)
  recipes/<slug>.json     one file per recipe, the source of truth (schema: references/schema.md)
  sources/<date>-<who>.md one note per reel/post: link, creator, what was on screen, how each field was read
  samples/<slug>/         frames from the reel (the creator's sample shots) — local only, never published
```

- Recipe files follow [schema.md](references/schema.md) exactly: the app and the `fuji` MCP server read the
  same folder.
- **Write recipes through `fuji`**, not by hand: the `fuji_save_recipe` MCP tool when it's available, else
  `fuji call save_recipe '<json>'` (`~/.local/bin/fuji`, from the one-line installer in
  github.com/vekaev/fuji-recipes). It checks every value against what the camera accepts, refuses a duplicate of another
  recipe's settings (naming it), fills `date_added` and rebuilds `library.md`. A refusal names the field; fix the
  value, don't loosen the check. After editing a file by hand, run `fuji index`.
- **No duplicates.** Before adding, compare `settings` with every existing file. Same settings → add the
  new source to `notes` (and credit), don't create a second file. One or two fields apart → say so ("same as
  *Summer Chrome* except Color +1") and ask whether it's a variant worth keeping.
- Credit the creator: `source.creator`, `source.url`, and `source.credit` in their words if they name an
  origin (e.g. "based on Fuji X Weekly's Kodak Portra 400"). Store the settings and a link, never the
  creator's caption text or images beyond local samples.

## Run: from a reel, post or screenshots

1. **Read the source.** For a link, read the whole reel (frames, caption, comments, speech) with
   the `transcribe` skill if it's installed (`/transcribe <url> --visual`: local Whisper + on-screen OCR +
   contact sheets); otherwise download it with `yt-dlp`, cut frames with `ffmpeg` and read them, or ask for screenshots
   (retry once with `--cookies-from-browser chrome` on a login wall). Read the note's caption, the first
   comments (creators often post the recipe there, or answer "what WB?"), the `## On screen` OCR, and look
   at every contact sheet: settings cards are often a single fast frame. For screenshots, read them
   directly. For a carousel photo post (`/p/` without video) the transcribe script can't fetch it: open it in the
   built-in browser (no login needed), step through the slides (Next button), download each full-size slide and read
   it; settings cards are usually the last slides. Without a browser, ask for screenshots.
2. **Extract** every field into the schema. Abbreviations are listed at the end of schema.md. Where the
   screen and the caption disagree, the screen wins; where speech adds something ("I push highlights to
   −1.5 in summer"), put it in `notes`. A field nobody gives stays at the camera default and goes into
   `uncertain`. ISO, exposure compensation and "use with" advice go into `shooting`, not `settings`.
3. **Show it in chat right away** as a two-column table (field · value, uncertain ones marked "check"),
   plus where each came from (frame time, caption, comment), before filing, so the owner can correct a
   misread number. WB shift and tone half-steps are the usual misreads.
4. **Check the camera.** The owner shoots an X-E5 (X-Trans V): everything is available. For another body,
   use the sensor table in schema.md and say plainly which fields it can't take and what's closest.
5. **File.** Name it the creator's name for it (or a short descriptive one), `status: "to-try"`, save it with
   `fuji_save_recipe` (source: kind reel, url, creator, credit, transcript path; `uncertain`; `shooting`), write
   one `sources/<date>-<creator>.md` per post, and copy 2–4 sample frames the creator shot with the recipe into
   `samples/<slug>/` (from the transcribe folder).
6. **Report**: the table, the file path, duplicates or near-duplicates found, and how to dial it in. If the
   camera is connected (`fuji_camera`), offer to put it in a free slot: `fuji_plan_write`, show the preview,
   and `fuji_apply_write` only after the owner says yes.

Several links at once: process them in parallel (one subagent per link for steps 1–2), then check
duplicates across the batch before filing.

## Library commands

- `mine [folders]` — find the recipes the owner actually shot with: `fuji_import_photos` (or
  `fuji mine [folders…] [--min N] --write`; without folders it uses every Fujifilm JPEG Spotlight knows; without
  `--write` it only lists). Fujifilm writes every recipe field into each JPEG's EXIF
  (monochrome sims live in the Saturation tag, WB shift is stored ×20). Groups get `status: "mine"`,
  shot counts, dates and up to 6 sample paths; a recipe already in the library with the same settings is
  updated instead. Then ask the owner to name the new ones and rebuild the index.
- `list [status|film]`, `show <name>` — read `library.md` / the recipe file; `show` prints the recipe in
  the camera's text format (schema.md) ready to dial in.
- `compare <a> <b>` — field-by-field table, differences only.
- `tried <name> [note]`, `rate <name> favorite|rejected [note]` — `fuji_set_status` (status + note; the index rebuilds itself).

## The camera

Through the `fuji` MCP server (Claude Code and the Claude desktop app have it): `fuji_camera`, `fuji_slots`,
`fuji_sync_slots` (recipes on the camera that the library lacks → added as "mine" with the owner's photos; dryRun first),
`fuji_compare` (recipe vs "C3"), `fuji_backup`, kits (`fuji_save_kit`), and writes only as
`fuji_plan_write` → show the preview → owner approves → `fuji_apply_write` (backs up every slot first, reads
back after). Never claim a recipe is on the camera unless `fuji_apply_write` reported it ok. The camera must be in
USB RAW CONV./BACKUP RESTORE mode; `fuji_camera` says what to fix.
