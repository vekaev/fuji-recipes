# App Store scout: Fujifilm film-simulation recipe apps

Read on **2026-11-04**. App Store data comes from the iTunes Search API (US storefront; `entity=software` and `macSoftware`, 22 phrases, up to 100 results each), from the App Store web pages (in-app purchase prices, version history) and from the US customer-review RSS (`sortBy=mostRecent` and `mostHelpful`). Ratings are **US-storefront** averages and counts. "Updated" is `currentVersionReleaseDate`. Off-store products come from WebSearch and WebFetch. Every row links its source.

## The headline

- **Writing recipes to C1–C7 is now table stakes, not a gap.** At least **14 Fuji recipe apps on the App Store** claim they can write to the camera. Most of them shipped in 2026. FujiStyle was first (beta in June 2025). Since 2026-08-20 the incumbent **Fuji X Weekly** app does it too, free for one recipe at a time.
- **Transport:** the common path is **USB-C PTP** with the camera in `USB RAW CONV./BACKUP RESTORE` mode. Since September–October 2026 several apps also write **over Bluetooth**: Huginn, Fuji Recipes, FujiStyle (beta), Color X and Fujirama.
- **Second wave: "the camera as render engine".** Apps send a RAF back through the camera's in-camera RAW conversion over USB to preview a recipe on your own photo. Fuji Recipes, Simu, Huginn, Bento, Film Kitchen, Recipe Lab, Fujirama and Filmsim do this.
- **Import from screenshots / Instagram is shipped too.** Simu (Instagram, Threads, Xiaohongshu screenshots, 20 at once), Color X (Instagram captions), Community for Fuji, Huginn and Fuji101 do it with OCR. Reading a recipe from a Fuji JPEG's EXIF is everywhere.
- **Mac is the thin side.** No native Mac App Store app writes to a camera. The Mac-only store apps read recipes from files (Fuji RAF Preview & Recipe, F Sort). On the Mac, the iPad apps run as "Designed for iPad", and SimuLook and Community for Fuji ship Mac builds. Mac tools that write to the camera exist only off-store: Fujifilm X RAW Studio (profile → C slot), the Fujifilm Tether App / X Acquire (whole-camera `.DAT` backup), and open-source projects (Ukiyo, FilmCase, FujiRecipesMac).
- **Fujifilm offers no recipe feature.** XApp 2.7.6 (2026-07-06) and the X half app have none. XApp only backs up and restores *all* camera settings. According to Fuji X Weekly, Fujifilm says **unlicensed software that connects to the camera voids the limited warranty** and declined to license the protocol.
- **Top complaints across the category:** writing doesn't work or freezes (FujiStyle, Fuji Recipes, Huginn setup); subscriptions that are too expensive; recipes and sample photos copied from creators without credit (Color X, Fuji Recipes, Filmsim); AI-generated sample photos (Color X); saved recipes lost after an update (FXW, Filmsim). Fujifilm's own XApp is rated 1★ over and over for Bluetooth and Wi-Fi connection failures, which is the main risk of any wireless approach.

## Comparison table

W = can write settings to the camera. Ratings are US ★ / count as of 2026-11-04.

| App | Platform | Price model | ★ / count | Updated | W? | How / cameras |
|---|---|---|---|---|---|---|
| [FujiStyle – Film Recipes Frame](https://apps.apple.com/us/app/fujistyle-film-recipes-frame/id6504739559) | iOS/iPadOS (+Mac as iPad app), Android | Free; Pro $3.99/mo, $9.99/qtr, $14.99/yr; USB write is Pro, wireless free for a limited time | 4.79 / 395 | 2026-09-18 | **Yes** | USB-C + wireless (beta, 1.3.46): X-T50, X-S20, X100VI, X-E5, X-T5, X-T30 III, X-T30, X-S10, X-H2/H2S, GFX100 II |
| [Fuji X Weekly — Film Recipes](https://apps.apple.com/us/app/fuji-x-weekly-film-recipes/id1539047257) | iOS, Android | Free; Patron $19.99/yr (filters, favorites, multi-recipe send) | 4.42 / 120 | 2026-10-09 | **Yes** (since 2026-08-20) | USB-C PTP "ATC RTP"; write only, no read-back; 20 bodies (X-Trans IV except X-T3/X-T30, all X-Trans V, newer GFX) |
| [Fuji Recipes – Film simulation](https://apps.apple.com/us/app/fuji-recipes-film-simulation/id6761905712) | iOS/iPadOS, Mac, Android, web library | Free; Pro $8.99/mo, $34.99/yr, $89.99 lifetime | 4.69 / 58 | 2026-10-12 | **Yes** | USB-C + Bluetooth (since v1.18, 2026-09-25); read + write + backup; folder → all 7 slots; RAW via the camera |
| [Huginn – Film Sim Recipes](https://apps.apple.com/us/app/huginn-film-sim-recipes/id6797092369) | iOS/iPadOS 17+ | Free (USB write); Pro $4.99/mo, $29.99/yr (wireless) | 4.25 / 4 | 2026-11-02 | **Yes** | Bluetooth ("first wireless", 2026-09) + USB-C; all 7 slots in one pass; per-slot backup |
| [Color X: Film Recipes](https://apps.apple.com/us/app/color-x-film-recipes/id6799859869) | iOS | Free (no IAP listed) | 2.60 / 5 | 2026-10-10 | **Yes** | Bluetooth + USB; C1–C7, FS1–FS3, video settings; 14 bodies |
| [Simu — Film Simulation Recipes](https://apps.apple.com/us/app/simu-film-simulation-recipes/id6811793155) | iOS/iPadOS (USB-C) | Free; $4.99 one-time "Unlock Camera Writing" | – / 0 | 2026-11-04 | **Yes** | USB-C; kit of 7; backup before + verify after + undo; 20 bodies |
| [Community for Fuji](https://apps.apple.com/us/app/community-for-fuji/id6798434965) | iOS/iPadOS + Mac build | Free; Pro $24.99/yr, $49.99 lifetime | 3.40 / 5 | 2026-10-29 | **Yes** | USB; read + write C1–C7; recipes matched to sensor |
| [SimuLook: Film Recipes](https://apps.apple.com/us/app/simulook-film-recipes/id6795308608) | iPhone, iPad, Mac | Free; Premium $6.99/mo, $59.99/yr, $129.99 founder lifetime | – / 0 | 2026-10-22 | **Yes** (Premium) | Read/backup C1–C7 free; write **X100VI fw 1.32 only** |
| [Fujirama – Fuji Recipes & RAW](https://apps.apple.com/us/app/fujirama-fuji-recipes-raw/id6762408057) | iOS/iPadOS | Free; Premium $39.99 lifetime | – / 0 | 2026-10-31 | **Yes** | Bluetooth slots + backup/restore; live view, card browser, RAW via the camera over USB |
| [Fuji Frame](https://apps.apple.com/us/app/fuji-frame/id6780652234) | iOS | Free; Pro $7.99/mo | 5.0 / 1 | 2026-06-30 | **Yes** | USB-C; read/write/rename/clear slots; AI recipe from an image or text |
| [Fuji101 – Fujifilm Recipes](https://apps.apple.com/us/app/fuji101-fujifilm-recipes/id6683306695) | iOS 15.2+ | Free (no IAP listed) | 1.0 / 1 | 2026-09-09 | **Yes** ("experimental") | USB; read slot first, report rejected values; folder → camera |
| [Bento: Film Recipes & Transfer](https://apps.apple.com/us/app/bento-film-recipes-transfer/id6789744125) | iOS | Free (no IAP listed) | – / 0 | 2026-09-10 | **Yes** | USB; per-setting report; verified X100VI only |
| [Filmsim Recipes](https://apps.apple.com/us/app/filmsim-recipes/id6775952554) | iOS, Android | Free; Pro $4.99–8.99/mo, $29.99–59.99/yr | 1.57 / 7 | 2026-11-02 | **Yes** (per its site) | USB on 25 bodies, Bluetooth on X100VI ([site](https://filmsimrecipes.com/app/)); the store text doesn't say so |
| [Filos.](https://apps.apple.com/us/app/filos/id6761323774) | iOS | Free | – / 0 | 2026-06-15 | **Yes** | USB-C "Loadouts" of 7; X-Trans IV |
| [Camset – Fuji & Ricoh Recipes](https://apps.apple.com/us/app/camset-fuji-ricoh-recipes/id6502640665) | iOS | Free; $2.99/mo, $6.99/yr, $19.99 lifetime | 4.88 / 34 | 2025-12-16 | Ricoh GR II only | Fuji: notebook only |
| [Film Kitchen](https://apps.apple.com/us/app/film-kitchen/id6785587484) | iOS | Free | 5.0 / 1 | 2026-10-12 | Renders only | USB-C RAW conversion in the camera; no slot writing claimed |
| [Recipe Lab: RAF Recipes](https://apps.apple.com/us/app/recipe-lab-raf-recipes/id6822887449) | iOS (USB-C) + web | 10 free JPEGs; $17.99/yr | – / 0 | 2026-11-03 | Renders only | X100VI over USB-C |
| [Film Recipes App for Fujifilm (film.recipes)](https://apps.apple.com/us/app/film-recipes-app-for-fujifilm/id6741566252) | iOS | **$24.99 paid** | 3.86 / 7 | 2026-01-14 | No | 800+ recipes catalogue |
| [FILMEMO – Fuji X/GFX](https://apps.apple.com/us/app/filmemo-fuji-x-gfx-cameras/id1571724917) | iOS | Free + ads; Premium subscription | 3.92 / 12 | 2026-04-26 | No ("won't save you the trouble of transferring") | – |
| [FxjiMate](https://apps.apple.com/us/app/fxjimate-for-fujifilm-users/id6469689080) | iOS | Free + one-time purchase | 4.0 / 1 | 2025-11-06 | No | EXIF import, QR sharing |
| [Fuji Recipe (YU FANG)](https://apps.apple.com/us/app/fuji-recipe/id1636605356) | iOS | Free | – / 0 | 2026-09-26 | No | 13 parameters, 5 photos, QR |
| [Simulated Film](https://apps.apple.com/us/app/simulated-film-film-recipes/id6755539247) | iOS/iPadOS | Free (3 recipes); one-time Premium | 5.0 / 3 | 2026-08-22 | No | Fuji + Ricoh notebook, frames, QR, iCloud |
| [Fuji Pic – Film Recipes](https://apps.apple.com/us/app/fuji-pic-film-recipes/id6780827261) | iOS | Free | – / 0 | 2026-11-03 | No | Curated, tested catalogue + guides |
| [Film Recipes: Fuji X Looks](https://apps.apple.com/us/app/film-recipes-fuji-x-looks/id6801854532) | iOS | Free; weekly sub or one-time Premium | – / 0 | 2026-08-18 | No | JPEG + **HEIF** extraction, "Not recorded" honesty, A/B preview |
| [FujiRecipes: Camera Recipes](https://apps.apple.com/us/app/fujirecipes-camera-recipes/id6770327167) | iOS | 1 free/week; $7.99/mo, $39.99/yr, $79.99 lifetime | – / 0 | 2026-07-15 | No | AI recipe from scene, weather and light |
| [Fujifilm Photo Assistant](https://apps.apple.com/us/app/fujifilm-photo-assistant/id6763054898) | iOS | $0.99 | 5.0 / 1 | 2026-09-12 | No | AI recommends a recipe from a photo |
| [Recipe Shuffle](https://apps.apple.com/us/app/recipe-shuffle/id6743686477) | iOS | Free | 5.0 / 1 | 2026-10-15 | No | Random X100VI recipes |
| [SOOC Camera Recipes](https://apps.apple.com/us/app/sooc-camera-recipes/id6758262512) / [Hikari](https://apps.apple.com/us/app/hikari-film-recipes/id6773081005) ($3.99) / [Recipe Room](https://apps.apple.com/us/app/recipe-room/id6757921646) | iOS | Free / paid | – / 0 | 2026 | No | Notebooks / social feed |
| [Fuji RAF Preview & Recipe](https://apps.apple.com/us/app/fuji-raf-preview-recipe/id6761335653) | **Mac** (menu bar) | $4.99 | – / 0 | 2026-08-10 | No | QuickLook for RAF + recipe readout per folder |
| [F Sort](https://apps.apple.com/us/app/f-sort/id6820890741) | **Mac** | $1.99 | – / 0 | 2026-10-28 | No | Sorts files into folders by film simulation |
| [FUJIFILM XApp](https://apps.apple.com/us/app/fujifilm-xapp/id1586089681) | iOS, Android | Free | 4.16 / 3,618 | 2026-07-06 | Whole-camera backup/restore only | Bluetooth + Wi-Fi; no recipe UI |
| [FUJIFILM Camera Remote](https://apps.apple.com/us/app/fujifilm-camera-remote/id793063045) | iOS (legacy) | Free | 1.39 / 3,265 | 2025-10-21 | No | Legacy Wi-Fi remote/transfer |
| [X half](https://apps.apple.com/us/app/x-half/id6743934694) | iOS, Android | Free | 2.10 / 30 | 2026-09-30 | No | Bluetooth/Wi-Fi transfer, "film camera mode" development |

Other recipe apps for other brands, for context: [AlphaLuma](https://apps.apple.com/us/app/alphaluma-film-recipes/id6758998655) (Sony, made by FujiStyle's developer, writes Creative Looks over BT/Wi-Fi/USB; 4.43/7), [AlphaLook](https://apps.apple.com/us/app/alphalook-sony-film-recipes/id6802362145) (Sony, 5.0/4), [Ricoh Recipes](https://apps.apple.com/us/app/ricoh-recipes-jpeg-settings/id1580485682) (Ritchie Roesch, 4.84/25).

## Off-store and desktop products

| Product | Platform | Price | W? | How | Source |
|---|---|---|---|---|---|
| **FUJIFILM X RAW Studio** | Mac, Windows | Free | Partly: saves a custom profile to a C slot | USB tether; only some settings (film sim, DR, grain, WB, push/pull…); availability depends on firmware | [Tuts+](https://photography.tutsplus.com/tutorials/profile-raw-photos-in-xraw--cms-37087), [fotowissen 2026-09-28](https://www.fotowissen.eu/?p=149716) |
| **FUJIFILM Tether App** (absorbed **X Acquire**) | Mac, Windows | Free | Whole-camera restore only | USB, `.DAT` file; everything except date/time, custom WB, Q menu | [Fujifilm X Acquire page](https://fujifilm-x.com/support/download/software/x-acquire/), [Fujifilm story](https://www.fujifilm-x.com/global/stories/fujifilm-x-acquire-backup-restore-camera-setting/) |
| **FujiShare** | iOS TestFlight beta; Android planned | Free | **Yes** | USB; restore point first, writes each setting and reads it back; 10 bodies (GFX untested) | [Notebookcheck 2026-08-26](https://www.notebookcheck.net/New-FujiShare-beta-writes-7-Fujifilm-film-recipes-to-C1-C7-over-USB-with-read-back-checks.1378419.0.html) |
| **Ukiyo** | Mac (Tauri; build from source), MIT | Free | Yes, but slot writes not yet tested on a real camera | USB PTP; settings editor, PTP "Lab" mapper, CLI + MCP server; X-T5 tested | [github.com/noahkiss/ukiyo](https://github.com/noahkiss/ukiyo) |
| **FilmCase** | macOS / Ubuntu (local Django) | Free, open source | **Yes** | USB; tested on X-S10; JPEG catalogue, QR cards | [FujiRumors 2026-05-26](https://www.fujirumors.com/the-free-filmcase-app-builds-a-film-simulation-recipe-catalog-and-gallery-from-your-images-and-loads-recipes-to-your-camera/), [github.com/gosku/Filmcase](https://github.com/gosku/Filmcase) (77★) |
| **Fudge** (Daniel C / petabyt) | Android (Play beta, F-Droid); library libfuji: USB, Wi-Fi, BLE | Free, GPL | No: film sim / properties still on the roadmap | – | [github.com/petabyt/fudge](https://github.com/petabyt/fudge), [libfuji](https://github.com/petabyt/libfuji) |
| Other GitHub projects (from a GitHub search, 2026-11-04) | – | Free | Mostly yes, USB PTP | FujiRecipesMac (macOS, X100VI), FujiSync (Android), kata (Flutter Android/Linux), ozure (CLI), fuji-xt30ii-webusb (WebUSB), plus protocol write-ups (ILFforever/fujifilm-ptp-recipes, zgrimz/fujifilm-ptp-reference, Junsudo/fuji-ptp-notes for GFX100RF) | [GitHub search](https://github.com/search?q=fujifilm+C1-C7&type=repositories) |

## Per-app notes

### FujiStyle – Film Recipes Frame (罡 丁) — the category leader by ratings
- URL: https://apps.apple.com/us/app/fujistyle-film-recipes-frame/id6504739559 · read 2026-11-04
- iOS/iPadOS (on Mac as an iPad app) and Android (`com.fujistylelead.global`, [appgoblin](https://appgoblin.info/apps/com.fujistylelead.global)). **4.79★ / 395 US**, the most ratings of any third-party app. v1.3.46, 2026-09-18. Listed as an Editor's Choice "App of the Week". Pro costs $3.99/mo, $9.99/quarter or $14.99/yr.
- Pitch: an all-in-one Fuji companion with recipe notes, EXIF recipe recognition, borders/watermarks and a community.
- Features: unlimited local recipes; one-tap recipe recognition from a JPEG (free since 1.3.46); 100+ Fuji-style borders and watermarks; community; recipe cards.
- **Writes:** yes. USB to C1–C7 with custom slot names (Pro). "Wireless Recipe Import (Beta)" since 1.3.46 for X-T50, X-S20, X100VI, X-E5, X-T5, X-T30 III, X-T30, X-S10, X-H2/H2S and GFX100 II; first use needs Pairing Registration in the camera menu. Writing was first reported June 2025 ([Notebookcheck](https://www.notebookcheck.net/Developer-makes-one-tap-Fuji-recipe-transfers-from-phone-to-camera-possible.1040911.0.html)): tested on 12+ bodies.
- Top complaint: **the write doesn't work or freezes** ("not once has it successfully applied a recipe to my X-T5", 1★, 2026-06-22; X-E5 and X-T5 connection failures; 2★ "always freezes"). Also a 5-minute countdown timer on the paywall, and imported recipes missing settings.

### Fuji X Weekly — Film Recipes (Ritchie Roesch) — the incumbent with the brand
- URL: https://apps.apple.com/us/app/fuji-x-weekly-film-recipes/id1539047257 · read 2026-11-04
- iOS and Android. **4.42★ / 120**. v1.16.2, 2026-10-09; first released 2020-12. Patron costs $19.99/yr.
- Pitch: 100+ (now many more) film simulation recipes from the best-known recipe author.
- Features: catalogue filtered by sensor; Patron early-access recipes; favorites and filters (Patron); custom recipes.
- **Writes:** yes, since **2026-08-20** ([announcement](https://fujixweekly.com/2026/08/20/new-send-recipes-to-your-camera-directly-from-the-fuji-x-weekly-app/)). It uses "ATC RTP" over PTP and a USB-C cable, with the camera in USB RAW CONV./BACKUP RESTORE mode. Android followed on 2026-09-09 ([post](https://fujixweekly.com/2026/09/09/fuji-x-weekly-app-to-camera-recipe-transfer-now-on-android/)). Sending one recipe is free; sets need Patron. It doesn't send ISO or exposure compensation, video recipes, or X-E5 FS1–FS3. It **can't read back** existing slots and overwrites without warning ([fotowissen test](https://www.fotowissen.eu/?p=149716)). It supports 20 bodies: X-Pro3, X100V/VI, X-T4, X-S10, X-E4, X-T30 II, X-H2/H2S, X-T5, X-S20, X-T50, X-M5, X-E5, X-T30 III and GFX100S, 50S II, 100 II, 100S II, 100RF.
- **Fujifilm stance:** Roesch says Fujifilm told him unlicensed software that connects to the camera can void the warranty, and that Fujifilm declined to license the feature because it only licenses large companies.
- Top complaint: paying a subscription just to filter ("$20 Subscription to unlock the ability to filter?!"), saved recipes vanishing, crashes on open, and clunky free-text entry for custom recipes.

### Fuji Recipes – Film simulation (Bechir Kaddech, fujirecipes.co)
- URL: https://apps.apple.com/us/app/fuji-recipes-film-simulation/id6761905712 · site https://fujirecipes.co/ · read 2026-11-04
- iPhone, iPad, Mac and Android, plus a web recipe library. **4.69★ / 58**. v1.21, 2026-10-12; released 2026-04. Pro costs $8.99/mo, $34.99/yr or $89.99 lifetime.
- Pitch: "Read, edit, and install custom recipes", plus the Darkroom.
- Features: read, write and back up slots; write a folder of 7 in one action; Darkroom renders a RAF through the camera over USB-C; wireless import of JPEG/RAW (Bluetooth pairing, then Wi-Fi); community sharing with up to 5 photos.
- **Writes:** yes. USB-C on X100VI, X-T5, X-T50, X-E5, X-H2/H2S, X-S20, X-M5, X-T30 III and X-T30 II. **Bluetooth since v1.18 (2026-09-25)**, extended to X-S20, X-S10, X-T50, X-T30 III, X-M5, X-E4 and X-Pro3 in the latest notes.
- Top complaint: the **install doesn't work on iOS, and there's no support reply** (1★, X-T50); "sitting here for 20 mins waiting to install"; recipes and photos taken from creators without credit (1★).

### Huginn – Film Sim Recipes (GATZ Holdings / "The Forge")
- URL: https://apps.apple.com/us/app/huginn-film-sim-recipes/id6797092369 · site huginnfilm.app · read 2026-11-04
- iOS/iPadOS 17+. **4.25★ / 4**. v1.0.22, 2026-11-02; released 2026-09-09. Pro costs $4.99/mo or $29.99/yr (founder price $3.99 / $19.99 per [pttl](https://www.pttl.gr/en/huginn-fujifilm-film-recipes-wireless-app/)).
- Pitch: "Choose the look, then send it to your Fujifilm wirelessly."
- Features: "film palettes" of 7 loaded in one pass; Bluetooth remote control of ISO, aperture, EC and drive, with an intervalometer; per-slot backup and restore; "virtual bracketing" (one RAF through the whole library, rendered by the camera); shoot planning (light, shot list); OCR and share codes.
- **Writes:** yes. It claims to be the first over **Bluetooth**, "even with the camera switched off in your bag" (Pro). USB-C writes are free. Supports recent X bodies with USB-C and C1–C7; no public model list. [PetaPixel 2026-09-12](https://petapixel.com/2026/09/12/this-new-app-is-the-first-to-send-custom-recipes-to-fujifilm-cameras-wirelessly/) (403 to the fetcher). [FujiRumors](https://www.fujirumors.com/?p=144863) disputes the "first" claim and notes there's no per-camera filtering.
- Top complaint: "wasn't able to setup camera and no way to troubleshoot… you also have to pay pro right away" (2★).

### Simu — Film Simulation Recipes (Bai-Kuan Yeh)
- URL: https://apps.apple.com/us/app/simu-film-simulation-recipes/id6811793155 · read 2026-11-04
- iOS/iPadOS (USB-C). No ratings yet. v1.2.1, 2026-11-04; released 2026-09-22. **$4.99 one-time** unlocks writing and RAW development.
- Pitch: "Less typing. More shooting." Screenshot → recipe → camera.
- Features: **OCR of Instagram, Threads, Xiaohongshu and web screenshots (up to 20 at once)**; read from a camera JPEG/HEIF or another camera's C1–C7 backup; kits of 7; every slot backed up before writing, verified after, undoable; RAW developed by the camera (X100VI full, others beta); share by code/QR, including a recipe embedded in a camera original that friends can view in a browser.
- **Writes:** yes, USB, to C1–C4, C1–C6 or C1–C7 depending on the model. 20 bodies: X100VI, X100V, X-T5, X-T50, X-T4, X-T30 III, X-T30 II, X-E5, X-E4, X-Pro3, X-H2/H2S, X-S20, X-S10, X-M5, GFX100RF, GFX100 II, GFX100S II, GFX100S, GFX50S II.
- Complaints: none yet. **Closest to our idea** (import from social → write over USB, one-time price, privacy).

### Color X: Film Recipes (Yunus Türkyılmaz)
- URL: https://apps.apple.com/us/app/color-x-film-recipes/id6799859869 · read 2026-11-04
- iOS. **2.6★ / 5**. v1.0.10, 2026-10-10. Free; no IAP listed.
- Features: 289 photo and 53 video recipes; scan a recipe card or **Instagram caption**; Bluetooth and USB writing to C1–C7, **FS1–FS3** and video settings; pull a C mode from the camera; community with sample photos verified against EXIF.
- **Writes:** yes, over Bluetooth (needs current firmware) and USB. Bodies: X-T3, X-T4, X-T5, X-T50, X-T30 III, X-H2/H2S, X-S20, X-M5, X-Pro3, X-E5, X100V, X100VI, GFX100RF.
- Top complaints: recipes taken without the creators' consent; **AI-generated sample photos**; no X-T3-or-older support (although the listing names the X-T3).

### Community for Fuji (Cristian Cruz, fuji-community.com)
- URL: https://apps.apple.com/us/app/community-for-fuji/id6798434965 · read 2026-11-04
- iOS/iPadOS plus a Mac build ("Requires macOS 13.0"). **3.4★ / 5**. v1.10.3, 2026-10-29. Pro costs $24.99/yr or $49.99 lifetime.
- Features: USB install to C1–C7 and read/save existing slots; scan a recipe from a screenshot, blog or print; browse the memory card and attach photos to recipes; catalogue matched to sensor generation; no account to browse.
- Top complaint: "Too expensive to ever be good… vibe coded apps" (1★).

### SimuLook: Film Recipes (Yusuf Yılmaz)
- URL: https://apps.apple.com/us/app/simulook-film-recipes/id6795308608 · read 2026-11-04
- iPhone, iPad and **Mac** (universal). No ratings. v1.0.13, 2026-10-22. Premium costs $6.99/mo or $59.99/yr; founder lifetime $129.99.
- Features: read a recipe from a JPEG; up to 6 software previews with editing, frames and text; community (publish, follow, comment, message); free reading and backup of C1–C7.
- **Writes:** Premium only, "verified camera writing" limited to the **X100VI on firmware 1.32**.

### Fujirama – Fuji Recipes & RAW (Alican Toprak)
- URL: https://apps.apple.com/us/app/fujirama-fuji-recipes-raw/id6762408057 · read 2026-11-04
- iOS/iPadOS. No ratings. v1.10.0, 2026-10-31. **$39.99 lifetime** Premium.
- Pitch: "Your camera can do more than its official app lets you." It's an XApp replacement with recipes.
- Features: load recipes over **Bluetooth**; read and back up slots; card browser with download manager; live-view remote; RAW development through the camera over USB; Google Drive backup from the camera; GPS and clock sync; recipe cards and vertical reels for Instagram/TikTok.

### Fuji Frame (Brandon Chase)
- URL: https://apps.apple.com/us/app/fuji-frame/id6780652234 · read 2026-11-04
- iOS. 5★ / 1. v1.0.1, 2026-06-30. Pro costs $7.99/mo.
- Features: **AI recipe from a movie still, film scan or text**; USB-C read of slots including names; write, rename and clear slots; "in sync" indicator; account sync.

### Fuji101 – Fujifilm Recipes (Mykola Starynskyi)
- URL: https://apps.apple.com/us/app/fuji101-fujifilm-recipes/id6683306695 · read 2026-11-04
- iOS 15.2+. 1★ / 1 (no text). v2.1, 2026-09-09. Free.
- Features: USB write that **reads the slot first and lists rejected settings**; import from the camera; paste-as-text and photo OCR; folders sent in one pass; whole-library export; 10 languages including Ukrainian. Writing is flagged "experimental", with an explicit acceptance step.

### Bento: Film Recipes & Transfer (Yannick Pulver)
- URL: https://apps.apple.com/us/app/bento-film-recipes-transfer/id6789744125 · read 2026-11-04
- iOS. No ratings. v1.0.1, 2026-09-10. Free.
- Features: community catalogue; USB write to C1–C7 with a per-setting report (some settings aren't exposed over USB); read presets; side-by-side RAF renders by the camera. Verified on the X100VI only.

### Filmsim Recipes (Vitor Lopes, filmsimrecipes.com)
- URL: https://apps.apple.com/us/app/filmsim-recipes/id6775952554 · site https://filmsimrecipes.com/app/ · read 2026-11-04
- iOS and Android. **1.57★ / 7**. v1.3.9, 2026-11-02. Free; Pro $4.99/mo or $29.99/yr (the store also lists $8.99/mo and $59.99/yr tiers).
- **Writes:** the site says USB on 25 bodies (X-T3 through GFX100RF) and Bluetooth on the X100VI; free users can send over USB. 156 recipes; Recipe Lab (RAF through the camera); camera gallery.
- Top complaints: "$60/year for a gallery of film sims taken from other people is insane"; the update wiped saved recipes and creators; "Can't connect to camera".

### Filos. (Nikolaos Kontis)
- URL: https://apps.apple.com/us/app/filos/id6761323774 · read 2026-11-04 · iOS, free, v1.1 (2026-06-15), no ratings.
- Scans the photo library and **groups photos by identical recipe** (nice idea for a gallery); USB-C "Loadouts" of 7 written to the slots; X-Trans IV.

### Render-only apps: Film Kitchen and Recipe Lab
- Film Kitchen (McKenna Fuller): https://apps.apple.com/us/app/film-kitchen/id6785587484. iOS, free, 5★/1, 2026-10-12. Applies recipes to RAWs with the camera's processor over USB-C and saves the results back to the card. No slot writing claimed.
- Recipe Lab: RAF Recipes (Andrea Aloisi): https://apps.apple.com/us/app/recipe-lab-raf-recipes/id6822887449. iOS, 10 free JPEGs then $17.99/yr, released 2026-10-26. X100VI only; recipes sync to getrecipelab.app.

### Catalogue and notebook apps (no camera writing)
- **Film Recipes App for Fujifilm (film.recipes, Justin Gould)**: https://apps.apple.com/us/app/film-recipes-app-for-fujifilm/id6741566252. **$24.99 paid**, 3.86★/7, 800+ recipes. Top complaint: "I paid… thinking it would have auto camera loading" (1★, 2026-02-09).
- **FILMEMO (MAPLE LLC)**: https://apps.apple.com/us/app/filmemo-fuji-x-gfx-cameras/id1571724917. 3.92★/12, ads plus a subscription. It says plainly that it won't save you the trouble of transferring. Complaint: subscription.
- **Camset (哲 蒋)**: https://apps.apple.com/us/app/camset-fuji-ricoh-recipes/id6502640665. 4.88★/34, $19.99 lifetime. Fuji + Ricoh; "sync to camera" only for Ricoh GR II. Complaint: slow to add new recipes.
- **FxjiMate, Fuji Recipe (YU FANG), Simulated Film, SOOC, Hikari, Fuji Pic, Recipe Room**: notebooks or curated catalogues, often with EXIF import and QR sharing. Fuji Pic emphasises "tested, not guessed" with sample photos per body. Hikari only links out to third-party recipes for copyright reasons, which is a useful policy precedent.
- **Film Recipes: Fuji X Looks**: https://apps.apple.com/us/app/film-recipes-fuji-x-looks/id6801854532. Notable for **HEIF** MakerNote reading and a "Not recorded" (never guess) policy. Limit of 3 extractions a day on the free tier.
- **AI recipe generators**: FujiRecipes (fujirecipes.io, $39.99/yr; from a scene description plus weather and sun phase), Fujifilm Photo Assistant ($0.99; from a photo), Fuji Frame (above).

### Mac App Store (native)
- **Fuji RAF Preview & Recipe** (Nick Roodenrijs, $4.99): https://apps.apple.com/us/app/fuji-raf-preview-recipe/id6761335653. QuickLook for RAF on macOS 13–15 (Tahoe handles RAF natively), recipe overview per folder, batch export of embedded JPEGs. Reads only.
- **F Sort** (Lucas Farah, $1.99, 2026-10-28): https://apps.apple.com/us/app/f-sort/id6820890741. Sorts JPEG/HEIF/RAF into Date › Film Simulation folders. Reads only.
- Universal apps with a Mac build: SimuLook and Community for Fuji. Everything else runs as "Designed for iPad / not verified for macOS" on Apple Silicon, which means a USB camera connection on the Mac is unproven for those apps.

### Fujifilm first-party
- **FUJIFILM XApp**: https://apps.apple.com/us/app/fujifilm-xapp/id1586089681. **4.16★ / 3,618**. v2.7.6, 2026-07-06. Bluetooth and Wi-Fi transfer, remote, location and time sync, firmware updates, activity diary, and **backup/restore of all camera settings**. It has **no recipe or film simulation feature**: the release notes for 2.7.1–2.7.6 add only activity, location and instax counts. The workaround of keeping several 7-recipe sets as separate whole-camera backups is described on [FujiRumors 2026-08-11](https://www.fujirumors.com/?p=144228) and [FXW](https://fujixweekly.com/tag/recipe-app/). The catches: backups hold *every* setting, a firmware update can make them incompatible, and they can be lost when you change phones. fotowissen found cable backup failed on the X-T5, and wireless backup worked only after about 45 minutes of retries. Recent reviews are dominated by 1★ connection failures ("It works 1/10 times", 2026-10-18; "Connection to camera never worked", 2026-10-17).
- **FUJIFILM Camera Remote** (legacy): 1.39★ / 3,265. No recipe features.
- **X half** app: https://apps.apple.com/us/app/x-half/id6743934694. 2.1★ / 30. Transfer and "Film Camera mode" development only; no recipe import. Complaints are about connection.
- **Camera firmware:** no Fujifilm body imports recipe files. The only official routes are typing settings into the menus, X RAW Studio saving a profile to a C slot, or restoring a whole-camera `.DAT` / XApp backup. (X100VI firmware 1.31 is the latest listed on [Fujifilm's page](https://fujifilm-x.com/global/support/download/firmware/cameras/x100vi), 2025-07-26; SimuLook references 1.32.)

## Implications for our idea (scout's read)
1. "Detect the camera, read C1–C7, edit, write" is **done by 14 shipped iOS apps**, FXW among them (free for one recipe at a time). Differentiation has to come from somewhere else: **a native Mac app** (empty shelf on the Mac App Store), reliability (backup before writing, read-back verification, undo, as Simu, FujiShare and Fuji101 do), and taste and minimal UI.
2. Instagram/TikTok import exists only as **screenshot OCR**. No app found ingests a reel or video URL (transcribe or OCR video frames). That's still open.
3. Pricing anchors: a one-time unlock of $4.99 (Simu) to $39.99 lifetime (Fujirama); subscriptions run $15–60/yr and draw the most complaints.
4. Risks: Fujifilm's warranty stance; Bluetooth flakiness (XApp's reviews); recipe copyright and attribution backlash (several 1★ reviews call apps out for copying recipes from creators without credit).
