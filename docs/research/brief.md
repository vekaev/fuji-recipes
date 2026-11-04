# Fujifilm recipe app: research brief (deep, 2026-11-04)

**Verdict.** On the iPhone, writing recipes to the camera became crowded in 2026. About 14 App Store apps write C1–C7 over USB-C, and since August 2026 the brand owner, Fuji X Weekly, does it for free. Five apps added Bluetooth writing in September–October. The **Mac** is still empty: no native Mac app writes to a camera, and the Mac tools that do are off-store developer projects (Ukiyo, FilmCase) or Fujifilm's own partial tools. Nobody imports a recipe from a **reel or TikTok link**; everyone starts from a screenshot. And nobody turns **your own shots** into the gallery, although Fuji JPEGs carry the whole recipe in EXIF. The protocol is solved, documented and reachable from Swift through Apple's ImageCaptureCore, and the owner's X-E5 is a confirmed-working body. *Judgement:* a small native Mac app (with iPhone/iPad from the same Swift code later) can win for the owner and for Mac-first shooters. It wins on being a careful librarian (read, back up, write, read back), on importing from reels, and on showing your own photos, not on "it writes to the camera", which every competitor already claims.

Notes behind this brief: [appstore](notes/appstore.md) · [web](notes/web.md) · [open source + protocol](notes/opensource-protocol.md) · [community](notes/community.md). Mockup: [Fuji Recipe Slots](https://claude.ai/artifact/Xnp7CyRfKGidhsWhvNaQAm) (source: [mockup/index.html](../mockup/index.html)).

## Competitors

US App Store, read 2026-11-04. W = writes settings to the camera.

| App | Platforms | Price | Rating | Updated | W | Standout | Top complaint |
|---|---|---|---|---|---|---|---|
| [FujiStyle](https://apps.apple.com/us/app/fujistyle-film-recipes-frame/id6504739559) | iPhone/iPad, Android | Free; Pro $14.99/yr | 4.79 (395) | 2026-09 | USB (Pro) + wireless beta | First to write (Jun 2025), EXIF recognition, frames | Write fails or freezes on X-T5 / X-E5 ([notes](notes/appstore.md)) |
| [Fuji X Weekly](https://apps.apple.com/us/app/fuji-x-weekly-film-recipes/id1539047257) | iPhone, Android | Free; Patron $19.99/yr | 4.42 (120) | 2026-10 | USB, write-only, one at a time free | 400+ recipes, the brand | No read-back; overwrites without warning; "pay to filter" |
| [Fuji Recipes](https://apps.apple.com/us/app/fuji-recipes-film-simulation/id6761905712) | iPhone/iPad, Mac, Android | $34.99/yr, $89.99 lifetime | 4.69 (58) | 2026-10 | USB + Bluetooth | Read + write + backup; RAW rendered by the camera | Write fails on X-T50; copied recipes without credit |
| [Huginn](https://apps.apple.com/us/app/huginn-film-sim-recipes/id6797092369) | iPhone/iPad | USB free; Pro $29.99/yr | 4.25 (4) | 2026-11 | Bluetooth + USB | "First wireless", all 7 slots in one pass | Setup |
| [Simu](https://apps.apple.com/us/app/simu-film-simulation-recipes/id6811793155) | iPhone/iPad | $4.99 once to write | – (0) | 2026-11 | USB | Screenshots from Instagram/Threads (20 at once), backup + verify + undo | New, unproven |
| [Community for Fuji](https://apps.apple.com/us/app/community-for-fuji/id6798434965) | iPhone/iPad + Mac build | $24.99/yr, $49.99 lifetime | 3.40 (5) | 2026-10 | USB read + write | Recipes matched to sensor | Subscription price |
| [Color X](https://apps.apple.com/us/app/color-x-film-recipes/id6799859869) | iPhone | Free | 2.60 (5) | 2026-10 | Bluetooth + USB, claims FS1–FS3 | Instagram captions | AI sample photos, uncredited recipes |
| [SimuLook](https://apps.apple.com/us/app/simulook-film-recipes/id6795308608) | iPhone, iPad, Mac | $59.99/yr | – (0) | 2026-10 | X100VI only | Read/backup free | – |
| [Fuji RAF Preview & Recipe](https://apps.apple.com/us/app/fuji-raf-preview-recipe/id6761335653) | **Mac** | $4.99 | – (0) | 2026-08 | No | Recipe readout per folder | – |
| [FUJIFILM XApp](https://apps.apple.com/us/app/fujifilm-xapp/id1586089681) | iPhone, Android | Free | 4.16 (3,618) | 2026-07 | Whole-camera backup only | Official | Bluetooth / Wi-Fi won't connect |
| FUJIFILM X RAW Studio / Tether App (ex X Acquire) | Mac, Windows | Free | – | – | Partial (profile → C slot) / whole-camera .DAT | Official, RAW render in camera | Clunky, partial |

About 20 more iPhone notebooks and catalogues (film.recipes $24.99, FILMEMO, FxjiMate, Simulated Film, Fuji Pic…) don't write; they are listed in [the App Store notes](notes/appstore.md).

**Open source** (details and licences in [the protocol notes](notes/opensource-protocol.md)):
- [zgrimz/fujifilm-ptp-reference](https://github.com/zgrimz/fujifilm-ptp-reference) (docs CC BY 4.0, tools MIT): the best spec, measured on an X-T50 against X RAW Studio captures, with errata for the other projects.
- [ILFforever/fujifilm-ptp-recipes](https://github.com/ILFforever/fujifilm-ptp-recipes) (MIT constants; X-H2, X-T5 tested).
- FilmKit (WebUSB, MIT, `src/ptp/constants.ts`) and [libfuji](https://github.com/petabyt/libfuji) (MIT, `lib/fujiptp.h`): the code most worth porting.
- [Ukiyo](https://github.com/noahkiss/ukiyo) (Mac, Tauri, MIT; slot writes untested on a real camera) and [FilmCase](https://github.com/gosku/Filmcase) (Django, GPL): the closest Mac projects.
- GPL, so facts only and no code copying: rawji, grawji, fujicli, Filmcase. Irrelevant: fujihack (patches firmware), Furble and fuji-cam-wifi-tool (no settings access).

## What people say

Source: 52 Reddit threads with comments (r/fujifilm, r/fujix, found through the Arctic Shift archive), 2 HN threads and 3 YouTube transcripts. Details are in the [community notes](notes/community.md).

- **Praise** (recurring):
  - The idea itself is wanted: "Wild to me that this isn't a feature for official Fuji app" ([r/fujifilm](https://www.reddit.com/r/fujifilm/comments/1vux5h8/)); "This is the type of app that Fuji should be making" (+15).
  - Fuji Recipe's "render my RAW with the recipe" mode is the most-praised single feature.
  - Fuji X Weekly is paid for mainly to support its author.
- **Complaints** (recurring):
  - **Typing recipes in is the pain.** "changing a bank means sitting in the menu punching in fifteen settings and I never bothered", from someone who shot a whole Japan trip on two recipes ([1vux5h8](https://www.reddit.com/r/fujifilm/comments/1vux5h8/)). "my collection is turning into a pile of screenshots and notes" ([r/fujix](https://www.reddit.com/r/fujix/comments/1x8gpnk/)). One YouTube test timed it at 5–10 minutes per recipe by hand.
  - **Fatigue with new apps:** "I've lost track of how many times this exact app has been built" (1vux5h8); "I feel like there's five apps that already do this" ([1vgrvjg](https://www.reddit.com/r/fujifilm/comments/1vgrvjg/)). Since April 2026 a new one has appeared every 1–2 weeks, and "vibe-coded" is now an insult.
  - **Trust comes first in every launch thread:** bricking ("open source it", +17), the warranty (+37), sign-up walls, FujiStyle's terms claiming rights to uploaded photos, AI-made promo photos.
  - **XApp is hated:** "I have to DELETE and REINSTALL the app every single time" (153 pts, [1rcjvyh](https://www.reddit.com/r/fujifilm/comments/1rcjvyh/)); its Bluetooth "works on the first try - and only on the first try".
  - **Hardware limits:** X-M5, X-S10 and X-S20 have only 4 slots. Older bodies (X-T2, X-Pro2, X-T3, X100F) store the WB shift per WB type, not per slot: "Old bodies don't save WB shifts. No workaround." ([1vi1s7z](https://www.reddit.com/r/fujifilm/comments/1vi1s7z/)). The X-E5's FS1–FS3 can't be renamed.
  - **Compatibility confusion:** "does it support my X-T2 / X-T3 / X100V / X-S20?" is the most common reply. Support follows the processor, not the sensor.
- **The workflow around the task:**
  1. Find a recipe on Fuji X Weekly, a reel or a forum.
  2. Screenshot it or save it in Notes.
  3. Type it into *Edit/Save Custom Setting*, about 15–20 fields.
  4. Shoot a whole trip on two or three slots, because swapping slots is too much work.
  - The free power-user trick: save seven-slot sets as named backups in XApp or X Acquire and restore whichever set suits the trip. This only works with the same camera model ([Fuji Rumors video](https://www.youtube.com/watch?v=oEg8sGVCL0g), 18k views).
  - Wanted: a sample photo per recipe ("I'm not going to remember what 'Grain Pulse' looks like"), tags, seven-recipe kits written in one go, import from a screenshot or reel.
- **Price:**
  - Fuji X Weekly costs about $20–25/yr and is accepted. FujiStyle's $14.99/yr got "you wasted your money". Fuji Recipe's ~$55–60 lifetime is called too high.
  - Subscriptions are resented and one-time purchases are praised. The free backup trick is the answer to any "$4.99 a month".
- **Audience:** YouTube videos on entering a recipe by hand get 100k–220k views each, while recipe-app videos get 6k–27k. Most people still dial recipes in by hand.

## How the camera side works (facts)

- **Transport:** USB-C with the camera set to *Connection Setting ▸ USB ▸ USB RAW CONV./BACKUP RESTORE*. Property `0xD16E` reads 6 in that mode, so the app can tell the owner when the mode is wrong. The camera's menu is locked while it's connected.
- **Banks are plain PTP device properties.** `GetDevicePropValue 0x1015` / `SetDevicePropValue 0x1016`. `0xD18C` selects which bank to edit, `0xD18D` is its name (≤ 25 ASCII), and `0xD18E–0xD1A4` hold the 23 settings: film `D192`, grain `D195`, Color Chrome `D196`, FX Blue `D197`, WB `D199` + shifts `D19A/B` + Kelvin `D19C`, DR `D190`, D-Range Priority `D191`, tone `D19D/E`, color `D19F`, sharpness `D1A0`, NR `D1A1`, clarity `D1A2`, mono toning `D193/4`.
- **Encodings:** film 1–20 (19 Nostalgic Neg., 20 Reala Ace). Tone, color, sharpness and clarity are signed ×10. WB shift is plain −9…+9. Effects: 1 Off, 2 Weak, 3 Strong. DR is 100/200/400 with Auto `0xFFFF`. NR uses a lookup table. Grain is written 1–5 but reads back 6/7 when off.
- **Write rules:** select the bank, then write in ascending order, except Kelvin right after the WB mode and D-Range Priority before DR. **Always read back:** an OK doesn't mean the value was stored, and values are refused depending on state (D-Range Priority on, a mono film, the bank's ISO, HEIF).
- **Bodies:**
  - Writes confirmed: X-T5, X-H2, X100VI, X-T50, X-S20 (4 banks), X-M5 (4), **X-E5**, X-S10, GFX100S, GFX100RF.
  - Partial: X100V.
  - Fails: X-Pro3.
  - No bank properties: X-T3, X-T30.
  - **FS1–FS3 on the X-E5 dial are not writable** by third-party apps (per Fuji X Weekly), though Color X claims it.
- **Swift:** `ICCameraDevice.requestSendPTPCommand(_:outData:completion:)` (macOS 10.15+, iOS 13+) passes raw vendor commands through.
  - Detect the camera with `ICDeviceBrowser`, filtering on USB vendor `0x04CB`.
  - macOS's `ptpcamerad` claims the camera's USB interface, so libusb isn't an option, but ImageCaptureCore works.
  - iPad/iPhone needs both Control and Contents permission, and iOS 18 has open bugs here.
- **Risk:** no reported bricked camera. The real risks are overwriting the owner's slots (snapshot first) and a camera stuck until it's power-cycled. Fujifilm reportedly says unlicensed connections void the warranty and declined to license the protocol ([Fuji X Weekly 2026-06-08](https://fujixweekly.com/)).
- **The camera can render a RAF with any recipe** (X RAW Studio's route, also used by Fuji Recipes, Simu, Huginn and Film Kitchen). That gives an exact preview of a recipe on your own photo, but only for RAWs from the same model.
- **EXIF:** every Fuji JPEG stores the full recipe. Monochrome films are stored in the Saturation tag, and the WB shift is stored ×20. Verified on the owner's photos: 62 shots with Acros+G and 39 with a Classic Neg recipe, all X-E5.

## Feature landscape

| Feature | Table stakes? | Who has it | Notes |
|---|---|---|---|
| Recipe catalogue / notebook | Yes | Everyone | FXW 400+, film.recipes 800+, a community sheet of ~1,058 |
| Write a recipe to C1–C7 over USB | Yes (since Aug 2026) | ~14 iPhone apps, FXW free | None native on the Mac |
| Read the slots back from the camera | Half | Fuji Recipes, Community for Fuji, SimuLook, Fuji Frame | FXW can't |
| Backup before write, verify after, undo | Rare | Simu, FujiShare (beta), Huginn (per slot) | The owner's "careful" angle |
| Bluetooth writing | New (Sep–Oct 2026) | Huginn, Fuji Recipes, FujiStyle beta, Color X, Fujirama | Undocumented; XApp's BT complaints show the risk |
| Recipe from a JPEG's EXIF | Yes | FujiStyle, FujiShare, FxjiMate… | Social media strips EXIF, so it only works on original files |
| Recipe from screenshots / captions (OCR) | Common | Simu, Color X, Community for Fuji, Huginn, Fuji101 | – |
| **Recipe from a reel / TikTok link** | **Nobody** | – | Our `/recipe` skill already does it on the Mac |
| Preview on your RAW rendered by the camera | Growing | Fuji Recipes, Simu, Huginn, Bento, Fujirama, Film Kitchen | Same-model RAWs only |
| **Gallery of your own shots grouped by recipe** | **Nobody as the core** | FilmCase (catalogue), F Sort (sort into folders) | Ours: "Shot with" from EXIF |
| Sensor / model compatibility check | Common | Community for Fuji, FXW tags | Depends on model and firmware, not just sensor |
| Native Mac app | **Missing** | Only iPad apps running on the Mac, off-store tools | The gap |

## The gap  (Judgement)

1. **The Mac.** Photographers cull and edit on the Mac, and the camera is already plugged in there for X RAW Studio or tethering. Every polished competitor is an iPhone app. A native Mac app reached by plugging in a cable fits the owner's existing Photo Minimalist workflow.
2. **From reel to slot.** The owner's real input is "a bunch of reels". Every competitor needs a screenshot of the right frame first. Link → download → OCR + speech → checked recipe already works locally (the `/recipe` skill), with credit to the creator.
3. **Your own shots as the gallery.** EXIF already tells which recipe each photo used. "Shot with" turns the library into a portfolio per recipe without any manual tagging. No competitor leads with that, and it avoids the sample-photo plagiarism complaints entirely.
4. **Careful by default.** Read everything on connect, snapshot, write, read back, and show exactly what was refused and why ("DR400 needs ISO 640+"). The top complaint across the category is writes that fail silently or freeze.

## Recommended scope  (Judgement)

- **Do:** a Mac app that wakes when the X-E5 is plugged in and shows C1–C7 (FS1–FS3 read-only if readable), with an editor, write + read-back, and automatic backups. Add a recipe library that shares one folder with the `/recipe` skill (`~/Documents/FujiRecipes`), a "Shot with" gallery from EXIF, and import from a reel link.
- **Then:** "render my RAW with this recipe" through the camera. iPhone/iPad from the same Swift core (ImageCaptureCore works there, with the permission caveats).
- **Refuse:** Bluetooth writing, a social feed, AI-generated recipes, and republishing other creators' sample photos. Bluetooth is undocumented and the source of XApp's worst reviews. The rest is what reviewers hate, or is outside "minimal".
- **Kits, not single recipes:** a named set of seven ("Iceland", "City nights") written in one go and restored later. It's the XApp backup trick made pleasant, and Redditors already do it by hand.
- **Names:** *Slots*, *Seven*, *Recipe Box* (*Dial In* is already taken by an app launched on r/fujifilm).
- **Risks:**
  - The iPhone market is saturated; if the owner wants a commercial product, the Mac-only angle is narrow.
  - Fujifilm's warranty stance.
  - Firmware updates may move property codes. Read-back catches that, but the app needs a per-model table.
  - FS1–FS3 may stay unwritable.

## Built so far (2026-11-04)

- **`fuji` MCP server + CLI**, in this repo (Swift package `FujiKit`, the core the app will
  share). It talks to the camera over ImageCaptureCore.
  - Tools: camera status, read slots, compare, backups, library and kit edits, import from photo EXIF, and
    camera writes as plan → preview → approve → apply (backup first, read back after).
  - Registered with Claude Code and the Claude desktop app.
  - Tested on a simulated X-E5 (10 unit tests, a full MCP session). Not yet tested on the real camera.
- **`/recipe` skill** (reel → checked recipe file) now saves through `fuji`, so there is one implementation of the
  format and its checks.
- **Design:** the [mockup](../mockup/index.html) is redone in Photo Minimalist's Mac
  style:
  - the camera is a tab in the 38 pt top bar, like a memory card;
  - sidebar list of slots or recipes, with filter tabs and List | Grid;
  - a photo pane with a chip ("Changed · Write C2") and the info card;
  - a 280 pt slot editor with tick dials, like the Adjust panel;
  - monochrome, light and dark.

## Open questions for the owner

- Mac first, or Mac + iPhone together from day one? The protocol works on both.
- A separate app, or a "Recipes" mode inside Photo Minimalist? Photo Minimalist's own rule is "preview, level, crop. Nothing else", which argues for a separate app sharing its folder conventions.
- For yourself only, or for the App Store? That decides whether to ship a recipe catalogue (credit and licensing) or stay a personal library.
- Do you want the X-E5's FS1–FS3 dial slots enough to experiment? The property scan in Ukiyo's PTP "Lab" could tell us whether they're readable.

## Sources and coverage

- **Searched:** App Store (iTunes Search API, 22 phrases, iPhone + Mac, about 35 apps profiled); the web (WebSearch/WebFetch: Fuji X Weekly, Notebookcheck, FujiRumors, fotowissen, Fujifilm support); GitHub (`gh search repos`/code, about 25 repos, licences checked); Reddit ✓ (52 threads via Arctic Shift, ~400 titles), HN ✓ (2 threads), YouTube ✓ (3 transcripts); the owner's own 112 Fuji JPEGs via exiftool.
- **Skipped:**
  - Live Reddit search (upstream 403; the archive was used instead).
  - r/FujiXWeekly and r/Fujifilm_X100VI (the archive timed out).
  - X and TikTok (not searched).
  - PetaPixel and openPR (blocked the fetcher; cited from search snippets).
  - Instagram (needs a login).
- **Date:** 2026-11-04.
