# Web scout: Fujifilm film-simulation recipe apps

All sources read 2026-11-04 with WebSearch / WebFetch (no Exa). "Per X" means the claim comes from that source alone and was not checked anywhere else. PetaPixel and openPR returned 403, so their claims come from search snippets and other articles that cite them.

## 0. Headline findings

- **The market moved in August–September 2026.** Writing recipes to the camera over a USB-C cable used to be rare. It is now a table-stakes feature. Fuji X Weekly (Aug 20, iOS; Android Sep 9), FujiShare (TestFlight, Aug 26), Filmsim, Fuji Recipes (Bechir Kaddech), FujiStyle, Fuji Frame, Simu and Filos all do it. Huginn (Sep 12) claims to be the first to send recipes over Bluetooth.
- **Every one of these apps uses the same mechanism.** The camera is set to *Connection Mode → USB RAW CONV./BACKUP RESTORE*, and the app sends PTP vendor properties (bank selector `0xD18C`, settings `0xD18E–0xD1A5`). This is the same channel X RAW Studio uses. There is no Fujifilm SDK and no licence.
- **Fujifilm's position: unlicensed software "will void the camera's limited product warranty".** Fujifilm told Ritchie Roesch this by phone, and FujiShare and others repeat the warning. No official recipe-sync feature exists in XApp: none of the XApp release notes from 1.2.0 (2023) to 2.7.6 (Jul 2026) mention recipes. XApp only has whole-camera Backup/Restore (same model only; excludes network settings and custom WB).
- **Fujifilm did adopt the word "Recipe" officially** on the X-E5 (June 2025): FS1–FS3 "FS RECIPE" dial slots plus C1–C7. Third-party tools cannot write the FS slots (per Fuji X Weekly).
- **Mac is the gap.** Nearly every polished app is iPhone-first. Some App Store listings show "Mac (Apple silicon)" but also "Not verified for macOS". The only Mac-native options for writing to the camera are developer projects: Ukiyo (Tauri/Rust, pre-release), FilmCase (local Django), Latent and FilmKit (WebUSB in Chromium only), ozure and fujiapp (CLI).

## 1. Apps and tools (roundup)

### iOS / Android apps that write recipes to the camera

| App | Dev | Platforms | Transfer | Price | Notable | Source |
|---|---|---|---|---|---|---|
| Fuji X Weekly (FXW) | Fuji X Weekly / Ritchie Roesch | iOS, iPadOS, Android (8+) | USB-C via PTP ("ATC RTP"), iOS from Aug 20 2026, Android from Sep 9 2026 | Free; Patron $19.99/yr US (CA$26.49, €21.99 regionally) | 400+ recipes, ~150k users. Free tier: browse + sample photos + compatible cameras + send ONE recipe at a time. Patron: filter by sensor/camera/sim/WB/DR, favorites, custom recipes, early access (~12), **recipe sets** (send several at once; Starter/Street/Travel included) | https://fujixweekly.com/app/ ; https://fujixweekly.com/2026/08/20/new-send-recipes-to-your-camera-directly-from-the-fuji-x-weekly-app/ ; https://fujixweekly.com/2026/09/09/fuji-x-weekly-app-to-camera-recipe-transfer-now-on-android/ |
| FujiShare | anon (r/FujifilmX u/Rude_Shoulder_2895) | iOS TestFlight beta; Android planned | USB; writes 7 recipes to C1–C7 in one pass, **reads each setting back**, saves a restore point first | Free in beta, paid later | Reads recipe from JPEG MakerNote, so you post a recipe "without typing". Community feed credits every maker in a pack. Wireless photo import over BLE + Wi-Fi. Writes: X100V, X100VI, X-T5, X-T50, X-E5, X-M5, X-T30 III, X-H2, X-E4, X-S10 | https://fujishare.com/ ; https://www.notebookcheck.net/New-FujiShare-beta-writes-7-Fujifilm-film-recipes-to-C1-C7-over-USB-with-read-back-checks.1378419.0.html (Aug 26 2026, upd. Oct 5) |
| Filmsim (filmsimrecipes.com) | — | iOS, Android | USB to C1–C7; **Bluetooth on X100VI only** | Free; Pro $4.99/mo or $29.99/yr | 156 recipes. Camera Gallery (browse the card over USB), Recipe Lab (renders your RAF through the camera), Studio (layouts for Stories/posts), community feed with recipes, filter by camera + mood. Older bodies get a manual checklist | https://filmsimrecipes.com/app/ ; https://filmsimrecipes.com/ |
| Fuji Recipes – Film simulation | Bechir Kaddech | iPhone, iPad, Mac (M1+) listed | USB-C read/edit/write C1–C7; Bluetooth on X-S20, X-S10, X-T50, X-T30 III, X-M5, X-E4, X-Pro3 | Free; Pro $8.99/mo, $34.99/yr, $89.99 lifetime | **Renders RAW through the camera** over USB-C. Wi-Fi photo import after BLE pairing. Darkroom edits, frames. **Recipe scanning with the phone camera (v1.10)**. iCloud sync. 4.7★ (58 ratings). v1.21 on Oct 12 | https://apps.apple.com/us/app/fuji-recipes-film-simulation/id6761905712 |
| FujiStyle – Film Recipes Frame | FujiStyle | iOS, Android (Mac listed) | USB one-tap write to C1–C7 (about a year before FXW) | IAP | 1,000+ community recipes, film frames. **Web Recipe Reader**: pulls 14 parameters out of the JPEG MakerNote. 4.8★ (178 ratings). Fuji X Weekly accuses it of aggregating without credit (not named, implied) | https://apps.apple.com/us/app/fujistyle-film-recipes-frame/id6504739559 ; https://www.fujistyleapp.com/tools/recipe-reader/ |
| Fuji Frame | Brandon Chase | iPhone (Mac listed, "not verified") | USB-C: reads C1–C7 live **with names**, writes, renames, clears | Free; Pro €8.99/mo | **AI recipe** from a reference image (film still or scan) or from a text description | https://apps.apple.com/fi/app/id6780652234 |
| Simu (Film Recipes) | Bai-Kuan Yeh | iOS | USB to C1–C7, verified on X100VI | Free, no account, no cloud, no subscription | **Reads a recipe from a screenshot** on the device (OCR in EN / JA / zh-Hant / zh-Hans), flags uncertain values. Entry points: share sheet, Photos, Shortcuts action. The closest existing thing to "import from a reel" | search snippet of the App Store listing via https://www.similarweb.com/app/apple/6811793155/ (listing not fetched directly) |
| Huginn | The Forge (also makes Valkyrie, Muninn) | iPhone, iPad | **Bluetooth** to C1–C7, auto-reconnect | Free core; Pro $19.99/yr founder rate, then $29.99 | Claims to be the first wireless sender (Sep 12 2026). Community library with creator credit, golden-hour planner, iCloud. FujiRumors critique: no filter by camera model, unclear compatibility, pairing kicks XApp off | https://stack-archive.com/blog/huginn-fujifilm-recipe-wireless-app-2026/ ; https://www.fujirumors.com/this-app-loads-recipes-wirelessly-to-your-fujifilm-camera-but-here-are-my-doubts/ |
| Filos | — | iPad listing (Mac "not verified") | USB-C to custom slots | ? | Extracts recipes from JPEG EXIF. First released Apr 2026 | https://mwm.ai/apps/filos/6761323774 |

### Library / editor apps (no camera write found)

- **Film Recipes App for Fujifilm (film.recipes):** by Justin Gould. $24.99 one-time ($14.99 earlier). 800+ of his own recipes, X-Trans IV/V. Manual entry only. Roesch explicitly says it is *not* a copy of his work. https://apps.apple.com/us/app/id6741566252
- **Simulated Film: Film Recipes:** Pandesal Bytes. Free, 3 recipes; $4.99 unlimited. Fuji X-Trans I–V **plus Ricoh GR III/IIIx/IV**. Frame designer, sample photos attached per recipe, compare two photos, lookbook PDF, QR / JSON import, beta import from JPG, iCloud. https://apps.apple.com/us/app/-/id6755539247
- **FujiRecipes (fujirecipes.io):** web + iPhone app. 39 recipes / 15 cameras / 8 scenes. The AI composes a recipe for the current weather, time and place. **Photo or screenshot → settings.** Recipes saved into "rolls". https://fujirecipes.io/
- Others seen in store results, not investigated: Camset (Fuji & Ricoh, Korean dev), Fuji101, FxjiMate (reads recipes from JPEGs), FILMEMO (Fuji X/GFX), Fuji Pic, Fuji Simulation Recipes (id1555208985), fujirecipes.co (community site). Store aggregator: https://appshunter.io/ios/topics/fujifilm-recipes

### Official Fujifilm

- **XApp** (iOS/Android, 4.2★ from 3.6K ratings). Features: wireless transfer, remote / live view (Film Simulation is adjustable in live view), location sync, Timeline/Activity (logs which film sims you used), and **Backup/Restore**. Backup/Restore saves every camera setting except network settings and custom WB, and restores to the same model only, over Bluetooth. FujiRumors (Aug 11 2026) promotes it as a "free" recipe switcher: program 7 recipes, back up, name the backup after the set, restore later. Release notes from 1.2.0 to 2.7.6 contain nothing about recipes; the only film-sim note is REALA ACE support (1.2.0, Sep 2023). https://www.fujifilm-x.com/global/products/software/xapp/ ; https://apps.apple.com/us/app/fujifilm-xapp/id1586089681 ; https://www.fujirumors.com/?p=144228
- **X RAW Studio** (Mac/Win; Mac v1.28.0, Oct 23 2025). Converts RAF **on the camera's X-Processor over USB**, from the same model only. Batch conversion to JPEG/TIFF. Profiles saved beside the RAW; FP1/FP2/FP3 XML profile files. X-Pro3 note: "custom-setting transfer (v1.8.0)", so XRS can move profiles to and from camera custom settings on some bodies. https://www.fujifilm-x.com/en-au/stories/fujifilm-x-raw-studio-features-users-guide/ ; https://fujifilm-x.com/support/download/software/x-raw-studio/?lang=ja
- **X-E5 "FS RECIPE"** (Jun 2025). This is Fujifilm's first official use of the word "Recipe". Three film-dial slots FS1–FS3 + C1–C7 + IQ menu = 11 recipes on the body. https://fujixweekly.com/2025/06/14/new-fujifilm-x-e5-fujifilms-first-recipe-camera/
- **Warranty statement** (reported by Roesch, Jun 8 2026): any non-licensed program used "to connect to, or control, any compatible Fujifilm camera, will void the camera's limited product warranty". Licences go only to large companies "like Adobe". https://fujixweekly.com/2026/06/08/your-cameras-warranty-might-be-voided/

### Desktop / web / open source (likely missed by an App Store scout)

| Project | What | Platform | Notes | URL |
|---|---|---|---|---|
| **zgrimz/fujifilm-ptp-reference** | Protocol reference: bank writes, in-camera RAW conversion, JPEG recipe reading, per-body table, **ImageCaptureCore notes** | docs (CC BY 4.0) + Python tools (MIT) | Checked Oct 2026. The best single technical source; see §6 | https://github.com/zgrimz/fujifilm-ptp-reference |
| FilmKit | Preset manager + RAW converter | Web (WebUSB, Chromium only), MIT | Tested on X100VI. Properties D18E–D1A5 via Get/SetDevicePropValue | https://github.com/eggricesoy/filmkit |
| Ukiyo | Mac app: recipe library, C1–C7, settings editor, CLI, **MCP server** | macOS 13+, Tauri/Rust, MIT, pre-release | X-T5 only; slot writes "not yet tried". Kills PTPCamera before claiming the camera. Bundles settings only from FXW, film.recipes and the Chavaz DB, with a link back to each original | https://github.com/noahkiss/ukiyo |
| FilmCase | Local catalog + gallery from your own JPEGs, push to C1–C7, QR recipe cards, compare, relation graph | Django on macOS/Ubuntu, free/OSS | Tested on X-S10. FujiRumors May 26 2026 | https://www.fujirumors.com/?p=142701 |
| Latent | Web library, read C1–C4, write verified fields | WebUSB | Tells you to close Image Capture, Photos and X RAW Studio first | https://github.com/formray/latent |
| ozure | CLI + agent skill, C1–C7 over USB PTP | CLI, MIT | Verified write on a real body | https://github.com/AlPeFe/ozure |
| Tintin0/fujiapp | Python backup/edit/restore of C1–C7 | CLI | X-Pro3 | https://github.com/Tintin0/fujiapp |
| petabyt/libfuji, Fudge | C library (Wi-Fi + USB), open-source Android "alternative XApp" (Compose rewrite, beta on Play/F-Droid) | Android | **"Fudge" = this project.** No recipe features listed, and no reviews of it as a recipe app | https://github.com/petabyt/fudge ; https://github.com/petabyt/libfuji |
| petabyt/fp | FP1/FP2/FP3 (X RAW Studio profile) parser | — | Archived Jul 1 2026 | https://github.com/petabyt/fp |
| `fuji` Rust crate | Reads the recipe from EXIF via exiftool | Rust, experimental | | https://docs.rs/fuji |
| Fuji Recipe Converter | Recipe → Lightroom .xmp + .cube LUT. Text, paste, **screenshot OCR (Tesseract.js)**, FP1/2/3 import, share code | Browser, offline, MIT | Hand-tuned approximations | https://github.com/sadziu/Fuji-Recipe-Converter |
| Fuji X Recipe Generator | Oliver Mandić. Questionnaire → recipe; Oct 2026: converts recipes between bodies, OCR (English only) | Web/PWA, free | | https://petapixel.com/2025/06/16/free-app-creates-the-perfect-custom-fujifilm-film-simulation-for-you |
| quiode/fujifilm-recipes | Recipes as **FP1 XML** files by camera | GitHub, MIT + per-author licences | Many taken from FXW, "will remove on request" | https://github.com/quiode/fujifilm-recipes |

### Table stakes vs unique (late 2026)

- **Table stakes:** browsable library with sample photos; compatible-camera info; favorites/collections; USB-C write to C1–C7 (by Sep 2026); iCloud or account sync.
- **Differentiators seen:**
  - Bluetooth write (Huginn; Filmsim X100VI; Fuji Recipes on some bodies)
  - read-back verification + restore point (FujiShare)
  - reading recipes from JPEG MakerNote (FujiShare, FujiStyle, Filos, FxjiMate, FilmCase)
  - screenshot OCR (Simu, Fuji Recipes scan, FujiRecipes.io, Fuji X Recipe Generator)
  - AI recipe from a reference image (Fuji Frame, FujiRecipes.io)
  - in-camera RAW render with a recipe (Filmsim Recipe Lab, Fuji Recipes, FilmKit)
  - gallery of your own shots grouped by recipe (FilmCase, Filmsim Camera Gallery)
  - frames/Stories layouts (FujiStyle, Filmsim Studio, Simulated Film)
  - recipe sets (FXW Patron)
- **Nobody found doing it:** a polished, signed **native Mac** app that does all of: plug in → see C1–C7 → edit → write → gallery of your own photos grouped by recipe. Also nobody imports directly from an Instagram/TikTok *reel URL*; the closest is screenshot OCR through the share sheet (Simu).

## 2. Recipe sources and structure

### Fuji X Weekly (Ritchie Roesch)

- Started Aug 2017. Roesch coined "Film Simulation Recipe". 400+ recipes. https://fujixweekly.com/2026/09/14/a-brief-history-of-fujifilm-recipes/
- Organized **by sensor family**: X-Trans V, IV, III, II, I, EXR-CMOS, Bayer, GFX, plus Full-Spectrum IR and Video. https://fujixweekly.com/recipes/
- X-Trans V page: ~112 recipes. X-Trans IV recipes work on V; for Classic Chrome / Classic Neg / Eterna / Eterna Bleach Bypass, "reduce Color Chrome FX Blue by one". https://fujixweekly.com/fujifilm-x-trans-v-recipes/
- **Exact text format** (CineStill 800T v2, Sep 29 2026): one setting per line, `Name: value`, always in this order:
  ```
  Film Simulation: Reala Ace
  Dynamic Range: DR200
  Grain Effect: Strong, Small
  Color Chrome Effect: Off
  Color Chrome FX Blue: Off
  White Balance: 4500K, -1 Red & -3 Blue
  Highlight: +2
  Shadow: 0
  Color: +4
  Sharpness: -1
  High ISO NR: -4
  Clarity: -3
  ISO: Auto, up to ISO 6400
  Exposure Compensation: -1/3 to +1/3 (typically)
  ```
  Each post also has a compatibility sentence listing bodies, and the sample photos are camera JPEGs (X-T5 in this case). https://fujixweekly.com/2026/09/29/cinestill-800t-v2-a-fujifilm-recipes-for-x-trans-v-cameras/
- Variants seen in other posts: `White Balance: Daylight, +2 Red & -4 Blue`; `ISO: Auto, up to ISO 1600`; `Grain Effect: Weak, Small`; `Toning: ...` for B&W; `D-Range Priority: ...`. Recipe "custom name" convention (credited to Randy Kirk): film name + WB mode code (AU, TN, KV…) + WB offset + EV + ISO. https://fujixweekly.com/2020/11/08/recipe-custom-name-format/
- FXW app transfer: ISO and exposure compensation are **not** transferred (they are not bank settings); video recipes are excluded; X-E5 FS1–FS3 cannot be set. The camera rejects some settings: DR400 when the base ISO is too low, and Clarity unless the drive mode is S. https://fujixweekly.com/2026/08/20/new-send-recipes-to-your-camera-directly-from-the-fuji-x-weekly-app/
- Community submissions: https://community.fujixweekly.com/

### Other sources

- **film.recipes (Justin Gould):** 800+ own recipes (221 counted in the Chavaz DB).
- **Fujifilm Film Simulation Recipes Database (Henri-Pierre Chavaz):** Google Sheet with ~1,058 recipes from 122 origins (Roesch 293, Gould 221). Columns include Creator, Type, Camera, Sensor, Published, URL; tabs Origins / Camera (sims by firmware) / Stats. Last entry 2024-05-05. https://docs.google.com/spreadsheets/d/11PvZ7rOnwmbz5VylVIvzOuWwEa83c0DweAlBwJ2pZJc/
- **filmsimrecipes.com:** "hundreds". Cards show title, saves, sim, creator handle and camera (X100VI 64, X100V 38, X-T5 18 …). Credits the creator handle (e.g. @chris.spaander). Mood filters.
- Fujifilm's own learning centre and "X-E5 x FS RECIPE" creator features: https://www.fujifilm-x.com/en-gb/learning-centre/make-your-own-film-simulation-recipe/
- Older blogs listed by FXW: Life, Unintended (Luis Costa), Jamie Chance Travels, Pete Takes Pictures, Kevin Mullins. https://fujixweekly.com/2022/03/31/more-fujifilm-film-simulation-recipes/

### Fields that vary by generation

The film-simulation list comes from Fujigraphy, updated 2026-11-04 (https://fujigraphy.com/guides/film-simulations-by-camera). Settings availability comes from FXW compatibility posts and the PTP reference.

| Generation / bodies | Sims added | Settings available |
|---|---|---|
| X-Trans III (X-Pro2, X-T2, X-T20, X-E3, X100F); X-H1 adds Eterna | Provia, Velvia, Astia, Classic Chrome, Pro Neg Hi/Std, Acros(+Ye/R/G), Monochrome, Sepia | Grain (Weak/Strong, no size), DR, Highlight/Shadow, Color, Sharpness, NR, Kelvin WB + R/B shift. **No** CC FX Blue, Clarity or grain size |
| X-T3 / X-T30 (X-Trans IV sensor, treated like III by FXW) | + Eterna | + Color Chrome Effect. No CC FX Blue, Clarity, grain size, Classic Neg |
| X-Pro3, X100V | + Classic Negative | + CC FX Blue, Clarity, grain size (Small/Large), B&W toning (Warm/Cool, Magenta/Green) |
| X-T4, X-S10, X-E4, X-T30 II | + Eterna Bleach Bypass | same as X-Pro3 |
| 5th gen: X-H2, X-H2S, X-T5, X-S20, X100VI, X-T50, X-M5, X-E5, X-T30 III, GFX100 II/S II/RF | + Nostalgic Neg., Reala Ace (Reala Ace by firmware: X-T5 fw 4.00, X-S20 3.00, X-H2 5.00) | Same keys, but blues render deeper (CC FX Blue −1 step). X-S20 / X-M5 / X-T30 III have an X-Trans IV sensor but X-Processor 5, so they count as 5th gen |

- Recipe portability is therefore a **per-body capability check**, not a per-sensor one: the firmware adds simulations, and the number of custom banks differs. X-M5, X-S20 and X-S10 have only **C1–C4**; GFX100S and GFX100 II have C1–C6; most bodies have C1–C7. https://raw.githubusercontent.com/zgrimz/fujifilm-ptp-reference/main/docs/07-cameras.md
- D-Range Priority exists on X-T3 and later; its interaction with DR/Highlight/Shadow is a gotcha. Not verified in a source this run.

### Licensing / republishing

- Roesch's stance is **plagiarism and attribution, not copyright**. He does not claim exclusive rights to settings. He objects to verbatim copying, renaming recipes, and especially **profiting** (paid tiers) from his recipes and **his photos** without permission or credit. He filed a takedown once (2021, resolved). https://fujixweekly.com/2021/01/11/dont-steal-my-stuff/
- 2026: he calls out apps that aggregate recipes and use his photos without permission; when he asked for removal he was told nothing was illegal. He supports film.recipes. https://fujixweekly.com/2026/06/08/your-cameras-warranty-might-be-voided/
- A commenter on his 2021 post argued that recipes and film sims have no copyright. No lawsuits found. Settings lists are probably facts and not copyrightable, but **photos and prose are copyrighted**. The safe pattern is Ukiyo's: store settings only, credit the creator, link to the original post, and never copy the sample images.
- Reputational risk: FXW has ~150k app users and an active blog that names and shames copycats.

## 3. Extracting recipes from reels / screenshots

- **Existing OCR tools:**
  - Simu: on-device OCR in 4 languages, uncertain values flagged, share sheet + Shortcuts
  - Fuji Recipes app "recipe scanning" (v1.10)
  - FujiRecipes.io photo/screenshot → settings
  - Fuji X Recipe Generator OCR (English only, with a reliability note)
  - Fuji Recipe Converter (Tesseract.js)
  - Fuji Frame (AI from a reference image, i.e. look matching rather than OCR)
- **EXIF route:** social platforms strip EXIF, so reading the MakerNote only works on original JPEGs (your own shots, or files a creator shares). FujiStyle Recipe Reader lists 14 MakerNote fields: Film Simulation, WB, DR, Highlight, Shadow, Color, Sharpness, NR, Clarity, Grain Roughness, Grain Size, CC Effect, CC FX Blue, WB Shift R/B. https://www.fujistyleapp.com/tools/recipe-reader/
- **Text formats creators use:**
  - FXW style `Name: value` lines (above)
  - captions with pipes or abbreviations (`DR400 | Classic Chrome | Grain: Weak, Small | WB: Auto, +2R -4B | H -1 S +1 | Color +2 | Sharp -2 | NR -4 | Clarity -2`)
  - camera-menu abbreviations CCR / CCB (on-screen display), CCE / CCFXB, DR, NR, H / S
  - FujiRumors example of a full listing: https://www.fujirumors.com/?p=128669
  - No standard caption format exists, so a parser needs aliases and tolerant number parsing ("+2 Red & -4 Blue", "R+2 B-4", "WB shift: +2/-4"). https://www.uniquephoto.com/community/qa/what-do-ccr-ccb-and-ssk-mean-on-the-fujifilm-x-t5-display
- **Reel transcription:** no dedicated tool found. Recipes in reels are usually an on-screen card or in the caption. A practical pipeline is to grab the caption text, OCR key frames (Apple Vision), then run a tolerant parser (inference, not sourced).

## 4. Applying a recipe to photos after the fact

- **With the camera:** X RAW Studio, or any third-party app using the `0xD185` conversion profile. Upload the RAF as `FUP_FILE.dat`, set the profile, trigger the conversion, download the JPEG. The camera must be the same model that shot the file. Done by Filmsim "Recipe Lab", Fuji Recipes, and FilmKit. https://github.com/zgrimz/fujifilm-ptp-reference
- **Without the camera on a Mac:**
  - Lightroom / ACR Camera Matching profiles: Adobe's interpretation, can auto-apply the in-camera sim (since LR 9.2). Approximates sim + WB but not grain or Color Chrome exactly. https://blog.thomasfitzgeraldphotography.com/blog/2020/2/automatically-apply-fuji-film-simulations-in-lightroom-92
  - Capture One: film-sim styles co-developed with Fujifilm (C1 12+), auto-applied on import. https://fstoppers.com/capture-one/how-use-fujifilm-film-simulations-capture-one-12-317845
  - LUT / XMP approximations (Fuji Recipe Converter): grain, clarity, sharpening and NR can't be expressed in a LUT, and WB is RAW-only. https://github.com/sadziu/Fuji-Recipe-Converter
  - Apple's RAW engine (Core Image) has no Fuji film sims, so anything native is an approximation unless the camera renders it.
- **Implication:** with the camera attached, a Mac app could re-render RAFs through it (X RAW Studio's path). Without it, only "preview-ish" looks are possible.

## 5. Fujifilm statements / smartphone import / Bluetooth

- No official recipe import or sync exists, in XApp or in firmware (2024–Nov 2026). Fujifilm's support path is manual entry (IQ menu → Edit/Save Custom Setting), XApp Backup/Restore (whole settings, same model), and X RAW Studio.
- Fujifilm declined to license Roesch, and says unlicensed connections void the warranty. It allegedly leaves a marker in the camera; this is secondhand and a commenter disputes it.
- **Bluetooth:** XApp Backup/Restore runs over Bluetooth. Third parties now write over BLE on some bodies (Huginn; Filmsim X100VI; Fuji Recipes on X-S20, X-S10, X-T50, X-T30 III, X-M5, X-E4, X-Pro3). Pairing a third-party app can disconnect XApp (FujiRumors). The PTP reference leaves Bluetooth out of scope, so the BLE protocol is undocumented publicly.

## 6. Technical notes for a Mac/iPhone build (from the PTP reference)

- **iOS/iPadOS:**
  - ImageCaptureCore `ICCameraDevice.requestSendPTPCommand` (needs the `ICCameraDeviceCanAcceptPTPCommands` capability)
  - request both control and contents authorization; without contents auth the camera never appears
  - keep a single `ICDeviceBrowser`; retry on `-9954`
  - one command in flight; correlate by context, not transaction ID (X-T50 / X-M5 quirk)
- **macOS:**
  - sandboxed apps need the USB entitlement
  - Photos / Image Capture / X RAW Studio / `ptpcamerad` can hold the interface
  - the iOS authorization APIs are unavailable on macOS
- **Writes:**
  - select the bank (`0xD18C`) before each operation
  - write in dependency order
  - **read back**, because an OK response does not prove the change
  - back up the bank first
- **Body table:**
  - **No** direct bank writes on X-Pro3 (fw 2.00), X-T20, X-T3 or X-T30. X-T3/X100F go via the settings-backup path (rawji/grawji).
  - X100V: partial (4 of 23 settings refused).
  - Confirmed: X-T50, X-H2, X-T5, X100VI, X-E5, GFX100RF (macOS and iOS), X-S20, X-M5 (C1–C4), GFX100S.
  - https://raw.githubusercontent.com/zgrimz/fujifilm-ptp-reference/main/docs/09-platform-notes.md ; …/07-cameras.md
