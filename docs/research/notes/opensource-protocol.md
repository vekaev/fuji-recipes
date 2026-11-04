# Fuji recipes over USB: open source and protocol scout

All sources were read on **2026-11-04** unless a row says otherwise. Commit hashes are the HEADs read that day:
zgrimz/fujifilm-ptp-reference `d78c79b`, ILFforever/fujifilm-ptp-recipes `daba2d9`, eggricesoy/filmkit `9e3bbcf`,
petabyt/libfuji `f032730`. "Verified in X" means I read the code or doc line myself. "Unverified" means I'm passing on
another project's claim and didn't check it.

## TL;DR

- **The protocol is solved and well documented.** The custom banks C1–C*n* are plain PTP device properties:
  - `0xD18C` selects the bank.
  - `0xD18D` holds the bank name (a PTP string).
  - `0xD18E…0xD1A4` hold the 23 bank settings, as u16 values written with `SetDevicePropValue 0x1016` and read with
    `GetDevicePropValue 0x1015`.
  - No vendor operation is needed. The camera must be in **USB RAW CONV./BACKUP RESTORE** mode (`0xD16E` reads `6`).
- **Best single reference:** <https://github.com/zgrimz/fujifilm-ptp-reference>. It's evidence-tagged, measured on an
  X-T50, with captures of X RAW Studio and an errata list against the other projects. Licence: CC BY 4.0 for the docs,
  MIT for the tools. It grew out of the iOS app "Fuji Cookbook", which uses ImageCaptureCore on iPhone and iPad.
- **Swift path:** ImageCaptureCore `ICCameraDevice.requestSendPTPCommand(_:outData:completion:)`.
  - It's available on macOS 10.15+, iOS/iPadOS 13+ and Mac Catalyst 13.1+.
  - It is a raw passthrough: you build the 12-byte container yourself. Vendor property codes go through.
  - It has been used successfully on macOS 26 and iOS 26/27 with an X-T50, GFX100S, GFX100RF and X-M5.
  - No libusb needed, so no fight with `ptpcamerad`.
- **Bodies with working bank writes:**
  - Confirmed: X-T50, X-H2, X-T5, X100VI, X-S20 (4 banks), X-M5 (4 banks), X-E5, GFX100S (6 banks), GFX100RF.
  - Partial: X100V (15 of 23 settings).
  - Community report: X-T30 II.
- **Bodies that fail or have no reports:**
  - X-Pro3 fw 2.00 fails.
  - X-T3, X-T30, X-T20 and X100F have no bank properties. Only the patched settings-backup route reaches their banks.
  - X-T4 and X-E4 have **no reports**.
- **The X Acquire backup is the PTP object 0** (`GetObject(0)`). It starts with `FUJIFILM`, then the model at `0x14` and
  the serial number at `0x34`. Its bank layout is reverse-engineered only for the X100F and X-T3 (grawji, GPL-3.0). The
  X-T3 layout has a checksum that the camera checks.

---

## 1. Projects

The "Reusable for us?" column assumes a closed-source or App Store Swift app.

| Project | URL | Licence | What it does with Fuji settings | Transport | Reusable for us? |
|--|--|--|--|--|--|
| **fujifilm-ptp-reference** (Zachary Grimshaw) | https://github.com/zgrimz/fujifilm-ptp-reference | Docs CC BY 4.0, `tools/` MIT | The full bank protocol: property map, encodings, write order, refusal causes, per-body matrix, ImageCaptureCore notes, RAW conversion, JPEG MakerNote extraction | USB (ImageCaptureCore on iOS, plus Python/pyusb `tools/bankprobe.py`) | **Yes, as the spec.** Facts are free to use; credit if we adapt the text. Key files: `docs/02-properties.md`, `docs/03-encodings.md`, `docs/04-custom-slots.md`, `docs/07-cameras.md`, `docs/09-platform-notes.md`, `docs/11-client-implementation.md`, `docs/errata.md` |
| **fujifilm-ptp-recipes** (ILFforever) | https://github.com/ILFforever/fujifilm-ptp-recipes | Docs CC BY 4.0, examples MIT | Bank read/write tested on an X-H2 fw 5.20 and X-T5 fw 4.20; fails on an X-Pro3 fw 2.00. Live state ("C0") codes. Static analysis of X RAW Studio, including its per-model capability table | USB (Android FujiSync, Python) | **Yes.** `examples/python/ptp_recipe_reference.py` is MIT: constants, `ptp_string`, name sanitiser. `docs/reverse-engineering/reference/xrfc-capabilities.xml` plus `xrfc-value-tables.md` give the values each model accepts (CC BY) |
| **FilmKit** (eggricesoy) | https://github.com/eggricesoy/filmkit | MIT | Web app over WebUSB: read and write C1–C7, RAW conversion. Reference body X100VI. Its GitHub issues hold the public X RAW Studio captures (#1 X100V, #5 X-T3, #12 X-T50, #13 X-T30) | WebUSB (Chromium) | **Yes, MIT.** `src/ptp/constants.ts` (bank map), `src/ptp/session.ts` (session, upload, conversion), `src/profile/enums.ts`. Known errors are listed in the zgrimz errata (`0xD1A3` is not Long Exp NR, grain UI values, profile offsets) |
| **libfuji** (petabyt / Daniel Cook) | https://github.com/petabyt/libfuji | MIT | USB mode detection, settings-backup download and restore, `0xD185` profile parser, X RAW Studio FP1/2/3 files, WiFi and BLE pairing | USB, WiFi (PTP/IP), BLE | **Yes, MIT.** `lib/fujiptp.h` (codes), `lib/fuji_usb.c` (mode at about L116, backup and restore at about L173–244), `fp/src/fp.h` and `fp/d185/` (profile) |
| **libpict** (formerly **camlib**, petabyt) | https://github.com/petabyt/libpict (`petabyt/camlib` redirects here) | Apache-2.0 | A generic PTP client library in C that libfuji uses | libusb, PTP/IP | Optional. ImageCaptureCore makes it unnecessary on Apple platforms |
| **Fudge** (petabyt) | https://github.com/petabyt/fudge (new, Kotlin, **no licence file**); legacy https://github.com/petabyt/fudge-legacy-android (GPL-2.0); https://github.com/petabyt/fudge-desktop-legacy | none / GPL-2.0 | An alternative to Fujifilm's WiFi/BLE app. Its desktop CLI did `--backup` / `--restore` of the `.dat` and FP1–3 profiles (https://fudge-www.pages.dev/blog/3) | WiFi, BLE, USB | Ideas only. Use libfuji for code |
| **libgphoto2** `camlibs/ptp2` | https://github.com/gphoto/libgphoto2 | LGPL-2.1+ | Fuji **live** properties `0xD001…` and tether capture. **No** bank codes `0xD18C–0xD1A5`; in its header those numbers are Canon and Nikon codes. Its film simulation table stops at 18 (Eterna Bleach Bypass). Camera dumps: `camlibs/ptp2/cameras/fuji-x100vi.txt`, `fuji-gfx100-ii.txt`, `fuji-gfx-100s.txt` | libusb | Not needed. LGPL plus a bundled libusb is awkward in a sandboxed or App Store app |
| **rawji** (pinpox) | https://github.com/pinpox/rawji | GPL-3.0-or-later (in `pyproject.toml`) | X RAW Studio clone: RAF upload, `0xD185` profile, conversion. `src/rawji/fuji_enums.py` (film simulations 1–0x14), `fuji_usb.py` | pyusb | Facts only |
| **grawji** (p5k369) | https://github.com/p5k369/grawji | GPL-3.0 | RAF development plus bank writes, using properties on newer bodies and **patching the settings backup** on the X100F and X-T3 (`src/grawji/camera/backup_recipe.py`, `camera_backup.py`, `fs_recipe.py` for the X-E5 FS dial) | pyusb | Facts only (layouts, checksum) |
| **fujicli** (karaolidis) | https://github.com/karaolidis/fujicli | GPL-3.0 | Rust CLI: simulations, backup and restore, rendering. X-T5 tested; schema in `fml/option.cue` | libusb (Linux, macOS) | Facts only |
| **Filmcase** (gosku) | https://github.com/gosku/Filmcase | GPL-3.0 (name reserved) | Django recipe manager, push to camera (X-S10 sweeps), WebUSB transport with stall recovery (ADR 016), `docs/ptp_encodings.md` | WebUSB, pyusb | Facts only |
| **fuji-ptp-notes** (Junsudo) | https://github.com/Junsudo/fuji-ptp-notes | **none** | GFX100RF register map; **macOS 26 and iOS 26 with ImageCaptureCore**; host and mode matrix | ImageCaptureCore | Read only |
| **fxraw** (tkcranny) | https://github.com/tkcranny/fxraw | none | Rust X RAW Studio replacement; origin of film simulations `0x11–0x14` from X100VI dumps | libusb | Read only |
| fuji-recipes-pro (AntApper) | https://github.com/AntApper/fuji-recipes-pro | MIT | Swift macOS/iOS, work in progress. Bundles libgphoto2 dylibs for macOS; the ImageCaptureCore path is "untested on actual hardware" (its own `FujiPTPClient/README.md`) | — | Low value |
| fuji-ptp-android (AlPeFe) | https://github.com/AlPeFe/fuji-ptp-android | none | Kotlin app for the X100VI, with a prebuilt `.so` | Android USB | Low |
| fuji-cook (mich8bsp) | https://github.com/mich8bsp/fuji-cook | other | Android recipes plus RAW conversion (`camera/PtpCodec.kt`, `FujiProfile.kt`) | Android USB | Low |
| omarchy-fujifilm-recipes (ctl0v0) | https://github.com/ctl0v0/omarchy-fujifilm-recipes | MIT | Rust C1–C7 backup and "guarded X100VI slot manager" | libusb | Maybe; small |
| **fujihack** | https://github.com/fujihack/fujihack | GPL-3.0 | **Firmware patching**: a PTP/USB debugger patched into firmware (XF1, X-A2). Its README warns that custom firmware "can cause damage" and that brick recovery is not reverse-engineered | patched firmware | **No.** Not relevant to recipes and dangerous |
| fuji-cam-wifi-tool (hkr) | https://github.com/hkr/fuji-cam-wifi-tool | Unlicense | WiFi remote: shutter, ISO, aperture, WB, shutter speed. No banks or film simulation | WiFi | No |
| furble (gkoh) | https://github.com/gkoh/furble | MIT | BLE remote shutter only | BLE | No |
| fujifilm-wifi-client-rs | https://github.com/jacobh/fujifilm-wifi-client-rs | none | WiFi client, 2018 | WiFi | No |
| ptpwebcam (dognotdog) | https://github.com/dognotdog/ptpwebcam | GPL-3.0 | Not Fuji-specific, but proof that macOS ImageCaptureCore `requestSendPTPCommand` carries vendor ops (Nikon `0x9xxx` live view) in `PtpWebcamDalPlugin/PtpCamera.m` L917–935. It now lists experimental Fuji support | ImageCaptureCore | Pattern reference |
| darktable / RawTherapee | https://github.com/darktable-org/darktable, https://github.com/RawTherapee/RawTherapee | GPL-3.0 | They don't read or write camera settings. RawTherapee's "Film Simulation" applies HaldCLUT files, not Fuji's simulations (from memory, not inspected) | — | Not relevant |
| Recipe file collections | https://github.com/plamf/fuji-x-weekly-simulation-profiles (GPL-3.0, FP1), https://github.com/akirichev/fujifilm-recipes, https://github.com/gosku/Filmcase | mixed | X RAW Studio FP1 profiles (XML) and recipe data | — | FP1 import format; check each licence |

**WiFi:** no source documents reading or writing banks over WiFi. libfuji's WiFi mode is Camera Connect / tether for
live settings and transfer; the zgrimz reference puts WiFi and BLE out of scope. Treat recipes as **USB-only**. (Not
verified that WiFi can't do it; nobody has shown it.)

---

## 2. Protocol

### 2.1 Transport

- Standard PTP (ISO 15740) over USB bulk, little-endian.
  - Container: `[u32 len][u16 type 1=cmd 2=data 3=resp 4=event][u16 code][u32 txid][params…]`.
  - Verified in zgrimz `docs/01-transport.md` and ILF `examples/python/ptp_recipe_reference.py` (`command_packet`, `data_packet`).
- USB IDs: vendor `0x04CB`. Product IDs: X-T3 `0x02DD`, X-T30 `0x02E3`, X100V `0x02E5`, X-T4 `0x02E6` (libgphoto2;
  FilmKit says `0x02E7`), X100VI `0x0305`, X-T50 `0x0306`, X-M5 `0x030C`/`0x030D` (may depend on the USB mode). FilmKit
  `constants.ts` lists `0x02E3, 0x02E5, 0x02E7, 0x0305` (verified). The rest are unverified (relayed from zgrimz `01-transport.md`).
- GetDeviceInfo vendor extension: `6`, `"fujifilm.co.jp: 1.0; "`.
- Operations used: `0x1001 / 0x1002 / 0x1003`, `0x1015` GetDevicePropValue, `0x1016` SetDevicePropValue. For backups:
  `0x1008 / 0x1009` and `0x100C / 0x100D`. For RAW conversion: `0x900C / 0x900D`.
- **USB mode.** The camera menu setting is **CONNECTION MODE / USB SETTING → "USB RAW CONV./BACKUP RESTORE"**. Read
  `0xD16E` to check it:
  - `5` = tether, `6` = RAW CONV./BACKUP RESTORE, `8` = webcam.
  - A refused read means card reader (storage) mode.
  - Verified in libfuji `lib/fuji_usb.c` (`fujiusb_setup`).
  - In card-reader mode the camera advertises about 4–5 properties and no banks.
  - A GFX100RF also exposes banks in tether mode from macOS, but RAW CONV. is the recommended mode (zgrimz `01-transport.md`).
- **The camera menu is locked while connected in RAW CONV. mode.** The X-T50 shows only its USB screen.
- **GetDeviceInfo's property list is unreliable in both directions.** The X-T30 and X-T30 II advertise 0 properties
  yet answer the bank properties. Don't gate on what's advertised; probe instead.
- `GetDevicePropDesc` is usually refused (`0x2002` or `0x200A`). Value sets come from menu sweeps, not from descriptors.

### 2.2 Bank (custom slot) workflow

Verified in zgrimz `docs/04-custom-slots.md` (X RAW Studio capture order, X-T50 measurements).

**Read a bank:**
1. Read `0xD18C` and save it.
2. Write `0xD18C = k` (1…n).
3. Read `0xD18D` and `0xD18E…0xD1A4`, about 2–4 ms each.
4. Restore the selector.

**Write a bank:**
1. Select the bank.
2. Optionally write the name.
3. Write only the changed settings, in ascending order, with these exceptions:
   - Kelvin `0xD19C` goes right after WB mode `0xD199`, and the shifts `0xD19A`/`0xD19B` come after Kelvin. On an
     X-S10, writing the shifts before Kelvin zeroed them.
   - When turning D-Range Priority off, write `0xD191` before `0xD190`.
   - Film simulation `0xD192` goes before tones and color (a GFX100RF reportedly resets them when the simulation changes).
4. **Read everything back and compare by meaning.** `0x2001` OK does not prove the value was stored (for example,
   grain Off is normalised).

**Selector and persistence behaviour:**
- `0xD18C` is an *edit pointer*, not the shooting bank. It persists across reconnects, so always select before every operation.
- The bank count is found by probing: select n+1 returns `0x200A`.
  - 7 banks: X-T50, X-H2, X-T5, X-E5, X100V, X-T30 II, GFX100RF.
  - 6 banks: GFX100S, GFX100 II.
  - 4 banks: X-M5, X-S20, X-S10.
- Persistence on an X-T50 fw 1.32: USB writes persist without a name write and survive power cycles and RESET THE
  CHANGES. A red dot appears in EDIT/SAVE CUSTOM SETTING, but it is cosmetic.
- Writing a bank doesn't change the live state. X RAW Studio optionally mirrors the recipe to live codes (table
  below). On bodies with a Film Simulation dial (X-T50, X-M5, X-E5, X-T30 III), **the dial overrides the bank's
  simulation unless it's set to C**.

### 2.3 Property codes, fields and value encodings

All values are u16 little-endian in the data phase. Some must be read signed, some unsigned (`0x8000` marks special values).

| Code | Field | Encoding (wire) | Gates / gotchas | Status |
|--|--|--|--|--|
| `0xD16E` | USB mode (camera-wide) | 5 tether, 6 RAW CONV./BACKUP RESTORE, 8 webcam; refused read = card reader | — | **verified in** libfuji `lib/fuji_usb.c` L116–133, `lib/fujiptp.h` L309 |
| `0xD15D` | SetUSBMode | ? | Whether it switches modes is an open question; a GFX100S refuses its descriptor | verified *name* in libgphoto2 `camlibs/ptp2/ptp.h` L2963; behaviour unverified |
| `0xD18C` | Bank selector | u16 `1…n` = C1…Cn | Not the shooting bank; persists across reconnects; `0x200A` above n | **verified in** FilmKit `src/ptp/constants.ts` ("PresetSlot"), ILF `ptp_recipe_reference.py` (`FUJI_SLOT_SELECTOR`) |
| `0xD18D` | Bank name | PTP string: u8 count (with NUL) + UCS-2LE + `0000`. Up to 25 printable ASCII characters round-trip | Unnamed bank reads `01 00 00`. Through ImageCaptureCore, an empty name `00` doesn't clear the name; send `01 00 00` | verified in FilmKit `constants.ts`, ILF `ptp_recipe_reference.py` (`ptp_string`, `SAFE_NAME_CHARS`); limits per zgrimz `03-encodings.md` |
| `0xD18E` | Image Size (size × aspect composite) | 1 S3:2, 4 M3:2, 7 L3:2, 8 L16:9, 9 L1:1, 14 L4:3, 16 L5:4 … | **Not a recipe field; carry it through.** X100V: `0x200A`. Refused under Digital Tele-Converter or Sports Finder | verified code in FilmKit `constants.ts`; values per zgrimz `03-encodings.md` (X-T50 menu-confirmed) |
| `0xD18F` | Image Quality | 1 RAW, 2 FINE, 3 NORMAL, 4 FINE+RAW, 5 NORMAL+RAW | Not a recipe field. X100V: `0x200A` | verified code in FilmKit `constants.ts`; values per zgrimz |
| `0xD190` | Dynamic Range | **percent**: 100 / 200 / 400; `0xFFFF` = Auto. `0` is refused | DR200 needs ISO ≥ 2× base and DR400 needs ≥ 4× base (bank ISO); refused while D-Range Priority ≠ Off | verified in FilmKit `constants.ts` (`DynRange: raw percentage 100/200/400`); Auto=`0xFFFF` per zgrimz (X-T50, GFX100S, X-M5 measured; ILF disputes and uses `0`) |
| `0xD191` | D-Range Priority | 0 Off, 1 Weak, 2 Strong, `0x8000` Auto (read unsigned) | Refused at base ISO; when on, locks `0xD190`/`0xD19D`/`0xD19E` | verified code in ILF `ptp_recipe_reference.py`; values per zgrimz `03-encodings.md` + ILF `docs/tested-bodies.md` (X-H2). FilmKit calls it unknown |
| `0xD192` | Film Simulation | 1 Provia, 2 Velvia, 3 Astia, 4 Pro Neg Hi, 5 Pro Neg Std, 6 Mono, 7 Mono+Ye, 8 Mono+R, 9 Mono+G, 10 Sepia, 11 Classic Chrome, 12 Acros, 13 Acros+Ye, 14 Acros+R, 15 Acros+G, 16 Eterna, 17 Classic Neg, 18 Eterna Bleach Bypass, **19 Nostalgic Neg, 20 Reala Ace** | Each body supports a subset (Reala Ace via fw 4.00 on X-T5, 5.00 on X-H2, 3.00 on X-S20) | **verified in** rawji `src/rawji/fuji_enums.py` L66–87; 1–18 also in libgphoto2 `camlibs/ptp2/config.c` L1994–2013 (live `0xD001`); 4–7, 10, 12–15 menu-confirmed on an X-T50 (zgrimz); 20 menu-confirmed on an X-M5 |
| `0xD193` | Monochromatic Color WC (warm–cool) | signed ×10, steps of 10, ±180 (±90 on single-axis bodies) | Only on Mono/Acros simulations (not Sepia); `0x201C` otherwise. Zero may be refused on an X100VI or GFX100RF | verified in FilmKit `constants.ts` ("MonoWC ×10, rejects writing 0, only for B&W sims") |
| `0xD194` | Monochromatic Color MG (magenta–green) | signed ×10, as above | as above | verified in FilmKit `constants.ts` |
| `0xD195` | Grain (strength + size) | **write** 1 Off, 2 Weak/Small, 3 Strong/Small, 4 Weak/Large, 5 Strong/Large; **read** Off comes back as 6 (size Small kept) or 7 (size Large kept) | Writes of 0/6/7/8 are refused. Older strength-only bodies are untested | verified in FilmKit `constants.ts` (1–5); 6/7 read-back per zgrimz `03-encodings.md` (X-T50, GFX100S, X-M5) |
| `0xD196` | Color Chrome Effect | 1 Off, 2 Weak, 3 Strong | — | verified in FilmKit `constants.ts` (`PresetEffectLabels`) |
| `0xD197` | Color Chrome FX Blue | 1 Off, 2 Weak, 3 Strong | — | verified in FilmKit `constants.ts` |
| `0xD198` | Smooth Skin | 1 Off, 2 Weak, 3 Strong | Missing on X-S20, X-S10, X-H2S, X-M5 (`0x200A`) | verified in FilmKit `constants.ts` |
| `0xD199` | White Balance mode | read unsigned: 2 Auto, `0x8020` Auto White Priority, `0x8021` Auto Ambience, 4 Daylight, `0x8006` Shade, `0x8001`/`0x8002`/`0x8003` Fluorescent 1–3, 6 Incandescent, 8 Underwater, `0x8007` Kelvin, `0x8008`–`0x800A` Custom 1–3 | Custom WB may be refused if empty | code verified in FilmKit `constants.ts` ("uint16, mask 0xFFFF"); values per zgrimz `03-encodings.md` (X-T50 menu-confirmed; all 14 written on an X-H2 per ILF `docs/tested-bodies.md`) |
| `0xD19A` | WB shift Red | signed, **not** ×10, −9…+9 | Stored per WB mode within the bank, so write it after the mode | verified in FilmKit `constants.ts` (signed integer formatting), ILF `SIGNED_PROPERTIES` |
| `0xD19B` | WB shift Blue | signed, −9…+9 | as above | verified as above |
| `0xD19C` | Color temperature | unsigned Kelvin (5300 = 5300 K); 2500–10000 in steps of 10 on X-Processor 5; older bodies have a list of 31 presets | Write only with `0xD199 = 0x8007` | verified in FilmKit `constants.ts` (`ColorTemp(K)`); prerequisite per FilmKit README / zgrimz |
| `0xD19D` | Highlight Tone | signed ×10, half steps (5 = +0.5); −2…+4 | Refused while D-Range Priority is on | verified in FilmKit `constants.ts` (`HighlightTone×10`), ILF `SIGNED_PROPERTIES` |
| `0xD19E` | Shadow Tone | signed ×10; −2…+4 | as above | verified as above |
| `0xD19F` | Color | signed ×10; −4…+4 | Refused on monochrome simulations | verified in FilmKit `constants.ts` (`Color×10`) |
| `0xD1A0` | Sharpness | signed ×10; −4…+4 | — | verified in FilmKit `constants.ts` |
| `0xD1A1` | High ISO NR | **lookup**: −4 `0x8000`, −3 `0x7000`, −2 `0x4000`, −1 `0x3000`, 0 `0x2000`, +1 `0x1000`, +2 `0x0000`, +3 `0x6000`, +4 `0x5000` | Read unsigned | −4, 0 and +4 verified in FilmKit `constants.ts` comment; full table per zgrimz `03-encodings.md` (FilmKit + GFX100S/X-M5 menu checks), unverified by me in code |
| `0xD1A2` | Clarity | signed ×10; −5…+5 | Refused when the bank's format is HEIF (X-T50) | verified in FilmKit `constants.ts` (`Clarity×10`) |
| `0xD1A3` | Lens Modulation Optimizer | 1 On, 2 Off | Not a recipe field. FilmKit wrongly labels it LongExpNR. X100V: `0x200A` | code verified in FilmKit; meaning per zgrimz `errata.md` (X-T50 menu-confirmed) |
| `0xD1A4` | Color Space | 1 sRGB, 2 Adobe RGB | Not a recipe field | verified in FilmKit `constants.ts` (`formatPresetValue`) |
| `0xD1A5` | *Live* Image Size (not a bank setting) | same codes as `0xD18E` | X RAW Studio's first live-mirror write; GFX100S refuses it | verified in ILF `ptp_recipe_reference.py` comment ("0xD1A5 is a live/C0 code, not a slot code") |
| `0xD183` | Start RAW conversion | write 1 = full size, 0 = reduced | after RAF upload | verified in libfuji `lib/fujiptp.h` L326, FilmKit `constants.ts` |
| `0xD184` | IOPCode string ("FF189504,FA189504") | string | — | verified name in libgphoto2 `ptp.h` L2983, libfuji `fujiptp.h` L327 |
| `0xD185` | RAW conversion profile (blob, about 600–632 bytes) | binary cells | Readable only after a RAF upload | verified in libfuji `fujiptp.h` L328, FilmKit `constants.ts` |
| `0xD186` / `0xD187` | Model / "TetherRawCompatibilityCode" ("X-T50_0100") | string | X RAW Studio's capability key | verified names in libgphoto2 `ptp.h` L2984–2985 |
| `0xD212` | Event list / CurrentState | u16 count + (u16 code, u32 value)… | Poll it for conversion completion | verified in libfuji `fujiptp.h` L44/L345, libgphoto2 `ptp.h` L3024 |
| `0xD36A` / `0xD36B` | Battery info | int / string | — | unverified (zgrimz `02-properties.md`) |

Not in the user's list but present:
- Exposure bias exists only inside the `0xD185` RAW profile (cell 5), **not in the bank block**.
- There is **no "Color Chrome FX" per-slot exposure, ISO or noise-reduction-for-long-exposure** in the bank block
  (Long Exposure NR is not exposed).
- ISO is a hidden bank attribute that gates DR. It isn't readable here: `0x500F` returns `0x200A` on an X-T50.

**Live mirror (current shooting state, "C0")**, bank code → live code. Verified in zgrimz `02-properties.md`, from an
X RAW Studio capture and ILF `docs/current-shooting-state.md`. The live codes are partly confirmed in libgphoto2 `ptp.h` L2864–3054.

| Bank → live | Bank → live | Bank → live |
|--|--|--|
| `0xD18E` → `0xD1A5` | `0xD196` → `0xD029` | `0xD19D` → `0xD320` |
| `0xD18F` → `0xD018` | `0xD197` → `0xD030` | `0xD19E` → `0xD321` |
| `0xD190` → `0xD007` | `0xD198` → `0xD189` | `0xD19F` → `0xD008` |
| `0xD191` → `0xD02E` | `0xD199` → `0x5005` | `0xD1A0` → `0x5015` |
| `0xD192` → `0xD001` | `0xD19C` → `0xD017` | `0xD1A1` → `0xD01C` |
| `0xD193` → `0xD104` | `0xD19A` → `0xD00B` | `0xD1A2` → `0xD032` |
| `0xD194` → `0xD031` | `0xD19B` → `0xD00C` | `0xD1A3` → `0xD34D` |
| `0xD195` → `0xD023` | | `0xD1A4` → `0xD00A` |

Note: FilmKit's live-code names (for example `0xD017` "GrainEffect") are wrong. libgphoto2 and libfuji call `0xD017`
ColorTemperature and `0xD023` GrainEffect. Ignore FilmKit's `FujiPropNames` for `0xD0xx`.

### 2.4 Response codes worth handling

| Code | Meaning | Cause / action |
|--|--|--|
| `0x2001` | OK | Not proof the value was stored; read it back |
| `0x2002` | General error | Descriptor refusals, `0xD185` read before an upload |
| `0x200A` | Property not supported | Bank beyond n, or a property the body lacks |
| `0x200F` | Access denied | Backup restore with a stale checksum; GetObject and SendObject in one session |
| `0x2019` | Busy | Wedged body; grawji's advice is a power cycle or battery pull |
| `0x201C` | Invalid value | Wrong value, or a state gate (DR Priority, monochrome simulation, ISO, HEIF, Kelvin mode) |
| `0x201E` | Session already open | Close the session and reopen |

Source: zgrimz `docs/01-transport.md`.

### 2.5 Which bodies can be written over plain USB

| Body | Bank write over `0xD18C` | Banks | Evidence |
|--|--|--|--|
| X-T5 | ✅ fw 4.20 | 7 | ILF `docs/tested-bodies.md` (verified), fujicli |
| X-H2 | ✅ fw 5.20, including names; 0 ms between writes works | 7 | ILF `docs/tested-bodies.md` (verified) |
| X100VI | ✅ (FilmKit's reference body); libgphoto2 dump fw 1.00 has the same 61 properties | 7 | FilmKit README; zgrimz `07-cameras.md` |
| X-T50 | ✅ end to end, fw 1.31/1.32 | 7 | zgrimz (measured) |
| X-S20 | ✅, no Smooth Skin | 4 | fujicli, grawji #114 (unverified by me) |
| X-M5 | ✅ fw 1.30 | 4 | zgrimz owner report, FilmKit #18 |
| X-E5 | ✅; FS-dial recipes go through the backup | 7 | grawji |
| X100V | ⚠️ 19 of 23 readable, 15 written; Image Size, Quality, LMO and Color Space are `0x200A` (firmware unknown) | 7 | X RAW Studio capture in FilmKit #1 (zgrimz) |
| X-T30 II | ✅ fw 2.04 (community report, unmerged PR) | 7 | ILF PR #2 |
| X-S10 | ✅ reads and writes (Filmcase) | 4 | Filmcase |
| GFX100S / GFX100RF | ✅ (from iOS and macOS) | 6 / 7 | zgrimz, fuji-ptp-notes |
| **X-Pro3** | ❌ fw 2.00: reads, writes and names fail, cause undiagnosed. X RAW Studio 1.8.0 claims "X-Pro3 or newer" for profile-to-custom-setting transfer, so a fix may exist | — | ILF `docs/tested-bodies.md` (verified) |
| **X-T4, X-E4** | ❓ **no report**. X RAW Studio's capability table lists them (half-step tones). grawji puts them in its "layout mapping needed" group (`docs/enable-bank-writing.md`, verified) | 7 (manual) | — |
| X-T3, X-T30 | ❌ selects 1–7 fail; banks only through the settings-backup patch (X-T3, checksum) | — | FilmKit #5/#13, grawji |
| X-T20, X-H1, X-T2, X-Pro2, X-E3, X100F | ❌ no bank block; backup patch (X100F verified; others "expected" by layout) | — | grawji `backup_recipe.py` L204–276 (verified) |

So the realistic target is **X-Processor 5 bodies plus the X-S10, X-T30 II, X100V (partial) and GFX100S**. The rest
of X-Processor 4 is unknown or broken. X-Trans III needs the backup-patch route.

### 2.6 Risk

- **Bricking: no report in any source.** Bank writes are ordinary property sets. Firmware patching (fujihack) is the
  only real brick risk, and we don't need it.
- **Realistic risks:**
  - Overwriting the user's banks. There's no undo and no "erase bank" operation; snapshot before writing.
  - Silent normalisation (grain), so compare by meaning.
  - A wedged body after a stalled transfer (`0x2019`, power cycle needed).
  - A settings-backup restore can change *everything*, though the camera rejects bad checksums with `0x200F` (X-T3).
- **Warranty:** Fuji X Weekly (2026-06-08) and the ILF README report that Fujifilm says any non-licensed program that
  connects to the camera voids the warranty. Show a disclaimer.
  - https://fujixweekly.com/2026/06/08/your-cameras-warranty-might-be-voided/ (cited by zgrimz; not fetched by me)

---

## 3. macOS and iOS access from Swift

| Option | Verdict |
|--|--|
| **ImageCaptureCore** `ICCameraDevice.requestSendPTPCommand(_ ptpCommand: Data, outData: Data?, completion: (Data, Data, Error?) -> Void)` (also `async throws -> (Data, Data)`) | **Use this.** Availability is macOS 10.15+, iOS/iPadOS 13+, Mac Catalyst 13.1+, visionOS 1+ (Apple doc, read 2026-11-04: https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand(_:outdata:completion:)). The local SDK header `MacOSX27.2.sdk/.../ICCameraDevice.h` L356–373 says to send only when `capabilities` contains `ICCameraDeviceCanAcceptPTPCommands` ("All PTP cameras have this capability"), available macOS 10.4 / iOS 13. You build the whole command container (type must be `1`) and the data phase goes in `outData`. Apple DTS (Kevin Elliott) in https://developer.apple.com/forums/thread/798202 (Aug–Sep 2025) said everything is little-endian and outData is passed through unchanged. Vendor codes go through: ptpwebcam uses it for Nikon `0x9xxx`; fuji-ptp-notes and zgrimz use it for Fuji `0xD18C–0xD1A5` on macOS 26 and iOS 26/27. Events come in through `ptpEventHandler` (macOS 12+). |
| libusb / IOKit `IOUSBHost` direct | It works (fujicli, the X-T30 II Python report), but **`ptpcamerad` claims the PTP interface**. That report says normal termination didn't help, force-killing did, and launchd restarts the daemon, so you must claim the interface quickly (ILF PR #2, via zgrimz `09-platform-notes.md`). `ptpcamerad` is on this Mac as `/System/Library/LaunchAgents/com.apple.ptpcamerad.plist` → `/usr/libexec/ptpcamerad` (checked locally). FilmKit issue #2: closing Photos or QuickTime freed the camera. **Avoid this route.** It's fragile and not App Store friendly |
| libgphoto2 | LGPL, no bank codes, and needs libusb anyway. No |

**Practical ImageCaptureCore notes** (zgrimz `docs/09-platform-notes.md`, measured on an X-T50 with iOS 26/27):

- **One browser.** Keep a single `ICDeviceBrowser` for the whole process, with mask `.camera | .local`. A second
  browser didn't re-announce an attached camera.
- **Opening the session.** `requestOpenSession(options:completion:)`. Retry on `-9954` (busy enumerating the card).
  Close and reopen if the open fails because of a stale session.
- **Transaction IDs.** The response transaction ID can differ from the one you sent: the first command got txid 6,
  because the framework sends its own traffic. Correlate by callback, not by txid.
- **One command at a time.** Serialise commands. Time out at 20 s + 1 s per MB, and ignore late completions.
- **Two iOS/iPadOS grants.** Call both `requestControlAuthorization` (Settings → Privacy → Camera) **and**
  `requestContentsAuthorization` (Files and Folders). Without contents authorization the camera is never posted to
  `didAdd`.
  - These APIs are `IC_UNAVAILABLE(macos)` and iOS 14+. Verified in the local SDK `ICDeviceBrowser.h` L35–38, L205–223.
  - Known iOS 18 bugs: contents authorization stuck on denied (https://developer.apple.com/forums/thread/765768,
    Oct 2024) and the browser finding no devices (https://developer.apple.com/forums/thread/756960, Jun–Nov 2024).
- **macOS sandbox.** Enable App Sandbox → Hardware → **USB** (`com.apple.security.device.usb`). Thread 756960 reports
  that this fixed discovery. The key name is my inference from the Xcode UI label; unverified.
- **iPadOS with USB-C.** Yes. The "Fuji Cookbook" client runs on iPad, and a GFX100S, X-T20 and X-M5 have been driven
  from iOS.
- **Caveat.** fuji-ptp-notes saw iOS return `0x200A` for *unadvertised* properties in **tether** mode, while macOS
  forwarded them. In **RAW CONV.** mode, iOS reaches unadvertised bank properties fine (GFX100S). So use RAW CONV.
  mode on iOS.

## 4. X Acquire backup (.DAT)

- **What Fujifilm says.** X Acquire (now folded into FUJIFILM TETHER APP) backs up "all camera settings except
  DATE/TIME, results of CUSTOM WHITE BALANCE, and customized QUICK menu", in USB RAW CONV./BACKUP RESTORE mode
  (https://www.fujifilm-x.com/en-in/?p=58972). The file is named `<model>_<date>.dat`
  (https://kirkville.com/back-up-the-settings-on-your-fujifilm-cameras/, not fetched). No official format documentation exists.
- **The wire object is PTP object handle 0:**
  - Read: `GetObjectInfo(0)` then `GetObject(0)`.
  - Restore: `SendObjectInfo(0x100C, [0,0])` with an ObjectInfo of format `0x5000` padded to 1088 bytes (libfuji)
    or 1076 bytes (grawji says this is what X Acquire sends), then `SendObject(0x100D)`.
  - Verified in libfuji `lib/fuji_usb.c` (`fujiusb_download_backup` / `fujiusb_restore_backup`, rejects anything over
    100,000 bytes, MIT) and grawji `src/grawji/camera/camera_backup.py` (`_OBJECTINFO_SIZE = 1076`, `_MODEL_OFFSET = 0x14`, `_SERIAL_OFFSET = 0x34`, magic `FUJIFILM`).
  - That X Acquire's `.dat` is byte-identical to this object is likely but **unverified**.
- **Partial reverse engineering, by grawji only (GPL-3.0)** in `src/grawji/camera/backup_recipe.py` L200–276 (verified):
  - **Gen3** (X100F verified; X-Pro2, X-T2, X-T20, X-E3 assumed): 5660-byte blob, 7 slots, slot 0 film-simulation
    byte at 3909, stride 256, a handful of field offsets, no checksum.
  - **Gen4-early** (X-T3 verified; X-T30 assumed): 33,404 bytes, film-simulation byte at 31658, stride 256, name at
    +67. Additive u16 checksum stored at 176 over `[0xA8, EOF)` with bias `0xFF56`, skipping `0x7AF6–0x7AFA`. Camera-rewritten volatile bytes at 176/248/380/408/3276.
  - The backup uses **its own value codes**, different from the property encodings (for example DR 0–3, grain 0–2).
- **No layout exists for X-Processor 4/5 backups** (X-T4, X-T5 and so on). They aren't needed, because those bodies
  have the property route. A backup is still worth taking as a safety net before writing; just treat it as an opaque
  blob. It contains the serial number in cleartext, so it's personal data.

## 5. Detecting the camera on plug-in

- **ImageCaptureCore (recommended, all platforms):**
  - `ICDeviceBrowser` (macOS 10.4+, iOS 13+) with `browsedDeviceTypeMask = [.camera, .local]`.
  - The delegate gets `deviceBrowser(_:didAdd:moreComing:)` and `didRemove`.
  - Filter on `ICDevice.usbVendorID == 0x04CB` (`usbProductID` also exists). Verified in the local SDK `ICDevice.h` L305–311, macOS 10.4 / iOS 13.
  - Then open a session and read `0xD16E` to tell the user "switch to USB RAW CONV./BACKUP RESTORE" if needed.
  - Doc: https://developer.apple.com/documentation/imagecapturecore/icdevicebrowser (read 2026-11-04).
  - Caveat: `didRemove` can arrive seconds late or never (X-T20 report).
- **IOKit (macOS only, if you want to know before ImageCaptureCore sees it):**
  - `IOServiceAddMatchingNotification(port, kIOFirstMatchNotification / kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice") + idVendor 0x04CB)`.
  - Present in the local SDK `IOKit.framework/Headers/IOKitLib.h` L475.
  - Useful for spotting a camera in **card-reader** mode, which may show up as mass storage rather than PTP, so you
    can show "change USB mode".
- On iOS, IOKit isn't available to apps; ImageCaptureCore is the only option.

## 6. Licences: what we can reuse

| Reuse level | Projects |
|--|--|
| **Port freely (MIT / Apache / CC BY with credit)** | zgrimz reference (spec; tools are MIT); ILF fujifilm-ptp-recipes (spec CC BY; `examples/python/ptp_recipe_reference.py` MIT); FilmKit (MIT: `src/ptp/constants.ts`, `src/ptp/session.ts`, `src/profile/enums.ts`); libfuji (MIT: `lib/fujiptp.h`, `lib/fuji_usb.c`, `fp/` profile parser and FP1–3); libpict (Apache-2.0); furble (MIT); fuji-cam-wifi-tool (Unlicense) |
| **Facts only, no code copying (GPL / LGPL)** | rawji, grawji, fujicli, Filmcase, fudge-legacy (GPL-2), fujihack, ptpwebcam, darktable, RawTherapee (GPL-3); libgphoto2 (LGPL) |
| **No licence (read only)** | fuji-ptp-notes, fxraw, new fudge, AlPeFe/fuji-ptp-android, jacobh WiFi client |

Protocol constants and encodings are functional facts. zgrimz's README states the same position: the licence "does not
create ownership of individual protocol constants, byte offsets, or value encodings". A clean Swift implementation from
the zgrimz/ILF specs is fine. Credit the zgrimz reference, ILF, FilmKit and libfuji in About.

**Port plan, roughly 600 lines of Swift:**
1. A PTP container builder and parser (ILF `command_packet` / `data_packet` / `ptp_string`).
2. An ImageCaptureCore session actor that runs one command at a time.
3. A table of `FujiBankProperty` (the table above) with a signed/unsigned flag per code.
4. Encoders and decoders for each field: grain read-normalisation, NR lookup, ×10 values, DR percent, WB high bit.
5. A writer that applies the order rules and gates, then reads back.
6. Optional: a backup snapshot via `GetObject(0)`.
7. Per-body capability data from ILF `docs/reverse-engineering/reference/xrfc-capabilities.xml` (CC BY).

## Open items to verify on hardware

- X-T4, X-E4 and X-Pro3 behaviour on current firmware: one `GetDeviceInfo` and one `0xD18C` read would tell us a lot.
- The DR Auto encoding (`0xFFFF` vs `0`) on the target bodies.
- Whether Monochromatic Color `0` is refused on an X100VI.
- Whether ImageCaptureCore passes `0x100C`/`0x100D` (backup restore) unchanged on macOS and iOS. Not reported anywhere.
- The tone floor (−2 per the menus vs a community report of ±4 accepted).
