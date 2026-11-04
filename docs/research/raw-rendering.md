# Rendering one RAF with many recipes (research, 2026-11-04)

The question: the owner picks one of his own X-E5 RAFs and sees it rendered with many recipes side by side, to
compare them and pick favourites. ADR 0003 already chose the camera as the renderer. This note checks that route
against the source code, looks at the alternatives on the Mac, and lists the apps that already do it.

Read-only research. Nothing was downloaded to run, and the camera wasn't touched. Source files were read through
the GitHub API at the commits named below.

**Verdict.** The camera route is solid and well documented: send the RAF once, then for each recipe patch the
`0xD185` profile, trigger `0xD183` and download the result. One upload serves any number of recipes. The X-E5 is a
confirmed body (rawji, grawji). For a grid, the X-E5 can return a 640×480 thumbnail of each render in about 12 ms
(grawji). The only per-render timing published is a vendor claim of about 120 recipes in 2.5 minutes (Huginn, about
1.25 s per recipe). No Mac software reproduces recipes faithfully. Lightroom, Capture One and DxO offer the base
film simulation at most, never grain, Color Chrome or Fuji's tone and clarity engine. LUTs are approximations of
the base simulation. Keep ADR 0003.

---

## 1. Camera-side RAW conversion over USB

### 1.1 Sources, read at these commits

| Project | Licence | What it is | Read at |
|---|---|---|---|
| [zgrimz/fujifilm-ptp-reference](https://github.com/zgrimz/fujifilm-ptp-reference) | docs CC BY 4.0, tools MIT | The specification. `docs/05-raw-conversion.md`, `06-conversion-profile.md`, `07-cameras.md`, `09-platform-notes.md`, `11-client-implementation.md`, `open-questions.md`. Measured on an X-T50 (fw 1.31/1.32) against X RAW Studio USB captures, **including conversions through ImageCaptureCore on iOS** | last commit 2026-11-01 |
| [eggricesoy/filmkit](https://github.com/eggricesoy/filmkit) | **MIT** | WebUSB web app; `src/ptp/session.ts` L471–702 is the whole conversion flow (a TypeScript port of rawji). Reference body: X100VI | pushed 2026-03-26 |
| [pinpox/rawji](https://github.com/pinpox/rawji) | GPL-3.0-or-later (pyproject); facts only | Python "X RAW Studio clone", `src/rawji/fuji_usb.py`, `fuji_profile.py`. **Tests listed: X-T30, X100F, X-T3, X-E5** | `02cb559`, 2026-09-20 |
| [p5k369/grawji](https://github.com/p5k369/grawji) | GPL-3.0; facts only | GTK front end for rawji: live preview, split compare against a starred recipe, batch export. **Its author shoots an X-E5** (FS dial mapped, "verified ✓" X-E5 row in `docs/feature-matrix.md`) | pushed 2026-11-04 |
| [petabyt/libfuji](https://github.com/petabyt/libfuji) | **MIT** | C. `lib/fuji_usb.c` `fuji_send_raf` + `fuji_process_raf` (about L290–418); `fp/` parses `0xD185` and X RAW Studio FP1/FP2/FP3 XML. Built on [petabyt/libpict](https://github.com/petabyt/libpict) (Apache-2.0, the PTP layer). [petabyt/fudge](https://github.com/petabyt/fudge) is the app; GitHub code search finds no `0xD185` code in its own tree (it may come in through a submodule), while the USB conversion code is in libfuji and `fudge-legacy-android` | `f032730`, 2026-11-04 |
| [karaolidis/fujicli](https://github.com/karaolidis/fujicli) | GPL-3.0; facts only | Rust CLI, `crates/fujicore/src/features/render/manager.rs`. X-T5 tested | pushed 2026-10-20 |
| [tkcranny/fxraw](https://github.com/tkcranny/fxraw) | none (read only) | Rust, X100VI; `docs/PROTOCOL.md` | pushed 2026-03-22 |
| [formray/latent](https://github.com/formray/latent) | AGPL-3.0 (its `@latent/*` packages MIT) | FilmKit fork, "camera-backed look lab": back up, preview a RAF, write a slot. X-S20 | pushed 2026-08-03 |
| [petabyt/vcam](https://github.com/petabyt/vcam) | LGPL-2.1 | Emulates Fuji PTP cameras for black-box testing; libfuji's `0xD185` layout came from it | 2026-10-16 |

### 1.2 The protocol, step by step

Preconditions:
- The camera is set to **SET UP ▸ CONNECTION SETTING ▸ USB MODE ▸ USB RAW CONV./BACKUP RESTORE**, and `0xD16E`
  reads `6`. FujiKit already checks this.
- The camera's menu is locked while connected. Fujifilm says power saving is off in this mode and the conversion
  runs on the camera's battery ([X RAW Studio Features & Users Guide](https://www.fujifilm-x.com/global/stories/fujifilm-x-raw-studio-features-users-guide/)).

| # | PTP | Exact content | Source |
|---|---|---|---|
| 1 | **`0x900C` SendObjectInfo** (Fuji vendor op), params `[0, 0, 0]` | Standard ObjectInfo dataset: StorageID 0, **ObjectFormat `0xF802`** (RAF; FilmKit says `0x5000` fails silently), ProtectionStatus 0, ObjectCompressedSize = file size, all thumbnail and image fields 0, ParentObject 0, then the PTP string **`FUP_FILE.dat`**, and three empty strings (capture date, modification date, keywords) | FilmKit `session.ts` `sendRaf`; rawji `send_raf`; libfuji `fuji_send_raf`; zgrimz 05 step 1 |
| 2 | **`0x900D` SendObject2** | Data phase: the RAF bytes. FilmKit allows 60 s. libfuji raises the USB packet size to 261,632 bytes, as Windows does | same |
| 3 | `0x1015` GetDevicePropValue **`0xD185`** | The conversion profile, now holding the RAF's as-shot settings. Reading it before an upload answers `0x2002`. **A RAF from another model answers `0x2002` here**, even though the upload itself said OK | zgrimz 05; rawji README; grawji `core.py` |
| 4 | — | Validate, then patch only the cells the recipe sets. Keep the as-read profile untouched as the base for every recipe | zgrimz 05 "Upload once, develop many" |
| 5 | `0x1016` SetDevicePropValue **`0xD185`** | The patched blob. X RAW Studio sends a 629-byte form with `numParams` = cells − 1. Also accepted: a 625-byte write (X-T50, FilmKit #12) and the native length (grawji, on the X-E5) | zgrimz 06 "host-write form" |
| 6 | GetDevicePropValue `0xD185` | Read back and compare the patched cells. A defensive check: once, the same bytes rendered green | zgrimz 05 "Verify the profile" |
| 7 | SetDevicePropValue **`0xD183`**, u16 | **`0` = reduced-size render, `1` = full resolution**; `2` is refused (`0x201C`). FilmKit and libfuji send 0; rawji and grawji send 1 for exports | FilmKit `triggerConversion`; rawji `trigger_conversion` (`struct.pack('<H', …)`); zgrimz 05 |
| 8 | Poll | Either `0x1007` GetObjectHandles(`0xFFFFFFFF`, 0, 0) until a new handle appears, or `0xD212` (event list) until a `0xD20E` event arrives (X RAW Studio's way). Wait budgets: rawji polls every 50 ms, FilmKit every 1 s, both up to 30 s; fujicli every 100 ms with no limit | zgrimz 05 "Completion" |
| 9 | `0x1008` GetObjectInfo → `0x1009` GetObject, **or `0x100A` GetThumb** | The output is format `0x3801` (JPEG) with a 114-byte ObjectInfo. **GetThumb on the X-E5 returns a 640×480 letterboxed JPEG of about 40 KB in about 12 ms**, against about 4 MB for the reduced render | zgrimz 05; grawji `core.py` `render_thumb` (L691–697); rawji `wait_for_result(thumbnail=True)` |
| 10 | `0x100B` DeleteObject | Delete the output, and only the object this job created (compare against the handle list taken just before step 7) | zgrimz 11 "Develop a RAF…" |

For the next recipe, repeat steps 4–10 without uploading again: "The conversion buffer survives a conversion"
(zgrimz 05, measured on an X-T50). grawji's whole live preview is built on this, through a `CameraSession` that is
"load once, render many".

**Never trigger twice after a timeout.** A wedged conversion makes the body answer `0x2019` until it is power
cycled, sometimes by pulling the battery (grawji, X RAW Studio users). A late output would also be taken as the
next job's result. All 13 retained X-T50 triggers produced output after 1–3 polls (zgrimz 05).

### 1.3 `0xD185` layout and how a recipe maps into it

Layout, from zgrimz `06-conversion-profile.md`, checked against X-H1, X-Pro3, X-T30, GFX100S and X-T50 profiles:

```
0x000  u16 LE   numParams
0x002  u8       IOPCode length (8 on read, 9 incl. NUL on host write)
0x003  UCS-2LE  IOPCode, e.g. "FF189504" (X-T50), zero-padded up to 0x1FD
0x1FD  i32 LE × k   cells; cell i at 0x1FD + 4·i  (odd base: every cell is unaligned)
```

X-Processor 5 bodies read 625 bytes with 29 cells. Never derive the base from `numParams`, because the camera
echoes the host's count. Validate a base by checking that cell 6 ∈ {100, 200, 400} and cell 8 is a known film
simulation. If no base passes, don't write. rawji, fujicli and grawji count cells from `0x201`, one lower than
here. Mixing their indices with the `0x1FD` base misreads every field.

| Cell | Field | Recipe field and encoding (same as the bank property unless noted) |
|---|---|---|
| 2 | Output file type | `7` JPEG, `9` TIFF 8-bit, `0xB` TIFF 16-bit, `0x12` HEIF (the X-E5 lists 8/16-bit TIFF "In-camera Raw Conversion Only" in its [specs](https://www.fujifilm-x.com/global/products/cameras/x-e5/specifications/)) |
| 3 / 4 | Image size / quality | carry through |
| 5 | **Exposure bias** | EV × 1000 (+⅔ = `667`); honoured range probably −2…+3 EV. It exists only here, not in the banks, so a recipe's "exposure compensation" can be applied |
| 6 | Dynamic range | 100/200/400 (= `0xD190`). **Cap at the frame's as-shot DR**: a higher value is accepted but renders a heavy green cast. No working DR Auto encoding (`-1` renders DR100) |
| 7 | D-Range Priority | **unknown**: three sources disagree, and there's no render evidence |
| 8 | Film simulation | = `0xD192` (1–20; 19 Nostalgic Neg., 20 Reala Ace) |
| 9 | Grain | = `0xD195` write values 1–5 (rawji: works on the X-E5; X RAW Studio writes `7` for Off) |
| 10 | Color Chrome | = `0xD196` |
| 11 | WB source | `1` = the RAF's as-shot WB, `2` = use cell 12. No bank counterpart |
| 12 | WB mode | = `0xD199` |
| 13 / 14 | WB shift R / B | = `0xD19A/B`, ±9, plain integers |
| 15 | Kelvin | = `0xD19C`; X-Processor 5 is said to take 2500–10000 in steps of 10 (not yet render-tested) |
| 16–19 | Highlight, Shadow, Color, Sharpness | signed ×10 (= `0xD19D–A0`) |
| 20 | High ISO NR | = `0xD1A1` lookup |
| 21 / 22 | LMO / Color space | carry through |
| 23 / 26 | Mono warm–cool / magenta–green | = `0xD193` / `0xD194`, ×10, −180…+180 |
| 24 / 25 | Smooth Skin / Color Chrome FX Blue | = `0xD198` / `0xD197` |
| 27 | Clarity | = `0xD1A2`, ×10 |
| 28 / 29 | reserved (fujicli: Digital Tele-Converter) / host-only cell | carry through: `2`, and `0` or `1` |

**Seventeen bank/profile pairs held identical raw values** in X RAW Studio's own conversion with a bank's recipe
(zgrimz 06). So FujiKit's existing bank encoder (`Sources/FujiKit/Bank.swift`) is most of the recipe → profile
mapper. What a recipe can't carry:
- ISO (fixed by the RAF);
- DR above the as-shot value;
- D-Range Priority (encoding unknown);
- whether "Auto WB + shift" re-runs Auto WB or keeps the as-shot WB (`cell 11 = 1` vs `2`): open, and fujicli and
  grawji disagree about the shifts under as-shot WB.

### 1.4 Bodies, speed, limits

- **X-E5: works.** rawji lists it as tested. grawji's matrix marks it "✓ verified" for conversion, TIFF 8/16 and
  HEIF, and its `core.py` documents the X-E5 thumbnail path. zgrimz `07-cameras.md` lists X-E5 conversion
  "yes" (Published: grawji + community).
- Other X-Processor 5 bodies:
  - X100VI: works (FilmKit's reference body; fxraw; X Sim Lab users).
  - X-T5: works (fujicli).
  - X-T50: works, with the deepest captures (zgrimz).
  - X-S20: works (grawji #108).
  - X-M5: works per FilmKit #18, but `0x2019` was seen once at fw 1.20.
  - X-H2: third-party conversion is unverified.
  - [Fujifilm's X RAW Studio list](https://www.fujifilm-x.com/global/support/compatibility/software/x-raw-studio/)
    includes X-E5, X100VI, X-T50, X-M5, X-T30 III, the X-H2 family and all GFX bodies. On the Mac it lists
    macOS 11–15.
- **Speed.** No trigger-to-output time is measured in the spec; it is an open question there.
  - Vendor and project claims:
    - rawji: "~2-5 seconds per image" for the whole process.
    - [Huginn](https://huginnfilm.app): "about 120 recipes in roughly two and a half minutes, measured on our own
      body", which is about 1.25 s per recipe, with the RAF uploaded once.
    - Fujifilm: about "the same time as taking a photo on the camera", independent of the computer
      ([Features & Users Guide](https://www.fujifilm-x.com/global/stories/fujifilm-x-raw-studio-features-users-guide/)).
  - Users on r/fujifilm ([1stsevn](https://www.reddit.com/r/fujifilm/comments/1stsevn/), 2026-04, 160 pts):
    X RAW Studio "takes up to 12 seconds to update" after a change, while FilmKit is "fast".
  - **Estimate for the app:** one upload of the RAF (owner's X-E5 RAFs are ~83 MB uncompressed; USB-C 10 Gbps on
    the body; a few seconds), then about 1–3 s per recipe with GetThumb tiles. That's about 30 recipes in under a
    minute, and a library of 100 in a few minutes. Full resolution (~25 MB JPEG per render on 26–40 MP) is on
    demand only.
- **Same model only.**
  - Fujifilm: "only compatible with a RAW file taken by the same camera model" (Features & Users Guide).
  - rawji: a foreign RAF is rejected with `0x2002` (at the profile read, per grawji).
  - Workaround, not needed here: grawji transplants a foreign RAF's sensor data into an uncompressed "carrier" RAF
    from the connected body. Its author verified X100F → X-E5 (Reala Ace) and X-T3 → X-E5, with a WB shift on
    the 40 MP body still under investigation ([grawji #53](https://github.com/p5k369/grawji/issues/53),
    2026-08/09).
- **Through ImageCaptureCore** (what FujiKit uses):
  - zgrimz records one iOS 27 connection of 301 commands, including **two 87 MB uploads and four conversions**,
    all well-formed, through `requestSendPTPCommand` with the RAF as `outData`.
  - Response transaction IDs differ from the client's, so correlate by callback, not by ID.
  - Timeout of 20 s + 1 s/MB (FujiKit's `send` already does exactly this for out-data). **GetObject of a 25 MB
    full render needs the same allowance for in-data**; FujiKit's current timeout only counts `outData`.
  - **macOS + ICC + conversion has no published trace**: macOS forwards bank properties fine (fuji-ptp-notes,
    GFX100RF), but the upload and trigger have only been recorded on iOS and over libusb/WebUSB.
- **Warranty.** grawji quotes Fujifilm's Camera Control SDK page: connecting "WILL VOID THE CAMERA'S LIMITED
  PRODUCT WARRANTY". It also cites [Fuji X Weekly 2026-06-08](https://fujixweekly.com/2026/06/08/your-cameras-warranty-might-be-voided/)
  saying the policy is reported to extend to unlicensed apps.

---

## 2. Local software on the Mac (no camera)

| Software | Fujifilm simulations | Recipe parameters | Fidelity / notes |
|---|---|---|---|
| **FUJIFILM X RAW Studio** (free; [page](https://www.fujifilm-x.com/global/products/software/x-raw-studio/)) | All the body has (it's the camera) | All of them, through the camera | Exact, but needs the camera. The UI is slow (r/fujifilm 1stsevn). Same-model RAFs only |
| **RAW FILE CONVERTER EX 3.0 powered by SILKYPIX** (free, Fujifilm; [page](https://www.fujifilm-x.com/global/support/download/software/raw-file-converter-ex-powered-by-silkypix/)) | Software simulations: Reala Ace added in 8.1.17.0 for X-H2S/X-H2/X-T5/X-S20; **X-E5 support in 8.1.19.0**; Mac 8.1.20.0 (2026) | The page doesn't say whether grain or Color Chrome are offered | Fujifilm's own software render, not the camera engine. Fidelity to in-camera JPEGs isn't documented. Worth one hands-on check by the owner |
| **Lightroom Classic / ACR** | "Camera Matching" profiles: Provia, Velvia, Astia, Classic Chrome, Pro Neg Hi/Std, Eterna, Acros/Mono variants; Reala Ace, Classic Neg and Bleach Bypass appear for newer bodies; Nostalgic Neg reported missing ([Adobe community thread](https://community.adobe.com/t5/camera-raw-discussions/p-camera-matching-profiles-requests-and-information/m-p/15275225)) | **Base simulation only.** Grain, tones and WB shifts are approximated with Adobe's own sliders by preset makers. Color Chrome / FX Blue and Fuji's grain don't exist | "Adobe's approximation" ([uniquephoto Q&A](https://www.uniquephoto.com/community/qa/do-fujifilm-film-simulations-match-between-in-camera-jpegs-in-camera-raw-conversion-and-lightroom)) |
| **Capture One** | Fujifilm simulations as Base Characteristics ▸ Curve on RAFs since C1 12, per-camera table ([support article](https://support.captureone.com/hc/en-us/articles/360002589937)); not on DNGs | Base simulation only | Users: "really good… but it still doesn't feel right", "not even Capture One Pro can truly match" ([1tdjyjt](https://www.reddit.com/r/fujifilm/comments/1tdjyjt/), 2026-05) |
| **DxO PhotoLab + FilmPack** | FilmPack 6 (2021) added "7 film simulation modes from X-series Fujifilm cameras" ([DIYPhotography](https://www.diyphotography.net/dxo-releases-photolab-5-and-filmpack-6-with-more-powerful-features-and-fuji-x-trans-raw-support/)) | Base simulation only; no newer sims found | Paid add-on |
| **darktable** | None built in | — | The [lut 3d module](https://docs.darktable.org/usermanual/4.2/en/module-reference/processing-modules/lut-3d/) takes `.cube`/`.3dl`/HaldCLUT `.png`/`.gmz` from the community |
| **RawTherapee** | None (its [Film Simulation](https://rawpedia.rawtherapee.com/Film_Simulation) tool applies HaldCLUTs, mostly analogue film stocks; "global tonal changes" only) | — | — |
| **Apple Photos / Core Image (`CIRAWFilter`)** | None | — | The only Fuji look Apple shows is the JPEG preview embedded in the RAF, i.e. the **as-shot recipe**, which is useful as the "original" tile |
| **Community LUTs / DCPs**, e.g. [abpy/FujifilmCameraProfiles](https://github.com/abpy/FujifilmCameraProfiles) (606★, no licence: read only) | 11 looks incl. Reala Ace; Classic Neg, Nostalgic Neg and Bleach Bypass as LUT only (Nov 2025) | Base simulation only; needs a linear profile first | Derived from Adobe's camera-matching profiles, so an approximation of an approximation |
| **Fujifilm's official F-Log2 / F-Log2 C LUTs** ([downloads](https://www.fujifilm-x.com/global/support/download/lut/); PetaPixel 2025-11-18) | 10 sims, Reala Ace included | None | For log video footage, not a stills RAW pipeline |

**LUT approach in short.**
- A 3D LUT can reproduce a film simulation's global colour mapping at one exposure and white balance.
- It can't reproduce:
  - grain;
  - clarity (local contrast);
  - sharpening or NR;
  - Color Chrome (saturation-dependent, local);
  - the DR / tone curves that act before the colour mapping.
- So LUTs cover the "base look" of a recipe and miss what separates two Classic Chrome recipes. ADR 0003 already
  rules them out ("No colour-filter imitations").
- One idea for later, not recommended now: render a colour chart RAF through the camera with each simulation at
  neutral settings, fit a LUT, and use it only as a clearly labelled "approximate" preview. It's off-strategy.

---

## 3. Apps that already do "try recipes on my RAW"

All of them use the camera route from §1. None renders without the camera.

| App | Platform | One RAF × many recipes? | Notes |
|---|---|---|---|
| **Huginn** ([site](https://huginnfilm.app), [App Store](https://apps.apple.com/us/app/huginn-film-sim-recipes/id6797092369)) | iPhone/iPad | **Yes: "Virtual Bracketing"**, "shoot once, then see the frame in every look", any selection or the whole library | Vendor: about 120 recipes in about 2.5 min. $29.99/yr Pro. The closest existing match to the owner's idea |
| **Fuji Recipes** (Bechir Kaddech) | iPhone/iPad/Mac (M1) | Darkroom: render one recipe at a time | Most-praised feature in its r/fujifilm launch ([1tad53l](https://www.reddit.com/r/fujifilm/comments/1tad53l/)): "render recipes directly on your raw with 100% Fuji colors"; 5 free renders, then Pro |
| **Bento** | iPhone | "Side-by-side RAF renders by the camera" | X100VI verified only |
| **grawji** | Linux (GTK) | Live preview plus a **split compare against a starred baseline recipe** (two real renders) | X-E5 verified; GPL |
| **FilmKit** / **Latent** | Web (Chromium WebUSB) | One live render, "latest wins" queue (`reconvert`) | Called "fast" next to X RAW Studio (1stsevn) |
| **X Sim Lab** ([App Store](https://apps.apple.com/us/app/x-sim-lab/id6761675489), $17.99, 3.5★/2) | iPad (iPhone planned) | "X RAW Studio for iPad" | X-T5-built; a user confirmed X100VI "works almost flawlessly"; called vibe-coded ([1sxezf4](https://www.reddit.com/r/fujifilm/comments/1sxezf4/)) |
| Fujirama, Simu, Film Kitchen, Recipe Lab, Filmsim | iPhone | Single renders | See [notes/appstore.md](notes/appstore.md) |
| X RAW Studio | Mac/Windows | One profile at a time; batch = many RAFs × one profile | Slow UI; macOS 11–15 listed |

**What users say** (Reddit through OpenCLI live reads and the Arctic Shift archive, plus the
[community notes](notes/community.md)):
- **The pull is real.**
  - "apply different simulations for all the photos shot during my Japan trip" (X-E5 owner,
    [1xcifp3](https://www.reddit.com/r/fujifilm/comments/1xcifp3/));
  - "being able to apply recipes to RAW files after shooting sounds amazing, especially when I can't decide which
    look I like best" (same thread);
  - the X RAW Studio tip thread got 160 pts (1stsevn).
- **The way people already use it is the owner's plan.** "I have my reference raw pictures for bright daylight,
  cloudy, sunset, lowlight, indoor and landscape. After i create my recipes, i store them in the camera"
  (1tdjyjt).
- **Software approximations disappoint.** "if I wanted to replicate a Vibrant Arizona or Kodak Gold 200 recipe,
  it just didn't work with third party software" (1tdjyjt); Lightroom presets "are just approximations"
  (1stsevn).
- **Pain points.**
  - Speed: X RAW Studio "up to 12 seconds to update".
  - Price: Fuji Recipe's lifetime called "way too high".
  - Body support: most replies in launch threads are "support my X-T5/X-T50/X-S10".
  - Trust: "vibe coded", warranty worries.
- **Nobody has a Mac-native contact sheet** of one RAF × N recipes. Huginn is iPhone/iPad. X RAW Studio and the
  Mac build of Fuji Recipes render one look at a time.

Coverage: GitHub API (9 repos, source read) ✓ · Fujifilm pages ✓ · WebSearch ✓ · Reddit ✓ (6 threads read live,
2 archive title searches; the archive was throttled, so r/fujix wasn't searched separately) · Huginn site ✓ ·
PetaPixel and Capture One support blocked the fetcher (cited from search results).

---

## 4. Recommendation

**Build "Contact sheet": one RAF, N recipes, rendered by the camera, cached on disk.**

1. **Transport.** Add `uploadRAF`, `getProfile`/`setProfile`, `trigger(reduced|full)`, `pollNewHandle(baseline)`,
   `getThumb`, `getObject` and `deleteObject` to `FujiKit`.
   - Most of this is `send(op, params, data)`, which already exists.
   - Scale the timeout by expected in-data too.
   - Serialize everything in one operation owner.
2. **Profile.** `ConversionProfile` parser:
   - base `0x1FD`, validated by cells 6 and 8;
   - an immutable as-read copy;
   - a writer for the native length;
   - unit tests on libfuji's published `fp/d185/` blobs (MIT) and zgrimz's X-T50 layout.
3. **Recipe → cells.** Reuse `Bank.swift` encodings for the 17 shared fields plus mono toning; set cell 2 = 7.
   - Cap DR at the as-shot value.
   - Skip D-Range Priority and badge the tile "DRP not rendered".
   - WB: cell 11 = 2 with the recipe's mode, shifts and Kelvin; test "Auto" on the camera before deciding.
   - Exposure (cell 5) is a per-photo slider, not part of the recipe (grawji's choice).
4. **Render loop.** For each recipe:
   - patch the base, set, read back, take a handle baseline;
   - trigger `0`, then poll every 100–250 ms up to 30 s;
   - **GetThumb** for the grid tile (~40 KB) and GetObject (~4 MB) for the enlarged view;
   - delete the output.
   - Full resolution (`1`) only on "Export".
   - Stop the batch at the first timeout or `0x2019`, and never re-trigger.
5. **Cache.** Key by RAF SHA-256 + recipe hash + body/firmware.
   - Renders are deterministic, so the sheet works offline later, on iPhone too (shared folder).
   - The RAF's embedded JPEG is tile 0, "as shot".
6. **UI.** A Photo Minimalist-style grid with the as-shot tile first. Click enlarges; keyboard ←→ moves; ♥ marks
   favourites, which feed "write to a C slot" and kits. A progress line shows "rendering 12 of 40".
7. **iPhone/iPad.** Same code over USB-C. Request both ICC grants (Control + Contents). The camera's battery does
   the work.

**Risks.**
- macOS ImageCaptureCore upload and conversion are unproven, since only iOS is traced. **Spike this first** on the
  owner's X-E5 with one RAF and 3 recipes, timing each step.
- A wedged body needs a battery pull.
- Green-cast cases: DR above as-shot, or an unexplained one-off.
- The warranty statement.
- Firmware updates may change the profile length or cells. The base/score validation and read-back catch that.
- ImageCaptureCore may react to the camera creating and deleting objects (`didAdd` items, Image Capture or Photos
  auto-launch). Watch for it in the spike.

**Open questions for the spike.**
- Seconds per render on the X-E5 (reduced vs full, GetThumb vs GetObject), and upload time for an 83 MB RAF over
  ICC on macOS.
- Does `cell 11 = 2` + Auto WB recompute Auto WB, and do shifts apply under as-shot WB?
- Does the X-E5 take free Kelvin, and grain `1` as Off (rawji says yes)?
- D-Range Priority's cell 7 encoding: shoot DRP Weak/Strong/Auto frames and read cell 7.
- Can GetThumb tiles be trusted for comparing grain and clarity, or does the grid need the 4 MB render scaled
  down?
